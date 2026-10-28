import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/analysis_result.dart';
import '../../models/correction.dart';
import '../../models/history_item.dart';
import '../../models/malware_result.dart';
import '../../providers/providers.dart';

/// Kartu "Hasil ini salah?" di detail riwayat: pengguna memilih label yang
/// benar, disimpan sebagai data latih asli untuk melatih ulang model.
class CorrectionCard extends ConsumerWidget {
  final HistoryItem item;
  const CorrectionCard({super.key, required this.item});

  static const _names = {
    'normal': 'Normal / aman',
    'penipuan': 'Penipuan',
    'promo': 'Promo / iklan',
    'aman': 'Aplikasi aman',
    'malware': 'Malware / berbahaya',
  };

  /// Label yang diprediksi aplikasi, dalam kosakata label latih.
  static String predictedLabel(HistoryItem item) {
    final a = item.analysis;
    if (a != null) {
      if (a.probabilities.isNotEmpty) {
        return a.probabilities.entries.reduce((x, y) => y.value > x.value ? y : x).key;
      }
      return a.riskLevel == RiskLevel.safe ? 'normal' : 'penipuan';
    }
    final level = item.malware!.riskLevel;
    return level.index >= Severity.high.index ? 'malware' : 'aman';
  }

  static String _key(HistoryItem item) =>
      item.analysis?.message ?? item.malware!.sha256;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final key = _key(item);
    final existing = ref
        .watch(correctionsProvider)
        .where((c) => c.key == key)
        .firstOrNull;
    final predicted = predictedLabel(item);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Icon(existing == null ? Icons.flag_outlined : Icons.flag,
                color: existing == null
                    ? theme.colorScheme.outline
                    : theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(existing == null ? 'Hasil ini salah?' : 'Sudah dikoreksi',
                      style: theme.textTheme.titleSmall),
                  Text(
                    existing == null
                        ? 'Aplikasi menilai: ${_names[predicted]}. Koreksi Anda '
                            'membantu melatih ulang AI.'
                        : 'Label yang benar: ${_names[existing.correctLabel]}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => _pick(context, ref, predicted, existing),
              child: Text(existing == null ? 'Koreksi' : 'Ubah'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context, WidgetRef ref, String predicted,
      Correction? existing) async {
    final labels = item.analysis != null ? Correction.messageLabels : Correction.apkLabels;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Seharusnya hasilnya:')),
            for (final l in labels)
              ListTile(
                leading: Icon(l == (existing?.correctLabel ?? predicted)
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off),
                title: Text(_names[l]!),
                subtitle: l == predicted ? const Text('penilaian aplikasi') : null,
                onTap: () => Navigator.pop(ctx, l),
              ),
            if (existing != null)
              ListTile(
                leading: const Icon(Icons.undo),
                title: const Text('Batalkan koreksi'),
                onTap: () => Navigator.pop(ctx, ''),
              ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    final notifier = ref.read(correctionsProvider.notifier);
    final key = _key(item);
    if (choice.isEmpty || choice == predicted) {
      // Batal, atau ternyata penilaian aplikasi sudah benar.
      notifier.remove(key);
      return;
    }
    final apk = item.malware;
    notifier.add(Correction(
      kind: apk == null ? CorrectionKind.message : CorrectionKind.apk,
      key: key,
      predictedLabel: predicted,
      correctLabel: choice,
      createdAt: DateTime.now(),
      packageName: apk?.packageName ?? '',
      permissions: apk?.permissions ?? const [],
      apis: apk?.apis ?? const [],
    ));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Koreksi disimpan. Ekspor dari Pengaturan untuk melatih ulang AI.')));
    }
  }
}
