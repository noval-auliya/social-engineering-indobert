# Dokumentasi — Social Engineering Detector

Aplikasi Android (Flutter) untuk mendeteksi **pesan WhatsApp bermuatan social
engineering** dan **risiko malware pada file APK**. Seluruh analisis berjalan
**di HP**: tidak ada server, tidak butuh internet.

| Dokumen | Isi | Untuk siapa |
|---|---|---|
| [01 — Setup](01-setup.md) | Install Flutter, Android SDK, Java, Python; clone & siapkan project | Developer baru |
| [02 — Menjalankan Project](02-menjalankan-project.md) | Run di emulator/HP, test, build APK, latih ulang model | Semua developer |
| [03 — Tech Spec](03-tech-spec.md) | Stack, kebutuhan sistem, model AI, aturan skor, batasan | Developer, reviewer |
| [04 — Struktur Project](04-struktur-project.md) | Isi setiap folder dan file penting | Developer |
| [05 — Flow](05-flow.md) | Alur analisis pesan, scan otomatis WhatsApp, analisis APK, koreksi, pipeline ML | Developer |
| [06 — ERD & Data](06-erd.md) | Entitas data, relasi, dan format penyimpanan lokal | Developer |
| [07 — Integrasi IndoBERT & LIME](07-integrasi-indobert-lime.md) | Kode yang menghubungkan IndoBERT dan LIME di menu Pesan; apa yang dipakai menu Malware | Developer, penguji |

## Ringkasan 30 detik

```
┌──────────────────────────── HP Android ─────────────────────────────┐
│                                                                     │
│  Notifikasi WhatsApp ──▶ WaNotificationListener.kt ──▶ antrean      │
│                                                        │            │
│  Pesan diketik/ditempel ─────────────┐                 ▼            │
│                                      ▼          Flutter (Dart)      │
│                          IndoBERT ONNX int8 ──▶ skor risiko         │
│                          + LIME              ──▶ kata pemicu        │
│                                                                     │
│  File APK ──▶ ApkAnalyzer.kt ──▶ MalwareDetector (ML + aturan       │
│                (izin, DEX,         + sertifikat resmi) ──▶ skor 0–100│
│                 sertifikat)                                         │
│                                                                     │
│  Riwayat, pengaturan, koreksi ──▶ SharedPreferences (lokal)         │
└─────────────────────────────────────────────────────────────────────┘

Folder ml/ (Python, hanya di PC developer): melatih & mengekspor model ke assets/.
```

## Mulai cepat

Jika Flutter dan Android Studio sudah terpasang:

```bash
git clone <url-repo> social_engineering_detector
cd social_engineering_detector
git lfs pull          # model .onnx disimpan dengan Git LFS
flutter pub get
flutter run
```

Detail lengkap ada di [01 — Setup](01-setup.md) dan
[02 — Menjalankan Project](02-menjalankan-project.md).

## Dokumen terkait

- [../README.md](../README.md) — ringkasan fitur
- [../ml/README.md](../ml/README.md) — riwayat versi & hasil model teks
- [../ml/malware/README.md](../ml/malware/README.md) — detail model malware APK
