import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/analysis_result.dart';
import '../models/history_item.dart';
import '../models/malware_result.dart';
import '../services/analysis_service.dart';
import '../services/malware_service.dart';
import '../services/mock_data.dart';
import '../services/wa_notification_service.dart';

// ---- services ----
final analysisServiceProvider =
    Provider<AnalysisService>((ref) => AnalysisService());
final aiStatusProvider = FutureProvider<AiEngineStatus>(
    (ref) => ref.watch(analysisServiceProvider).status());
final malwareServiceProvider =
    Provider<MalwareService>((ref) => MalwareService());
final waNotificationServiceProvider = Provider<WaNotificationService>(
    (ref) => const WaNotificationService());

// ---- riwayat gabungan ----
class HistoryNotifier extends StateNotifier<List<HistoryItem>> {
  HistoryNotifier() : super(MockData.seedHistory());

  HistoryItem addAnalysis(AnalysisResult r, {String? title}) {
    final item = title == null
        ? HistoryItem.fromAnalysis(r)
        : HistoryItem.fromAnalysis(r, title: title);
    state = [item, ...state];
    return item;
  }

  void addMalware(MalwareResult r) =>
      state = [HistoryItem.fromMalware(r), ...state];

  void clear() => state = [];
}

final historyProvider =
    StateNotifierProvider<HistoryNotifier, List<HistoryItem>>(
        (ref) => HistoryNotifier());

/// Entri hasil scan otomatis yang belum dilihat (badge & label "BARU").
final unseenHistoryProvider = StateProvider<Set<HistoryItem>>((ref) => {});

/// Progres scan otomatis WhatsApp, untuk animasi & notifikasi selesai.
class ScanProgress {
  final bool active;
  final int done;
  final int total;
  final String currentSender;

  /// Ringkasan putaran scan terakhir yang sudah selesai.
  final int finishedCount;
  final int finishedRisky;

  const ScanProgress({
    this.active = false,
    this.done = 0,
    this.total = 0,
    this.currentSender = '',
    this.finishedCount = 0,
    this.finishedRisky = 0,
  });
}

final scanProgressProvider =
    StateProvider<ScanProgress>((ref) => const ScanProgress());

// ---- analisis pesan (state: AsyncValue) ----
class AnalysisNotifier extends StateNotifier<AsyncValue<AnalysisResult?>> {
  AnalysisNotifier(this._ref) : super(const AsyncValue.data(null));
  final Ref _ref;

