"""Distilasi: model "murid" 6 lapis belajar dari IndoBERT 12 lapis (guru).

Tujuan: APK lebih kecil dan inferensi ~2x lebih cepat (LIME ikut cepat),
dengan akurasi sedekat mungkin dengan guru.

- Guru  : ml/output/model (hasil train.py)
- Murid : config sama, num_hidden_layers=6. Embedding, classifier, dan lapis
          0,2,4,7,9,11 disalin dari guru, jadi tokenizer/vocab tetap sama.
- Loss  : alpha * CE(label) + (1 - alpha) * KL(murid/T || guru/T) * T^2
- Data  : sama persis dengan train.py (split, augmentasi nomor, seed).

Pemakaian:
  python distill.py                          # hasil di ml/output/model_student
  python export_onnx.py --model-dir output/model_student
  python evaluate.py --show-errors
"""

import argparse
import copy
import json
import time
from pathlib import Path

import numpy as np
import torch
import torch.nn.functional as F
from sklearn.metrics import classification_report
from sklearn.model_selection import train_test_split
from transformers import AutoModelForSequenceClassification, AutoTokenizer, get_linear_schedule_with_warmup

import train as base

ROOT = Path(__file__).resolve().parent
TEACHER_DIR = ROOT / "output" / "model"
STUDENT_DIR = ROOT / "output" / "model_student"
KEEP_LAYERS = [0, 2, 4, 7, 9, 11]


def make_student(teacher):
    student = copy.deepcopy(teacher)
    student.bert.encoder.layer = torch.nn.ModuleList(
        [copy.deepcopy(teacher.bert.encoder.layer[i]) for i in KEEP_LAYERS])
    student.config.num_hidden_layers = len(KEEP_LAYERS)
    return student


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--epochs", type=int, default=4)
    ap.add_argument("--batch-size", type=int, default=16)
    ap.add_argument("--lr", type=float, default=5e-5)
    ap.add_argument("--temperature", type=float, default=2.0)
    ap.add_argument("--alpha", type=float, default=0.5)
    args = ap.parse_args()

    base.set_seed(base.SEED)
    data = base.load_data()
    train_df, rest = train_test_split(data, test_size=0.2, stratify=data["label"],
                                      random_state=base.SEED)
    val_df, test_df = train_test_split(rest, test_size=0.5, stratify=rest["label"],
                                       random_state=base.SEED)
    train_df = base.augment_numbers(train_df)

    tokenizer = AutoTokenizer.from_pretrained(TEACHER_DIR)
    teacher = AutoModelForSequenceClassification.from_pretrained(TEACHER_DIR).eval()
    student = make_student(teacher)
    n_t = sum(p.numel() for p in teacher.parameters()) / 1e6
    n_s = sum(p.numel() for p in student.parameters()) / 1e6
    print(f"Guru {n_t:.1f}M parameter -> murid {n_s:.1f}M parameter")

    train_dl = base.make_loader(tokenizer, train_df["Teks"], train_df["label"], args.batch_size, True)
    val_dl = base.make_loader(tokenizer, val_df["Teks"], val_df["label"], 32, False)
    test_dl = base.make_loader(tokenizer, test_df["Teks"], test_df["label"], 32, False)

    optim = torch.optim.AdamW(student.parameters(), lr=args.lr, weight_decay=0.01)
    total = len(train_dl) * args.epochs
    sched = get_linear_schedule_with_warmup(optim, int(0.1 * total), total)
    t = args.temperature

    best_acc, best_state = -1.0, None
    for epoch in range(1, args.epochs + 1):
        student.train()
        t0, loss_sum = time.time(), 0.0
        for step, (ids, mask, y) in enumerate(train_dl, 1):
            with torch.no_grad():
                t_logits = teacher(input_ids=ids, attention_mask=mask).logits
            s_logits = student(input_ids=ids, attention_mask=mask).logits
            kd = F.kl_div(F.log_softmax(s_logits / t, -1), F.softmax(t_logits / t, -1),
                          reduction="batchmean") * t * t
            loss = args.alpha * F.cross_entropy(s_logits, y) + (1 - args.alpha) * kd
            loss.backward()
            torch.nn.utils.clip_grad_norm_(student.parameters(), 1.0)
            optim.step()
            sched.step()
            optim.zero_grad()
            loss_sum += loss.item()
            if step % 20 == 0:
                print(f"  epoch {epoch} step {step}/{len(train_dl)} loss {loss_sum / step:.4f}",
                      flush=True)
        gold, pred = base.predict(student, val_dl)
        acc = float((gold == pred).mean())
        print(f"Epoch {epoch}: loss {loss_sum / len(train_dl):.4f} | val acc {acc:.4f} "
              f"| {time.time() - t0:.0f}s", flush=True)
        if acc > best_acc:
            best_acc = acc
            best_state = {k: v.detach().clone() for k, v in student.state_dict().items()}

    student.load_state_dict(best_state)
    gold, pred = base.predict(student, test_dl)
    t_gold, t_pred = base.predict(teacher, test_dl)
    print("\n=== Murid, data test ===")
    print(classification_report(gold, pred, target_names=base.LABELS, digits=4))
    print(f"Akurasi guru di data test yang sama: {(t_gold == t_pred).mean():.4f}")

    STUDENT_DIR.mkdir(parents=True, exist_ok=True)
    student.save_pretrained(STUDENT_DIR)
    tokenizer.save_pretrained(STUDENT_DIR)
    test_df.to_csv(STUDENT_DIR / "test_split.csv", index=False)
    (STUDENT_DIR / "metrics.json").write_text(json.dumps({
        "val_accuracy": best_acc,
        "test_accuracy": float((gold == pred).mean()),
        "teacher_test_accuracy": float((t_gold == t_pred).mean()),
        "layers": KEEP_LAYERS,
    }, indent=2))
    print(f"Murid disimpan di {STUDENT_DIR}")


if __name__ == "__main__":
    main()
