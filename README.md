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

## Menjalankan

Project ini berisi kode aplikasi, tetapi folder platform Android belum dibuat.
Jalankan perintah berikut dari folder project menggunakan Flutter SDK 3.27+ dan
Android toolchain yang sudah terpasang:

```bash
flutter create . --platforms=android
flutter pub get
flutter run
```

Jika `flutter` tidak dikenali, tambahkan folder `bin` dari Flutter SDK ke
`PATH`, buka terminal baru, lalu cek dengan `flutter doctor`.

Build APK debug:

```bash
flutter build apk --debug
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
