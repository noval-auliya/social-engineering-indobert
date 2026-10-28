# Panduan Setup — Social Engineering Detector (Flutter)

Panduan ini untuk Windows. Tujuannya: dari nol sampai aplikasi jalan di
emulator/HP Android. Project ini **UI + data dummy**, jadi tidak butuh backend.

> Catatan: folder `android/` **belum ada** di project ini. Folder tersebut
> dibuat otomatis oleh perintah `flutter create .` pada langkah 4 — perintah itu
> **tidak** menimpa folder `lib/` yang sudah berisi kode aplikasi.

---

## 1. Install Flutter SDK

1. Unduh Flutter SDK (stable) dari <https://docs.flutter.dev/get-started/install/windows>.
2. Ekstrak ke lokasi tanpa spasi, misalnya `C:\src\flutter`
   (hindari `C:\Program Files`).
3. Tambahkan `C:\src\flutter\bin` ke **PATH**:
   - Buka *Edit the system environment variables* → *Environment Variables*.
   - Pada **User variables** → pilih `Path` → *Edit* → *New* →
     masukkan `C:\src\flutter\bin` → OK.
4. Tutup semua terminal, buka PowerShell baru, lalu cek:

   ```bash
   flutter --version
   ```

Disarankan **Flutter 3.27 atau lebih baru** (project memakai API terbaru seperti
`Color.withValues`, `CardThemeData`, `surfaceContainerHighest`).

---

## 2. Install Android toolchain

Pilih salah satu:

**A. Android Studio (paling mudah)**
1. Install Android Studio: <https://developer.android.com/studio>.
2. Saat *setup wizard*, pastikan ikut terinstall:
   - Android SDK
   - Android SDK Command-line Tools
   - Android SDK Build-Tools
   - Android Emulator + 1 system image (mis. API 34)
3. Buat emulator: *Device Manager* → *Create Device* → pilih Pixel → unduh image → Finish.

**B. Tanpa Android Studio** — pakai HP Android asli (lihat langkah 5B).

Lalu setujui lisensi:

```bash
flutter doctor --android-licenses
```

Ketik `y` untuk semua.

---

## 3. Cek kesiapan

```bash
flutter doctor
```

Pastikan baris berikut ✓ (centang):

```
[√] Flutter
[√] Android toolchain
[√] Android Studio    (jika pakai opsi A)
```

Abaikan centang untuk Chrome/Visual Studio jika Anda hanya menargetkan Android.

---

## 4. Siapkan project ini

Masuk ke folder project:

```bash
cd C:\project\test-app\social_engineering_detector
```

Generate scaffolding platform (membuat `android/`, `ios/`, dll **tanpa**
menghapus `lib/`, `pubspec.yaml`, atau `test/`):

```bash
flutter create .
```

> Jika ingin membatasi ke Android saja:
> `flutter create . --platforms=android`

Ambil dependency:

```bash
flutter pub get
```

Periksa kode (opsional tapi disarankan):

```bash
flutter analyze
flutter test
```

---

## 5. Jalankan aplikasi

Cek perangkat yang terdeteksi:

```bash
flutter devices
```

**5A. Lewat emulator**
- Jalankan emulator dari Android Studio *Device Manager*, atau:

  ```bash
  flutter emulators
  flutter emulators --launch <emulator_id>
  ```
- Lalu:

  ```bash
  flutter run
  ```

**5B. Lewat HP Android asli**
1. Di HP: *Settings* → *About phone* → ketuk *Build number* 7x untuk membuka
   *Developer options*.
2. Aktifkan **USB debugging**.
3. Sambungkan HP via USB, pilih *Allow* saat muncul prompt.
4. Jalankan:

   ```bash
   flutter devices
   flutter run -d <device_id>
   ```

Saat aplikasi jalan, tekan `r` (hot reload) atau `R` (hot restart) di terminal.

---

## 6. Build APK

Debug (cepat, untuk uji coba):

```bash
flutter build apk --debug
```

Output: `build\app\outputs\flutter-apk\app-debug.apk`

Release (lebih ringan; untuk produksi perlu signing — lihat dok. utama bagian 40):

```bash
flutter build apk --release
```

Output: `build\app\outputs\flutter-apk\app-release.apk`

---

## 7. Troubleshooting

| Masalah | Solusi |
|---|---|
| `flutter: not recognized` | PATH belum ditambah / terminal belum di-restart (langkah 1). |
| `cmdline-tools component is missing` | Buka Android Studio → SDK Manager → SDK Tools → centang *Android SDK Command-line Tools* → Apply. |
| `Android license status unknown` | Jalankan `flutter doctor --android-licenses`. |
| Error API seperti `withValues` / `CardThemeData` | Flutter terlalu lama — `flutter upgrade` ke 3.27+. |
| `file_picker` error di desktop | Normal; fitur pilih file ditujukan untuk Android. Pakai chip *sample* di halaman Malware. |
| Emulator lambat | Aktifkan hardware acceleration (HAXM/Hyper-V) atau pakai HP asli (5B). |

---

## 8. Ringkas (copy-paste)

Setelah Flutter + Android toolchain siap:

```bash
cd C:\project\test-app\social_engineering_detector
flutter create .
flutter pub get
flutter run
```

Selesai — aplikasi akan terbuka di halaman **Dashboard**. Coba buka tab **Pesan**,
tempel contoh pesan, tekan **Analisis Pesan**, dan lihat skor risiko + penjelasan
LIME. Semua data bersifat **dummy/indikatif**.
