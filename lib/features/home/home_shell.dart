import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/providers.dart';
import '../../widgets/warm_background.dart';
import '../dashboard/dashboard_page.dart';
import '../history/history_page.dart';
import '../malware_analysis/malware_analysis_page.dart';
import '../settings/settings_page.dart';
import '../whatsapp_analysis/whatsapp_analysis_page.dart';

/// Kerangka utama: latar gradasi hangat + navigasi pil melayang dengan
/// tombol Beranda oranye di tengah.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  // Urutan sesuai HomeTab (indeks stabil, urutan tampilan di _NavPill).
  static const _pages = [
    DashboardPage(),
    WhatsAppAnalysisPage(),
    MalwareAnalysisPage(),
    HistoryPage(),
    SettingsPage(),
  ];

  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    _openFromNotification();
    _lifecycle = AppLifecycleListener(onResume: _openFromNotification);
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  /// Dibuka dengan mengetuk notifikasi peringatan -> langsung ke Riwayat.
  Future<void> _openFromNotification() async {
    final target =
        await ref.read(waNotificationServiceProvider).consumeLaunchTarget();
    if (target == 'history' && mounted) {
      ref.read(homeTabProvider.notifier).state = HomeTab.history;
    }
  }

  void _showScanFinished(ScanProgress p) {
    final risky = p.finishedRisky;
    final scheme = Theme.of(context).colorScheme;
    final onHistory = ref.read(homeTabProvider) == HomeTab.history;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        backgroundColor: risky > 0 ? AppColors.crimson : AppColors.ink,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        content: Row(
          children: [
            Icon(risky > 0 ? Icons.warning_amber_rounded : Icons.verified_user,
                color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                risky > 0
                    ? '$risky dari ${p.finishedCount} pesan WhatsApp berisiko!'
                    : '${p.finishedCount} pesan WhatsApp di-scan, '
                        'tidak ada yang berisiko tinggi',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        action: onHistory
            ? null
            : SnackBarAction(
                label: 'Lihat',
                textColor: risky > 0 ? Colors.white : scheme.primary,
                onPressed: () =>
                    ref.read(homeTabProvider.notifier).state = HomeTab.history,
              ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ScanProgress>(scanProgressProvider, (prev, next) {
      if ((prev?.active ?? false) && !next.active && next.finishedCount > 0) {
        _showScanFinished(next);
      }
    });
    // Penanda "BARU" hilang setelah pengguna meninggalkan tab Riwayat.
    ref.listen<int>(homeTabProvider, (prev, next) {
      if (prev == HomeTab.history && next != HomeTab.history) {
        ref.read(unseenHistoryProvider.notifier).state = {};
      }
    });
    final index = ref.watch(homeTabProvider);

    return WarmBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        body: IndexedStack(index: index, children: _pages),
        bottomNavigationBar: const _NavPill(),
      ),
    );
  }
}

/// Navigasi pil melayang: Pesan · Malware · [Beranda] · Riwayat · Pengaturan.
class _NavPill extends ConsumerWidget {
  const _NavPill();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(homeTabProvider);
    final unseen = ref.watch(unseenHistoryProvider).length;
    final scanning = ref.watch(scanProgressProvider.select((p) => p.active));
    final light = Theme.of(context).brightness == Brightness.light;
    void go(int tab) => ref.read(homeTabProvider.notifier).state = tab;

    return SafeArea(
      minimum: const EdgeInsets.only(bottom: 10),
      child: Center(
        heightFactor: 1,
        child: Container(
          height: 68,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: light ? Colors.white.withValues(alpha: 0.92) : AppColors.cocoaRaised,
            borderRadius: BorderRadius.circular(34),
            border: Border.all(
                color: light ? const Color(0xFFF3E7DD) : const Color(0xFF3A2C23)),
            boxShadow: [
              BoxShadow(
                color: (light ? AppColors.ink : Colors.black)
                    .withValues(alpha: light ? 0.08 : 0.3),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _NavIcon(Icons.chat_bubble_outline_rounded, 'Pesan',
                  selected: index == HomeTab.messages, onTap: () => go(HomeTab.messages)),
              _NavIcon(Icons.shield_outlined, 'Malware',
                  selected: index == HomeTab.malware, onTap: () => go(HomeTab.malware)),
              _HomeButton(
                  selected: index == HomeTab.dashboard,
                  onTap: () => go(HomeTab.dashboard)),
              _NavIcon(Icons.history_rounded, 'Riwayat',
                  selected: index == HomeTab.history,
                  onTap: () => go(HomeTab.history),
                  // Angka = hasil baru belum dilihat; titik = sedang memindai.
                  badgeVisible: index != HomeTab.history && (unseen > 0 || scanning),
                  badgeLabel: unseen > 0 ? '$unseen' : null),
              _NavIcon(Icons.tune_rounded, 'Pengaturan',
                  selected: index == HomeTab.settings, onTap: () => go(HomeTab.settings)),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool badgeVisible;
  final String? badgeLabel;

  const _NavIcon(this.icon, this.label,
      {required this.selected,
      required this.onTap,
      this.badgeVisible = false,
      this.badgeLabel});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkResponse(
          onTap: onTap,
          radius: 28,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? scheme.primaryContainer : Colors.transparent,
            ),
            child: Badge(
              isLabelVisible: badgeVisible,
              label: badgeLabel == null ? null : Text(badgeLabel!),
              backgroundColor: AppColors.signal,
              child: Icon(icon,
                  color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tombol Beranda oranye bulat di tengah pil (seperti referensi).
class _HomeButton extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  const _HomeButton({required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Beranda',
      child: Semantics(
        button: true,
        selected: selected,
        label: 'Beranda',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  center: Alignment(-0.3, -0.4),
                  colors: [AppColors.apricot, AppColors.ember],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.ember.withValues(alpha: selected ? 0.45 : 0.25),
                    blurRadius: selected ? 18 : 10,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(Icons.home_rounded, color: Colors.white, size: 26),
            ),
          ),
        ),
      ),
    );
  }
}
