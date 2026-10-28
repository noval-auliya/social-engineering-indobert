import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:social_engineering_detector/services/ai/indobert_classifier.dart';
import 'package:social_engineering_detector/services/analysis_service.dart';

/// Dijalankan di HP Android sungguhan:
///   flutter test integration_test/indobert_on_device_test.dart -d <device_id>
///
/// Membuktikan model ONNX di HP memberi probabilitas yang sama dengan
/// onnxruntime Python, dan mengukur kecepatan analisis + LIME.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('IndoBERT di HP == hasil Python, plus waktu inferensi',
      (tester) async {
    final fixture = jsonDecode(
        await rootBundle.loadString('assets/ai/fixtures.json'))
        as Map<String, dynamic>;
    final cases = (fixture['cases'] as List).cast<Map<String, dynamic>>();

    final sw = Stopwatch()..start();
    final model = await IndoBertClassifier.load();
    debugPrint('Muat model: ${sw.elapsedMilliseconds} ms');

    for (final c in cases) {
      sw.reset();
      final probs = (await model.predict([c['text'] as String])).first;
      final expected = (c['probs'] as List).cast<num>();
      debugPrint('${sw.elapsedMilliseconds} ms  $probs  "${c['text']}"');
      // Kernel int8 ARM vs x86 berbeda pembulatan; pada pesan yang ambigu
      // selisihnya bisa ~0.03 (int8 vs fp32 di laptop pun 0.022). Label hasil
      // prediksi harus tetap sama.
      for (var k = 0; k < probs.length; k++) {
        expect(probs[k], closeTo(expected[k].toDouble(), 0.05));
      }
      int argmax(List<num> p) =>
          List.generate(p.length, (i) => i).reduce((a, b) => p[a] >= p[b] ? a : b);
      expect(argmax(probs), argmax(expected));
    }

    final service = AnalysisService(loadModel: () async => model);
    for (final text in [
      cases.first['text'] as String,
      'Ma, ini aku. HP aku rusak jadi pakai nomor teman dulu. Aku lagi butuh '
          'banget pulsa 100rb buat urusan kampus, nanti aku ganti kalau sudah '
          'pulang. Tolong kirim ke nomor ini ya Ma, jangan telepon dulu.',
    ]) {
      sw.reset();
      final r = await service.analyzeMessage(text);
      debugPrint('Analisis + LIME: ${sw.elapsedMilliseconds} ms -> '
          '${r.riskLevel} ${r.score.toStringAsFixed(3)} '
          '${r.explanation.map((e) => '${e.word}:${e.weight.toStringAsFixed(3)}')}');
      expect(r.engine, AnalysisService.aiEngine);
    }
  });
}
