import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_engineering_detector/core/theme/app_theme.dart';
import 'package:social_engineering_detector/features/history/history_page.dart';
import 'package:social_engineering_detector/models/analysis_result.dart';
import 'package:social_engineering_detector/models/history_item.dart';
import 'package:social_engineering_detector/models/lime_explanation.dart';
import 'package:social_engineering_detector/models/malware_result.dart';
import 'package:social_engineering_detector/providers/providers.dart';
import 'package:social_engineering_detector/services/local_store.dart';

const _phishing =
    'Selamat! Anda mendapatkan hadiah Rp5.000.000. Klik link berikut untuk '
    'klaim sekarang. Akun akan diblokir jika tidak melakukan verifikasi.';

/// Riwayat tersimpan di HP (format sama dengan yang ditulis aplikasi).
MemoryLocalStore _savedHistory() => MemoryLocalStore({
      HistoryNotifier.storageKey: jsonEncode([
        HistoryItem.fromAnalysis(AnalysisResult(
          message: _phishing,
          riskLevel: RiskLevel.malicious,
          score: 0.97,
          confidence: 0.97,
          explanation: const [LimeExplanation(word: 'hadiah', weight: 0.56)],
          createdAt: DateTime(2026, 10, 28, 9),
        )).toJson(),
        HistoryItem.fromMalware(MalwareResult(
          fileName: 'game_booster.apk',
          sha256: 'a1' * 32,
          riskScore: 72,
          indicators: const [
            MalwareIndicator(name: 'Bisa mengirim SMS', severity: Severity.high),
          ],
          createdAt: DateTime(2026, 10, 28, 8),
        )).toJson(),
      ]),
    });

Widget _app() => ProviderScope(
      overrides: [localStoreProvider.overrideWithValue(_savedHistory())],
      child: MaterialApp(theme: AppTheme.light(), home: const HistoryPage()),
    );

void main() {
  testWidgets('Klik riwayat pesan membuka detail isi pesan + LIME',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('WhatsApp Message').first);
    await tester.pumpAndSettle();

    expect(find.text('Kenapa? (LIME)'), findsOneWidget);
    expect(find.text('Pesan yang dianalisis'), findsOneWidget);
    // Isi pesan tampil utuh, tidak terpotong seperti di daftar.
    expect(find.text(_phishing), findsOneWidget);
  });

  testWidgets('Klik riwayat APK membuka detail malware', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('game_booster.apk'));
    await tester.pumpAndSettle();

    expect(find.text('Risk Score'), findsOneWidget);
  });

  testWidgets('Badge memakai istilah indikatif (default aktif)', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(find.text('Terindikasi Serangan'), findsOneWidget);
    expect(find.text('Berisiko tinggi'), findsOneWidget);
  });
}
