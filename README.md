# Social Engineering Detector (Flutter — UI Demo)

Tampilan aplikasi mobile untuk **deteksi social engineering pada pesan WhatsApp**
dan **visualisasi risiko malware Android**, dibangun dari dokumentasi build.

> **Analisis pesan memakai IndoBERT + LIME yang berjalan langsung di HP**
> (ONNX Runtime, tanpa server, tanpa internet). Lihat [ml/README.md](ml/README.md)
> untuk cara melatih ulang model. Jika model gagal dimuat, aplikasi memakai
> heuristik kata kunci sebagai cadangan (ditandai "Kata kunci (cadangan)").
>
> **Analisis malware APK juga di HP:** manifest, kode DEX, dan sertifikat APK
> dibaca oleh `ApkAnalyzer.kt`, lalu dinilai oleh model ML (dataset TUANDROMD)
> + aturan indikator perilaku + verifikasi sertifikat aplikasi resmi. Lihat
> [ml/malware/README.md](ml/malware/README.md).

## Fitur (tampilan)

- **Dashboard** — total analisis, kartu statistik (aman/mencurigakan/berisiko),
  pie chart distribusi, daftar analisis terakhir.
- **Analisis Pesan WhatsApp** — ketik/tempel pesan → skor risiko (gauge),
  label, dan penjelasan **LIME** (bar bobot kata). Input berbeda = hasil berbeda.
- **Analisis Malware** — pilih sample / file APK → risk score 0–100, level
  (LOW/MEDIUM/HIGH/CRITICAL), daftar indikator izin, bar chart keparahan.
- **Riwayat** — gabungan hasil pesan & APK, bisa dihapus.
- **Pengaturan** — tema terang/gelap/sistem, opsi privasi (dummy).

## Dokumentasi

Dokumentasi lengkap ada di folder [docs/](docs/README.md):
[setup](docs/01-setup.md) · [menjalankan project](docs/02-menjalankan-project.md) ·
[tech spec](docs/03-tech-spec.md) · [struktur](docs/04-struktur-project.md) ·
[flow](docs/05-flow.md) · [ERD & data](docs/06-erd.md).

## Menjalankan

```bash
git lfs pull        # model .onnx disimpan dengan Git LFS
flutter pub get
flutter run
```

Build APK rilis (per arsitektur, lebih kecil):

```bash
flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64 --obfuscate --split-debug-info=build/symbols
```

## Struktur

```
lib/
├── main.dart
├── core/        (theme, constants)
├── models/      (analysis_result, lime_explanation, malware_result, history_item)
├── services/    (analysis_service, malware_service, mock_data)  ← logika dummy
├── providers/   (Riverpod: analysis, malware, history, settings)
├── features/    (dashboard, whatsapp_analysis, malware_analysis, history, settings)
└── widgets/     (risk_gauge, lime_word, stat_tile, loading_widget)
```

## Arsitektur AI (on-device)

```
lib/services/ai/
├── bert_tokenizer.dart        WordPiece IndoBERT (identik dengan HuggingFace)
├── indobert_classifier.dart   ONNX Runtime: teks -> probabilitas normal/penipuan/promo
└── lime_text_explainer.dart   LIME: kata mana yang mendorong prediksi
assets/ai/                     model int8 + vocab + config (dari ml/export_onnx.py)
ml/                            Python, hanya untuk training & ekspor
```

Test di HP sungguhan (kesesuaian dengan Python + waktu inferensi):

```bash
flutter test integration_test/indobert_on_device_test.dart -d <device_id>
```

## Catatan

Sistem deteksi bersifat probabilistik. Label "berisiko" **bukan** bukti mutlak
adanya serangan — gunakan sebagai indikasi, bukan vonis.
