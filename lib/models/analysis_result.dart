import 'lime_explanation.dart';

/// Tingkat risiko pesan, selaras dengan label pada dokumentasi.
enum RiskLevel { safe, suspicious, high, malicious }

extension RiskLevelX on RiskLevel {
  String get label => switch (this) {
        RiskLevel.safe => 'SAFE',
        RiskLevel.suspicious => 'SUSPICIOUS',
        RiskLevel.high => 'HIGH RISK',
        RiskLevel.malicious => 'MALICIOUS',
      };

  /// Istilah yang lebih "halus" sesuai catatan metodologi di dokumentasi.
  String get labelId => switch (this) {
        RiskLevel.safe => 'Aman',
        RiskLevel.suspicious => 'Mencurigakan',
        RiskLevel.high => 'Berisiko Tinggi',
        RiskLevel.malicious => 'Terindikasi Serangan',
      };

  String get apiLabel => switch (this) {
        RiskLevel.safe => 'safe',
        RiskLevel.suspicious => 'suspicious',
        RiskLevel.high => 'high_risk',
        RiskLevel.malicious => 'malicious',
      };

  static RiskLevel fromApi(String value) => switch (value) {
        'safe' => RiskLevel.safe,
        'suspicious' => RiskLevel.suspicious,
        'high_risk' => RiskLevel.high,
        'malicious' => RiskLevel.malicious,
        _ => RiskLevel.suspicious,
      };
}

/// Hasil analisis sebuah pesan.
class AnalysisResult {
  final String message;
  final RiskLevel riskLevel;
  final double score; // 0..1
  final double confidence; // 0..1
  final List<LimeExplanation> explanation;
  final DateTime createdAt;

  /// Mesin yang menghasilkan analisis, mis. "IndoBERT (on-device)".
  final String engine;

  /// Probabilitas per label model (kosong untuk analisis kata kunci).
  final Map<String, double> probabilities;

  /// Skor sudah ada tetapi penjelasan LIME belum dihitung (dihitung
  /// belakangan karena butuh ~100x inferensi).
  final bool explanationPending;

  const AnalysisResult({
    required this.message,
    required this.riskLevel,
    required this.score,
    required this.confidence,
    required this.explanation,
    required this.createdAt,
    this.engine = 'Kata kunci',
    this.probabilities = const {},
    this.explanationPending = false,
  });

  AnalysisResult withExplanation(List<LimeExplanation> e) => AnalysisResult(
        message: message,
        riskLevel: riskLevel,
        score: score,
        confidence: confidence,
        explanation: e,
        createdAt: createdAt,
        engine: engine,
        probabilities: probabilities,
      );

  factory AnalysisResult.fromJson(Map<String, dynamic> json) {
    return AnalysisResult(
      message: json['message'] as String? ?? '',
      riskLevel: RiskLevelX.fromApi(json['label'] as String),
      score: (json['score'] as num).toDouble(),
      confidence: (json['confidence'] as num).toDouble(),
      explanation: (json['explanation'] as List)
          .map((e) => LimeExplanation.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdAt: json['created_at'] == null
          ? DateTime.now()
          : DateTime.parse(json['created_at'] as String),
      engine: json['engine'] as String? ?? 'Kata kunci',
      probabilities: {
        for (final e in ((json['probabilities'] as Map?) ?? const {}).entries)
          e.key as String: (e.value as num).toDouble(),
      },
      explanationPending: json['explanation_pending'] as bool? ?? false,
    );
  }

  /// Format sama dengan [AnalysisResult.fromJson], untuk disimpan di HP.
  Map<String, dynamic> toJson() => {
        'message': message,
        'label': riskLevel.apiLabel,
        'score': score,
        'confidence': confidence,
        'explanation': [for (final e in explanation) e.toJson()],
        'created_at': createdAt.toIso8601String(),
        'engine': engine,
        'probabilities': probabilities,
        'explanation_pending': explanationPending,
      };
}
