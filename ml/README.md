# Model AI — IndoBERT on-device

Folder ini **hanya untuk development**. Python dipakai untuk melatih dan
mengekspor model. Aplikasi tidak memanggil Python ataupun server: model
dijalankan langsung di HP oleh Flutter lewat ONNX Runtime.

```
[Laptop / Colab, sekali saja]           [HP Android, setiap pesan]
dataset ─▶ train.py ─▶ export_onnx.py ─▶ assets/ai/ ─▶ tokenizer Dart
           (IndoBERT)   (ONNX int8)                    ─▶ ONNX Runtime
                                                       ─▶ skor + LIME (Dart)
```

## Isi folder

| File | Fungsi |
|---|---|
| `train.py` | Fine-tune `indobenchmark/indobert-base-p1` menjadi klasifikasi 3 label: `normal`, `penipuan`, `promo`. Termasuk augmentasi nomor (lihat bawah). |
| `export_onnx.py` | Ekspor ke ONNX, kuantisasi int8, verifikasi akurasi, salin ke `../assets/ai/`. |
| `prune_vocab.py` | Buang baris embedding yang tidak terpakai (vocab_size 50000 → 30521) agar model lebih kecil. |
| `evaluate.py` | Uji model pada set kasus sulit, akurasi per kategori. |
| `buat_data_kontras.py` | Membuat `data/kontras.csv`: normal/promo **dengan** nomor, penipuan **tanpa** nomor. |
| `eval/kasus_sulit.csv` | 50 pesan jebakan yang **tidak pernah dilatih** (dibuang otomatis jika bocor ke data latih). |
| `data/whatsapp_tambahan.csv` | Contoh pesan gaya WhatsApp (**sintetis**, ditulis manual) agar model mengenal pesan panjang. |
| `data/dataset_sms_spam_v1.csv` | Dataset SMS Spam Indonesia (1.143 SMS), diunduh otomatis oleh `train.py`. |
| `requirements.txt` | Paket Python untuk development. |

Hasil yang dipakai aplikasi (dibuat oleh `export_onnx.py`):

```
assets/ai/
├── indobert_se_<hash>.onnx   model int8
├── vocab.txt                 kosakata WordPiece untuk tokenizer Dart
├── config.json               label, panjang token maksimum, nama file model
└── fixtures.json             contoh hasil Python untuk test kesesuaian Dart
```

## Hasil model saat ini

### Versi 3.1 (sekarang) — vocab dipangkas (`prune_vocab.py`)

Config IndoBERT memakai `vocab_size=50000`, padahal tokenizer hanya punya
30.521 token, jadi 19.479 baris embedding tidak pernah terjangkau. Baris itu
dibuang; output model **identik** (selisih probabilitas 0, kasus sulit tetap
48/50). Ukuran ONNX int8: 82,3 MB → **67,4 MB**.

`--keep N` bisa memangkas lebih jauh (token jarang dibuang), tetapi tidak
lossless. Pada kasus sulit: `--keep 20000` mengubah tokenisasi 12% pesan
(label tetap sama); `--keep 10000` membalik 1 dari 50 label. Belum dipakai.

```bash
python prune_vocab.py                              # hasil di output/model_pruned
python export_onnx.py --model-dir output/model_pruned
python evaluate.py --show-errors
```

### Versi 3 — distilasi 6 lapis (`distill.py`)

Model "murid" 6 lapis belajar dari versi 2 (guru, 12 lapis). Lapis murid
disalin dari lapis guru 0,2,4,7,9,11; loss = 0,5·CE + 0,5·KL(T=2).
Tokenizer/vocab sama, jadi kode Dart tidak berubah.

| | Guru (v2) | **Murid (v3)** |
|---|---|---|
| Ukuran ONNX int8 | 125,2 MB | **82,3 MB** |
| Inferensi 1 pesan (CPU laptop) | 9,2 ms | **4,5 ms** |
| LIME 100 sampel (CPU laptop) | 0,64 s | **0,33 s** |
| Data test (145) | 90,3% | **91,0%** |
| Set kasus sulit (50) | 94% | **96%** |

```bash
python distill.py                                  # ±25 menit di CPU
python export_onnx.py --model-dir output/model_student
python evaluate.py --show-errors
```

### Versi 2 — dengan data kontras & augmentasi nomor

Masalah versi 1: di dataset SMS, 52% pesan penipuan memuat nomor HP/rekening
tetapi pesan normal hanya 1%, sehingga model belajar "ada nomor = penipuan".

Perbaikan: `data/kontras.csv` (258 pesan sintetis) + augmentasi nomor saat
training. Data: 1.448 pesan unik, split 80/10/10, train 1.158 + 459 augmentasi.
Dilatih di CPU laptop, 4 epoch, ±85 menit.

**Set kasus sulit** (`eval/kasus_sulit.csv`, 50 pesan, tidak pernah dilatih):

| Kategori | Versi 1 | Versi 2 |
|---|---|---|
| normal dengan nomor (20) | 30% | **90%** |
| penipuan tanpa nomor (12) | 0% | **100%** |
| penipuan dengan nomor (8) | 100% | 87,5% |
| promo dengan nomor (5) | 40% | **100%** |
| normal tanpa nomor (5) | 100% | 100% |
| **Total** | **42%** | **94%** |

