# 03 — Technical Specification

## 1. Ringkasan

| | |
|---|---|
| Nama | Social Engineering Detector |
| Platform | Android (Flutter) |
| Package ID | `com.example.social_engineering_detector` *(ganti sebelum rilis publik)* |
| Versi | `1.0.0+2002` (`pubspec.yaml`) |
| Arsitektur | Aplikasi **offline-first, on-device**. Tanpa backend, tanpa akun. |
| Bahasa UI | Indonesia |

### Tujuan

1. Mendeteksi pesan WhatsApp bermuatan **social engineering** (penipuan,
   phishing, hadiah palsu, permintaan OTP, dsb.) dan menjelaskan **kata apa**
   yang memicu penilaian.
2. Menilai **risiko malware** sebuah file APK sebelum dipasang.
3. Semua pemrosesan terjadi **di HP**: isi pesan dan APK tidak pernah
   meninggalkan perangkat.

### Di luar cakupan

- Tidak memblokir pesan atau aplikasi — hanya memberi indikasi.
- Tidak menjalankan APK (analisis **statis** saja).
- Tidak ada sinkronisasi cloud / multi-perangkat.
- Hasil bersifat **probabilistik**; label "berisiko" bukan bukti mutlak.

---

## 2. Tech stack

### Aplikasi (Flutter / Dart)

| Lapisan | Teknologi | Versi |
|---|---|---|
| Framework | Flutter | 3.47 (Dart 3.13) |
| State management | `flutter_riverpod` | ^2.5.1 (`StateNotifier`, `Provider`, `FutureProvider`) |
| Inferensi AI | `flutter_onnxruntime` → ONNX Runtime Android | 1.9.0 → ORT 1.28 |
| Grafik | `fl_chart` | ^0.69.0 |
| Penyimpanan lokal | `shared_preferences` | ^2.3.2 |
| Pilih / simpan file | `file_picker` | 13.3.0 |
| Izin runtime | `permission_handler` | ^11.3.1 |
| Format tanggal/angka | `intl` | ^0.19.0 |
| Font | Plus Jakarta Sans (SIL OFL 1.1, `licenses/`) | — |

### Native Android (Kotlin)

| Komponen | Fungsi |
|---|---|
| `WaNotificationListener` | `NotificationListenerService` yang membaca notifikasi WhatsApp / WhatsApp Business |
| `WaListenerStore` | Antrean pesan + konfigurasi listener (SharedPreferences native) |
| `BackgroundScanner` | Menyalakan mesin Flutter tanpa layar untuk scan saat aplikasi tertutup |
| `ApkAnalyzer` | Membaca manifest, tabel method DEX, sertifikat, SHA-256 dari file APK |
| `RiskNotifier` | Notifikasi sistem untuk pesan berisiko |
| `AppChannels` | Mendaftarkan MethodChannel / EventChannel di setiap mesin Flutter |

### Pipeline ML (Python, hanya di PC developer)

PyTorch, HuggingFace `transformers` 5.x, `onnx`, `onnxruntime` (kuantisasi),
`scikit-learn`, `pandas`. Lihat `ml/requirements.txt`.

---

## 3. Kebutuhan sistem (perangkat pengguna)

| Item | Nilai |
|---|---|
| Android minimum | **7.0 (API 24)** |
| Target SDK | 36 (Android 16) |
| Arsitektur CPU | `arm64-v8a`, `armeabi-v7a` |
| 16 KB page size (Android 15+) | Didukung — semua native library ber-alignment ≥ 16 KB |
| Ukuran APK | ±95 MB (arm64) / ±85 MB (arm32) |
| RAM | Perkiraan ±150 MB saat model aktif (belum diukur di HP); disarankan HP ≥ 3 GB |
| Internet | Tidak dibutuhkan |

### Perbedaan perilaku per versi Android

| Versi | Catatan |
|---|---|
| 7.0 – 10 | Pantau WhatsApp memakai teks `bigText` notifikasi (bisa berupa ringkasan) |
| 11+ | Pantau WhatsApp membaca `MessagingStyle`: pesan utuh per pengirim |
| 13+ | Izin `POST_NOTIFICATIONS` diminta saat peringatan diaktifkan |

### Izin Android

