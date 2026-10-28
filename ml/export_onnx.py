"""Ekspor model hasil `train.py` ke ONNX int8 untuk dijalankan di Android.

Langkah:
  1. Bungkus model: input int32 (input_ids, attention_mask) -> output
     probabilitas softmax [batch, 3]. Int32 dipakai agar mudah dikirim dari Dart.
  2. Ekspor ONNX (fp32), lalu kuantisasi dinamis ke int8 (~4x lebih kecil).
  3. Verifikasi: bandingkan prediksi int8 vs PyTorch pada data test.
  4. Salin model + vocab + config ke ../assets/ai/ dan buat fixture untuk
     test Dart di ../assets/ai/fixtures.json.

Pemakaian:
  python export_onnx.py
"""

import hashlib
import json
import shutil
from pathlib import Path

import numpy as np
import onnxruntime as ort
import pandas as pd
import torch
from onnxruntime.quantization import QuantType, quantize_dynamic
from transformers import AutoModelForSequenceClassification, AutoTokenizer

ROOT = Path(__file__).resolve().parent
MODEL_DIR = ROOT / "output" / "model"
ONNX_DIR = ROOT / "output" / "onnx"
APP_ROOT = ROOT.parent
ASSET_DIR = APP_ROOT / "assets" / "ai"
# Di assets agar bisa dibaca juga oleh integration test di HP (ukuran kecil).
FIXTURE_PATH = ASSET_DIR / "fixtures.json"

# Panjang token maksimum saat inferensi di HP (pesan WhatsApp bisa panjang).
INFER_MAX_LEN = 256
RISK_LABEL = "penipuan"

# Contoh teks untuk memastikan tokenizer Dart == tokenizer HuggingFace.
FIXTURE_TEXTS = [
    "Selamat! Anda mendapatkan hadiah Rp5.000.000. Klik link berikut untuk klaim sekarang.",
    "Pak, file laporan rapat sudah saya kirim ke email ya. Terima kasih.",
    "Info: paket Anda tertahan. Bayar pajak kirim di http://cek-paket.link",
    "Ma, ini aku. HP aku rusak jadi pakai nomor teman dulu, tolong kirim pulsa 100rb ya",
    "KODE OTP anda 482913, JANGAN berikan ke siapapun (termasuk petugas bank)!!!",
    "Undangan_Pernikahan.apk -- buka sekarang ya kak 🙏😊",
    "Café di Jl. Sudirman No.12 buka jam 07:30–21:00, harga mulai 15rb/porsi.",
    "Meeting besok jam 10 di ruang 3, jangan lupa bawa laptop.",
    "   spasi   berlebih\tdan\nbaris baru   ",
    "Investasi aman pasti untung!!! Modal 1jt jadi 5jt dlm seminggu, hub admin wa.me/6281234567890",
]


class ProbWrapper(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, input_ids, attention_mask):
        ids = input_ids.long()
        logits = self.model(
            input_ids=ids,
            attention_mask=attention_mask.long(),
            token_type_ids=torch.zeros_like(ids),
        ).logits
        return torch.softmax(logits, dim=-1)


def export_fp32(model, tokenizer, path: Path) -> None:
    sample = tokenizer(["contoh pesan untuk ekspor"], return_tensors="pt")
    args = (sample["input_ids"].int(), sample["attention_mask"].int())
    torch.onnx.export(
        ProbWrapper(model).eval(), args, str(path),
        input_names=["input_ids", "attention_mask"],
        output_names=["probs"],
        dynamic_axes={"input_ids": {0: "batch", 1: "seq"},
                      "attention_mask": {0: "batch", 1: "seq"},
                      "probs": {0: "batch"}},
        opset_version=17,
        dynamo=False,
    )


def run_onnx(session, tokenizer, texts, max_len):
    enc = tokenizer(list(texts), truncation=True, max_length=max_len, padding=True,
                    return_tensors="np")
    return session.run(["probs"], {
        "input_ids": enc["input_ids"].astype(np.int32),
        "attention_mask": enc["attention_mask"].astype(np.int32),
    })[0]


def write_vocab(path: Path) -> None:
    """vocab.txt (satu token per baris, nomor baris = id) untuk tokenizer Dart.

    transformers v5 hanya menyimpan tokenizer.json, jadi vocab diambil dari sana.
    """
    vocab = json.loads((MODEL_DIR / "tokenizer.json").read_text(encoding="utf-8"))["model"]["vocab"]
    tokens = sorted(vocab, key=vocab.get)
    assert [vocab[t] for t in tokens] == list(range(len(tokens))), "id vocab tidak berurutan"
    path.write_text("\n".join(tokens) + "\n", encoding="utf-8")


