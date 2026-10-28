import 'package:flutter/material.dart';
import '../models/lime_explanation.dart';

/// Baris visualisasi satu kontribusi LIME: kata + bar proporsional + bobot.
/// Bobot negatif (mendorong ke "aman") memakai [safeColor].
class LimeWord extends StatelessWidget {
  final LimeExplanation item;
  final double maxWeight; // nilai |bobot| terbesar
  final Color color;
  final Color safeColor;

  const LimeWord({
    super.key,
    required this.item,
    required this.maxWeight,
    required this.color,
    required this.safeColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final frac =
        maxWeight <= 0 ? 0.0 : (item.weight.abs() / maxWeight).clamp(0.0, 1.0);
    final barColor = item.isRisky ? color : safeColor;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(
              item.word,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: frac),
                duration: const Duration(milliseconds: 650),
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => LinearProgressIndicator(
                  value: v,
                  minHeight: 14,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(barColor),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 48,
            child: Text(
              '${item.isRisky ? '+' : '−'}${item.weight.abs().toStringAsFixed(2)}',
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
