import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_engineering_detector/core/theme/app_theme.dart';
import 'package:social_engineering_detector/features/history/history_detail_page.dart';
import 'package:social_engineering_detector/models/analysis_result.dart';
import 'package:social_engineering_detector/models/lime_explanation.dart';
import 'package:social_engineering_detector/providers/providers.dart';
import 'package:social_engineering_detector/services/analysis_service.dart';
import 'package:social_engineering_detector/services/local_store.dart';
import 'package:social_engineering_detector/services/risk_alert_policy.dart';

/// Meniru IndoBERT: skor langsung, LIME selesai saat [finishLime] dipanggil.
class _FakeAi extends AnalysisService {
  final _lime = Completer<void>();
  int explainCalls = 0;
  void finishLime() => _lime.complete();

  @override
  Future<AnalysisResult> analyzeMessage(String message, {bool explain = true}) async =>
      AnalysisResult(
        message: message,
        riskLevel: RiskLevel.malicious,
        score: 0.97,
        confidence: 0.97,
        explanation: const [],
        explanationPending: true,
        createdAt: DateTime(2026, 10, 28),
        engine: AnalysisService.aiEngine,
      );

  @override
  Future<AnalysisResult> explain(AnalysisResult r) async {
    explainCalls++;
    await _lime.future;
    return r.withExplanation(const [LimeExplanation(word: 'hadiah', weight: 0.56)]);
  }
}

void main() {
  test('Analisis manual: skor tampil dulu, LIME menyusul & tersimpan', () async {
    final ai = _FakeAi();
    final app = ProviderContainer(overrides: [
      analysisServiceProvider.overrideWithValue(ai),
      localStoreProvider.overrideWithValue(MemoryLocalStore()),
    ]);
    final done = app.read(analysisProvider.notifier).analyze('Selamat Anda menang hadiah');
    await Future<void>.delayed(Duration.zero);

    // Tahap 1: skor sudah ada, penjelasan belum.
    final first = app.read(analysisProvider).value!;
    expect(first.score, 0.97);
    expect(first.explanationPending, isTrue);
    expect(app.read(historyProvider).single.analysis!.explanationPending, isTrue);

    // Tahap 2: LIME selesai -> halaman & riwayat diperbarui.
    ai.finishLime();
    await done;
    expect(app.read(analysisProvider).value!.explanation.single.word, 'hadiah');
    expect(app.read(historyProvider).single.analysis!.explanationPending, isFalse);
  });

  testWidgets('Detail riwayat menghitung LIME yang tertunda, cukup sekali',
      (tester) async {
    final ai = _FakeAi();
    final app = ProviderContainer(overrides: [
      analysisServiceProvider.overrideWithValue(ai),
      localStoreProvider.overrideWithValue(MemoryLocalStore()),
    ]);
    final item = app.read(historyProvider.notifier).addAnalysis(
        await ai.analyzeMessage('Klik link ini untuk klaim hadiah'),
        title: 'Otomatis · Penipu');

    await tester.pumpWidget(UncontrolledProviderScope(
      container: app,
      child: MaterialApp(theme: AppTheme.light(), home: HistoryDetailPage(item: item)),
    ));
    await tester.pump();
    expect(find.textContaining('Menyusun penjelasan'), findsOneWidget);

    // Membuka detail lagi sebelum selesai tidak menjalankan LIME dua kali.
    app.read(historyProvider.notifier).explainItem(item);
    expect(ai.explainCalls, 1);

    ai.finishLime();
    await tester.pumpAndSettle();
    expect(find.textContaining('Menyusun penjelasan'), findsNothing);
    expect(find.text('hadiah'), findsOneWidget);
  });

  test('Kebijakan peringatan: hanya HIGH RISK ke atas', () {
    AnalysisResult r(RiskLevel l) => AnalysisResult(
        message: 'x', riskLevel: l, score: 0.5, confidence: 0.5,
        explanation: const [], createdAt: DateTime(2026));
    expect(shouldAlert(r(RiskLevel.safe)), isFalse);
    expect(shouldAlert(r(RiskLevel.suspicious)), isFalse);
    expect(shouldAlert(r(RiskLevel.high)), isTrue);
    expect(shouldAlert(r(RiskLevel.malicious)), isTrue);

    final text = alertText(
        AnalysisResult(
            message: 'a' * 300, riskLevel: RiskLevel.malicious, score: 0.97,
            confidence: 0.97, explanation: const [], createdAt: DateTime(2026)),
        'Budi');
    expect(text.title, contains('Budi'));
    expect(text.body, startsWith('Terindikasi Serangan · 97%'));
    expect(text.body.length, lessThan(200)); // isi pesan dipotong
  });
}
