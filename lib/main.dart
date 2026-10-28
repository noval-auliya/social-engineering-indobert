import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'core/constants/app_constants.dart';
import 'providers/providers.dart';
import 'features/home/home_shell.dart';
import 'features/onboarding/onboarding_page.dart';
import 'widgets/warm_background.dart';

void main() {
  runApp(const ProviderScope(child: SocialEngineeringApp()));
}

/// Entrypoint mesin Flutter tanpa layar, dinyalakan oleh BackgroundScanner.kt
/// saat pesan WhatsApp masuk dan aplikasi tertutup. Memakai provider yang
/// sama dengan aplikasi: scan -> simpan riwayat -> notifikasi pesan berisiko.
@pragma('vm:entry-point')
Future<void> backgroundScanMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer(
      overrides: [backgroundEngineProvider.overrideWithValue(true)]);
  // Riwayat harus selesai dimuat agar entri baru tidak menimpa yang lama.
  container.read(historyProvider);
  await container.read(historyProvider.notifier).loaded;
  await container.read(waMonitorProvider.notifier).ready;
  // Container dibiarkan hidup: pesan berikutnya diproses lewat event stream
  // sampai BackgroundScanner mematikan mesin ini.
}

class SocialEngineeringApp extends ConsumerWidget {
  const SocialEngineeringApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    // Menghidupkan pemantau notifikasi WhatsApp sejak aplikasi dibuka.
    ref.watch(waMonitorProvider.select((s) => s.active));
    final mode = switch (settings.theme) {
      ThemeChoice.system => ThemeMode.system,
      ThemeChoice.light => ThemeMode.light,
      ThemeChoice.dark => ThemeMode.dark,
    };
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: mode,
      home: const _StartGate(),
    );
  }
}

/// Onboarding sekali saja. Menunggu pengaturan dimuat agar pengguna lama
/// tidak melihat onboarding berkedip sesaat.
class _StartGate extends ConsumerWidget {
  const _StartGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loaded = ref.watch(settingsLoadedProvider);
    final done = ref.watch(settingsProvider.select((s) => s.onboardingDone));
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      child: loaded.isLoading
          ? const WarmBackground(intensity: 1, child: SizedBox.expand())
          : done
              ? const HomeShell()
              : const OnboardingPage(),
    );
  }
}
