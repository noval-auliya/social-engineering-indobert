"""Uji model ONNX pada set "kasus sulit" (ml/eval/kasus_sulit.csv).

Set ini TIDAK pernah dipakai untuk training. Isinya jebakan yang sengaja
dibuat: pesan normal yang memuat nomor HP/rekening, penipuan tanpa nomor,
promo dengan nomor, dll. Akurasinya lebih jujur daripada data test biasa.

Pemakaian:
  python evaluate.py                          # model di ../assets/ai
  python evaluate.py --model path/model.onnx  # model lain (mis. versi lama)
"""

import argparse
import json
from pathlib import Path

import numpy as np
import onnxruntime as ort
import pandas as pd
from transformers import AutoTokenizer

ROOT = Path(__file__).resolve().parent
ASSET_DIR = ROOT.parent / "assets" / "ai"
EVAL_CSV = ROOT / "eval" / "kasus_sulit.csv"
LABELS = ["normal", "penipuan", "promo"]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", type=Path, default=None)
    ap.add_argument("--show-errors", action="store_true")
    args = ap.parse_args()

    model_path = args.model
    if model_path is None:
        cfg = json.loads((ASSET_DIR / "config.json").read_text())
        model_path = ASSET_DIR / cfg["model_file"]

    tokenizer = AutoTokenizer.from_pretrained(ROOT / "output" / "model")
    session = ort.InferenceSession(str(model_path), providers=["CPUExecutionProvider"])
    df = pd.read_csv(EVAL_CSV)

    enc = tokenizer(df["Teks"].tolist(), truncation=True, max_length=256, padding=True,
                    return_tensors="np")
    probs = session.run(["probs"], {
        "input_ids": enc["input_ids"].astype(np.int32),
        "attention_mask": enc["attention_mask"].astype(np.int32),
    })[0]
    df["pred"] = probs.argmax(-1)
    df["p_penipuan"] = probs[:, 1]
    df["benar"] = df["pred"] == df["label"]

    print(f"Model: {model_path.name}")
    print(f"{'kategori':24s} benar")
    for kat, g in df.groupby("kategori", sort=False):
        print(f"{kat:24s} {g['benar'].sum():2d}/{len(g):2d}  ({g['benar'].mean() * 100:5.1f}%)")
    print(f"{'TOTAL':24s} {df['benar'].sum():2d}/{len(df):2d}  ({df['benar'].mean() * 100:5.1f}%)")

    if args.show_errors:
        print("\nSalah prediksi:")
        for _, r in df[~df["benar"]].iterrows():
            print(f"  asli={LABELS[r['label']]:8s} prediksi={LABELS[r['pred']]:8s} "
                  f"p_penipuan={r['p_penipuan']:.3f} | {r['Teks'][:80]}")


if __name__ == "__main__":
    main()
