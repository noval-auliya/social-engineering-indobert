import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:social_engineering_detector/main.dart';
import 'package:social_engineering_detector/providers/providers.dart';
import 'package:social_engineering_detector/services/local_store.dart';
import 'package:social_engineering_detector/services/analysis_service.dart';
import 'package:social_engineering_detector/models/analysis_result.dart';

/// Service tanpa model: memaksa jalur cadangan kata kunci.
AnalysisService _keywordOnly() =>
    AnalysisService(loadModel: () => Future.error('tanpa model'));

void main() {
  testWidgets('App memuat dan menampilkan dashboard', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        analysisServiceProvider.overrideWithValue(_keywordOnly()),
        localStoreProvider.overrideWithValue(MemoryLocalStore()),
      ],
      child: const SocialEngineeringApp(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Total Analisis'), findsOneWidget);
  });

  test('Cadangan kata kunci: pesan phishing -> risiko tinggi', () async {
    final r = await _keywordOnly().analyzeMessage(
      'Selamat Anda mendapatkan hadiah, klik link untuk verifikasi akun sekarang!',
    );
    expect(r.riskLevel == RiskLevel.high || r.riskLevel == RiskLevel.malicious,
        isTrue);
    expect(r.explanation, isNotEmpty);
    expect(r.engine, AnalysisService.keywordEngine);
  });

  test('Cadangan kata kunci: pesan biasa -> aman', () async {
    final r = await _keywordOnly()
        .analyzeMessage('Meeting besok jam 10 di ruang 3.');
    expect(r.riskLevel, RiskLevel.safe);
  });
}
