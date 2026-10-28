/// Koreksi pengguna atas hasil deteksi ("Hasil ini salah").
///
/// Disimpan di HP lalu diekspor ke CSV sebagai data latih asli:
///  - pesan -> ml/data/*.csv            (kolom Teks,label; dibaca train.py)
///  - APK   -> ml/malware/data/koreksi_apk*.csv (dibaca train_malware.py)
enum CorrectionKind { message, apk }

class Correction {
  /// Label yang sama dengan model teks (ml/train.py LABELS).
  static const messageLabels = ['normal', 'penipuan', 'promo'];
  static const apkLabels = ['aman', 'malware'];

  final CorrectionKind kind;

  /// Kunci unik: isi pesan, atau SHA-256 untuk APK.
  final String key;
  final String predictedLabel;
  final String correctLabel;
  final DateTime createdAt;

  // ---- khusus APK: fitur yang dibutuhkan untuk melatih ulang ----
  final String packageName;
  final List<String> permissions;
  final List<String> apis;

  const Correction({
    required this.kind,
    required this.key,
    required this.predictedLabel,
    required this.correctLabel,
    required this.createdAt,
    this.packageName = '',
    this.permissions = const [],
    this.apis = const [],
  });

  /// Indeks label untuk CSV latih (pesan: 0/1/2, APK: 0 aman / 1 malware).
  int get labelIndex => (kind == CorrectionKind.message ? messageLabels : apkLabels)
      .indexOf(correctLabel);

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'key': key,
        'predicted': predictedLabel,
        'correct': correctLabel,
        'created_at': createdAt.toIso8601String(),
        if (kind == CorrectionKind.apk) ...{
          'package': packageName,
          'permissions': permissions,
          'apis': apis,
        },
      };

  factory Correction.fromJson(Map<String, dynamic> j) => Correction(
        kind: CorrectionKind.values.byName(j['kind'] as String),
        key: j['key'] as String,
        predictedLabel: j['predicted'] as String,
        correctLabel: j['correct'] as String,
        createdAt: DateTime.parse(j['created_at'] as String),
        packageName: j['package'] as String? ?? '',
        permissions: ((j['permissions'] as List?) ?? const []).cast<String>(),
        apis: ((j['apis'] as List?) ?? const []).cast<String>(),
      );
}
