import 'analysis_result.dart';
import 'malware_result.dart';

enum HistoryKind { message, malware }

/// Entri riwayat gabungan (pesan WhatsApp atau analisis APK).
class HistoryItem {
  final HistoryKind kind;
  final String title;
  final String subtitle;
  final String badge; // label risiko singkat
  final Severity severity; // dipakai untuk warna
  final DateTime createdAt;

  /// Hasil lengkap untuk halaman detail (sesuai [kind]).
  final AnalysisResult? analysis;
  final MalwareResult? malware;

  const HistoryItem({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.severity,
    required this.createdAt,
    this.analysis,
    this.malware,
  });

  factory HistoryItem.fromAnalysis(AnalysisResult r,
      {String title = 'WhatsApp Message'}) {
    final sev = switch (r.riskLevel) {
      RiskLevel.safe => Severity.low,
      RiskLevel.suspicious => Severity.medium,
      RiskLevel.high => Severity.high,
      RiskLevel.malicious => Severity.critical,
    };
    return HistoryItem(
      kind: HistoryKind.message,
      title: title,
      subtitle: r.message,
      badge: r.riskLevel.label,
      severity: sev,
      createdAt: r.createdAt,
      analysis: r,
    );
  }

  factory HistoryItem.fromMalware(MalwareResult r) {
    return HistoryItem(
      kind: HistoryKind.malware,
      title: r.fileName,
      subtitle: 'APK Analysis · skor ${r.riskScore}/100',
      badge: r.riskLevel.label,
      severity: r.riskLevel,
      createdAt: r.createdAt,
      malware: r,
    );
  }
}
