import 'dart:math';

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Latar gradasi oranye hangat dengan tekstur titik halus di bagian atas
/// (seperti layar onboarding di referensi desain).
class WarmBackground extends StatelessWidget {
  final Widget child;

  /// Intensitas oranye: 0 = tenang (halaman biasa), 1 = penuh (onboarding).
  final double intensity;

  const WarmBackground({super.key, required this.child, this.intensity = 0});

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final base = AppColors.pageGradient(b);
    final top = Color.lerp(base.first, AppColors.ember, intensity * 0.85)!;
    final mid = Color.lerp(base.first, AppColors.apricot, intensity * 0.6)!;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, mid, base.last],
          stops: const [0, 0.38, 0.8],
        ),
      ),
      child: CustomPaint(
        painter: _DotTexturePainter(
            color: (b == Brightness.light ? Colors.white : AppColors.apricot)
                .withValues(alpha: 0.35 + intensity * 0.2)),
        child: child,
      ),
    );
  }
}

/// Titik-titik halus yang memudar ke bawah (tekstur "halftone" referensi).
class _DotTexturePainter extends CustomPainter {
  final Color color;
  _DotTexturePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 14.0;
    final fadeEnd = size.height * 0.32;
    final paint = Paint();
    for (var y = gap; y < fadeEnd; y += gap) {
      final fade = 1 - y / fadeEnd;
      paint.color = color.withValues(alpha: color.a * fade);
      // Baris ganjil digeser setengah jarak -> pola selang-seling.
      final offset = (y ~/ gap).isOdd ? gap / 2 : 0.0;
      for (var x = gap / 2 + offset; x < size.width; x += gap) {
        canvas.drawCircle(Offset(x, y), max(0.6, 1.2 * fade), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotTexturePainter old) => old.color != color;
}
