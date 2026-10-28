import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_engineering_detector/features/settings/settings_page.dart';
import 'package:social_engineering_detector/core/theme/app_theme.dart';
import 'package:social_engineering_detector/models/captured_message.dart';
import 'package:social_engineering_detector/providers/providers.dart';
import 'package:social_engineering_detector/services/local_store.dart';
import 'package:social_engineering_detector/services/analysis_service.dart';
import 'package:social_engineering_detector/services/wa_notification_service.dart';

class FakeService extends WaNotificationService {
  FakeService(this.granted);
  final bool granted;
  @override
  Future<WaMonitorStatus?> getStatus() async =>
      WaMonitorStatus(granted: granted, enabled: true, minLength: 150);
  @override
  Future<List<CapturedMessage>> drain() async => [];
  @override
  Stream<void> get onNewMessage => const Stream.empty();
}

void main() {
  for (final granted in [false, true]) {
    testWidgets('Pengaturan tampil tanpa error (akses notifikasi=$granted)', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          localStoreProvider.overrideWithValue(MemoryLocalStore()),
          waNotificationServiceProvider.overrideWithValue(FakeService(granted)),
          aiStatusProvider.overrideWith(
              (ref) async => AiEngineStatus(granted, 'status uji')),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const SettingsPage()),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Scan Otomatis WhatsApp'), findsOneWidget);
      expect(find.text('Mesin Deteksi AI'), findsOneWidget);
    });
  }
}