| Izin | Alasan |
|---|---|
| `POST_NOTIFICATIONS` | Peringatan pesan berisiko (Android 13+) |
| `BIND_NOTIFICATION_LISTENER_SERVICE` | Dideklarasikan pada service; pengguna mengaktifkan *Akses notifikasi* secara manual |

Aplikasi **tidak** meminta izin SMS, kontak, lokasi, atau penyimpanan. File
APK dibaca lewat *Storage Access Framework* (`file_picker`).

---

## 4. Modul AI #1 — Deteksi social engineering pada pesan

### Model

| Properti | Nilai |
|---|---|
| Basis | `indobenchmark/indobert-base-p1` |
| Arsitektur | BERT, **6 lapis** (didistilasi dari 12 lapis; lapis 0,2,4,7,9,11) |
| Hidden size | 768, 12 attention head |
| Vocab | 30.521 token WordPiece (embedding dipangkas dari 50.000 baris) |
| Kelas | `normal` (0), `penipuan` (1), `promo` (2) |
| Format | ONNX opset 17, kuantisasi dinamis **int8** |
| Ukuran | ±67 MB (`assets/ai/indobert_se_<hash>.onnx`) |
| Input | `input_ids`, `attention_mask` — int32 `[batch, seq]` |
| Output | `probs` — float `[batch, 3]` (softmax) |
| Panjang maksimum | 256 token (`config.json → max_len`) |
| Akurasi | Data test 91,0% (145 pesan); set kasus sulit 96% (48/50) |

### Tokenizer

`lib/services/ai/bert_tokenizer.dart` adalah implementasi WordPiece di Dart
yang **identik** dengan tokenizer HuggingFace (lowercase, strip accent,
pemisahan tanda baca, greedy longest-match). Kesesuaiannya dijaga oleh
`test/bert_tokenizer_test.dart` terhadap `assets/ai/fixtures.json`.

### Skor dan level risiko

`score` = probabilitas kelas `penipuan`.

| Skor | `RiskLevel` | Label | Label halus |
|---|---|---|---|
| < 0,25 | `safe` | SAFE | Aman |
| 0,25 – < 0,50 | `suspicious` | SUSPICIOUS | Mencurigakan |
| 0,50 – < 0,75 | `high` | HIGH RISK | Berisiko Tinggi |
| ≥ 0,75 | `malicious` | MALICIOUS | Terindikasi Serangan |

`confidence` = probabilitas tertinggi di antara ketiga kelas.

### Penjelasan (LIME)

`lime_text_explainer.dart` — port dari `lime.lime_text.LimeTextExplainer`:

| Parameter | Nilai |
|---|---|
| Sampel perturbasi | 100 (`AnalysisService.limeSamples`) |
| Kernel | eksponensial, lebar 25, jarak kosinus |
| Regresi | Ridge berbobot, α = 1,0 |
| Fitur ditampilkan | 6 kata teratas |
| Batch inferensi | 16 |

Karena LIME butuh ±100 inferensi (5–15 detik di HP), analisis dibuat **dua
tahap**: skor tampil dulu (±0,1 detik), penjelasan dihitung menyusul. Untuk
scan otomatis, LIME baru dihitung saat pengguna membuka detail.

### Cadangan (fallback)

Jika model gagal dimuat atau inferensi error, `AnalysisService` memakai
**heuristik kata kunci** (33 kata berbobot + jumlah tanda seru). Hasilnya
ditandai engine `Kata kunci (cadangan)` dan status ini tampil di Pengaturan.

---

## 5. Modul AI #2 — Risiko malware APK

### Ekstraksi fitur (`ApkAnalyzer.kt`)

- Izin dari manifest (`PackageManager.getPackageArchiveInfo`)
- Referensi method API dari tabel `method_ids` di `classes*.dex`
  (parser DEX ringan, hanya API yang dipakai model)
- Flag: `hidden_dex` (dex/jar tersembunyi di luar root), `debug_cert`, dsb.
- SHA-256 sertifikat penanda tangan + subject
- SHA-256 file APK

Berjalan di thread terpisah (`Executors.newSingleThreadExecutor`).

### Penilaian (`MalwareDetector`, Dart)

1. **Regresi logistik** — `assets/malware/model.json`, dilatih dari
   TUANDROMD (4.464 APK) + KronoDroid (78.137 APK). Fitur: izin + 27 API.