  Future<void> analyze(String message) async {
    if (message.trim().isEmpty) return;
    state = const AsyncValue.loading();
    try {
      final service = _ref.read(analysisServiceProvider);
      final result = await service.analyzeMessage(message);
      _ref.read(historyProvider.notifier).addAnalysis(result);
      state = AsyncValue.data(result);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void reset() => state = const AsyncValue.data(null);
}

final analysisProvider =
    StateNotifierProvider<AnalysisNotifier, AsyncValue<AnalysisResult?>>(
        (ref) => AnalysisNotifier(ref));

// ---- analisis malware (state: AsyncValue) ----
class MalwareNotifier extends StateNotifier<AsyncValue<MalwareResult?>> {
  MalwareNotifier(this._ref) : super(const AsyncValue.data(null));
  final Ref _ref;

  /// [source] = path / URI file APK, [fileName] untuk ditampilkan.
  Future<void> analyze(String source, String fileName) async {
    state = const AsyncValue.loading();
    try {
      final service = _ref.read(malwareServiceProvider);
      final result = await service.analyzeFile(source, fileName);
      _ref.read(historyProvider.notifier).addMalware(result);
      state = AsyncValue.data(result);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void reset() => state = const AsyncValue.data(null);
}

final malwareProvider =
    StateNotifierProvider<MalwareNotifier, AsyncValue<MalwareResult?>>(
        (ref) => MalwareNotifier(ref));

// ---- pantau notifikasi WhatsApp (Android) ----
class WaMonitorState {
  final bool supported; // false di luar Android
  final bool granted;
  final bool enabled;
  final int minLength;

  const WaMonitorState({
    this.supported = false,
    this.granted = false,
    this.enabled = true,
    this.minLength = 150,
  });

  WaMonitorState copyWith({bool? enabled, int? minLength}) => WaMonitorState(
        supported: supported,
        granted: granted,
        enabled: enabled ?? this.enabled,
        minLength: minLength ?? this.minLength,
      );

  /// Listener benar-benar aktif menangkap pesan.
  bool get active => supported && granted && enabled;
}

/// Mengambil pesan yang ditangkap listener native, men-scan otomatis,
/// lalu memasukkannya ke riwayat. Pesan yang masuk saat aplikasi tertutup
/// di-scan ketika aplikasi dibuka kembali.
class WaMonitorNotifier extends StateNotifier<WaMonitorState> {
  WaMonitorNotifier(this._ref) : super(const WaMonitorState()) {
    _init();
  }
  final Ref _ref;
  StreamSubscription<void>? _sub;
  AppLifecycleListener? _lifecycle;
  bool _scanning = false;

  WaNotificationService get _service => _ref.read(waNotificationServiceProvider);

  Future<void> _init() async {
    await refresh();
    if (!mounted || !state.supported) return;
    _sub = _service.onNewMessage.listen((_) => scanPending());
    // Cek ulang izin setelah pengguna kembali dari halaman pengaturan Android.
    _lifecycle = AppLifecycleListener(onResume: refresh);
  }

  Future<void> refresh() async {
    final status = await _service.getStatus();
    if (!mounted) return;
    if (status == null) {
      state = const WaMonitorState();
      return;
    }
    state = WaMonitorState(
      supported: true,
      granted: status.granted,
      enabled: status.enabled,
      minLength: status.minLength,
    );
    await scanPending();
  }

  Future<void> scanPending() async {
    if (_scanning) return;
    _scanning = true;
    final progress = _ref.read(scanProgressProvider.notifier);
    var done = 0, total = 0, risky = 0;
    try {
      // Ulangi sampai antrean kosong: pesan bisa masuk selama proses scan.
      while (mounted) {
        final pending = await _service.drain();
        if (pending.isEmpty) break;
        total += pending.length;
        final analysis = _ref.read(analysisServiceProvider);
        for (final m in pending) {
          progress.state = ScanProgress(
              active: true,
              done: done,
              total: total,
              currentSender: m.senderLabel);
          final result = await analysis.analyzeMessage(m.text);
          if (!mounted) return;
          final item = _ref
              .read(historyProvider.notifier)
              .addAnalysis(result, title: 'Otomatis · ${m.senderLabel}');
          _ref
              .read(unseenHistoryProvider.notifier)
              .update((s) => {...s, item});
          done++;
          if (result.riskLevel.index >= RiskLevel.high.index) risky++;
        }
      }
    } finally {
      _scanning = false;
      if (mounted) {
        progress.state =
            ScanProgress(finishedCount: done, finishedRisky: risky);
      }
    }
  }

  Future<void> openPermissionSettings() => _service.openPermissionSettings();

  Future<void> setEnabled(bool v) => _save(state.copyWith(enabled: v));

  Future<void> setMinLength(int v) => _save(state.copyWith(minLength: v));

  Future<void> _save(WaMonitorState next) async {
    state = next;
    await _service.setConfig(enabled: next.enabled, minLength: next.minLength);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }
}

final waMonitorProvider =
    StateNotifierProvider<WaMonitorNotifier, WaMonitorState>(
        (ref) => WaMonitorNotifier(ref));

// ---- statistik dashboard (turunan dari riwayat) ----
class DashboardStats {
  final int total;
  final int safe;
  final int warning; // suspicious + medium
  final int high; // high + critical/malicious

  const DashboardStats(this.total, this.safe, this.warning, this.high);
}

final dashboardStatsProvider = Provider<DashboardStats>((ref) {
  final history = ref.watch(historyProvider);
  int safe = 0, warn = 0, high = 0;
  for (final h in history) {
    switch (h.severity) {
      case Severity.low:
        safe++;
      case Severity.medium:
        warn++;
      case Severity.high:
      case Severity.critical:
        high++;
    }
  }
  return DashboardStats(history.length, safe, warn, high);
});

// ---- pengaturan (dummy, in-memory) ----
class AppSettings {
  final ThemeChoice theme;
  final bool saveHistory;
  final bool softLabels;

  const AppSettings({
    this.theme = ThemeChoice.system,
    this.saveHistory = true,
    this.softLabels = true,
  });

  AppSettings copyWith({ThemeChoice? theme, bool? saveHistory, bool? softLabels}) =>
      AppSettings(
        theme: theme ?? this.theme,
        saveHistory: saveHistory ?? this.saveHistory,
        softLabels: softLabels ?? this.softLabels,
      );
}

enum ThemeChoice { system, light, dark }

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(const AppSettings());

  void setTheme(ThemeChoice t) => state = state.copyWith(theme: t);
  void toggleSaveHistory(bool v) => state = state.copyWith(saveHistory: v);
  void toggleSoftLabels(bool v) => state = state.copyWith(softLabels: v);
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>(
        (ref) => SettingsNotifier());
