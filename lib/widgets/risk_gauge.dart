import 'dart:math';
import 'package:flutter/material.dart';

/// Gauge setengah lingkaran untuk menampilkan skor risiko 0..1.
class RiskGauge extends StatelessWidget {
  final double value; // 0..1
  final Color color;
  final String label;
  final String caption;

  const RiskGauge({
    super.key,
    required this.value,
    required this.color,
    required this.label,
    required this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 220,
      height: 150,
      child: CustomPaint(
        painter: _GaugePainter(
          value: value.clamp(0, 1),
          color: color,
          track: theme.colorScheme.surfaceContainerHighest,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              '${(value * 100).round()}%',
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: theme.textTheme.titleMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(caption, style: theme.textTheme.bodySmall),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double value;
  final Color color;
  final Color track;

  _GaugePainter({required this.value, required this.color, required this.track});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 16.0;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      (size.height - stroke) * 2,
    );
    final base = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final fg = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    // setengah lingkaran: 180° (pi) mulai dari kiri.
    canvas.drawArc(rect, pi, pi, false, base);
    canvas.drawArc(rect, pi, pi * value, false, fg);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.value != value || old.color != color || old.track != track;
}
