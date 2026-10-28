import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'core/constants/app_constants.dart';
import 'providers/providers.dart';
import 'features/home/home_shell.dart';

void main() {
  runApp(const ProviderScope(child: SocialEngineeringApp()));
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
      home: const HomeShell(),
    );
  }
}
