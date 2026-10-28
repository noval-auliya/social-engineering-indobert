import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_engineering_detector/core/theme/app_theme.dart';
import 'package:social_engineering_detector/features/history/history_page.dart';
import 'package:social_engineering_detector/services/mock_data.dart';

Widget _app() => ProviderScope(
      child: MaterialApp(theme: AppTheme.light(), home: const HistoryPage()),
    );

void main() {
  testWidgets('Klik riwayat pesan membuka detail isi pesan + LIME',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.text('WhatsApp Message').first);
    await tester.pumpAndSettle();

    expect(find.text('Kenapa? (LIME)'), findsOneWidget);
    expect(find.text('Pesan yang dianalisis'), findsOneWidget);
    // Isi pesan tampil utuh, tidak terpotong seperti di daftar.
    expect(find.text(MockData.sampleMessages[0]), findsOneWidget);
  });

  testWidgets('Klik riwayat APK membuka detail malware', (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.text('game_booster.apk'));
    await tester.pumpAndSettle();

    expect(find.text('Risk Score'), findsOneWidget);
  });
}
