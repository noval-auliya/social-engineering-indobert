"""Fine-tune IndoBERT untuk deteksi pesan penipuan (social engineering).

Hanya dipakai saat development. Hasilnya diekspor ke ONNX oleh
`export_onnx.py` lalu dijalankan langsung di HP oleh aplikasi Flutter.

Data:
  1. Dataset SMS Spam Bahasa Indonesia (1.143 SMS, label 0=normal,
     1=penipuan, 2=promo), diunduh otomatis dari GitHub.
  2. ml/data/whatsapp_tambahan.csv  -> contoh pesan gaya WhatsApp.
  3. ml/data/kontras.csv  -> dibuat oleh buat_data_kontras.py (normal/promo
     dengan nomor, penipuan tanpa nomor).
  4. (opsional) ml/data/*.csv lain dengan kolom Teks,label -> data Anda sendiri.

Augmentasi (hanya data train): sebagian pesan normal/promo disisipi nomor
HP/rekening acak, dan pesan penipuan yang memuat nomor diberi salinan tanpa
nomor. Tujuannya agar model menilai isi kalimat, bukan ada-tidaknya angka.

Pesan di ml/eval/kasus_sulit.csv tidak pernah ikut dilatih.

Pemakaian:
  python train.py                 # default: 4 epoch
  python train.py --epochs 3 --batch-size 16
"""

import argparse
import json
import random
import re
import time
import urllib.request
from pathlib import Path

import numpy as np
import pandas as pd
import torch
from sklearn.metrics import classification_report, confusion_matrix
from sklearn.model_selection import train_test_split
from torch.utils.data import DataLoader
from transformers import (
    AutoModelForSequenceClassification,
    AutoTokenizer,
    get_linear_schedule_with_warmup,
)

import buat_data_kontras as kontras

ROOT = Path(__file__).resolve().parent
DATA_DIR = ROOT / "data"
EVAL_CSV = ROOT / "eval" / "kasus_sulit.csv"
OUT_DIR = ROOT / "output" / "model"

BASE_MODEL = "indobenchmark/indobert-base-p1"
SMS_URL = (
    "https://raw.githubusercontent.com/nadyatyandra/IndonesianSMSSpamDetector/"
    "HEAD/dataset/dataset_sms_spam_v1.csv"
)
LABELS = ["normal", "penipuan", "promo"]
MAX_LEN = 128
SEED = 42


def set_seed(seed: int) -> None:
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)


def load_data() -> pd.DataFrame:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    sms_path = DATA_DIR / "dataset_sms_spam_v1.csv"
    if not sms_path.exists():
        print(f"Mengunduh dataset SMS -> {sms_path}")
        urllib.request.urlretrieve(SMS_URL, sms_path)

    frames = []
    for path in sorted(DATA_DIR.glob("*.csv")):
        df = pd.read_csv(path)[["Teks", "label"]]
        df["sumber"] = path.name
        frames.append(df)
        print(f"  {path.name}: {len(df)} baris")

    data = pd.concat(frames, ignore_index=True)
    data["Teks"] = data["Teks"].astype(str).str.strip()
    data = data[data["Teks"] != ""].drop_duplicates(subset="Teks")
    data["label"] = data["label"].astype(int)

    # Jaga set uji kasus sulit tetap "belum pernah dilihat".
    if EVAL_CSV.exists():
        held_out = set(pd.read_csv(EVAL_CSV)["Teks"].str.strip())
        leaked = data["Teks"].isin(held_out)
        if leaked.any():
            print(f"  Membuang {leaked.sum()} pesan yang ada di set uji kasus sulit")
        data = data[~leaked]

    print("Distribusi label:", data["label"].map(dict(enumerate(LABELS))).value_counts().to_dict())
    return data


# Nomor HP / rekening / angka panjang (berbagai format penulisan).
NUMBER_RE = re.compile(r"\+?\d[\d\s\-.]{6,}\d")

INSERT_NORMAL = [
    " Nomorku {hp}.", " Ini nomorku {hp} ya.", " Kontak aku di {hp}.",
    " Telepon aja ke {hp}.", " Rekeningku {bank} {rek} a.n. {nama}.",
    " Transfer ke {bank} {rek} ya.", " Kirim ke {ewallet} {hp} aja.",
    " (nomor {nama}: {hp})", " Kalau ada apa-apa hubungi {hp}.",
]
INSERT_PROMO = [" Order: {hp}.", " Info & pemesanan {hp}.", " WA {hp}.", " Hubungi {telp}."]


