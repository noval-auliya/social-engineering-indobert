import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_engineering_detector/models/analysis_result.dart';
import 'package:social_engineering_detector/models/history_item.dart';
import 'package:social_engineering_detector/models/lime_explanation.dart';
import 'package:social_engineering_detector/models/malware_result.dart';
import 'package:social_engineering_detector/providers/providers.dart';
import 'package:social_engineering_detector/services/local_store.dart';

AnalysisResult sampleAnalysis(String msg, RiskLevel level) => AnalysisResult(
      message: msg,
      riskLevel: level,
      score: 0.9,
      confidence: 0.95,
      explanation: const [LimeExplanation(word: 'hadiah', weight: 0.5)],
      createdAt: DateTime(2026, 10, 28, 9, 30),
      engine: 'IndoBERT (on-device)',
      probabilities: const {'normal': 0.05, 'penipuan': 0.9, 'promo': 0.05},
    );

/// Container baru dengan store yang sama = aplikasi ditutup lalu dibuka lagi.
ProviderContainer openApp(MemoryLocalStore store) =>
    ProviderContainer(overrides: [localStoreProvider.overrideWithValue(store)]);

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('Riwayat pesan & APK tetap ada setelah aplikasi dibuka ulang', () async {
    final store = MemoryLocalStore();
    final app1 = openApp(store);
    app1.read(historyProvider);
    await settle();
    app1.read(historyProvider.notifier)
      ..addAnalysis(sampleAnalysis('Selamat Anda menang hadiah', RiskLevel.malicious),
          title: 'Otomatis · Budi')
      ..addMalware(MalwareResult(
        fileName: 'undangan.apk',
        sha256: 'ab' * 32,
        riskScore: 79,
        indicators: const [
          MalwareIndicator(name: 'Pola pencuri SMS/OTP', severity: Severity.critical),
        ],
        createdAt: DateTime(2026, 10, 28),
        packageName: 'com.undangan.app',
        mlProbability: 0.4,
        mlFactors: const [MapEntry('RECEIVE_SMS', 2.17)],
      ));
    await settle();
    app1.dispose();

    final app2 = openApp(store);
    app2.read(historyProvider);
    await settle();
    await settle();
    final items = app2.read(historyProvider);
    expect(items.map((h) => h.title), ['undangan.apk', 'Otomatis · Budi']);

    final apk = items.first.malware!;
    expect(apk.packageName, 'com.undangan.app');
    expect(apk.indicators.single.severity, Severity.critical);
    expect(apk.mlFactors.single.key, 'RECEIVE_SMS');

    final msg = items.last.analysis!;
    expect(msg.message, 'Selamat Anda menang hadiah');
    expect(msg.engine, 'IndoBERT (on-device)');
    expect(msg.probabilities['penipuan'], 0.9);
    expect(msg.explanation.single.word, 'hadiah');
    expect(msg.createdAt, DateTime(2026, 10, 28, 9, 30));
  });

  test('Sakelar "Simpan riwayat" mati: salinan di HP dihapus & tidak ditulis lagi',
      () async {
    final store = MemoryLocalStore();
    final app = openApp(store);
    app.read(historyProvider);
    await settle();
    app.read(historyProvider.notifier)
        .addAnalysis(sampleAnalysis('pesan 1', RiskLevel.safe));
    await settle();
    expect(store.data.containsKey(HistoryNotifier.storageKey), isTrue);

    app.read(settingsProvider.notifier).toggleSaveHistory(false);
    await settle();
    expect(store.data.containsKey(HistoryNotifier.storageKey), isFalse);

    app.read(historyProvider.notifier)
        .addAnalysis(sampleAnalysis('pesan 2', RiskLevel.safe));
    await settle();
    expect(store.data.containsKey(HistoryNotifier.storageKey), isFalse);
    // Selama aplikasi terbuka riwayat tetap terlihat.
    expect(app.read(historyProvider).length, 2);
    app.dispose();

    // Dibuka ulang: pengaturan "mati" ikut tersimpan, riwayat kosong.
    final again = openApp(store);
    again.read(historyProvider);
    await settle();
    await settle();
    expect(again.read(settingsProvider).saveHistory, isFalse);
    expect(again.read(historyProvider), isEmpty);
  });

  test('Pengaturan tema & istilah indikatif tersimpan', () async {
    final store = MemoryLocalStore();
    final app = openApp(store);
    app.read(settingsProvider.notifier)
      ..setTheme(ThemeChoice.dark)
      ..toggleSoftLabels(false);
    await settle();
    app.dispose();

    final again = openApp(store);
    await again.read(settingsProvider.notifier).loaded;
    expect(again.read(settingsProvider).theme, ThemeChoice.dark);
    expect(again.read(settingsProvider).softLabels, isFalse);
  });

  test('Data tersimpan yang rusak tidak membuat aplikasi crash', () async {
    final store = MemoryLocalStore({HistoryNotifier.storageKey: '{rusak'});
    final app = openApp(store);
    app.read(historyProvider);
    await settle();
    await settle();
    expect(app.read(historyProvider), isEmpty);
  });

  test('Label badge mengikuti pengaturan istilah indikatif', () {
    final item = HistoryItem.fromAnalysis(sampleAnalysis('x', RiskLevel.malicious));
    expect(item.badge(), 'MALICIOUS');
    expect(item.badge(soft: true), 'Terindikasi Serangan');
    final json = jsonEncode(item.toJson());
    expect(HistoryItem.fromJson(jsonDecode(json) as Map<String, dynamic>).badge(),
        'MALICIOUS');
  });
}
