import 'analysis_result.dart';
import 'malware_result.dart';

enum HistoryKind { message, malware }

/// Entri riwayat gabungan (pesan WhatsApp atau analisis APK).
class HistoryItem {
  final HistoryKind kind;
  final String title;
  final String subtitle;
  final Severity severity; // dipakai untuk warna
  final DateTime createdAt;

  /// Hasil lengkap untuk halaman detail (sesuai [kind]).
  final AnalysisResult? analysis;
  final MalwareResult? malware;

  const HistoryItem({
    required this.kind,
    required this.title,
    required this.subtitle,
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
      severity: r.riskLevel,
      createdAt: r.createdAt,
      malware: r,
    );
  }

  /// Label risiko singkat; [soft] = istilah "indikatif" dari Pengaturan.
  String badge({bool soft = false}) {
    final level = analysis?.riskLevel;
    if (level != null) return soft ? level.labelId : level.label;
    return soft ? severity.labelId : severity.label;
  }

  /// Yang disimpan hanya hasil analisis + judul; sisanya dihitung ulang.
  Map<String, dynamic> toJson() => {
        'title': title,
        if (analysis != null) 'analysis': analysis!.toJson(),
        if (malware != null) 'malware': malware!.toJson(),
      };

  factory HistoryItem.fromJson(Map<String, dynamic> j) {
    final a = j['analysis'];
    if (a != null) {
      return HistoryItem.fromAnalysis(
          AnalysisResult.fromJson(a as Map<String, dynamic>),
          title: j['title'] as String);
    }
    return HistoryItem.fromMalware(
        MalwareResult.fromJson(j['malware'] as Map<String, dynamic>));
  }
}