def augment_numbers(train_df: pd.DataFrame, seed: int = SEED) -> pd.DataFrame:
    """Pasangan kontras: normal/promo + nomor, penipuan - nomor."""
    rng = random.Random(seed)
    extra = []
    for text, label in zip(train_df["Teks"], train_df["label"]):
        if label == 0 and rng.random() < 0.35:
            extra.append((text + kontras.isi(rng.choice(INSERT_NORMAL)), 0))
        elif label == 2 and rng.random() < 0.3:
            extra.append((text + kontras.isi(rng.choice(INSERT_PROMO)), 2))
        elif label == 1 and NUMBER_RE.search(text):
            stripped = re.sub(r"\s{2,}", " ", NUMBER_RE.sub("", text)).strip()
            if len(stripped) >= 20:
                extra.append((stripped, 1))
    aug = pd.DataFrame(extra, columns=["Teks", "label"])
    print(f"Augmentasi: +{len(aug)} pesan "
          f"({aug['label'].map(dict(enumerate(LABELS))).value_counts().to_dict()})")
    return pd.concat([train_df[["Teks", "label"]], aug], ignore_index=True)


def make_loader(tokenizer, texts, labels, batch_size, shuffle):
    enc = tokenizer(list(texts), truncation=True, max_length=MAX_LEN, padding=True,
                    return_tensors="pt")
    ds = torch.utils.data.TensorDataset(enc["input_ids"], enc["attention_mask"],
                                        torch.tensor(list(labels)))
    return DataLoader(ds, batch_size=batch_size, shuffle=shuffle)


@torch.no_grad()
def predict(model, loader):
    model.eval()
    preds, gold = [], []
    for ids, mask, y in loader:
        logits = model(input_ids=ids, attention_mask=mask).logits
        preds.extend(logits.argmax(-1).tolist())
        gold.extend(y.tolist())
    return np.array(gold), np.array(preds)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--epochs", type=int, default=4)
    ap.add_argument("--batch-size", type=int, default=16)
    ap.add_argument("--lr", type=float, default=3e-5)
    args = ap.parse_args()

    set_seed(SEED)
    torch.set_num_threads(max(1, torch.get_num_threads()))
    device = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"Device: {device}")

    data = load_data()
    train_df, rest = train_test_split(data, test_size=0.2, stratify=data["label"],
                                      random_state=SEED)
    val_df, test_df = train_test_split(rest, test_size=0.5, stratify=rest["label"],
                                       random_state=SEED)
    print(f"Train {len(train_df)} | Val {len(val_df)} | Test {len(test_df)}")
    train_df = augment_numbers(train_df)
    print(f"Train setelah augmentasi: {len(train_df)}")

    tokenizer = AutoTokenizer.from_pretrained(BASE_MODEL)
    model = AutoModelForSequenceClassification.from_pretrained(
        BASE_MODEL, num_labels=len(LABELS),
        id2label=dict(enumerate(LABELS)), label2id={l: i for i, l in enumerate(LABELS)},
    ).to(device)

    train_dl = make_loader(tokenizer, train_df["Teks"], train_df["label"], args.batch_size, True)
    val_dl = make_loader(tokenizer, val_df["Teks"], val_df["label"], 32, False)
    test_dl = make_loader(tokenizer, test_df["Teks"], test_df["label"], 32, False)

    optim = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=0.01)
    total = len(train_dl) * args.epochs
    sched = get_linear_schedule_with_warmup(optim, int(0.1 * total), total)

    best_acc, best_state = -1.0, None
    for epoch in range(1, args.epochs + 1):
        model.train()
        t0, loss_sum = time.time(), 0.0
        for step, (ids, mask, y) in enumerate(train_dl, 1):
            ids, mask, y = ids.to(device), mask.to(device), y.to(device)
            loss = model(input_ids=ids, attention_mask=mask, labels=y).loss
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            optim.step()
            sched.step()
            optim.zero_grad()
            loss_sum += loss.item()
            if step % 10 == 0:
                print(f"  epoch {epoch} step {step}/{len(train_dl)} loss {loss_sum / step:.4f}",
                      flush=True)
        gold, pred = predict(model, [(a.to(device), b.to(device), c) for a, b, c in val_dl])
        acc = float((gold == pred).mean())
        print(f"Epoch {epoch}: loss {loss_sum / len(train_dl):.4f} | val acc {acc:.4f} "
              f"| {time.time() - t0:.0f}s")
        if acc > best_acc:
            best_acc = acc
            best_state = {k: v.detach().cpu().clone() for k, v in model.state_dict().items()}

    model.load_state_dict(best_state)
    gold, pred = predict(model, [(a.to(device), b.to(device), c) for a, b, c in test_dl])
    report = classification_report(gold, pred, target_names=LABELS, digits=4, output_dict=True)
    print("\n=== Evaluasi data test ===")
    print(classification_report(gold, pred, target_names=LABELS, digits=4))
    print("Confusion matrix (baris=asli, kolom=prediksi):")
    print(confusion_matrix(gold, pred))

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    model.cpu().save_pretrained(OUT_DIR)
    tokenizer.save_pretrained(OUT_DIR)
    test_df.to_csv(OUT_DIR / "test_split.csv", index=False)
    (OUT_DIR / "metrics.json").write_text(json.dumps(
        {"val_accuracy": best_acc, "test_report": report,
         "train_size": len(train_df), "val_size": len(val_df), "test_size": len(test_df)},
        indent=2))
    print(f"\nModel disimpan di {OUT_DIR}")


if __name__ == "__main__":
    main()
