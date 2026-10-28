import 'package:flutter/material.dart';
import '../../models/analysis_result.dart';
import '../../models/malware_result.dart';

/// Tema Material 3 + helper warna untuk tingkat risiko.
class AppTheme {
  static const seed = Color(0xFF2563EB); // biru

  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      appBarTheme: const AppBarTheme(centerTitle: false),
    );
  }

  // ---- warna risiko pesan ----
  static Color riskColor(RiskLevel level) => switch (level) {
        RiskLevel.safe => const Color(0xFF16A34A),
        RiskLevel.suspicious => const Color(0xFFD97706),
        RiskLevel.high => const Color(0xFFEA580C),
        RiskLevel.malicious => const Color(0xFFDC2626),
      };

  // ---- warna severity (malware) ----
  static Color severityColor(Severity s) => switch (s) {
        Severity.low => const Color(0xFF16A34A),
        Severity.medium => const Color(0xFFD97706),
        Severity.high => const Color(0xFFEA580C),
        Severity.critical => const Color(0xFFDC2626),
      };
}
