import 'dart:math';

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Gauge setengah lingkaran berupa kapsul-kapsul (gaya "Protection Score" di
/// referensi). Kapsul yang terisi = proporsi [score] 0..100.
class ProtectionGauge extends StatelessWidget {
  final int score;
  final String label;
  final double size;

  const ProtectionGauge({
    super.key,
    required this.score,
    required this.label,
    this.size = 260,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return Semantics(
      label: '$label $score dari 100',
      child: SizedBox(
        width: size,
        height: size * 0.62,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: score.toDouble()),
          duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (_, v, __) => CustomPaint(
            painter: _CapsulePainter(
              fill: v / 100,
              on: AppColors.ember,
              onLight: AppColors.apricot,
              off: theme.brightness == Brightness.light
                  ? const Color(0xFFF6E3D4)
                  : const Color(0xFF3A2C23),
            ),
            child: Align(
              alignment: const Alignment(0, 0.85),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${v.round()}',
                      style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w800, letterSpacing: -1.5, height: 1)),
                  const SizedBox(height: 2),
                  Text(label, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CapsulePainter extends CustomPainter {
  final double fill;
  final Color on, onLight, off;
  _CapsulePainter({required this.fill, required this.on, required this.onLight, required this.off});

  static const _count = 11;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.98);
    final outer = size.width * 0.48;
    final inner = size.width * 0.29;
    final thickness = size.width * 0.085;
    final lit = (fill * _count).round();

    for (var i = 0; i < _count; i++) {
      // Dari kiri (180°) ke kanan (0°).
      final angle = pi - pi * i / (_count - 1);
      final dir = Offset(cos(angle), -sin(angle));
      final a = center + dir * inner;
      final b = center + dir * outer;
      final on_ = i < lit;
      final paint = Paint()
        ..strokeWidth = thickness
        ..strokeCap = StrokeCap.round
        ..shader = on_
            ? LinearGradient(colors: [onLight, on]).createShader(Rect.fromPoints(a, b))
            : null
        ..color = off;
      canvas.drawLine(a, b, paint);
      if (on_) {
        // Kilau tipis agar kapsul terlihat "kaca" seperti referensi.
        canvas.drawLine(
            a + dir * thickness * 0.2,
            b - dir * thickness * 0.4,
            Paint()
              ..strokeWidth = thickness * 0.22
              ..strokeCap = StrokeCap.round
              ..color = Colors.white.withValues(alpha: 0.35));
      }
    }
  }

  @override
  bool shouldRepaint(_CapsulePainter old) => old.fill != fill || old.off != off;
}
