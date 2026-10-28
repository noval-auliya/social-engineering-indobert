import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../providers/providers.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Tampilan', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                RadioListTile<ThemeChoice>(
                  value: ThemeChoice.system,
                  groupValue: s.theme,
                  onChanged: (v) => notifier.setTheme(v!),
                  title: const Text('Ikuti sistem'),
                ),
                RadioListTile<ThemeChoice>(
                  value: ThemeChoice.light,
                  groupValue: s.theme,
                  onChanged: (v) => notifier.setTheme(v!),
                  title: const Text('Terang'),
                ),
                RadioListTile<ThemeChoice>(
                  value: ThemeChoice.dark,
                  groupValue: s.theme,
                  onChanged: (v) => notifier.setTheme(v!),
                  title: const Text('Gelap'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _AiEngineCard(),
          const SizedBox(height: 16),
          const _WaMonitorSection(),
          const SizedBox(height: 16),
          Text('Privasi & Data', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  value: s.saveHistory,
                  onChanged: notifier.toggleSaveHistory,
                  title: const Text('Simpan riwayat analisis'),
                  subtitle: const Text('Hanya metadata, bukan isi pesan penuh.'),
                ),
                SwitchListTile(
                  value: s.softLabels,
                  onChanged: notifier.toggleSoftLabels,
                  title: const Text('Gunakan istilah "indikatif"'),
                  subtitle:
                      const Text('"Berisiko / terindikasi", bukan vonis pasti.'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text(AppConstants.appName),
              subtitle: const Text(
                  'Versi 1.0.0 · Pesan: IndoBERT · Malware: ML + indikator · '
                  'semua di HP'),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer
                  .withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(AppConstants.disclaimer,
                style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

/// Status mesin deteksi: IndoBERT on-device atau cadangan kata kunci.
class _AiEngineCard extends ConsumerWidget {
  const _AiEngineCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(aiStatusProvider);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Mesin Deteksi AI', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: status.when(
            loading: () => const ListTile(
              leading: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              title: Text('Memuat model IndoBERT...'),
            ),
            error: (e, _) => ListTile(
              leading: Icon(Icons.error_outline, color: theme.colorScheme.error),
              title: const Text('Gagal memeriksa model'),
              subtitle: Text('$e'),
            ),
            data: (s) => ListTile(
              leading: Icon(
                s.ready ? Icons.memory : Icons.warning_amber_outlined,
                color: s.ready ? Colors.green : theme.colorScheme.error,
              ),
              title: Text(s.ready
                  ? 'IndoBERT aktif (offline, di HP)'
                  : 'Memakai cadangan kata kunci'),
              subtitle: Text(s.detail),
            ),
          ),
        ),
      ],
    );
  }
}

/// Pengaturan scan otomatis dari notifikasi WhatsApp (khusus Android).
class _WaMonitorSection extends ConsumerWidget {
  const _WaMonitorSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(waMonitorProvider);
    final notifier = ref.read(waMonitorProvider.notifier);
    final theme = Theme.of(context);
    if (!s.supported) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Scan Otomatis WhatsApp', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: Icon(
                  s.granted
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_off_outlined,
                  color: s.granted ? Colors.green : theme.colorScheme.error,
                ),
                title: Text(s.granted
                    ? 'Akses notifikasi aktif'
                    : 'Akses notifikasi belum diberikan'),
                subtitle: Text(s.granted
                    ? 'Pesan WhatsApp yang masuk di-scan otomatis.'
                    : 'Izinkan "SE Detector - Pantau WhatsApp" di daftar '
                        'akses notifikasi.'),
              ),
              // Bukan trailing ListTile: tema FilledButton selebar layar.
              if (!s.granted)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: FilledButton(
                    onPressed: notifier.openPermissionSettings,
                    child: const Text('Izinkan akses notifikasi'),
                  ),
                ),
              SwitchListTile(
                value: s.enabled,
                onChanged: s.granted ? notifier.setEnabled : null,
                title: const Text('Pantau pesan WhatsApp'),
                subtitle:
                    const Text('Hasil scan masuk ke Riwayat secara otomatis.'),
              ),
              ListTile(
                title: const Text('Hanya scan pesan panjang'),
                subtitle: Text(s.minLength == 0
                    ? 'Semua pesan di-scan.'
                    : 'Minimal ${s.minLength} karakter.'),
              ),
              Slider(
                value: s.minLength.toDouble(),
                min: 0,
                max: 500,
                divisions: 20,
                label: '${s.minLength}',
                onChanged: s.granted && s.enabled
                    ? (v) => notifier.setMinLength(v.round())
                    : null,
              ),
            ],
          ),
        ),
        if (!s.granted)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4, right: 4),
            child: Text(
              'Jika opsi tidak bisa diaktifkan (Android 13+, APK di luar Play '
              'Store): buka Info Aplikasi → menu ⋮ → "Izinkan setelan '
              'terbatas", lalu coba lagi.',
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}
