import '../models/analysis_result.dart';

/// Kebijakan peringatan: kapan hasil scan otomatis WhatsApp memunculkan
/// notifikasi sistem di HP pengguna.
///
/// Ini keputusan UX yang menentukan kepercayaan pengguna:
///  - terlalu longgar (mis. ikut "SUSPICIOUS") -> notifikasi sering muncul,
///    pengguna jadi terbiasa mengabaikannya (alert fatigue);
///  - terlalu ketat (hanya "MALICIOUS") -> penipuan yang skornya 0,5–0,75 lolos
///    tanpa peringatan.
bool shouldAlert(AnalysisResult r) =>
    r.riskLevel.index >= RiskLevel.high.index;

/// Judul & isi notifikasi untuk pesan dari [sender].
({String title, String body}) alertText(AnalysisResult r, String sender,
    {bool soft = true}) {
  final label = soft ? r.riskLevel.labelId : r.riskLevel.label;
  final snippet =
      r.message.length > 140 ? '${r.message.substring(0, 140)}…' : r.message;
  return (
    title: '⚠️ Pesan berisiko dari $sender',
    body: '$label · ${(r.score * 100).round()}% kemungkinan penipuan\n$snippet',
  );
}
