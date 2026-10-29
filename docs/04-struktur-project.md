# 04 — Struktur Project

## 1. Gambaran tingkat atas

```
social_engineering_detector/
├── lib/                  Kode aplikasi Flutter (Dart)
├── android/              Proyek Android + kode native Kotlin
├── assets/               Model AI, aturan malware, font (ikut dikemas di APK)
├── test/                 Unit & widget test (jalan di PC)
├── integration_test/     Test di HP asli (model ONNX, pembaca APK)
├── ml/                   Pipeline Python: training & ekspor model (tidak masuk APK)
├── docs/                 Dokumentasi ini
├── licenses/             Lisensi font pihak ketiga
├── pubspec.yaml          Dependency, aset, font, versi aplikasi
└── analysis_options.yaml Aturan lint Dart (flutter_lints)
```

## 2. Arsitektur lapisan (lib/)

```
┌────────────────────────────────────────────────────────┐
│ features/   Layar (UI)  — ConsumerWidget               │
│ widgets/    Komponen UI yang dipakai ulang             │
├────────────────────────────────────────────────────────┤
│ providers/  State Riverpod (StateNotifier)             │  ← logika aplikasi
├────────────────────────────────────────────────────────┤
│ services/   Logika domain, AI, platform channel        │
│ models/     Data class + (de)serialisasi JSON          │
├────────────────────────────────────────────────────────┤
│ Platform channel ─▶ Kotlin (android/…/kotlin)          │
│ SharedPreferences, ONNX Runtime, file_picker           │
└────────────────────────────────────────────────────────┘
```

Aturan dependensi: **UI → provider → service → model**. Layar tidak memanggil
service secara langsung untuk mengubah state; semuanya lewat provider.
Service tidak mengenal Riverpod sehingga mudah diuji (dependensi seperti
pemuat model bisa disuntikkan lewat konstruktor).

## 3. `lib/` — rinci

```
lib/
├── main.dart                       Entry point UI + backgroundScanMain (mesin headless)
│
├── core/
│   ├── constants/app_constants.dart   Nama aplikasi, disclaimer
│   └── theme/app_theme.dart           Tema terang/gelap, warna, tipografi
│
├── models/                         Data class murni (tanpa Flutter)
│   ├── analysis_result.dart        Hasil analisis pesan + RiskLevel
│   ├── lime_explanation.dart       Satu kata + bobot LIME
│   ├── malware_result.dart         Hasil analisis APK + Severity + MalwareIndicator
│   ├── history_item.dart           Entri riwayat gabungan (pesan | APK)
│   ├── correction.dart             Koreksi pengguna → data latih
│   └── captured_message.dart       Pesan WhatsApp dari listener native
│
├── providers/
│   └── providers.dart              SEMUA provider Riverpod (lihat tabel di bawah)
│
├── services/
│   ├── analysis_service.dart       Orkestrasi analisis pesan: IndoBERT → LIME, fallback kata kunci
│   ├── ai/
│   │   ├── bert_tokenizer.dart     WordPiece tokenizer (identik HuggingFace)
│   │   ├── indobert_classifier.dart Memuat ONNX & inferensi batch
│   │   └── lime_text_explainer.dart LIME untuk teks
│   ├── malware_service.dart        Panggil ApkAnalyzer.kt → MalwareDetector → MalwareResult
│   ├── malware/
│   │   ├── apk_features.dart       Fitur APK dari Kotlin
│   │   └── malware_detector.dart   Regresi logistik + aturan + sertifikat
│   ├── wa_notification_service.dart Jembatan MethodChannel/EventChannel ke listener WhatsApp
│   ├── risk_alert_policy.dart      Kapan notifikasi dikirim + teksnya
│   ├── protection_score.dart       Skor "perlindungan aktif" di Beranda
│   ├── correction_export.dart      Koreksi → CSV latih
│   ├── local_store.dart            Abstraksi SharedPreferences (+ versi memori untuk test)
│   └── mock_data.dart              Sisa data contoh
│
├── features/                       Satu folder per layar
│   ├── home/home_shell.dart        Kerangka + navigasi bawah, badge, banner scan
│   ├── onboarding/                 Perkenalan (sekali)
│   ├── dashboard/                  Beranda: skor perlindungan, statistik, grafik
│   ├── whatsapp_analysis/          Input pesan + tampilan hasil
│   ├── malware_analysis/           Pilih APK + tampilan hasil
│   ├── history/                    Daftar, filter/cari, detail, kartu koreksi
│   └── settings/                   Tema, privasi, pantau WhatsApp, status AI, ekspor
│
└── widgets/                        risk_gauge, protection_gauge, lime_word,
                                    stat_tile, scan_progress_banner, warm_background, …
```

### Provider (`lib/providers/providers.dart`)

