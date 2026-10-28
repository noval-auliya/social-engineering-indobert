import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_engineering_detector/core/theme/app_theme.dart';
import 'package:social_engineering_detector/features/history/history_page.dart';
import 'package:social_engineering_detector/features/history/history_query.dart';
import 'package:social_engineering_detector/models/analysis_result.dart';
import 'package:social_engineering_detector/models/history_item.dart';
import 'package:social_engineering_detector/models/malware_result.dart';
import 'package:social_engineering_detector/providers/providers.dart';
import 'package:social_engineering_detector/services/local_store.dart';
import 'package:social_engineering_detector/services/protection_score.dart';

HistoryItem _msg(int i, String text, RiskLevel level) => HistoryItem.fromAnalysis(
      AnalysisResult(
        message: text,
        riskLevel: level,
        score: 0.5,
        confidence: 0.9,
        explanation: const [],
        createdAt: DateTime(2026, 10, 28).subtract(Duration(minutes: i)),
      ),
      title: 'Otomatis · Pengirim $i',
    );

HistoryItem _apk(String name, String pkg, int score) => HistoryItem.fromMalware(MalwareResult(
      fileName: name,
      sha256: name.hashCode.toRadixString(16).padLeft(64, '0'),
      riskScore: score,
      indicators: const [],
      createdAt: DateTime(2026, 10, 27),
      packageName: pkg,
      appName: 'Undangan Digital',
    ));

void main() {
  final sample = [
    _msg(1, 'Selamat Anda menang hadiah, transfer biaya admin', RiskLevel.malicious),
    _msg(2, 'Rapat besok jam 10 di ruang 3', RiskLevel.safe),
    _apk('undangan.apk', 'com.undangan.nikah', 85),
    _apk('kalkulator.apk', 'com.calc', 5),
  ];

  group('filterHistory', () {
    test('cari: semua kata harus cocok, tanpa beda huruf besar-kecil', () {
      expect(filterHistory(sample, query: 'HADIAH transfer').map((h) => h.title),
          ['Otomatis · Pengirim 1']);
      expect(filterHistory(sample, query: 'hadiah rapat'), isEmpty);
    });

    test('cari APK lewat nama aplikasi & nama paket', () {
      expect(filterHistory(sample, query: 'Undangan Digital'), hasLength(2));
      expect(filterHistory(sample, query: 'com.undangan').single.title, 'undangan.apk');
    });

    test('cari label risiko (biasa & istilah indikatif)', () {
      expect(filterHistory(sample, query: 'malicious'), hasLength(1));
      expect(filterHistory(sample, query: 'terindikasi'), hasLength(1));
    });

    test('filter jenis & berisiko', () {
      expect(filterHistory(sample, filter: HistoryFilter.messages), hasLength(2));
      expect(filterHistory(sample, filter: HistoryFilter.apks), hasLength(2));
      expect(filterHistory(sample, filter: HistoryFilter.risky).map((h) => h.title),
          ['Otomatis · Pengirim 1', 'undangan.apk']);
    });
  });

  test('Skor perlindungan = jumlah bobot perlindungan yang aktif', () {
    expect(
        protectionScore(protectionFactors(
            aiReady: true, monitorActive: true, alertsActive: true, historySaved: true)),
        100);
    expect(
        protectionScore(protectionFactors(
            aiReady: true, monitorActive: false, alertsActive: false, historySaved: true)),
        45);
  });

  testWidgets('Riwayat: dimuat 20 per halaman saat menggulir, lalu dicari',
      (tester) async {
    final items = [
      for (var i = 0; i < 45; i++)
        _msg(i, i == 37 ? 'pesan kurir paket tertahan' : 'pesan biasa nomor $i',
            RiskLevel.safe),
    ];
    final store = MemoryLocalStore({
      HistoryNotifier.storageKey: jsonEncode([for (final h in items) h.toJson()]),
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [localStoreProvider.overrideWithValue(store)],
      child: MaterialApp(theme: AppTheme.light(), home: const HistoryPage()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('45 hasil tersimpan'), findsOneWidget);
    // Halaman pertama: entri ke-20 belum dibangun.
    expect(find.text('Otomatis · Pengirim 25', skipOffstage: false), findsNothing);

    await tester.fling(find.byType(CustomScrollView), const Offset(0, -3000), 3000);
    await tester.pumpAndSettle();
    await tester.fling(find.byType(CustomScrollView), const Offset(0, -6000), 3000);
    await tester.pumpAndSettle();
    expect(find.text('Menampilkan 45 dari 45 hasil'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'kurir');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Otomatis · Pengirim 37'), findsOneWidget);
    expect(find.text('Otomatis · Pengirim 36'), findsNothing);

    await tester.enterText(find.byType(TextField), 'tidakadayangcocok');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Tidak ada hasil yang cocok'), findsOneWidget);
  });
}
