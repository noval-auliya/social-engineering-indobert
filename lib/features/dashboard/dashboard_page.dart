import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../models/history_item.dart';
import '../../providers/providers.dart';
import '../../services/protection_score.dart';
import '../../widgets/protection_gauge.dart';
import '../history/history_detail_page.dart';

/// Beranda: skor perlindungan, aksi cepat, status pantauan, aktivitas.
class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  int _days = 7;

  void _go(int tab) => ref.read(homeTabProvider.notifier).state = tab;

  /// Tarik-untuk-segarkan: muat ulang riwayat, cek antrean WhatsApp & model.
  Future<void> _refresh() async {
    ref.invalidate(aiStatusProvider);
    await Future.wait([
      ref.read(historyProvider.notifier).reload(),
      ref.read(waMonitorProvider.notifier).refresh(),
      ref.read(aiStatusProvider.future).then((_) {}, onError: (_) {}),
    ]);
  }

  static String _greeting(DateTime now) => switch (now.hour) {
        < 11 => 'Selamat pagi',
        < 15 => 'Selamat siang',
        < 18 => 'Selamat sore',
        _ => 'Selamat malam',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final monitor = ref.watch(waMonitorProvider);
    final settings = ref.watch(settingsProvider);
    final aiReady = ref.watch(aiStatusProvider).valueOrNull?.ready ?? false;
    final factors = protectionFactors(
      aiReady: aiReady,
      monitorActive: monitor.active,
      alertsActive: monitor.active && monitor.alerts,
      historySaved: settings.saveHistory,
    );
    final score = protectionScore(factors);
    final missing = factors.where((f) => !f.active).toList();
    final unseen = ref.watch(unseenHistoryProvider).length;
    final stats = ref.watch(activityStatsProvider(_days));
    final recent = ref.watch(historyProvider).take(3).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.ember,
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
            children: [
              _Header(
                greeting: _greeting(DateTime.now()),
                unseen: unseen,
                onBell: () => _go(HomeTab.history),
              ),
              const SizedBox(height: 20),
              Center(child: ProtectionGauge(score: score, label: 'Skor perlindungan')),
              const SizedBox(height: 6),
              Center(
                child: Tooltip(
                  message: missing.map((f) => f.hint).join('\n'),
                  child: TextButton.icon(
                    onPressed: missing.isEmpty ? null : () => _go(HomeTab.settings),
                    icon: Icon(missing.isEmpty
                        ? Icons.verified_rounded
                        : Icons.add_moderator_outlined),
                    label: Text(missing.isEmpty
                        ? 'Semua perlindungan aktif'
                        : 'Aktifkan ${missing.length} perlindungan lagi'),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _QuickActions(
                onMessage: () => _go(HomeTab.messages),
                onApk: () => _go(HomeTab.malware),
                onHistory: () => _go(HomeTab.history),
              ),
              const SizedBox(height: 16),
              _MonitorBand(
                monitor: monitor,
                checked: stats.safeMessages + stats.suspiciousMessages + stats.scamMessages,
                onActivate: () => _go(HomeTab.settings),
                onCheck: () => _go(HomeTab.messages),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(child: Text('Aktivitas', style: theme.textTheme.titleMedium)),
                  SegmentedButton<int>(
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      selectedBackgroundColor: theme.brightness == Brightness.light
                          ? AppColors.ink
                          : AppColors.ember,
                      selectedForegroundColor: Colors.white,
                    ),
                    segments: const [
                      ButtonSegment(value: 7, label: Text('7 hari')),
                      ButtonSegment(value: 30, label: Text('30 hari')),
                    ],
                    selected: {_days},
                    onSelectionChanged: (s) => setState(() => _days = s.first),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _ActivityList(stats: stats),
              const SizedBox(height: 24),
              Text('Terakhir dianalisis', style: theme.textTheme.titleMedium),
              const SizedBox(height: 10),
              if (recent.isEmpty)
                _EmptyRecent(onStart: () => _go(HomeTab.messages))
              else
                for (final h in recent) _RecentTile(item: h),
              const SizedBox(height: 20),
              Text(AppConstants.disclaimer,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String greeting;
  final int unseen;
  final VoidCallback onBell;
  const _Header({required this.greeting, required this.unseen, required this.onBell});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colorScheme.surfaceContainerLowest,
          ),
          child: const Icon(Icons.shield_rounded, color: AppColors.ember),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(greeting,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              Text('Penjaga pesanmu', style: theme.textTheme.titleMedium),
            ],
          ),
        ),
        _CircleIconButton(
          icon: Icons.notifications_none_rounded,
          tooltip: unseen > 0 ? '$unseen hasil scan baru' : 'Hasil scan',
          badge: unseen > 0 ? '$unseen' : null,
          onTap: onBell,
        ),
      ],
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final String? badge;
  final VoidCallback onTap;
  const _CircleIconButton(
      {required this.icon, required this.tooltip, required this.onTap, this.badge});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: scheme.surfaceContainerLowest,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Badge(
              isLabelVisible: badge != null,
              label: badge == null ? null : Text(badge!),
              backgroundColor: AppColors.signal,
              child: Icon(icon, color: scheme.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}

/// Panel putih dengan tombol aksi bulat hitam (gaya referensi).
class _QuickActions extends StatelessWidget {
  final VoidCallback onMessage, onApk, onHistory;
  const _QuickActions({required this.onMessage, required this.onApk, required this.onHistory});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ActionCircle(icon: Icons.sms_outlined, label: 'Cek pesan', onTap: onMessage),
          _ActionCircle(icon: Icons.android_rounded, label: 'Scan APK', onTap: onApk),
          _ActionCircle(icon: Icons.history_rounded, label: 'Riwayat', onTap: onHistory),
        ],
      ),
    );
  }
}

