import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../models/history_item.dart';
import '../../models/malware_result.dart';
import '../../providers/providers.dart';
import '../../widgets/stat_tile.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(dashboardStatsProvider);
    final history = ref.watch(historyProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appName),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0),
          child: Container(height: 1, color: theme.colorScheme.outlineVariant),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _TotalCard(total: stats.total),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: 'Aman',
                  value: '${stats.safe}',
                  color: const Color(0xFF16A34A),
                  icon: Icons.verified_user_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatTile(
                  label: 'Mencurigakan',
                  value: '${stats.warning}',
                  color: const Color(0xFFD97706),
                  icon: Icons.warning_amber_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatTile(
                  label: 'Berisiko',
                  value: '${stats.high}',
                  color: const Color(0xFFDC2626),
                  icon: Icons.gpp_maybe_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _DistributionCard(stats: stats),
          const SizedBox(height: 16),
          Text('Analisis Terakhir', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (history.isEmpty)
            const _EmptyHint()
          else
            ...history.take(5).map((h) => _RecentTile(item: h)),
          const SizedBox(height: 16),
          _DisclaimerBanner(),
        ],
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  final int total;
  const _TotalCard({required this.total});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 28),
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              theme.colorScheme.primary,
              theme.colorScheme.primary.withValues(alpha: 0.75),
            ],
          ),
        ),
        child: Column(
          children: [
            Text('Total Analisis',
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: Colors.white70)),
            const SizedBox(height: 6),
            Text('$total',
                style: theme.textTheme.displayMedium?.copyWith(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

class _DistributionCard extends StatelessWidget {
  final DashboardStats stats;
  const _DistributionCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = stats.total == 0 ? 1 : stats.total;
    final sections = <_Seg>[
      _Seg('Aman', stats.safe, const Color(0xFF16A34A)),
      _Seg('Mencurigakan', stats.warning, const Color(0xFFD97706)),
      _Seg('Berisiko', stats.high, const Color(0xFFDC2626)),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Distribusi Risiko', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 130,
                  height: 130,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 34,
                      sections: [
                        for (final s in sections)
                          PieChartSectionData(
                            value: s.value.toDouble(),
                            color: s.color,
                            radius: 26,
                            showTitle: false,
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    children: [
                      for (final s in sections)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                    color: s.color,
                                    borderRadius: BorderRadius.circular(3)),
                              ),
                              const SizedBox(width: 8),
                              Expanded(child: Text(s.label)),
                              Text('${((s.value / total) * 100).round()}%',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Seg {
  final String label;
  final int value;
  final Color color;
  _Seg(this.label, this.value, this.color);
}

class _RecentTile extends StatelessWidget {
  final HistoryItem item;
  const _RecentTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.severityColor(item.severity);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          item.kind == HistoryKind.message
              ? Icons.chat_bubble_outline
              : Icons.android,
          color: color,
        ),
        title: Text(item.title,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(item.subtitle,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: _Badge(text: item.badge, color: color),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text('Belum ada analisis.',
                style: Theme.of(context).textTheme.bodyMedium),
          ),
        ),
      );
}

class _DisclaimerBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(AppConstants.disclaimer,
                style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
