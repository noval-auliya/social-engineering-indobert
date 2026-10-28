import '../models/correction.dart';

/// Ekspor koreksi ke CSV yang langsung bisa dipakai skrip training.

/// `Teks,label` (0 normal, 1 penipuan, 2 promo) -> salin ke ml/data/.
String messageCorrectionsCsv(List<Correction> all) {
  final rows = [
    'Teks,label',
    for (final c in all)
      if (c.kind == CorrectionKind.message) '${csvField(c.key)},${c.labelIndex}',
  ];
  return '${rows.join('\n')}\n';
}

/// `label,package,sha256,permissions,apis` (izin/API dipisah `|`, bukan `;`
/// karena nama API Android sendiri memuat `;`, mis. `Ljava/lang/Runtime;->exec`)
/// -> salin ke ml/malware/data/ dengan nama koreksi_apk*.csv.
String apkCorrectionsCsv(List<Correction> all) {
  final rows = [
    'label,package,sha256,permissions,apis',
    for (final c in all)
      if (c.kind == CorrectionKind.apk)
        [
          '${c.labelIndex}',
          csvField(c.packageName),
          c.key,
          csvField(c.permissions.join(listSeparator)),
          csvField(c.apis.join(listSeparator)),
        ].join(','),
  ];
  return '${rows.join('\n')}\n';
}

/// Pemisah daftar izin/API di CSV koreksi APK (lihat train_malware.py).
const listSeparator = '|';

/// RFC 4180: bungkus dengan tanda kutip, kutip di dalam digandakan.
/// Pesan WhatsApp sering berisi koma, kutip, dan baris baru.
String csvField(String v) => '"${v.replaceAll('"', '""')}"';
