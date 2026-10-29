# 05 — Flow Aplikasi

Diagram memakai **Mermaid** dan tampil otomatis di GitHub, GitLab, dan
VS Code (dengan ekstensi *Markdown Preview Mermaid Support*).

Daftar flow:

1. [Startup aplikasi](#1-startup-aplikasi)
2. [Analisis pesan manual (dua tahap)](#2-analisis-pesan-manual-dua-tahap)
3. [Scan otomatis WhatsApp — aplikasi terbuka](#3-scan-otomatis-whatsapp--aplikasi-terbuka)
4. [Scan otomatis WhatsApp — aplikasi tertutup](#4-scan-otomatis-whatsapp--aplikasi-tertutup)
5. [Analisis APK](#5-analisis-apk)
6. [Koreksi pengguna → latih ulang](#6-koreksi-pengguna--latih-ulang)
7. [Pipeline model AI (developer)](#7-pipeline-model-ai-developer)

---

## 1. Startup aplikasi

```mermaid
flowchart TD
    A[main] --> B[ProviderScope + SocialEngineeringApp]
    B --> C[settingsProvider memuat settings_v1]
    B --> D[waMonitorProvider: cek izin listener,<br/>dengarkan EventChannel, scan antrean]
    C --> E{_StartGate:<br/>pengaturan sudah dimuat?}
    E -- belum --> F[Latar kosong]
    E -- ya --> G{onboardingDone?}
    G -- tidak --> H[OnboardingPage]
    H -- selesai --> I[completeOnboarding]
    I --> J
    G -- ya --> J[HomeShell]
    J --> K{Dibuka dari notifikasi?<br/>consumeLaunchTarget}
    K -- "history" --> L[Pindah ke tab Riwayat]
    K -- null --> M[Tab Beranda]
    J --> N[historyProvider memuat history_v1]
```

Catatan:
- `_StartGate` menunggu pengaturan termuat agar pengguna lama tidak melihat
  onboarding berkedip sesaat.
- Riwayat baru ditulis setelah riwayat lama selesai dimuat (`loaded`), agar
  tidak saling menimpa.

---

## 2. Analisis pesan manual (dua tahap)

```mermaid
sequenceDiagram
    actor U as Pengguna
    participant P as WhatsAppAnalysisPage
    participant AN as analysisProvider
    participant S as AnalysisService
    participant M as IndoBertClassifier
    participant H as historyProvider
    participant L as LimeTextExplainer

    U->>P: Tempel pesan, tekan Analisis
    P->>AN: analyze(message)
    AN->>AN: state = loading
    AN->>S: analyzeMessage(explain: false)
    S->>M: load() (sekali, di-cache)
    alt model gagal dimuat
        S-->>AN: hasil heuristik kata kunci
    else model siap
        S->>M: predict([pesan])
        M-->>S: [p_normal, p_penipuan, p_promo]
        S-->>AN: AnalysisResult (score, explanationPending = true)
    end
    AN->>H: addAnalysis(hasil) → simpan history_v1
    AN-->>P: state = data (skor tampil ±0,1 dtk)
    AN->>H: explainItem(item)
    H->>S: explain(hasil)
    S->>L: explain(pesan, predict, classIndex = penipuan)
    loop 100 variasi pesan, batch 16
        L->>M: predict(batch)
    end
    L-->>S: 6 kata paling berpengaruh
    S-->>H: hasil + penjelasan
    H->>H: ganti entri, simpan history_v1
    H-->>AN: hasil lengkap
    AN-->>P: state = data (bar LIME tampil, 5–15 dtk)
```

Tahap 1 dan 2 dipisah karena LIME butuh ±100 inferensi. Jika pengguna sudah
menganalisis pesan lain sebelum LIME selesai, hasil lama tidak menimpa layar.

### Penentuan level

```mermaid
flowchart LR
    S[score = p penipuan] --> A{≥ 0,75}
    A -- ya --> MAL[MALICIOUS]
    A -- tidak --> B{≥ 0,50}
    B -- ya --> HIGH[HIGH RISK]
    B -- tidak --> C{≥ 0,25}
    C -- ya --> SUS[SUSPICIOUS]
    C -- tidak --> SAFE[SAFE]
```

---

## 3. Scan otomatis WhatsApp — aplikasi terbuka

```mermaid
sequenceDiagram
    participant WA as WhatsApp
    participant NL as WaNotificationListener.kt
    participant ST as WaListenerStore.kt
    participant BS as BackgroundScanner.kt
    participant EV as EventChannel
    participant MON as waMonitorProvider
    participant S as AnalysisService
    participant H as historyProvider
    participant UI as HomeShell

    WA->>NL: onNotificationPosted
    NL->>NL: Filter: paket WhatsApp, pemantauan aktif,<br/>bukan ringkasan grup
    NL->>NL: Ambil pesan (Android 11+: MessagingStyle,<br/>≤10: bigText / text)
    NL->>NL: Buang pesan lama (< since) & pendek (< minLength)
    NL->>ST: add(pesan) — tolak jika dedupeKey sudah ada
    NL->>BS: onMessagesQueued
    BS->>ST: notifyNewMessage()
    ST->>EV: events.success(1)
    EV->>MON: onNewMessage
    MON->>ST: drain() (ambil & kosongkan antrean)
    loop setiap pesan, ulangi sampai antrean kosong
        MON->>UI: scanProgress (banner "memindai…")
        MON->>S: analyzeMessage(explain: false)
        S-->>MON: hasil
        MON->>H: addAnalysis(title: "Otomatis · pengirim")
        MON->>UI: unseenHistory += item (badge "BARU")
        Note over MON: Aplikasi di layar → tidak ada notifikasi sistem
    end
    MON->>UI: scanProgress selesai (jumlah & berisiko)
```

LIME untuk pesan otomatis **tidak** dihitung saat scan. LIME dihitung ketika
pengguna membuka detail entri (`historyProvider.explainItem`).

---

## 4. Scan otomatis WhatsApp — aplikasi tertutup

```mermaid
sequenceDiagram
    participant NL as WaNotificationListener.kt
    participant ST as WaListenerStore.kt
    participant BS as BackgroundScanner.kt
    participant FE as Mesin Flutter headless<br/>(backgroundScanMain)
    participant MON as waMonitorProvider
    participant RN as RiskNotifier.kt
    actor U as Pengguna

    NL->>ST: add(pesan)
    NL->>BS: onMessagesQueued
    BS->>ST: notifyNewMessage() → false (tidak ada mesin hidup)
    alt peringatan dimatikan
        Note over BS: Pesan menunggu di antrean sampai aplikasi dibuka
    else peringatan aktif
        BS->>FE: start(): FlutterEngine + AppChannels + entrypoint
        FE->>FE: Muat riwayat (wajib sebelum menulis)
        FE->>MON: ready → refresh → scanPending
        MON->>ST: drain()
        loop setiap pesan
            MON->>MON: analyze → simpan riwayat
            opt level ≥ HIGH
                MON->>RN: showRiskAlert(judul, isi)
                RN->>U: Notifikasi "⚠️ Pesan berisiko dari …"
            end
        end
        MON->>BS: backgroundIdle
        BS->>BS: Jadwalkan stop() dalam 60 dtk
        Note over BS: Pesan baru dalam 60 dtk → event ke mesin ini,<br/>timer di-reset
        BS->>FE: stop() → destroy
    end
    U->>RN: Ketuk notifikasi
    RN->>U: Buka MainActivity (open_tab = history) → tab Riwayat
```

Mesin headless menjalankan **kode Dart yang sama** dengan aplikasi, sehingga
tidak ada logika analisis ganda di Kotlin.

---

## 5. Analisis APK

```mermaid
sequenceDiagram
    actor U as Pengguna
    participant P as MalwareAnalysisPage
    participant MP as malwareProvider
    participant MS as MalwareService
    participant K as ApkAnalyzer.kt<br/>(thread terpisah)
    participant D as MalwareDetector
    participant H as historyProvider

    U->>P: Pilih file .apk (file_picker)
    P->>MP: analyze(uri, namaFile)
    MP->>MS: analyzeFile
    MS->>D: muat model.json, rules.json, trusted_signers.json (sekali)
    MS->>K: sed/apk_analyzer.analyze(source, apiFeatures)
    K->>K: Salin URI ke file sementara, SHA-256
    K->>K: getPackageArchiveInfo → izin, nama, versi
    K->>K: Baca classes*.dex → referensi API yang dicari
    K->>K: Cek dex tersembunyi, sertifikat debug, SHA-256 sertifikat
    K-->>MS: Map fitur
    MS->>D: assess(ApkFeatures)
    D->>D: 1. p_ML = sigmoid(intercept + Σ bobot)
    D->>D: 2. Aturan cocok → poin × faktor ukuran
    D->>D: 3. Gabung, batasi jika sertifikat resmi
    D-->>MS: MalwareAssessment
    MS-->>MP: MalwareResult (skor, indikator, izin berbahaya, faktor ML)
    MP->>H: addMalware → simpan history_v1
    MP-->>P: Tampilkan hasil
```

```mermaid
flowchart TD
    F[Fitur APK] --> T{Paket ada di<br/>trusted_signers?}
    T -- tidak --> ML
    T -- ya --> C{Sertifikat cocok?}
    C -- ya --> V[flag verified_official]
    C -- tidak --> FK[flag fake_official<br/>aturan 85 poin]
    V --> ML
    FK --> ML
    ML[Regresi logistik → p_ML] --> R[Aturan perilaku → poin]
    R --> G["skor = 100 × (1 − (1−p_ML)(1−poin/100))"]
    G --> Q{verified_official?}
    Q -- ya --> CAP[skor = min skor, trusted_cap]
    Q -- tidak --> LV
    CAP --> LV[Level: ≤30 LOW · ≤60 MEDIUM · ≤80 HIGH · >80 CRITICAL]
```

---

## 6. Koreksi pengguna → latih ulang

```mermaid
flowchart LR
    A[Detail riwayat] -->|"Hasil ini salah"| B[Pilih label benar]
    B --> C[correctionsProvider.add<br/>ganti koreksi lama untuk kunci sama]
    C --> D[(corrections_v1)]
    D --> E[Pengaturan → Ekspor]
    E --> F1[koreksi_pesan.csv<br/>Teks,label]
    E --> F2[koreksi_apk.csv<br/>label,package,sha256,permissions,apis]
    F1 -->|developer salin| G1[ml/data/]
    F2 -->|developer salin| G2[ml/malware/data/]
    G1 --> H1[train → distill → prune → export]
    G2 --> H2[train_malware.py]
    H1 --> I[assets/ → build APK baru]
    H2 --> I
```

---

## 7. Pipeline model AI (developer)

```mermaid
flowchart TD
    D1[dataset_sms_spam_v1.csv<br/>diunduh otomatis] --> T
    D2[whatsapp_tambahan.csv] --> T
    D3[kontras.csv<br/>buat_data_kontras.py] --> T
    D4[CSV koreksi / data lain] --> T
    T[train.py<br/>IndoBERT 12 lapis + augmentasi nomor] --> O1[output/model]
    O1 --> DS[distill.py<br/>murid 6 lapis, CE + KL]
    DS --> O2[output/model_student]
    O2 --> PR[prune_vocab.py<br/>embedding 50.000 → 30.521]
    PR --> O3[output/model_pruned]
    O3 --> EX[export_onnx.py<br/>ONNX fp32 → int8, verifikasi]
    EX --> AS[assets/ai/<br/>model · vocab · config · fixtures]
    AS --> EV[evaluate.py<br/>kasus_sulit.csv]
    AS --> FT[flutter test<br/>tokenizer Dart = Python]
    FT --> BLD[flutter build apk]
```

Prinsip penting:
- `ml/eval/kasus_sulit.csv` tidak pernah dipakai untuk melatih (dibuang
  otomatis jika bocor ke data latih).
- Setiap ekspor membuat nama file model baru (hash) dan fixture baru.