def main() -> None:
    tokenizer = AutoTokenizer.from_pretrained(MODEL_DIR)
    normalizer = json.loads(
        (MODEL_DIR / "tokenizer.json").read_text(encoding="utf-8"))["normalizer"] or {}
    model = AutoModelForSequenceClassification.from_pretrained(MODEL_DIR).eval()
    labels = [model.config.id2label[i] for i in range(model.config.num_labels)]

    ONNX_DIR.mkdir(parents=True, exist_ok=True)
    fp32_path = ONNX_DIR / "model_fp32.onnx"
    int8_path = ONNX_DIR / "model_int8.onnx"
    print("Ekspor ONNX fp32 ...")
    export_fp32(model, tokenizer, fp32_path)
    print("Kuantisasi int8 ...")
    quantize_dynamic(str(fp32_path), str(int8_path), weight_type=QuantType.QInt8)
    print(f"  fp32: {fp32_path.stat().st_size / 1e6:.1f} MB | "
          f"int8: {int8_path.stat().st_size / 1e6:.1f} MB")

    # --- verifikasi pada data test ---
    test_df = pd.read_csv(MODEL_DIR / "test_split.csv")
    sess = ort.InferenceSession(str(int8_path), providers=["CPUExecutionProvider"])
    texts, gold = test_df["Teks"].tolist(), test_df["label"].to_numpy()
    onnx_pred, torch_pred = [], []
    for i in range(0, len(texts), 32):
        batch = texts[i:i + 32]
        onnx_pred.extend(run_onnx(sess, tokenizer, batch, INFER_MAX_LEN).argmax(-1))
        enc = tokenizer(batch, truncation=True, max_length=INFER_MAX_LEN, padding=True,
                        return_tensors="pt")
        with torch.no_grad():
            torch_pred.extend(model(**enc).logits.argmax(-1).tolist())
    onnx_pred, torch_pred = np.array(onnx_pred), np.array(torch_pred)
    print(f"Akurasi test PyTorch  : {(torch_pred == gold).mean():.4f}")
    print(f"Akurasi test ONNX int8: {(onnx_pred == gold).mean():.4f}")
    print(f"Kesesuaian int8 vs PyTorch: {(onnx_pred == torch_pred).mean():.4f}")

    # --- salin ke assets aplikasi ---
    # Nama file memuat hash: plugin ONNX meng-cache model per nama file,
    # jadi model baru harus punya nama baru agar tidak memakai cache lama.
    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    for old in ASSET_DIR.glob("indobert_se*.onnx"):
        old.unlink()
    digest = hashlib.sha256(int8_path.read_bytes()).hexdigest()[:10]
    model_file = f"indobert_se_{digest}.onnx"
    shutil.copy(int8_path, ASSET_DIR / model_file)
    write_vocab(ASSET_DIR / "vocab.txt")
    (ASSET_DIR / "config.json").write_text(json.dumps({
        "model_file": model_file,
        "base_model": "indobenchmark/indobert-base-p1",
        "labels": labels,
        "risk_label": RISK_LABEL,
        "max_len": INFER_MAX_LEN,
        "do_lower_case": normalizer.get("lowercase", True),
    }, indent=2))
    print(f"Aset disalin ke {ASSET_DIR}")

    # --- fixture untuk test Dart ---
    cases = []
    for text in FIXTURE_TEXTS:
        ids = tokenizer(text, truncation=True, max_length=INFER_MAX_LEN)["input_ids"]
        probs = run_onnx(sess, tokenizer, [text], INFER_MAX_LEN)[0]
        cases.append({"text": text, "input_ids": ids,
                      "tokens": tokenizer.convert_ids_to_tokens(ids),
                      "probs": [float(p) for p in probs]})
    FIXTURE_PATH.parent.mkdir(parents=True, exist_ok=True)
    FIXTURE_PATH.write_text(json.dumps({"max_len": INFER_MAX_LEN, "labels": labels,
                                        "cases": cases}, ensure_ascii=False, indent=1),
                            encoding="utf-8")
    print(f"Fixture test ditulis ke {FIXTURE_PATH}")


if __name__ == "__main__":
    main()
