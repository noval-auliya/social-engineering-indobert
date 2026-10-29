# 02 — Menjalankan Project

Pastikan [01 — Setup](01-setup.md) sudah selesai. Semua perintah dijalankan
dari folder root project kecuali disebut lain.

---

## 1. Menjalankan aplikasi (mode debug)

```bash
flutter pub get
flutter devices                 # lihat ID perangkat
flutter run                     # perangkat tunggal
flutter run -d <device_id>      # pilih perangkat
```

Di terminal yang menjalankan aplikasi:

| Tombol | Fungsi |
|---|---|
| `r` | Hot reload (perubahan UI langsung terlihat) |
| `R` | Hot restart (state di-reset) |
| `q` | Keluar |

> Hot reload **tidak** berlaku untuk kode Kotlin (`android/app/src/main/kotlin`)
> dan aset model. Setelah mengubahnya, hentikan dan jalankan `flutter run` lagi.

Mode profile (performa mendekati rilis, untuk mengukur kecepatan inferensi):

```bash
flutter run --profile
```

---

## 2. Mencoba fitur setelah aplikasi terbuka

1. **Onboarding** — tampil sekali saat pertama dibuka.
2. **Pesan** — tempel contoh pesan, tekan *Analisis*. Skor muncul dalam
   ±0,1 detik, penjelasan LIME (kata pemicu) menyusul 5–15 detik.
3. **Pantau WhatsApp** — *Pengaturan* → izinkan **Akses notifikasi** →
   kirim pesan WhatsApp ke HP ini dari nomor lain (minimal 150 karakter,
   bisa diubah di Pengaturan). Pesan muncul di *Riwayat* dengan label "BARU".
4. **APK** — pilih file `.apk` dari penyimpanan HP. APK hanya dibaca, tidak
   dipasang.
5. **Riwayat** — filter (Semua/Pesan/APK/Berisiko), cari, buka detail,
   tandai "Hasil ini salah".
6. **Pengaturan** — status model AI, tema, label halus, ekspor koreksi CSV.

Contoh pesan untuk uji cepat:

```
Selamat! Nomor Anda memenangkan hadiah Rp50.000.000 dari undian resmi.
Segera klaim dengan klik link berikut dan masukkan kode OTP yang kami kirim.
```

---

## 3. Menjalankan test

### Unit & widget test (di PC, tanpa HP)

```bash
flutter test                                  # semua test di test/
flutter test test/bert_tokenizer_test.dart    # satu file
```

Test penting:

| File | Yang diuji |
|---|---|
| `bert_tokenizer_test.dart` | Tokenizer Dart identik dengan HuggingFace (pakai `assets/ai/fixtures.json`) |
| `malware_detector_test.dart` | Skor APK Dart identik dengan `ml/malware/evaluate_apk.py` |
| `two_stage_lime_test.dart` | Alur skor dulu → LIME menyusul |
| `history_persistence_test.dart` | Riwayat tersimpan & dimuat ulang dengan benar |
| `scan_notification_test.dart` | Kebijakan notifikasi pesan berisiko |
| `assets_declared_test.dart` | Semua aset yang dibutuhkan terdaftar di `pubspec.yaml` |
| `screenshots/render_screens_test.dart` | Render setiap layar tanpa error |

### Integration test (di HP Android asli)

Menguji model ONNX dan pembaca APK sungguhan di perangkat:

```bash
flutter test integration_test/indobert_on_device_test.dart -d <device_id>
flutter test integration_test/apk_analyzer_on_device_test.dart -d <device_id>
```

### Analisis statis

```bash
flutter analyze                         # lint Dart
```

Android Lint (mendeteksi pemanggilan API yang tidak ada di Android versi lama):

```powershell
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
cd android
.\gradlew.bat :app:lintDebug
# laporan: build/app/reports/lint-results-debug.txt
```

> Gunakan `lintDebug`, bukan `lintRelease`: menjalankan Gradle langsung untuk
> varian release gagal karena `integration_test` hanya terdaftar di debug.
> Pemeriksaan `NewApi` sama untuk keduanya. Error `PropertyEscape` pada
> `local.properties` boleh diabaikan.

---

## 4. Build APK rilis

### Untuk dibagikan langsung (sideload)

```bash
flutter build apk --release --split-per-abi \
  --target-platform android-arm,android-arm64 \
  --obfuscate --split-debug-info=build/symbols
```

Hasil di `build/app/outputs/flutter-apk/`:

