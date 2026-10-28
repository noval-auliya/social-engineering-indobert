import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../models/history_item.dart';
import '../../providers/providers.dart';
import '../../widgets/scan_progress_banner.dart';
import 'history_detail_page.dart';

class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    final unseen = ref.watch(unseenHistoryProvider);
    final scan = ref.watch(scanProgressProvider);
    final scheme = Theme.of(context).colorScheme;
    final df = DateFormat('dd MMM, HH:mm');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Analisis'),
        actions: [
          if (history.isNotEmpty)
            IconButton(
              tooltip: 'Hapus semua',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () => _confirmClear(context, ref),
            ),
        ],
      ),
      body: Column(
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            child: scan.active
                ? ScanProgressBanner(progress: scan)
                : const SizedBox(width: double.infinity),
          ),
          Expanded(child: _buildList(context, history, unseen, scheme, df)),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context, List<HistoryItem> history,
      Set<HistoryItem> unseen, ColorScheme scheme, DateFormat df) {
    return history.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inbox_outlined,
                      size: 48, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 8),
                  const Text('Belum ada riwayat.'),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: history.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final h = history[i];
                final color = AppTheme.severityColor(h.severity);
                final isNew = unseen.contains(h);
                return Card(
                  clipBehavior: Clip.antiAlias,
                  shape: isNew
                      ? RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: scheme.primary, width: 1.5),
                        )
                      : null,
                  child: ListTile(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => HistoryDetailPage(item: h),
                    )),
                    leading: CircleAvatar(
                      backgroundColor: color.withValues(alpha: 0.12),
                      child: Icon(
                        h.kind == HistoryKind.message
                            ? Icons.chat_bubble_outline
                            : Icons.android,
                        color: color,
                      ),
                    ),
                    title: Row(
                      children: [
                        if (isNew)
                          Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('BARU',
                                style: TextStyle(
                                    color: scheme.onPrimary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800)),
                          ),
                        Flexible(
                          child: Text(h.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                    subtitle: Text(
                      '${h.subtitle}\n${df.format(h.createdAt)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    isThreeLine: true,
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(h.badge,
                          style: TextStyle(
                              color: color,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                );
              },
            );
  }

  void _confirmClear(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus riwayat?'),
        content: const Text('Semua entri riwayat (dummy) akan dihapus.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal')),
          FilledButton(
            onPressed: () {
              ref.read(historyProvider.notifier).clear();
              ref.read(unseenHistoryProvider.notifier).state = {};
              Navigator.pop(context);
            },
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }
}