2. **Aturan perilaku** — `assets/malware/rules.json` (mis. accessibility +
   overlay, pencuri SMS, dropper).
3. **Sertifikat resmi** — `assets/malware/trusted_signers.json`. Nama paket
   cocok + sertifikat cocok → resmi; nama paket cocok + sertifikat beda →
   aplikasi palsu/mod.

```
p_ML    = sigmoid(intercept + Σ bobot fitur yang ada)
faktor  = clamp(reference_permissions / jumlah_izin, min_factor, 1)
poin    = Σ poin_aturan × (faktor jika scaled, 1 jika tidak)
skor    = round(100 × (1 − (1 − p_ML) × (1 − min(poin,100)/100)))
skor    = min(skor, trusted_cap)   jika resmi terverifikasi
```

| Skor | `Severity` |
|---|---|
| 0 – 30 | LOW |
| 31 – 60 | MEDIUM |
| 61 – 80 | HIGH |
| 81 – 100 | CRITICAL |

Logika Dart identik dengan `ml/malware/evaluate_apk.py`, dijaga oleh
`test/malware_detector_test.dart`.

---

## 6. Scan otomatis WhatsApp

| Aspek | Spesifikasi |
|---|---|
| Sumber | Notifikasi dari `com.whatsapp` dan `com.whatsapp.w4b` |
| Filter | Bukan ringkasan grup; panjang ≥ `minLength` (default 150 karakter); diterima setelah pemantauan aktif |
| Deduplikasi | Kunci `paket|percakapan|pengirim|timestamp|hash(teks)`, 500 kunci terakhir |
| Antrean | Maks 200 pesan (SharedPreferences native) |
| Scan saat aplikasi terbuka | Mesin Flutter UI menerima event lalu menguras antrean |
| Scan saat aplikasi tertutup | `BackgroundScanner` menyalakan mesin Flutter headless (`backgroundScanMain`), dimatikan setelah 60 detik tanpa pesan baru |
| Notifikasi | Hanya jika level ≥ HIGH (`risk_alert_policy.dart`) **dan** aplikasi tidak sedang di layar |

---

## 7. Penyimpanan data

Semua data disimpan lokal di SharedPreferences sebagai JSON. Detail skema di
[06 — ERD & Data](06-erd.md).

| Kunci | Isi | Batas |
|---|---|---|
| `settings_v1` | Pengaturan aplikasi | — |
| `history_v1` | Riwayat analisis pesan & APK | 300 entri terbaru |
| `corrections_v1` | Koreksi pengguna ("Hasil ini salah") | 1 per pesan/APK |
| `wa_listener` *(native)* | Antrean & konfigurasi listener | antrean 200, dedup 500 |

Riwayat tidak disimpan jika pengguna mematikan *Simpan riwayat di HP*.

---

## 8. Kebutuhan non-fungsional

| Kategori | Target / Keputusan |
|---|---|
| Privasi | Tidak ada jaringan; data tidak keluar dari HP kecuali pengguna mengekspor CSV koreksi |
| Kecepatan | Skor pesan ±0,1 dtk; LIME 5–15 dtk; inferensi laptop 4,5 ms/pesan |
| Ketahanan | Kegagalan model → fallback kata kunci; kegagalan SharedPreferences → log, aplikasi tetap jalan |
| Baterai | Mesin latar belakang hanya menyala saat ada pesan, mati setelah 60 dtk idle |
| Ukuran | Split per ABI, R8 + shrink resources, `--obfuscate`, vocab dipangkas |
| Kompatibilitas | API 24+, ARM 32/64-bit, 16 KB page size |
| Konsistensi Python↔Dart | Fixture test untuk tokenizer dan detektor malware |

---

## 9. Batasan yang diketahui

- Data latih model pesan kecil (±1.450 pesan, sebagian sintetis); akurasi
  pada gaya bahasa baru belum terjamin.
- Pantau WhatsApp bergantung pada isi notifikasi: pesan di chat yang
  di-*mute*, atau saat WhatsApp sedang terbuka, bisa tidak ter-scan.
- Model malware berbasis izin + API lemah terhadap malware yang mengunduh
  kode saat runtime; aturan perilaku hanya mengurangi celah ini.
- Rilis masih ditandatangani debug key dan memakai package `com.example.*`.