| File | Untuk HP | Ukuran ± |
|---|---|---|
| `app-arm64-v8a-release.apk` | Hampir semua HP modern (64-bit) | 95 MB |
| `app-armeabi-v7a-release.apk` | HP lama / murah (32-bit) | 85 MB |

Kenapa tidak `flutter build apk` biasa? APK universal memuat native library
untuk 3 arsitektur sekaligus (±203 MB), padahal satu HP hanya memakai satu.

> Simpan folder `build/symbols/` untuk setiap rilis. Tanpa folder itu, stack
> trace crash dari versi ter-obfuscate tidak bisa dibaca
> (`flutter symbolize`).

### Untuk Google Play

```bash
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols
```

Play Store otomatis mengirim versi yang sesuai arsitektur tiap HP.

### Signing

Saat ini build rilis ditandatangani dengan **debug key**
(`android/app/build.gradle.kts`, `signingConfig = debug`). Sebelum rilis
publik, buat keystore sendiri dan konfigurasikan `signingConfigs.release`.
Jangan commit keystore atau `key.properties` (sudah di `.gitignore`).

### Versi aplikasi

Diatur di `pubspec.yaml`: `version: 1.0.0+2002` → `versionName+versionCode`.
Naikkan angka setelah `+` setiap rilis.

---

## 5. Memasang APK ke HP

```bash
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

Atau salin file APK ke HP lalu buka (izinkan *Install unknown apps*).

Cek arsitektur HP jika ragu:

```bash
adb shell getprop ro.product.cpu.abi     # arm64-v8a / armeabi-v7a
```

---

## 6. Melatih ulang model AI

Butuh lingkungan Python dari [01 — Setup §8](01-setup.md#8-opsional-lingkungan-python-untuk-ml).
Semua perintah dijalankan dari folder `ml/` dengan venv aktif.

### Model pesan (IndoBERT)

```bash
cd ml
python train.py                                         # 1. fine-tune guru 12 lapis
python distill.py                                       # 2. murid 6 lapis (±25 menit CPU)
python prune_vocab.py                                   # 3. buang embedding tak terpakai
python export_onnx.py --model-dir output/model_pruned   # 4. ONNX int8 → assets/ai/
python evaluate.py --show-errors                        # 5. uji set kasus sulit
cd ..
flutter test                                            # 6. tokenizer Dart masih cocok
```

`export_onnx.py` otomatis menulis `assets/ai/` (model ber-hash, `vocab.txt`,
`config.json`, `fixtures.json`) dan menghapus model lama. Nama file model
memuat hash agar plugin ONNX tidak memakai cache model lama.

Menambah data latih: taruh CSV berkolom `Teks,label` (0 normal, 1 penipuan,
2 promo) di `ml/data/`. Koreksi dari aplikasi (*Pengaturan → Ekspor koreksi*)
sudah dalam format ini.

### Model malware APK

```bash
cd ml/malware
python train_malware.py           # → assets/malware/model.json
python evaluate_apk.py <folder>   # uji semua APK di sebuah folder, di PC
```

Detail dataset & aturan: [ml/malware/README.md](../ml/malware/README.md).

---

## 7. Troubleshooting saat menjalankan

| Masalah | Solusi |
|---|---|
| Analisis memakai "Kata kunci (cadangan)" | Model tidak termuat. Cek *Pengaturan* → status AI; pastikan `git lfs pull`. |
| Pesan WhatsApp tidak ter-scan | Izin *Akses notifikasi* belum aktif, pesan < panjang minimum, atau pesan masuk sebelum pemantauan aktif. |
| Notifikasi peringatan tidak muncul | Android 13+: izin notifikasi ditolak. Aktifkan di Pengaturan aplikasi. |
| "Analisis APK hanya tersedia di Android" | Aplikasi dijalankan di platform non-Android (mis. test di PC). |
| Build gagal setelah ganti model | `flutter clean` lalu build ulang. |
| Build release gagal: `package dev.flutter.plugins.integration_test does not exist` | `GeneratedPluginRegistrant.java` masih sisa dari `flutter run`/`flutter test` (debug, ikut plugin dev). Hapus `android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java` (dibuat ulang otomatis) atau `flutter clean`, lalu build ulang. |
| `flutter test` gagal di `bert_tokenizer_test` setelah ekspor | `fixtures.json` dan `vocab.txt` harus dari ekspor yang sama — jalankan ulang `export_onnx.py`. |
