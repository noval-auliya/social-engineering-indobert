import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';
import '../dashboard/dashboard_page.dart';
import '../whatsapp_analysis/whatsapp_analysis_page.dart';
import '../malware_analysis/malware_analysis_page.dart';
import '../history/history_page.dart';
import '../settings/settings_page.dart';

/// Kerangka utama dengan bottom navigation (5 bagian sesuai dokumentasi).
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  static const _historyTab = 3;
  int _index = 0;

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
    if (target == 'history' && mounted) _select(_historyTab);
  }

  void _select(int i) {
    // Penanda "BARU" hilang setelah pengguna meninggalkan tab Riwayat.
    if (_index == _historyTab && i != _historyTab) {
      ref.read(unseenHistoryProvider.notifier).state = {};
    }
    setState(() => _index = i);
  }

  void _showScanFinished(ScanProgress p) {
    final risky = p.finishedRisky;
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: risky > 0 ? scheme.error : null,
        content: Row(
          children: [
            Icon(risky > 0 ? Icons.warning_amber_rounded : Icons.verified_user,
                color: risky > 0 ? scheme.onError : null),
            const SizedBox(width: 10),
            Expanded(
              child: Text(risky > 0
                  ? '$risky dari ${p.finishedCount} pesan WhatsApp berisiko!'
                  : '${p.finishedCount} pesan WhatsApp di-scan · '
                      'tidak ada yang berisiko tinggi'),
            ),
          ],
        ),
        action: _index == _historyTab
            ? null
            : SnackBarAction(
                label: 'Lihat',
                textColor: risky > 0 ? scheme.onError : null,
                onPressed: () => _select(_historyTab),
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
    final unseen = ref.watch(unseenHistoryProvider).length;
    final scanning = ref.watch(scanProgressProvider.select((p) => p.active));
    final showBadge = _index != _historyTab && (unseen > 0 || scanning);

    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        destinations: [
          const NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'Beranda'),
          const NavigationDestination(
              icon: Icon(Icons.chat_outlined),
              selectedIcon: Icon(Icons.chat),
              label: 'Pesan'),
          const NavigationDestination(
              icon: Icon(Icons.security_outlined),
              selectedIcon: Icon(Icons.security),
              label: 'Malware'),
          NavigationDestination(
              // Angka = hasil baru belum dilihat; titik = sedang memindai.
              icon: Badge(
                isLabelVisible: showBadge,
                label: unseen > 0 ? Text('$unseen') : null,
                child: const Icon(Icons.history_outlined),
              ),
              selectedIcon: const Icon(Icons.history),
              label: 'Riwayat'),
          const NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Pengaturan'),
        ],
      ),
    );
  }
}
