import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:social_engineering_detector/services/malware_service.dart';

/// Dijalankan di HP Android:
///   flutter test integration_test/apk_analyzer_on_device_test.dart -d <device_id>
///
/// Menganalisis APK aplikasi ini sendiri (yang sudah terpasang) dengan
/// ApkAnalyzer.kt, lalu memeriksa fitur yang pasti ada.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ApkAnalyzer membaca APK asli di HP', (tester) async {
    const channel = MethodChannel('sed/apk_analyzer');
    final path = await channel.invokeMethod<String>('selfApkPath');
    debugPrint('APK: $path');

    final sw = Stopwatch()..start();
    final result = await MalwareService().analyzeFile(path!, 'self.apk');
    debugPrint('Analisis: ${sw.elapsedMilliseconds} ms');
    debugPrint('paket=${result.packageName} skor=${result.riskScore} '
        'ml=${result.mlProbability} aturan=${result.rulePoints}');
    debugPrint('indikator=${result.indicators.map((i) => i.name).toList()}');
    debugPrint('faktorML=${result.mlFactors.map((e) => e.key).toList()}');
    debugPrint('sha256=${result.sha256} sertifikat=${result.certSubject}');

    expect(result.packageName, 'com.example.social_engineering_detector');
    expect(result.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(result.certSubject, contains('Android Debug'));
    // Aplikasi ini memang punya NotificationListenerService.
    expect(result.indicators.map((i) => i.name),
        contains('Membaca semua notifikasi'));
    expect(result.indicators.map((i) => i.name),
        contains('Ditandatangani sertifikat debug'));
    // Flutter memuat library native -> API System.loadLibrary terbaca dari DEX.
    expect(result.mlFactors.map((e) => e.key),
        contains('Ljava/lang/System;->loadLibrary'));
  });
}