| Provider | Tipe | Tanggung jawab |
|---|---|---|
| `settingsProvider` | `StateNotifier<AppSettings>` | Tema, simpan riwayat, label halus, onboarding; persist `settings_v1` |
| `settingsLoadedProvider` | `FutureProvider<void>` | Gerbang onboarding menunggu pengaturan termuat |
| `historyProvider` | `StateNotifier<List<HistoryItem>>` | Riwayat + retensi 300 + persist `history_v1` + hitung LIME tertunda |
| `correctionsProvider` | `StateNotifier<List<Correction>>` | Koreksi pengguna; persist `corrections_v1` |
| `analysisProvider` | `StateNotifier<AsyncValue<AnalysisResult?>>` | Analisis pesan manual (dua tahap) |
| `malwareProvider` | `StateNotifier<AsyncValue<MalwareResult?>>` | Analisis APK |
| `waMonitorProvider` | `StateNotifier<WaMonitorState>` | Status izin, konfigurasi, dan loop scan otomatis |
| `scanProgressProvider` | `StateProvider<ScanProgress>` | Progres scan untuk banner |
| `unseenHistoryProvider` | `StateProvider<Set<HistoryItem>>` | Entri "BARU" dari scan otomatis |
| `homeTabProvider` | `StateProvider<int>` | Tab aktif (`HomeTab.*`) |
| `dashboardStatsProvider`, `activityStatsProvider` | `Provider` | Statistik turunan dari riwayat |
| `analysisServiceProvider`, `malwareServiceProvider`, `waNotificationServiceProvider`, `localStoreProvider` | `Provider` | Instans service (bisa di-override di test) |
| `aiStatusProvider` | `FutureProvider<AiEngineStatus>` | Status model AI untuk Pengaturan |
| `backgroundEngineProvider` | `Provider<bool>` | `true` di mesin headless |

## 4. `android/`

```
android/
├── app/
│   ├── build.gradle.kts            minSdk/targetSdk dari Flutter, R8, signing
│   ├── proguard-rules.pro          -keep ONNX Runtime (dipanggil via JNI)
│   └── src/main/
│       ├── AndroidManifest.xml     Izin, MainActivity, WaNotificationListener service
│       └── kotlin/com/example/social_engineering_detector/
│           ├── MainActivity.kt          Mesin Flutter UI; tab tujuan dari notifikasi
│           ├── AppChannels.kt           Registrasi semua channel (dipakai 2 mesin)
│           ├── WaNotificationListener.kt Baca notifikasi WhatsApp
│           ├── WaListenerStore.kt       Antrean + dedup + config (SharedPreferences "wa_listener")
│           ├── BackgroundScanner.kt     Mesin Flutter headless saat aplikasi tertutup
│           ├── RiskNotifier.kt          Notifikasi peringatan
│           └── ApkAnalyzer.kt           Ekstraksi fitur APK (manifest, DEX, sertifikat)
├── build.gradle.kts, settings.gradle.kts
└── gradle.properties               Memori JVM Gradle
```

### Platform channel

| Channel | Jenis | Method |
|---|---|---|
| `sed/wa_listener` | MethodChannel | `getStatus`, `openSettings`, `setConfig`, `drain`, `showRiskAlert`, `consumeLaunchTarget`, `backgroundIdle` |
| `sed/wa_listener/events` | EventChannel | Event setiap ada pesan baru di antrean |
| `sed/apk_analyzer` | MethodChannel | `analyze`, `selfApkPath` (untuk integration test) |

## 5. `assets/`

```
assets/
├── ai/                                  ← dibuat oleh ml/export_onnx.py, JANGAN diedit manual
│   ├── indobert_se_<hash>.onnx          Model int8 (Git LFS)
│   ├── vocab.txt                        Vocab WordPiece (baris ke-n = id n)
│   ├── config.json                      Nama file model, label, max_len, lowercase
│   └── fixtures.json                    Contoh token & probabilitas dari Python (untuk test)
├── malware/
│   ├── model.json                       Bobot regresi logistik (ml/malware/train_malware.py)
│   ├── rules.json                       Aturan indikator perilaku (diedit manual)
│   └── trusted_signers.json             SHA-256 sertifikat aplikasi resmi
└── fonts/                               Plus Jakarta Sans (5 ketebalan)
```

## 6. `ml/`

```
ml/
├── train.py              Fine-tune IndoBERT 12 lapis → output/model
├── distill.py            Distilasi ke 6 lapis → output/model_student
├── prune_vocab.py        Pangkas embedding → output/model_pruned
├── export_onnx.py        ONNX int8 + verifikasi + salin ke assets/ai/
├── evaluate.py           Uji set kasus sulit
├── buat_data_kontras.py  Generator data kontras (nomor HP/rekening)
├── data/                 CSV data latih (Teks,label)
├── eval/kasus_sulit.csv  50 pesan uji yang tidak pernah dilatih
├── malware/              Training & evaluasi model malware APK
├── output/               Hasil training (gitignored)
├── .venv/                Virtualenv (gitignored)
└── requirements.txt
```

## 7. `test/` dan `integration_test/`

```
test/
├── bert_tokenizer_test.dart        Dart vs HuggingFace (fixtures.json)
├── malware_detector_test.dart      Dart vs evaluate_apk.py
├── lime_text_explainer_test.dart
├── two_stage_lime_test.dart
├── history_*_test.dart             Persistensi, halaman, cari & paging
├── corrections_test.dart
├── scan_notification_test.dart
├── settings_page_test.dart
├── assets_declared_test.dart
├── widget_test.dart
├── fixtures/                       Data uji
└── screenshots/                    Render semua layar

integration_test/                   Dijalankan di HP: -d <device_id>
├── indobert_on_device_test.dart
└── apk_analyzer_on_device_test.dart
```

## 8. Konvensi

| Hal | Konvensi |
|---|---|
| Bahasa | Komentar, teks UI, dan nama skrip ML dalam Bahasa Indonesia; identifier kode dalam Bahasa Inggris |
| Kunci penyimpanan | Diberi akhiran versi (`_v1`); ubah versi jika format JSON tidak kompatibel |
| Format JSON | `snake_case` untuk kunci yang disimpan |
| Model ONNX | Nama file memuat hash isi (`indobert_se_<hash>.onnx`) agar cache plugin tidak memakai model lama |
| Logika ganda Python↔Dart | Wajib punya fixture test (tokenizer, detektor malware) |
| Test | Service menerima dependensi lewat konstruktor; `MemoryLocalStore` menggantikan SharedPreferences |