Data test standar (145 pesan): akurasi 90,3% (penipuan F1 86,1%), val 97,9%.
Tidak sebanding langsung dengan 95,8% versi 1 karena test versi 2 ikut
memuat pesan kontras yang lebih sulit.

Catatan kejujuran: set kasus sulit dan data kontras ditulis oleh orang yang
sama, jadi skor 94% kemungkinan sedikit optimistis. Uji dengan pesan asli.

### Versi 1

Akurasi test 95,8% (119 pesan SMS), tetapi hanya 42% di set kasus sulit.

### Performa di HP (Infinix X6833B, Android 14, model versi 1)

- ONNX int8: 125 MB (fp32 498 MB), prediksi 100% sama dengan PyTorch.
- Muat model 3–6 dtk, prediksi 90–300 ms, prediksi + LIME (100 sampel) 7–15 dtk.

## Label & skor di aplikasi

- Skor risiko = probabilitas label **`penipuan`**.
- Ambang: ≥ 0,75 `MALICIOUS`, ≥ 0,50 `HIGH RISK`, ≥ 0,25 `SUSPICIOUS`, selain itu `SAFE`.
- `promo` (iklan operator/toko) **tidak** dihitung sebagai social engineering,
  tapi probabilitasnya tetap ditampilkan di halaman detail.
- Penjelasan = **LIME** sungguhan (implementasi Dart di
  `lib/services/ai/lime_text_explainer.dart`): 100 variasi pesan, kernel
  eksponensial, regresi Ridge berbobot. Bobot `+` mendorong ke penipuan,
  `−` mendorong ke aman.

## Melatih ulang model

### Opsi A — di laptop (CPU, gratis)

```bash
cd ml
python -m venv .venv
.venv\Scripts\activate            # Windows
pip install torch --index-url https://download.pytorch.org/whl/cpu
pip install -r requirements.txt
python buat_data_kontras.py       # data kontras (sekali saja)
python train.py                   # ~25–50 menit di CPU
python export_onnx.py
python evaluate.py --show-errors  # cek kasus sulit
```

### Opsi B — Google Colab (GPU gratis, lebih cepat)

1. Buka <https://colab.research.google.com>, *Runtime → Change runtime type → T4 GPU*.
2. Upload folder `ml/` (atau zip lalu ekstrak), kemudian jalankan:

   ```
   %cd ml
   !pip install -q transformers accelerate onnx onnxruntime onnxscript
   !python buat_data_kontras.py
   !python train.py
   !python export_onnx.py
   !python evaluate.py --show-errors
   ```
3. Unduh folder `assets/ai/` hasil Colab dan timpa `assets/ai/` di project.

### Setelah model baru

```bash
flutter test                                              # termasuk cek tokenizer
flutter test integration_test/indobert_on_device_test.dart -d <device_id>
flutter build apk --release
```

## Melatih ulang dari koreksi di HP (cara termudah mengumpulkan data asli)

1. Di aplikasi: buka **Riwayat** → ketuk entri yang hasilnya salah →
   **Hasil ini salah? → Koreksi** → pilih label yang benar.
2. **Pengaturan → Data Koreksi → Ekspor koreksi pesan (CSV)** →
   simpan `koreksi_pesan.csv`, salin ke `ml/data/`.
3. `python train.py` lalu `python export_onnx.py` (atau `distill.py` dulu
   untuk model 6 lapis). Semua `*.csv` di `ml/data/` otomatis ikut dilatih.
4. **Jangan** salin pesan dari `eval/kasus_sulit.csv` ke data latih —
   `train.py` otomatis membuangnya agar set uji tetap jujur.

Koreksi APK: ekspor `koreksi_apk.csv` → `ml/malware/data/` →
`python train_malware.py` (lihat `ml/malware/README.md`).

Isi koreksi adalah pesan WhatsApp asli: hapus nama, nomor HP, dan nomor
rekening yang bukan milik pelaku sebelum dibagikan ke orang lain.

## Menambah data sendiri (sangat disarankan)

Buat file CSV baru di `ml/data/` (nama bebas), format sama:

```csv
Teks,label
"isi pesan penipuan yang Anda terima",1
"isi pesan biasa / normal",0
"isi pesan promo operator atau toko",2
```

Semua `*.csv` di `ml/data/` otomatis ikut dilatih. Pesan WhatsApp asli yang
Anda kumpulkan akan menaikkan akurasi jauh lebih banyak daripada data sintetis.
Hapus data pribadi (nama, nomor HP, nomor rekening) sebelum dipakai.

## Batasan

- Dataset kecil (±1.200 pesan) dan sebagian besar SMS lama (2015-an), jadi
  cocok untuk prototipe/tugas akhir, belum untuk produksi.
- `whatsapp_tambahan.csv` adalah data sintetis; jangan dilaporkan sebagai data asli.
- Hasil model bersifat probabilistik — "berisiko" bukan bukti mutlak penipuan.
- Model memotong pesan ke 256 token (±180 kata); bagian setelahnya diabaikan.
