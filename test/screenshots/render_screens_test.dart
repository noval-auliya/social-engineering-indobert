@Tags(['screenshots'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_engineering_detector/core/theme/app_theme.dart';
import 'package:social_engineering_detector/features/home/home_shell.dart';
import 'package:social_engineering_detector/features/onboarding/onboarding_page.dart';
import 'package:social_engineering_detector/models/analysis_result.dart';
import 'package:social_engineering_detector/models/history_item.dart';
import 'package:social_engineering_detector/models/malware_result.dart';
import 'package:social_engineering_detector/providers/providers.dart';
import 'package:social_engineering_detector/services/analysis_service.dart';
import 'package:social_engineering_detector/services/local_store.dart';

/// Render layar ke PNG untuk ditinjau (bukan bagian test biasa):
///   flutter test test/screenshots --tags screenshots
/// Hasil: build/screenshots/*.png
Future<void> _loadFonts() async {
  final jakarta = FontLoader('PlusJakartaSans');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    jakarta.addFont(File('assets/fonts/PlusJakartaSans-$w.ttf')
        .readAsBytes()
        .then((b) => ByteData.view(b.buffer)));
  }
  await jakarta.load();
  final flutterRoot = Platform.environment['FLUTTER_ROOT']!;
  final icons = FontLoader('MaterialIcons')
    ..addFont(File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
        .readAsBytes()
        .then((b) => ByteData.view(b.buffer)));
  await icons.load();
}

Future<void> _shot(WidgetTester tester, GlobalKey key, String name) async {
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final out = File('build/screenshots/$name.png')..createSync(recursive: true);
    out.writeAsBytesSync(png!.buffer.asUint8List());
  });
}

HistoryItem _msg(String title, String text, RiskLevel level, int minutesAgo) =>
    HistoryItem.fromAnalysis(
        AnalysisResult(
          message: text,
          riskLevel: level,
          score: 0.9,
          confidence: 0.9,
          explanation: const [],
          createdAt: DateTime.now().subtract(Duration(minutes: minutesAgo)),
        ),
        title: title);

void main() {
  setUpAll(_loadFonts);

  final history = [
    _msg('Otomatis · Mama', 'Ma, ini aku. HP aku rusak jadi pakai nomor teman, tolong kirim pulsa 100rb ya',
        RiskLevel.malicious, 3),
    _msg('Otomatis · Grup RT 05', 'Info kerja bakti hari Minggu jam 7 pagi, bawa cangkul ya bapak-bapak',
        RiskLevel.safe, 40),
    HistoryItem.fromMalware(MalwareResult(
      fileName: 'Undangan_Pernikahan.apk',
      sha256: 'ab' * 32,
      riskScore: 79,
      indicators: const [],
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      packageName: 'com.undangan.digital',
    )),
    _msg('WhatsApp Message', 'Paket Anda tertahan, bayar ongkir kurang di link berikut', RiskLevel.suspicious, 300),
    _msg('Otomatis · Kantor', 'Rapat koordinasi dipindah ke Rabu jam 14.00 di lantai 3', RiskLevel.safe, 900),
  ];

  for (final dark in [false, true]) {
    final suffix = dark ? '_gelap' : '';

    testWidgets('render beranda & riwayat$suffix', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      final store = MemoryLocalStore({
        HistoryNotifier.storageKey: jsonEncode([for (final h in history) h.toJson()]),
        SettingsNotifier.storageKey: jsonEncode({'onboarding_done': true}),
      });
      final app = ProviderContainer(overrides: [
        localStoreProvider.overrideWithValue(store),
        aiStatusProvider.overrideWith((ref) async => const AiEngineStatus(true, 'uji')),
      ]);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: app,
        child: RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: dark ? AppTheme.dark() : AppTheme.light(),
            home: const HomeShell(),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await _shot(tester, key, 'beranda$suffix');

      app.read(homeTabProvider.notifier).state = HomeTab.history;
      await tester.pumpAndSettle();
      await _shot(tester, key, 'riwayat$suffix');

      app.read(homeTabProvider.notifier).state = HomeTab.messages;
      await tester.pumpAndSettle();
      await _shot(tester, key, 'pesan$suffix');
    });
  }

  testWidgets('render onboarding', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(ProviderScope(
      overrides: [localStoreProvider.overrideWithValue(MemoryLocalStore())],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            home: const OnboardingPage()),
      ),
    ));
    await tester.pumpAndSettle();
    await _shot(tester, key, 'onboarding');
  });
}
