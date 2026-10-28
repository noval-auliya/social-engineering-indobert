import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/history_item.dart';
import '../malware_analysis/malware_result_view.dart';
import '../whatsapp_analysis/analysis_result_view.dart';

/// Detail satu entri riwayat: isi pesan lengkap + penjelasan hasil scan.
class HistoryDetailPage extends StatelessWidget {
  final HistoryItem item;
  const HistoryDetailPage({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final analysis = item.analysis;
    final malware = item.malware;

    return Scaffold(
      appBar: AppBar(
        title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Icon(Icons.schedule,
                  size: 16, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                'Di-scan ${DateFormat('dd MMM yyyy, HH:mm').format(item.createdAt)}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (analysis != null)
            AnalysisResultView(result: analysis)
          else if (malware != null)
            MalwareResultView(result: malware)
          else
            const Text('Detail hasil tidak tersedia untuk entri ini.'),
        ],
      ),
    );
  }
}
