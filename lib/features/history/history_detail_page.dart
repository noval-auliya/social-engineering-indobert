import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/history_item.dart';
import '../../providers/providers.dart';
import '../malware_analysis/malware_result_view.dart';
import '../whatsapp_analysis/analysis_result_view.dart';
import 'correction_card.dart';

/// Detail satu entri riwayat: isi pesan lengkap + penjelasan hasil scan.
///
/// Entri dari scan otomatis hanya berisi skor; penjelasan LIME dihitung saat
/// halaman ini dibuka lalu disimpan kembali ke riwayat.
class HistoryDetailPage extends ConsumerStatefulWidget {
  final HistoryItem item;
  const HistoryDetailPage({super.key, required this.item});

  @override
  ConsumerState<HistoryDetailPage> createState() => _HistoryDetailPageState();
}

class _HistoryDetailPageState extends ConsumerState<HistoryDetailPage> {
  late HistoryItem _item = widget.item;

  @override
  void initState() {
    super.initState();
    if (_item.analysis?.explanationPending ?? false) {
      ref.read(historyProvider.notifier).explainItem(_item).then((updated) {
        if (mounted) setState(() => _item = updated);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final analysis = _item.analysis;
    final malware = _item.malware;

    return Scaffold(
      appBar: AppBar(
        title: Text(_item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
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
                'Di-scan ${DateFormat('dd MMM yyyy, HH:mm').format(_item.createdAt)}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (analysis != null || malware != null) ...[
            CorrectionCard(item: _item),
            const SizedBox(height: 12),
          ],
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
