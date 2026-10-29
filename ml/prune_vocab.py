"""Pangkas vocab + tabel embedding agar model ONNX (dan APK) lebih kecil.

Dua sumber penghematan:
  1. config IndoBERT memakai vocab_size=50000, padahal tokenizer hanya punya
     30521 token. Baris 30521..49999 tidak pernah terjangkau -> selalu dibuang,
     output model dijamin identik.
  2. (opsional, --keep N) token yang jarang dipakai juga dibuang. Yang selalu
     disimpan: token spesial, semua token 1-karakter (agar kata apa pun tetap
     bisa dipecah WordPiece), dan semua token yang muncul di data latih.
     Urutan vocab IndoBERT kira-kira mengikuti frekuensi, jadi N id pertama
     = N token paling umum.

Token disimpan dalam urutan id aslinya, sehingga [PAD]/[UNK]/[CLS]/[SEP]
tetap di id 0..3 dan tokenizer Dart tidak perlu diubah.

Pemakaian:
  python prune_vocab.py                       # tahap 1 saja (tanpa risiko)
  python prune_vocab.py --keep 15000          # tahap 1 + 2
  python export_onnx.py --model-dir output/model_pruned
  python evaluate.py --show-errors
"""

import argparse
import json
import shutil
from pathlib import Path

import numpy as np
import pandas as pd
import torch
from transformers import AutoModelForSequenceClassification, AutoTokenizer

ROOT = Path(__file__).resolve().parent
SRC_DIR = ROOT / "output" / "model_student"
OUT_DIR = ROOT / "output" / "model_pruned"
DATA_DIR = ROOT / "data"
EVAL_CSV = ROOT / "eval" / "kasus_sulit.csv"
MAX_LEN = 256


def corpus_texts(src_dir: Path) -> list[str]:
    """Teks data latih. kasus_sulit.csv sengaja TIDAK dipakai agar evaluasinya
    tetap mengukur pesan yang belum pernah dilihat."""
    texts = []
    for path in sorted(DATA_DIR.glob("*.csv")) + [src_dir / "test_split.csv"]:
        texts += pd.read_csv(path)["Teks"].dropna().astype(str).tolist()
    return texts


def select_kept_ids(vocab: dict[str, int], special_ids: set[int],
                    corpus_ids: set[int], keep: int | None) -> list[int]:
    n = len(vocab)
    kept = set(range(min(keep or n, n)))
    kept |= special_ids
    kept |= {i for t, i in vocab.items() if len(t.removeprefix("##")) == 1}
    kept |= corpus_ids
    return sorted(kept)


def remap_tokenizer_json(tok_json: dict, kept: list[int]) -> dict:
    new_id = {old: new for new, old in enumerate(kept)}
    id2tok = {i: t for t, i in tok_json["model"]["vocab"].items()}
    tok_json["model"]["vocab"] = {id2tok[old]: new for new, old in enumerate(kept)}
    for tok in tok_json["added_tokens"]:
        tok["id"] = new_id[tok["id"]]
    for tok in (tok_json.get("post_processor") or {}).get("special_tokens", {}).values():
        tok["ids"] = [new_id[i] for i in tok["ids"]]
    return tok_json


def predict(model, tokenizer, texts: list[str]) -> np.ndarray:
    probs = []
    for i in range(0, len(texts), 32):
        enc = tokenizer(texts[i:i + 32], truncation=True, max_length=MAX_LEN,
                        padding=True, return_tensors="pt")
        with torch.no_grad():
            probs.append(torch.softmax(model(**enc).logits, -1).numpy())
    return np.concatenate(probs)


def compare(name, texts, old_model, old_tok, new_model, new_tok) -> None:
    same_tok = sum(old_tok.tokenize(t) == new_tok.tokenize(t) for t in texts)
    p_old, p_new = predict(old_model, old_tok, texts), predict(new_model, new_tok, texts)
    agree = (p_old.argmax(-1) == p_new.argmax(-1)).mean()
    print(f"  {name:12s} n={len(texts):4d} | tokenisasi sama {same_tok / len(texts):6.1%}"
          f" | label sama {agree:6.1%} | maks selisih prob {np.abs(p_old - p_new).max():.2e}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model-dir", type=Path, default=SRC_DIR)
    ap.add_argument("--out-dir", type=Path, default=OUT_DIR)
    ap.add_argument("--keep", type=int, default=None,
                    help="simpan N token paling umum (default: semua token tokenizer)")
    args = ap.parse_args()
    src, out = args.model_dir.resolve(), args.out_dir.resolve()
    print(f"Model: {src}")

    tok_json = json.loads((src / "tokenizer.json").read_text(encoding="utf-8"))
    vocab = tok_json["model"]["vocab"]
    old_tok = AutoTokenizer.from_pretrained(src)
    old_model = AutoModelForSequenceClassification.from_pretrained(src).eval()

    corpus_ids = set()
    for ids in old_tok(corpus_texts(src), add_special_tokens=False)["input_ids"]:
        corpus_ids.update(ids)
    special_ids = {t["id"] for t in tok_json["added_tokens"]}
    kept = select_kept_ids(vocab, special_ids, corpus_ids, args.keep)

    # --- model: ambil baris embedding yang disimpan ---
    new_model = AutoModelForSequenceClassification.from_pretrained(src).eval()
    old_emb = old_model.get_input_embeddings().weight.detach()
    emb = torch.nn.Embedding(len(kept), old_emb.shape[1],
                             padding_idx=new_model.config.pad_token_id)
    emb.weight.data.copy_(old_emb[torch.tensor(kept)])
    new_model.set_input_embeddings(emb)
    new_model.config.vocab_size = len(kept)
    print(f"Embedding: {old_emb.shape[0]} -> {len(kept)} baris "
          f"(vocab tokenizer {len(vocab)}, muncul di data latih {len(corpus_ids)})")

    # --- simpan model + tokenizer baru ---
    out.mkdir(parents=True, exist_ok=True)
    new_model.save_pretrained(out)
    (out / "tokenizer.json").write_text(
        json.dumps(remap_tokenizer_json(tok_json, kept), ensure_ascii=False),
        encoding="utf-8")
    for name in ("tokenizer_config.json", "test_split.csv", "metrics.json"):
        if (src / name).exists():
            shutil.copy(src / name, out / name)
    (out / "prune_info.json").write_text(json.dumps(
        {"source": src.name, "keep": args.keep, "rows_before": old_emb.shape[0],
         "rows_after": len(kept)}, indent=2))
    new_tok = AutoTokenizer.from_pretrained(out)
    print(f"Disimpan ke {out}")

    # --- verifikasi: model asli vs terpangkas ---
    print("Perbandingan dengan model asli (PyTorch):")
    compare("test_split", pd.read_csv(src / "test_split.csv")["Teks"].tolist(),
            old_model, old_tok, new_model, new_tok)
    compare("kasus_sulit", pd.read_csv(EVAL_CSV)["Teks"].tolist(),
            old_model, old_tok, new_model, new_tok)


if __name__ == "__main__":
    main()
