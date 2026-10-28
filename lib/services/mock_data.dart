import '../models/analysis_result.dart';
import '../models/history_item.dart';
import '../models/lime_explanation.dart';
import '../models/malware_result.dart';

/// Data awal (seed) agar dashboard & riwayat tidak kosong saat pertama dibuka.
class MockData {
  static List<String> sampleMessages = const [
    'Selamat! Anda mendapatkan hadiah Rp5.000.000. Klik link berikut untuk '
        'klaim sekarang. Akun akan diblokir jika tidak melakukan verifikasi.',
    'Pak, file laporan rapat sudah saya kirim ke email ya. Terima kasih.',
    'Info: paket Anda tertahan. Bayar pajak kirim di http://cek-paket.link',
    'Meeting besok jam 10 di ruang 3, jangan lupa bawa laptop.',
  ];

  static List<String> sampleApks = const [
    'whatsapp_mod_v2.apk',
    'bank_secure.apk',
    'game_booster.apk',
    'invoice_viewer.apk',
  ];

  static List<AnalysisResult> seedAnalyses() => [
        AnalysisResult(
          message: sampleMessages[0],
          riskLevel: RiskLevel.high,
          score: 0.94,
          confidence: 0.94,
          explanation: const [
            LimeExplanation(word: 'hadiah', weight: 0.31),
            LimeExplanation(word: 'verifikasi', weight: 0.26),
            LimeExplanation(word: 'diblokir', weight: 0.28),
            LimeExplanation(word: 'klik', weight: 0.21),
          ],
          createdAt: DateTime.now().subtract(const Duration(minutes: 8)),
        ),
        AnalysisResult(
          message: sampleMessages[1],
          riskLevel: RiskLevel.safe,
          score: 0.05,
          confidence: 0.92,
          explanation: const [
            LimeExplanation(word: '(tidak ada indikator)', weight: 0.02),
          ],
          createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        ),
      ];

  static List<HistoryItem> seedHistory() => [
        ...seedAnalyses().map(HistoryItem.fromAnalysis),
        HistoryItem.fromMalware(
          MalwareResult(
            fileName: 'game_booster.apk',
            sha256: 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2',
            riskScore: 72,
            indicators: const [
              MalwareIndicator(name: 'SEND_SMS', severity: Severity.high),
              MalwareIndicator(
                  name: 'REQUEST_INSTALL_PACKAGES', severity: Severity.high),
              MalwareIndicator(
                  name: 'Obfuscated code', severity: Severity.high),
            ],
            createdAt: DateTime.now().subtract(const Duration(hours: 5)),
          ),
        ),
      ];
}