class _ActionCircle extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionCircle({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final light = theme.brightness == Brightness.light;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: light ? AppColors.ink : AppColors.ember,
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(height: 8),
            Text(label, style: theme.textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}

/// Pita oranye: status pantauan WhatsApp + satu aksi yang relevan.
class _MonitorBand extends StatelessWidget {
  final WaMonitorState monitor;
  final int checked;
  final VoidCallback onActivate, onCheck;
  const _MonitorBand(
      {required this.monitor, required this.checked, required this.onActivate, required this.onCheck});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (title, body, action, onTap) = switch (monitor) {
      WaMonitorState(active: true) => (
          'Pantauan WhatsApp aktif',
          '$checked pesan dicek otomatis di HP ini minggu ini.',
          'Periksa',
          onCheck,
        ),
      WaMonitorState(supported: true) => (
          'Aktifkan pantauan WhatsApp',
          'Pesan penipuan dikenali begitu masuk, tanpa dikirim ke server.',
          'Aktifkan',
          onActivate,
        ),
      _ => (
          'Ragu dengan sebuah pesan?',
          'Tempel di sini, IndoBERT menilai risikonya.',
          'Periksa',
          onCheck,
        ),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(colors: AppColors.ctaGradient),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.2),
            ),
            child: Icon(monitor.active ? Icons.radar : Icons.document_scanner_outlined,
                color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: theme.textTheme.titleSmall?.copyWith(color: Colors.white)),
                const SizedBox(height: 2),
                Text(body,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.white.withValues(alpha: 0.9))),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onTap,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.ink,
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              textStyle: const TextStyle(
                  fontFamily: AppTheme.fontFamily, fontWeight: FontWeight.w700, fontSize: 13),
            ),
            child: Text(action),
          ),
        ],
      ),
    );
  }
}

class _ActivityList extends StatelessWidget {
  final ActivityStats stats;
  const _ActivityList({required this.stats});

  @override
  Widget build(BuildContext context) {
    final rows = [
      (Icons.gpp_bad_outlined, 'Pesan penipuan terdeteksi', stats.scamMessages, AppColors.signal),
      (Icons.help_outline_rounded, 'Pesan mencurigakan', stats.suspiciousMessages, AppColors.amber),
      (Icons.mark_chat_read_outlined, 'Pesan aman dicek', stats.safeMessages, AppColors.moss),
      (Icons.android_rounded, 'APK diperiksa', stats.apksChecked, AppColors.ink),
    ];
    final max = rows.map((r) => r.$3).fold<int>(1, (a, b) => b > a ? b : a);
    return Column(
      children: [
        for (final r in rows)
          _ActivityRow(
            icon: r.$1,
            label: r.$2,
            value: r.$3,
            fraction: r.$3 / max,
            color: r.$4,
            note: r.$2 == 'APK diperiksa' && stats.riskyApks > 0
                ? '${stats.riskyApks} berisiko'
                : null,
          ),
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  final double fraction;
  final Color color;
  final String? note;
  const _ActivityRow(
      {required this.icon,
      required this.label,
      required this.value,
      required this.fraction,
      required this.color,
      this.note});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final barColor = theme.brightness == Brightness.dark && color == AppColors.ink
        ? AppColors.apricot
        : color;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: barColor.withValues(alpha: 0.12),
              child: Icon(icon, size: 18, color: barColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(note == null ? label : '$label ($note)',
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: fraction,
                      minHeight: 6,
                      color: barColor,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Text('$value',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _RecentTile extends ConsumerWidget {
  final HistoryItem item;
  const _RecentTile({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final soft = ref.watch(settingsProvider.select((s) => s.softLabels));
    final color = AppTheme.severityColor(item.severity);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => HistoryDetailPage(item: item))),
          leading: Icon(
            item.kind == HistoryKind.message ? Icons.chat_bubble_outline : Icons.android,
            color: color,
          ),
          title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(item.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Text(item.badge(soft: soft),
              style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
        ),
      ),
    );
  }
}

class _EmptyRecent extends StatelessWidget {
  final VoidCallback onStart;
  const _EmptyRecent({required this.onStart});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Text('Belum ada analisis',
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text('Tempel pesan yang meragukan untuk mulai.',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onStart, child: const Text('Cek pesan')),
        ],
      ),
    );
  }
}
