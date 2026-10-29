# 07 — Integrasi IndoBERT & LIME

Dokumen ini menunjukkan **di kode mana** IndoBERT dan LIME (*Local Interpretable
Model-agnostic Explanations*) dipakai, dari tombol di layar sampai inferensi
model di HP.

## Ringkasan

| Menu | Model deteksi | Penjelasan hasil | IndoBERT? | LIME? |
|---|---|---|---|---|
| **Pesan** (input manual & scan otomatis WhatsApp) | IndoBERT fine-tuned, ONNX int8, on-device | LIME teks (100 variasi pesan) | **Ya** | **Ya** |
| **Malware APK** | Regresi logistik + aturan perilaku + sertifikat resmi | Bobot fitur regresi logistik | Tidak | Tidak |

> **Penting untuk laporan/skripsi:** menu Malware **tidak** memakai IndoBERT
> maupun LIME. IndoBERT adalah model *bahasa*, sedangkan input APK berupa daftar
> izin dan panggilan API, bukan teks. Penjelasan di menu Malware berasal dari
> bobot regresi logistik (lihat [bagian B](#b-menu-malware--bukan-indobert-bukan-lime)).

---

## A. Menu Pesan — IndoBERT + LIME

### Alur

```
WhatsAppAnalysisPage / scan otomatis
        │
        ▼
AnalysisNotifier.analyze()                 lib/providers/providers.dart
        │  tahap 1: skor (~0,1 dtk)
        ▼
AnalysisService.analyzeMessage(explain:false)
        │                                  lib/services/analysis_service.dart
        ▼
IndoBertClassifier.predict([pesan])        lib/services/ai/indobert_classifier.dart
        │  probabilitas normal / penipuan / promo
        ▼
HistoryNotifier.explainItem()  ── tahap 2: penjelasan (5–15 dtk)
        │
        ▼
AnalysisService.explain() → LimeTextExplainer.explain(pesan, model.predict)
        │                                  lib/services/ai/lime_text_explainer.dart
        ▼
AnalysisResultView  "Kenapa? (LIME)"       lib/features/whatsapp_analysis/analysis_result_view.dart
```

### A1. Memuat IndoBERT di HP

[lib/services/ai/indobert_classifier.dart:26-45](../lib/services/ai/indobert_classifier.dart#L26-L45)
memuat model ONNX, vocab, dan label dari `assets/ai/` (hasil `ml/export_onnx.py`):

```dart
static Future<IndoBertClassifier> load() async {
  final config = jsonDecode(
      await rootBundle.loadString('$_assetDir/config.json')) as Map<String, dynamic>;
  final labels = (config['labels'] as List).cast<String>();
  final tokenizer = BertTokenizer.fromVocab(
    await rootBundle.loadString('$_assetDir/vocab.txt'),
    doLowerCase: config['do_lower_case'] as bool? ?? true,
  );
  final session = await OnnxRuntime().createSessionFromAsset(
    '$_assetDir/${config['model_file']}',
    options: OrtSessionOptions(intraOpNumThreads: 4),
  );
  ...
}
```

### A2. Inferensi IndoBERT

[lib/services/ai/indobert_classifier.dart:48-83](../lib/services/ai/indobert_classifier.dart#L48-L83):
teks ditokenisasi (WordPiece, [bert_tokenizer.dart](../lib/services/ai/bert_tokenizer.dart)),
lalu `input_ids` dan `attention_mask` dimasukkan ke ONNX Runtime:

```dart
Future<List<List<double>>> predict(List<String> texts) async {
  final encoded = [for (final t in texts) tokenizer.encode(t, maxLen: maxLen)];
  ...
  final outputs = await _session.run({
    'input_ids': inputIds,
    'attention_mask': attention,
  });
  final probs = outputs['probs']!;
  ...
}
```

Fungsi ini menerima **banyak teks sekaligus (batch)**. Hal ini penting karena LIME
memanggilnya untuk ratusan variasi pesan.

### A3. Skor risiko dari IndoBERT

[lib/services/analysis_service.dart:114-131](../lib/services/analysis_service.dart#L114-L131):

```dart
Future<AnalysisResult> _scoreModel(
    IndoBertClassifier model, String message) async {
  final probs = (await model.predict([message])).first;
  final score = probs[model.riskIndex];          // probabilitas kelas "penipuan"
  return AnalysisResult(
    ...
    engine: aiEngine,                             // 'IndoBERT (on-device)'
    explanationPending: true,
    probabilities: { for (...) model.labels[i]: probs[i] },
  );
}
```

### A4. Titik integrasi IndoBERT ↔ LIME

[lib/services/analysis_service.dart:133-140](../lib/services/analysis_service.dart#L133-L140).
**Ini baris kunci integrasinya.** Fungsi `model.predict` milik IndoBERT dioper ke LIME
sebagai fungsi prediksi:

```dart
Future<AnalysisResult> _explainWith(
    IndoBertClassifier model, AnalysisResult r) async {
  final explanation = await LimeTextExplainer(numSamples: limeSamples)
      .explain(r.message, model.predict, classIndex: model.riskIndex);
  return r.withExplanation(...);
}
```

LIME bersifat **model-agnostic**. LIME tidak perlu tahu isi IndoBERT; ia hanya
butuh fungsi `List<String> → probabilitas`, yaitu
[`ProbaFn`](../lib/services/ai/lime_text_explainer.dart#L6).

### A5. Algoritma LIME

[lib/services/ai/lime_text_explainer.dart](../lib/services/ai/lime_text_explainer.dart)
mengikuti `lime.lime_text.LimeTextExplainer` (Ribeiro dkk., 2016):

| Langkah | Baris | Isi |
|---|---|---|
| 1. Pecah pesan jadi kata unik | [40-69](../lib/services/ai/lime_text_explainer.dart#L40-L69) | regex `[\p{L}\p{N}_]+` |
| 2. Buat variasi pesan | [71-88](../lib/services/ai/lime_text_explainer.dart#L71-L88) | sampel 0 = asli; sisanya menghapus 1..d-1 kata acak |
| 3. **IndoBERT memprediksi tiap variasi** | [90-94](../lib/services/ai/lime_text_explainer.dart#L90-L94) | `predict(...)` per batch 16 |
| 4. Bobot kedekatan | [96-102](../lib/services/ai/lime_text_explainer.dart#L96-L102) | kernel eksponensial atas jarak kosinus |
| 5. Model linear lokal | [106-118](../lib/services/ai/lime_text_explainer.dart#L106-L118) | Ridge berbobot, pilih 6 kata dengan \|koefisien\| terbesar |

Langkah 3 adalah tempat LIME memanggil IndoBERT:

```dart
final y = <double>[];
for (var i = 0; i < texts.length; i += batchSize) {
  final probs = await predict(texts.sublist(i, min(i + batchSize, texts.length)));
  y.addAll(probs.map((p) => p[classIndex]));
}
```

Dengan `limeSamples = 100` ([analysis_service.dart:27](../lib/services/analysis_service.dart#L27)),
satu penjelasan = 100 inferensi IndoBERT. Itu sebabnya penjelasan butuh 5–15 detik di HP.

### A6. Dipanggil dari menu Pesan

[lib/providers/providers.dart:284-302](../lib/providers/providers.dart#L284-L302).
Prosesnya dua tahap: skor IndoBERT tampil dulu, penjelasan LIME menyusul:

```dart
Future<void> analyze(String message) async {
  final service = _ref.read(analysisServiceProvider);
  final scored = await service.analyzeMessage(message, explain: false); // IndoBERT
  final item = history.addAnalysis(scored);
  state = AsyncValue.data(scored);

  final explained = await history.explainItem(item);                    // LIME
  ...
}
```

`explainItem` ([providers.dart:114-133](../lib/providers/providers.dart#L114-L133))
memanggil `AnalysisService.explain()`. Scan otomatis WhatsApp
([providers.dart:455](../lib/providers/providers.dart#L455)) hanya menghitung
skor; LIME dihitung saat entri riwayat dibuka
([history_detail_page.dart](../lib/features/history/history_detail_page.dart)).

### A7. Ditampilkan di layar

[lib/features/whatsapp_analysis/analysis_result_view.dart:57-95](../lib/features/whatsapp_analysis/analysis_result_view.dart#L57-L95):
bagian **"Kenapa? (LIME)"** menampilkan setiap kata lewat widget
[LimeWord](../lib/widgets/lime_word.dart). Bobot positif mendorong ke berisiko,
bobot negatif mendorong ke aman.

### A8. Cadangan bila IndoBERT gagal dimuat

[analysis_service.dart:93-104](../lib/services/analysis_service.dart#L93-L104):
jika model tidak bisa dimuat, aplikasi memakai **heuristik kata kunci**
(`engine: 'Kata kunci (cadangan)'`). Hasil seperti ini **bukan** IndoBERT dan
bukan LIME. Status mesin yang aktif terlihat di menu Pengaturan.

---

## B. Menu Malware — bukan IndoBERT, bukan LIME

[lib/services/malware/malware_detector.dart:123-164](../lib/services/malware/malware_detector.dart#L123-L164)
menilai APK dengan tiga komponen:

1. **Regresi logistik** atas izin + panggilan API (dilatih TUANDROMD + KronoDroid,
   `ml/malware/train_malware.py`).
2. **Aturan perilaku** dari `assets/malware/rules.json`.
3. **Verifikasi sertifikat** aplikasi resmi (`trusted_signers.json`).

Penjelasan "Fitur paling berpengaruh" diambil langsung dari bobot regresi
logistik untuk fitur yang ada di APK:

```dart
_weights.forEach((name, w) {
  if (present.contains(name)) {
    z += w;
    contributions.add(FeatureContribution(name, w));
  }
});
final pMl = 1 / (1 + exp(-z));
```

Ditampilkan di
[malware_result_view.dart:249-274](../lib/features/malware_analysis/malware_result_view.dart#L249-L274).

**Kenapa bukan LIME?** Regresi logistik adalah model yang *interpretable by
design*: kontribusi tiap fitur langsung terlihat dari bobotnya, tanpa perlu
menguji ratusan variasi seperti LIME. Namun penjelasan ini hanya mencakup
bagian ML. Pengaruh aturan perilaku dan batas sertifikat terhadap skor akhir
tidak dijelaskan per fitur.

---

## Cara membuktikan saat demo

1. **Pengaturan → status mesin** harus menampilkan *"IndoBERT aktif (offline, di HP)"*.
   Jika tertulis kata kunci, model gagal dimuat (lihat A8).
2. **Menu Pesan:** tempel pesan, lalu tekan Analisis. Skor muncul hampir instan
   (IndoBERT), kemudian muncul *"Menyusun penjelasan: menguji ~100 variasi
   pesan"* sebelum daftar kata **"Kenapa? (LIME)"** tampil.
3. Hasil analisis mencantumkan `engine = IndoBERT (on-device)` dan tabel
   **Probabilitas model** (normal / penipuan / promo). Tabel ini hanya ada
   jika IndoBERT yang menilai.
4. **Unit test:** `flutter test test/lime_text_explainer_test.dart
   test/two_stage_lime_test.dart` menguji algoritma LIME
   ([lime_text_explainer_test.dart](../test/lime_text_explainer_test.dart)) dan
   alur dua tahap skor → LIME
   ([two_stage_lime_test.dart](../test/two_stage_lime_test.dart)).
