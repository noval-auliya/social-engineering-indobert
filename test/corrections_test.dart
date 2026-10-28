import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_engineering_detector/core/theme/app_theme.dart';
import 'package:social_engineering_detector/features/history/history_detail_page.dart';
import 'package:social_engineering_detector/models/analysis_result.dart';
import 'package:social_engineering_detector/models/correction.dart';
import 'package:social_engineering_detector/models/history_item.dart';
import 'package:social_engineering_detector/models/lime_explanation.dart';
import 'package:social_engineering_detector/providers/providers.dart';
import 'package:social_engineering_detector/services/correction_export.dart';
import 'package:social_engineering_detector/services/local_store.dart';

/// Pesan normal yang (salah) dinilai penipuan oleh model.
const _msg = 'Iuran kas RT 30rb, transfer ke "BNI 0123456789", a.n. Bendahara.\nMakasih';

Correction _c(String key, String label,
        {CorrectionKind kind = CorrectionKind.message}) =>
    Correction(
      kind: kind,
      key: key,
      predictedLabel: 'penipuan',
      correctLabel: label,
      createdAt: DateTime(2026, 10, 28),
      packageName: kind == CorrectionKind.apk ? 'com.bank.app' : '',
      permissions: kind == CorrectionKind.apk ? const ['INTERNET', 'RECEIVE_SMS'] : const [],
      apis: kind == CorrectionKind.apk
          ? const ['Ljava/lang/Runtime;->exec']
          : const [],
    );

void main() {
  test('CSV pesan: koma, kutip, & baris baru aman; label sesuai train.py', () {
    expect(
      messageCorrectionsCsv([_c(_msg, 'normal'), _c('promo kuota 50GB', 'promo')]),
      'Teks,label\n'
      '"Iuran kas RT 30rb, transfer ke ""BNI 0123456789"", a.n. Bendahara.\nMakasih",0\n'
      '"promo kuota 50GB",2\n',
    );
  });

  test('CSV APK: izin & API dipisah "|" (nama API sendiri memuat ";")', () {
    final csv = apkCorrectionsCsv([_c('ab' * 32, 'aman', kind: CorrectionKind.apk)]);
    expect(
      csv,
      'label,package,sha256,permissions,apis\n'
      '0,"com.bank.app",${'ab' * 32},"INTERNET|RECEIVE_SMS","Ljava/lang/Runtime;->exec"\n',
    );
    // Bukti utuh: memisah kolom API dengan pemisah harus mengembalikan nama asli.
    final apis = csv.trim().split('\n').last.split(',').last.replaceAll('"', '');
    expect(apis.split(listSeparator), ['Ljava/lang/Runtime;->exec']);
  });

  test('Koreksi tersimpan, menggantikan koreksi lama untuk pesan yang sama',
      () async {
    final store = MemoryLocalStore();
    final app = ProviderContainer(overrides: [localStoreProvider.overrideWithValue(store)]);
    app.read(correctionsProvider.notifier)
      ..add(_c(_msg, 'promo'))
      ..add(_c(_msg, 'normal'));
    await Future<void>.delayed(Duration.zero);
    app.dispose();

    final again = ProviderContainer(overrides: [localStoreProvider.overrideWithValue(store)]);
    await again.read(correctionsProvider.notifier).loaded;
    final all = again.read(correctionsProvider);
    expect(all, hasLength(1));
    expect(all.single.correctLabel, 'normal');
    expect(all.single.labelIndex, 0);
  });

  testWidgets('Detail riwayat: tandai "salah" -> pilih label -> tersimpan',
      (tester) async {
    final app = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(MemoryLocalStore())]);
    final item = HistoryItem.fromAnalysis(AnalysisResult(
      message: _msg,
      riskLevel: RiskLevel.malicious,
      score: 0.99,
      confidence: 0.99,
      explanation: const [LimeExplanation(word: 'transfer', weight: 0.4)],
      createdAt: DateTime(2026, 10, 28),
      probabilities: const {'normal': 0.01, 'penipuan': 0.99, 'promo': 0.0},
    ));

    await tester.pumpWidget(UncontrolledProviderScope(
      container: app,
      child: MaterialApp(theme: AppTheme.light(), home: HistoryDetailPage(item: item)),
    ));
    expect(find.text('Hasil ini salah?'), findsOneWidget);
    expect(find.textContaining('Aplikasi menilai: Penipuan'), findsOneWidget);

    await tester.tap(find.text('Koreksi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Normal / aman'));
    await tester.pumpAndSettle();

    expect(find.text('Sudah dikoreksi'), findsOneWidget);
    final saved = app.read(correctionsProvider).single;
    expect(saved.key, _msg);
    expect(saved.predictedLabel, 'penipuan');
    expect(saved.correctLabel, 'normal');
  });
}
