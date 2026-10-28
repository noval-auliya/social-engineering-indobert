import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_engineering_detector/core/theme/app_theme.dart';
import 'package:social_engineering_detector/features/history/history_page.dart';
import 'package:social_engineering_detector/features/home/home_shell.dart';
import 'package:social_engineering_detector/models/captured_message.dart';
import 'package:social_engineering_detector/providers/providers.dart';
import 'package:social_engineering_detector/services/analysis_service.dart';
import 'package:social_engineering_detector/services/wa_notification_service.dart';

/// Listener palsu: antrean berisi 2 pesan WhatsApp, lalu kosong.
class _FakeWa extends WaNotificationService {
  final _queue = [
    CapturedMessage(
      sender: 'Penipu',
      conversation: 'Penipu',
      text: 'Selamat Anda menang hadiah undian! Klik link dan transfer biaya '
          'admin ke rekening kami untuk verifikasi akun sekarang!',
      receivedAt: DateTime(2026),
    ),
    CapturedMessage(
      sender: 'Budi',
      conversation: 'Budi',
      text: 'Besok meeting jam 10 di ruang 3.',
      receivedAt: DateTime(2026),
    ),
  ];

  @override
  Future<WaMonitorStatus?> getStatus() async =>
      const WaMonitorStatus(granted: true, enabled: true, minLength: 0);
  @override
  Future<List<CapturedMessage>> drain() async {
    final out = List.of(_queue);
    _queue.clear();
    return out;
  }

  @override
  Stream<void> get onNewMessage => const Stream.empty();
}

void main() {
  testWidgets('Scan otomatis: badge, label BARU, dan notifikasi selesai',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        waNotificationServiceProvider.overrideWithValue(_FakeWa()),
        analysisServiceProvider.overrideWithValue(
            AnalysisService(loadModel: () => Future.error('tanpa model'))),
        aiStatusProvider.overrideWith(
            (ref) async => const AiEngineStatus(false, 'uji')),
      ],
      child: Consumer(builder: (_, ref, __) {
        ref.watch(waMonitorProvider); // memicu scan seperti di main.dart
        return MaterialApp(theme: AppTheme.light(), home: const HomeShell());
      }),
    ));
    await tester.pumpAndSettle();

    // Notifikasi: 1 dari 2 pesan berisiko, tombol Lihat.
    expect(find.text('1 dari 2 pesan WhatsApp berisiko!'), findsOneWidget);
    // Badge jumlah hasil baru di tab Riwayat.
    final badgeCount =
        find.descendant(of: find.byType(Badge), matching: find.text('2'));
    expect(badgeCount, findsOneWidget);

    await tester.tap(find.text('Lihat'));
    await tester.pumpAndSettle();
    expect(find.text('BARU'), findsNWidgets(2));
    expect(find.text('Otomatis · Penipu'), findsOneWidget);

    // Keluar dari Riwayat -> penanda BARU & badge hilang.
    await tester.tap(find.text('Beranda'));
    await tester.pumpAndSettle();
    expect(badgeCount, findsNothing);
    expect(find.text('BARU', skipOffstage: false), findsNothing);
  });

  testWidgets('Banner animasi menampilkan progres scan', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        scanProgressProvider.overrideWith((ref) => const ScanProgress(
            active: true, done: 1, total: 3, currentSender: 'Budi')),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: const HistoryPage()),
    ));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Memindai pesan 2 dari 3'), findsOneWidget);
    expect(find.textContaining('dari Budi'), findsOneWidget);
  });
}
