import 'package:flutter/material.dart';

import '../providers/providers.dart';

/// Banner beranimasi saat pesan WhatsApp sedang di-scan otomatis.
class ScanProgressBanner extends StatefulWidget {
  final ScanProgress progress;
  const ScanProgressBanner({super.key, required this.progress});

  @override
  State<ScanProgressBanner> createState() => _ScanProgressBannerState();
}

class _ScanProgressBannerState extends State<ScanProgressBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.progress;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RotationTransition(
                turns: _spin,
                child: Icon(Icons.radar, color: scheme.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Memindai pesan ${p.done + 1} dari ${p.total}',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'dari ${p.currentSender} · IndoBERT + LIME',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Bar atas: jumlah pesan selesai; bar bawah: pesan yang sedang diproses.
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: p.total == 0 ? 0 : p.done / p.total),
              duration: const Duration(milliseconds: 400),
              builder: (_, v, __) =>
                  LinearProgressIndicator(value: v, minHeight: 6),
            ),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: Colors.transparent,
              color: scheme.primary.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}
