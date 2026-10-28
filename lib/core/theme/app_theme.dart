import 'package:flutter/material.dart';

import '../../models/analysis_result.dart';
import '../../models/malware_result.dart';

/// Token warna aplikasi: oranye hangat sebagai identitas, tinta gelap untuk
/// aksi utama. Oranye TIDAK dipakai untuk tingkat risiko agar "tombol" dan
/// "bahaya" tidak tertukar.
class AppColors {
  static const ember = Color(0xFFFF5A1F); // aksi utama, tombol tengah, skor
  static const apricot = Color(0xFFFFB37A); // gradasi, batang skor kosong
  static const peachMist = Color(0xFFFFF0E3); // latar atas
  static const paper = Color(0xFFFBFAF8); // latar bawah & kartu
  static const ink = Color(0xFF161412); // tombol bulat & tombol utama
  static const moss = Color(0xFF1F9D57); // aman
  static const amber = Color(0xFFC98A04); // mencurigakan
  static const signal = Color(0xFFE5484D); // berisiko tinggi
  static const crimson = Color(0xFFB42318); // kritis / terindikasi serangan

  // Mode gelap: kakao gelap, bukan hitam netral.
  static const cocoa = Color(0xFF1C1511);
  static const cocoaRaised = Color(0xFF2A201A);
  static const emberDim = Color(0xFF4A2414);

  /// Gradasi latar halaman (atas -> bawah).
  static List<Color> pageGradient(Brightness b) => b == Brightness.light
      ? const [peachMist, paper]
      : const [Color(0xFF3A2216), cocoa];

  /// Gradasi pita aksi (CTA) seperti "Run Smart Scan" di referensi.
  static const ctaGradient = [Color(0xFFFF7A3D), ember, Color(0xFFE8430E)];
}

/// Tema Material 3 + helper warna untuk tingkat risiko.
class AppTheme {
  static const fontFamily = 'PlusJakartaSans';

  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final light = brightness == Brightness.light;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.ember,
      brightness: brightness,
    ).copyWith(
      primary: AppColors.ember,
      onPrimary: Colors.white,
      primaryContainer: light ? const Color(0xFFFFE1CF) : AppColors.emberDim,
      onPrimaryContainer: light ? const Color(0xFF5A1D04) : const Color(0xFFFFD8C4),
      secondary: AppColors.ink,
      surface: light ? AppColors.paper : AppColors.cocoa,
      surfaceContainerLowest: light ? Colors.white : const Color(0xFF221A15),
      surfaceContainerHighest: light ? const Color(0xFFF1ECE7) : AppColors.cocoaRaised,
      error: AppColors.signal,
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: fontFamily,
      // Latar padat untuk halaman yang di-push (detail); gradasi dipasang di
      // HomeShell dan halaman tab memakai Scaffold transparan di atasnya.
      scaffoldBackgroundColor: light ? AppColors.paper : AppColors.cocoa,
    );
    // Material 3 menambah letterSpacing 0,1–0,5 yang membuat Plus Jakarta Sans
    // terlalu renggang; nolkan dulu, lalu rapatkan judul besar.
    final t = base.textTheme.apply(fontFamily: fontFamily);
    TextStyle? tight(TextStyle? s, {double spacing = 0, FontWeight? w, double? h}) =>
        s?.copyWith(letterSpacing: spacing, fontWeight: w, height: h);
    final text = t.copyWith(
      displaySmall: tight(t.displaySmall, spacing: -1, w: FontWeight.w800),
      headlineMedium: tight(t.headlineMedium, spacing: -0.6, w: FontWeight.w800, h: 1.1),
      titleLarge: tight(t.titleLarge, spacing: -0.3, w: FontWeight.w700),
      titleMedium: tight(t.titleMedium, w: FontWeight.w700),
      titleSmall: tight(t.titleSmall, w: FontWeight.w700),
      bodyLarge: tight(t.bodyLarge),
      bodyMedium: tight(t.bodyMedium),
      bodySmall: tight(t.bodySmall),
      labelLarge: tight(t.labelLarge, w: FontWeight.w600),
      labelMedium: tight(t.labelMedium, w: FontWeight.w600),
      labelSmall: tight(t.labelSmall),
    );
    // Label chip: putih saat terpilih (latar tinta/ember), gelap saat tidak.
    final chipLabel = WidgetStateColor.resolveWith((s) =>
        s.contains(WidgetState.selected) ? Colors.white : scheme.onSurface);

    return base.copyWith(
      textTheme: text,
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLowest,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(
              color: light ? const Color(0xFFF0E6DD) : const Color(0xFF3A2C23)),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      // Tombol utama hitam seperti referensi; oranye untuk satu aksi tengah.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: light ? AppColors.ink : AppColors.ember,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(54),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(
              fontFamily: fontFamily, fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape: const StadiumBorder(),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant),
        backgroundColor: scheme.surfaceContainerLowest,
        selectedColor: light ? AppColors.ink : AppColors.ember,
        labelStyle: TextStyle(
            fontFamily: fontFamily, fontWeight: FontWeight.w600, color: chipLabel),
        checkmarkColor: Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
              color: light ? const Color(0xFFF0E6DD) : const Color(0xFF3A2C23)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.ember, width: 1.6),
        ),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: StadiumBorder(),
      ),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: AppColors.ember),
    );
  }

  // ---- warna risiko pesan ----
  static Color riskColor(RiskLevel level) => switch (level) {
        RiskLevel.safe => AppColors.moss,
        RiskLevel.suspicious => AppColors.amber,
        RiskLevel.high => AppColors.signal,
        RiskLevel.malicious => AppColors.crimson,
      };

  // ---- warna severity (malware) ----
  static Color severityColor(Severity s) => switch (s) {
        Severity.low => AppColors.moss,
        Severity.medium => AppColors.amber,
        Severity.high => AppColors.signal,
        Severity.critical => AppColors.crimson,
      };
}
