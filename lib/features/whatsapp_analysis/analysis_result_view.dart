import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../models/analysis_result.dart';
import '../../providers/providers.dart';
import '../../widgets/lime_word.dart';
import '../../widgets/risk_gauge.dart';

/// Tampilan hasil analisis pesan + penjelasan LIME.
class AnalysisResultView extends ConsumerWidget {
  final AnalysisResult result;
  const AnalysisResultView({super.key, required this.result});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final soft = ref.watch(settingsProvider.select((s) => s.softLabels));
    final theme = Theme.of(context);
    final color = AppTheme.riskColor(result.riskLevel);
    final safeColor = AppTheme.riskColor(RiskLevel.safe);
    final maxWeight = result.explanation
        .map((e) => e.weight.abs())
        .fold<double>(0.01, (a, b) => b > a ? b : a);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Column(
              children: [
                Text('SOCIAL ENGINEERING',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(letterSpacing: 1.2)),
                const SizedBox(height: 4),
                RiskGauge(
                  value: result.score,
                  color: color,
                  label: soft ? result.riskLevel.labelId : result.riskLevel.label,
                  caption: 'Confidence ${(result.confidence * 100).round()}%',
                ),
                const SizedBox(height: 6),
                Text('Mesin: ${result.engine}',
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Icon(Icons.psychology_alt_outlined,
                size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text('Kenapa? (LIME)', style: theme.textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 4),
        Text(
            'Kata yang paling memengaruhi prediksi. Positif (+) mendorong ke '
            'berisiko, negatif (−) mendorong ke aman.',
            style: theme.textTheme.bodySmall),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: result.explanationPending
                // Tahap 2: skor sudah tampil, LIME (~100x inferensi) menyusul.
                ? Row(
                    children: [
                      const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                            'Menyusun penjelasan: menguji ~100 variasi pesan '
                            'di HP. Biasanya 5–15 detik.',
                            style: theme.textTheme.bodySmall),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      for (final e in result.explanation)
                        LimeWord(
                            item: e,
                            maxWeight: maxWeight,
                            color: color,
                            safeColor: safeColor),
                    ],
                  ),
          ),
        ),
        if (result.probabilities.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Probabilitas model', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                children: [
                  for (final p in result.probabilities.entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          SizedBox(width: 92, child: Text(p.key)),
                          Expanded(
                            child: LinearProgressIndicator(
                              value: p.value,
                              minHeight: 10,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          SizedBox(
                            width: 52,
                            child: Text('${(p.value * 100).toStringAsFixed(1)}%',
                                textAlign: TextAlign.right,
                                style: theme.textTheme.bodySmall),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pesan yang dianalisis',
                    style: theme.textTheme.labelLarge),
                const SizedBox(height: 6),
                Text(result.message,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 18, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(AppConstants.disclaimer,
                    style: theme.textTheme.bodySmall),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
