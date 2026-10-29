# 01 — Setup Lingkungan Development

Panduan dari nol sampai project siap dijalankan, untuk **Windows**. Langkah di
macOS/Linux sama, hanya path dan cara mengatur `PATH` yang berbeda.

Ada dua lingkungan:

| Lingkungan | Wajib? | Dipakai untuk |
|---|---|---|
| **Flutter + Android** | Ya | Menjalankan, menguji, dan mem-build aplikasi |
| **Python (ml/)** | Tidak | Hanya jika ingin melatih ulang / mengekspor model AI |

Model yang sudah jadi sudah ada di `assets/`, jadi Python **tidak** dibutuhkan
untuk sekadar menjalankan aplikasi.

---

## 1. Kebutuhan

| Komponen | Versi yang dipakai | Minimum |
|---|---|---|
| Flutter SDK | 3.47.0 (stable) | Dart SDK ≥ 3.3 (lihat `pubspec.yaml`) |
| Android Studio | terbaru | — (dibutuhkan untuk Android SDK + Java) |
| Android SDK Platform | 36 | compileSdk mengikuti Flutter |
| Android Build-Tools | 36.0.0 | — |
| Android NDK | 28.x | otomatis diunduh Gradle |
| Java (JDK) | 17+ (`jbr` bawaan Android Studio) | 17 |
| Git + **Git LFS** | terbaru | wajib, model `.onnx` disimpan di LFS |
| Python *(opsional)* | 3.13 | 3.10 |
| Ruang disk | ±15 GB | SDK + emulator + build |
| RAM PC | 16 GB disarankan | 8 GB (Gradle diset `-Xmx8G`) |

---

## 2. Install Git dan Git LFS

1. Install Git: <https://git-scm.com/download/win>
2. Aktifkan Git LFS (sudah termasuk di Git for Windows):

   ```bash
   git lfs install
   ```

> **Penting:** tanpa Git LFS, file `assets/ai/indobert_se_*.onnx` hanya berupa
> file teks kecil (pointer), model gagal dimuat, dan aplikasi diam-diam memakai
> analisis kata kunci cadangan.

---

## 3. Install Flutter SDK

1. Unduh Flutter (channel **stable**) dari
   <https://docs.flutter.dev/get-started/install/windows>.
2. Ekstrak ke folder **tanpa spasi khusus sistem**, mis. `C:\src\flutter`
   atau `C:\Users\<nama>\Documents\flutter`. Hindari `C:\Program Files`.
3. Tambahkan `<folder-flutter>\bin` ke **PATH**:
   *Edit the system environment variables* → *Environment Variables* →
   *User variables* → `Path` → *Edit* → *New*.
4. Buka terminal **baru**, lalu cek:

   ```bash
   flutter --version
   ```

---

## 4. Install Android Studio dan Android SDK

1. Install Android Studio: <https://developer.android.com/studio>
2. Pada setup wizard, pastikan terpasang:
   - Android SDK Platform (API 36)
   - Android SDK Build-Tools
   - Android SDK Command-line Tools
   - Android Emulator + 1 system image (disarankan juga satu image lama,
     mis. API 24 atau 28, untuk menguji kompatibilitas)
3. Install plugin **Flutter** dan **Dart** di Android Studio (opsional, jika
   tidak memakai VS Code).
4. Setujui lisensi Android:

   ```bash
   flutter doctor --android-licenses
   ```

### Java untuk menjalankan Gradle langsung

`flutter build` / `flutter run` otomatis memakai Java bawaan Android Studio.
Tetapi jika ingin menjalankan `gradlew` langsung (mis. untuk Android Lint),
arahkan `JAVA_HOME` ke folder `jbr`:

```powershell
# PowerShell (sementara, hanya untuk terminal ini)
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
```

---

## 5. Cek kesiapan

```bash
flutter doctor -v
```

Yang harus ✓:

```
[√] Flutter
[√] Android toolchain
[√] Android Studio
[√] Connected device   (setelah emulator/HP tersambung)
```

Centang Chrome / Visual Studio boleh diabaikan karena aplikasi ini hanya
menargetkan Android.

---

## 6. Ambil source code

```bash
git clone <url-repo> social_engineering_detector
cd social_engineering_detector
git lfs pull
flutter pub get
```

Cek bahwa model benar-benar terunduh (harus ±67 MB, bukan beberapa byte):

```bash
ls -la assets/ai/
```

File `android/local.properties` dibuat otomatis oleh Flutter saat build
pertama dan **tidak** di-commit (isinya path SDK di PC masing-masing).

---

## 7. Siapkan perangkat uji

**A. Emulator**

Android Studio → *Device Manager* → *Create Device* → pilih Pixel → pilih
system image → *Finish*. Atau dari terminal:

```bash
flutter emulators
flutter emulators --launch <emulator_id>
```

> Emulator x86_64 bisa dipakai, tetapi APK rilis yang kita distribusikan hanya
> berisi ARM. Gunakan `flutter run` (debug) untuk emulator.

**B. HP Android asli (disarankan)**

1. *Settings* → *About phone* → ketuk *Build number* 7× untuk membuka
   *Developer options*.
2. Aktifkan **USB debugging**.
3. Sambungkan via USB, pilih *Allow* pada prompt di HP.
4. Cek: `flutter devices`.

Fitur **pantau WhatsApp** dan **analisis APK** hanya bisa diuji penuh di HP
asli yang memiliki WhatsApp.

---

## 8. (Opsional) Lingkungan Python untuk `ml/`

Hanya jika ingin melatih ulang model, memangkas vocab, atau mengekspor ONNX.

```bash
cd ml
python -m venv .venv
.venv\Scripts\activate                 # Windows
# source .venv/bin/activate            # macOS/Linux

# torch versi CPU (jauh lebih kecil dari versi CUDA)
pip install torch --index-url https://download.pytorch.org/whl/cpu
pip install -r requirements.txt
```

Folder `ml/.venv/` dan `ml/output/` sudah ada di `.gitignore`.

Cek:

```bash
python -c "import torch, transformers, onnxruntime; print('OK')"
```

> Model PyTorch hasil training (`ml/output/model*`) **tidak** ada di git karena
> besar. Untuk latih ulang dari awal, jalankan `train.py` (lihat
> [02 — Menjalankan Project](02-menjalankan-project.md#6-melatih-ulang-model-ai)).

---

## 9. Troubleshooting setup

| Masalah | Penyebab / Solusi |
|---|---|
| `flutter: not recognized` | `PATH` belum berisi `<flutter>\bin`, atau terminal belum dibuka ulang. |
| `cmdline-tools component is missing` | Android Studio → SDK Manager → SDK Tools → centang *Command-line Tools*. |
| `Android license status unknown` | `flutter doctor --android-licenses`. |
| `JAVA_HOME is not set` saat `gradlew` | Set `JAVA_HOME` ke `...\Android Studio\jbr` (langkah 4). |
| Aplikasi menampilkan "Kata kunci (cadangan)" | Model tidak termuat — biasanya `git lfs pull` belum dijalankan. Cek status di *Pengaturan*. |
| Gradle kehabisan memori | Turunkan `-Xmx8G` di `android/gradle.properties` sesuai RAM PC. |
| Peringatan "Built-in Kotlin / KGP" saat build | Hanya peringatan untuk versi Flutter mendatang (plugin pihak ketiga belum migrasi). Aman untuk saat ini. |

Lanjut ke **[02 — Menjalankan Project](02-menjalankan-project.md)**.
