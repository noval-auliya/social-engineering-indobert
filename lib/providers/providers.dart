import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/analysis_result.dart';
import '../models/correction.dart';
import '../models/history_item.dart';
import '../models/malware_result.dart';
import '../services/analysis_service.dart';
import '../services/local_store.dart';
import '../services/malware_service.dart';
import '../services/risk_alert_policy.dart';
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

final localStoreProvider = Provider<LocalStore>((ref) => PrefsLocalStore());

// ---- riwayat gabungan (tersimpan di HP jika pengaturan mengizinkan) ----
class HistoryNotifier extends StateNotifier<List<HistoryItem>> {
  HistoryNotifier(this._ref) : super(const []) {
    loaded = _load();
  }
  final Ref _ref;
  static const storageKey = 'history_v1';

  /// Selesai saat riwayat tersimpan sudah dimuat dari HP.
  late final Future<void> loaded;

  LocalStore get _store => _ref.read(localStoreProvider);

  Future<void> _load() async {
    await _ref.read(settingsProvider.notifier).loaded;
    if (!_ref.read(settingsProvider).saveHistory) return;
    final raw = await _store.read(storageKey);
    if (raw == null || !mounted) return;
    try {
      final saved = [
        for (final j in (jsonDecode(raw) as List).cast<Map<String, dynamic>>())
          HistoryItem.fromJson(j),
      ];
      // Entri yang ditambahkan selama proses muat tetap di atas.
      state = applyRetention([...state, ...saved]);
    } catch (e) {
      debugPrint('Riwayat tersimpan rusak, diabaikan: $e');
    }
  }

  Future<void> _persist() async {
    // Jangan menulis sebelum riwayat lama dimuat (bisa menimpanya).
    await loaded;
    await _ref.read(settingsProvider.notifier).loaded;
    if (!_ref.read(settingsProvider).saveHistory) return;
    await _store.write(storageKey,
        jsonEncode([for (final h in state) h.toJson()]));
  }

  /// Dipanggil saat sakelar "Simpan riwayat" berubah.
  Future<void> onSaveHistoryChanged(bool save) =>
      save ? _persist() : _store.remove(storageKey);

  HistoryItem addAnalysis(AnalysisResult r, {String? title}) {
    final item = title == null
        ? HistoryItem.fromAnalysis(r)
        : HistoryItem.fromAnalysis(r, title: title);
    state = applyRetention([item, ...state]);
    _persist();
    return item;
  }

  void addMalware(MalwareResult r) {
    state = applyRetention([HistoryItem.fromMalware(r), ...state]);
    _persist();
  }

  final _explaining = <HistoryItem, Future<HistoryItem>>{};

  /// Menghitung penjelasan LIME yang tertunda lalu mengganti entri di riwayat.
  /// Pemanggilan ganda untuk entri yang sama memakai proses yang sama.
  Future<HistoryItem> explainItem(HistoryItem item) {
    final a = item.analysis;
    if (a == null || !a.explanationPending) return Future.value(item);
    return _explaining[item] ??= () async {
      try {
        final explained = await _ref.read(analysisServiceProvider).explain(a);
        final updated = HistoryItem.fromAnalysis(explained, title: item.title);
        if (!mounted) return updated;
        state = [for (final h in state) identical(h, item) ? updated : h];
        final unseen = _ref.read(unseenHistoryProvider.notifier);
        if (unseen.state.contains(item)) {
          unseen.state = {...unseen.state..remove(item), updated};
        }
        _persist();
        return updated;
      } finally {
        _explaining.remove(item);
      }
    }();
  }

  void clear() {
    state = [];
    _store.remove(storageKey);
  }
}

/// Batas riwayat yang disimpan (terbaru di depan).
const maxHistoryItems = 300;

/// Kebijakan retensi riwayat: [items] urut dari yang terbaru.
List<HistoryItem> applyRetention(List<HistoryItem> items) =>
    items.length <= maxHistoryItems ? items : items.sublist(0, maxHistoryItems);

final historyProvider =
    StateNotifierProvider<HistoryNotifier, List<HistoryItem>>((ref) {
  final notifier = HistoryNotifier(ref);
  ref.listen<bool>(settingsProvider.select((s) => s.saveHistory),
      (_, save) => notifier.onSaveHistoryChanged(save));
  return notifier;
});

// ---- koreksi pengguna ("Hasil ini salah") -> data latih asli ----
class CorrectionsNotifier extends StateNotifier<List<Correction>> {
  CorrectionsNotifier(this._store) : super(const []) {
    loaded = _load();
  }
  final LocalStore _store;
  static const storageKey = 'corrections_v1';
  late final Future<void> loaded;

  Future<void> _load() async {
    final raw = await _store.read(storageKey);
    if (raw == null || !mounted) return;
    try {
      state = [
        ...state,
        for (final j in (jsonDecode(raw) as List).cast<Map<String, dynamic>>())
          Correction.fromJson(j),
      ];
    } catch (e) {
      debugPrint('Data koreksi rusak, diabaikan: $e');
    }
  }

  Future<void> _persist() async {
    await loaded;
    await _store.write(storageKey, jsonEncode([for (final c in state) c.toJson()]));
  }

  /// Koreksi baru untuk pesan/APK yang sama menggantikan yang lama.
  void add(Correction c) {
    state = [c, for (final o in state) if (o.key != c.key) o];
    _persist();
  }

  void remove(String key) {
    state = [for (final o in state) if (o.key != key) o];
    _persist();
  }

  void clear() {
    state = [];
    _store.remove(storageKey);
  }
}

final correctionsProvider =
    StateNotifierProvider<CorrectionsNotifier, List<Correction>>(
        (ref) => CorrectionsNotifier(ref.read(localStoreProvider)));

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

  /// Dua tahap: skor tampil dulu (~0,1 dtk), penjelasan LIME menyusul.
  Future<void> analyze(String message) async {
    if (message.trim().isEmpty) return;
    state = const AsyncValue.loading();
    try {
      final service = _ref.read(analysisServiceProvider);
      final scored = await service.analyzeMessage(message, explain: false);
      final history = _ref.read(historyProvider.notifier);
      final item = history.addAnalysis(scored);
      state = AsyncValue.data(scored);

      final explained = await history.explainItem(item);
      // Jangan timpa jika pengguna sudah menganalisis pesan lain.
      if (mounted && state.valueOrNull == scored) {
        state = AsyncValue.data(explained.analysis);
      }
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

  /// Scan di latar belakang + notifikasi sistem untuk pesan berisiko.
  final bool alerts;

  const WaMonitorState({
    this.supported = false,
    this.granted = false,
    this.enabled = true,
    this.minLength = 150,
    this.alerts = true,
  });

  WaMonitorState copyWith({bool? enabled, int? minLength, bool? alerts}) =>
      WaMonitorState(
        supported: supported,
        granted: granted,
        enabled: enabled ?? this.enabled,
        minLength: minLength ?? this.minLength,
        alerts: alerts ?? this.alerts,
      );

  /// Listener benar-benar aktif menangkap pesan.
  bool get active => supported && granted && enabled;
}

/// true di mesin Flutter latar belakang (`backgroundScanMain`), tanpa layar.
final backgroundEngineProvider = Provider<bool>((ref) => false);

/// Mengambil pesan yang ditangkap listener native, men-scan otomatis,
/// lalu memasukkannya ke riwayat. Berjalan di mesin UI, atau di mesin latar
/// belakang saat aplikasi tertutup (lihat BackgroundScanner.kt).
class WaMonitorNotifier extends StateNotifier<WaMonitorState> {
  WaMonitorNotifier(this._ref) : super(const WaMonitorState()) {
    ready = _init();
  }
  final Ref _ref;
  StreamSubscription<void>? _sub;
  AppLifecycleListener? _lifecycle;
  bool _scanning = false;

  /// Selesai setelah status dimuat dan antrean pertama di-scan.
  late final Future<void> ready;

  WaNotificationService get _service => _ref.read(waNotificationServiceProvider);
  bool get _background => _ref.read(backgroundEngineProvider);

  Future<void> _init() async {
    await refresh();
    if (!mounted || !state.supported) return;
    _sub = _service.onNewMessage.listen((_) => scanPending());
    // Cek ulang izin setelah pengguna kembali dari halaman pengaturan Android.
    if (!_background) _lifecycle = AppLifecycleListener(onResume: refresh);
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
      alerts: status.alerts,
    );
    await scanPending();
  }

  /// Notifikasi sistem hanya jika pengguna tidak sedang melihat aplikasi
  /// (di dalam aplikasi sudah ada SnackBar & badge Riwayat).
  Future<void> _maybeAlert(AnalysisResult r, String sender) async {
    if (!state.alerts || !shouldAlert(r)) return;
    // Mesin UI: null (baru menyala) / resumed / inactive = masih di layar.
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    final inForeground = !_background &&
        (lifecycle == null ||
            lifecycle == AppLifecycleState.resumed ||
            lifecycle == AppLifecycleState.inactive);
    if (inForeground) return;
    await _ref.read(settingsProvider.notifier).loaded;
    final text = alertText(r, sender, soft: _ref.read(settingsProvider).softLabels);
    try {
      await _service.showRiskAlert(
          id: Object.hash(sender, r.createdAt) & 0x7fffffff,
          title: text.title,
          body: text.body);
    } catch (e) {
      debugPrint('Gagal menampilkan notifikasi: $e');
    }
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
          // Skor saja (~0,1 dtk); LIME dihitung saat detail dibuka.
          final result = await analysis.analyzeMessage(m.text, explain: false);
          if (!mounted) return;
          final item = _ref
              .read(historyProvider.notifier)
              .addAnalysis(result, title: 'Otomatis · ${m.senderLabel}');
          _ref
              .read(unseenHistoryProvider.notifier)
              .update((s) => {...s, item});
          done++;
          if (result.riskLevel.index >= RiskLevel.high.index) risky++;
          await _maybeAlert(result, m.senderLabel);
        }
      }
    } finally {
      _scanning = false;
      if (mounted) {
        progress.state =
            ScanProgress(finishedCount: done, finishedRisky: risky);
      }
      // Mesin latar belakang boleh dimatikan setelah jeda tanpa pesan baru.
      if (_background) {
        try {
          await _service.backgroundIdle();
        } catch (_) {}
      }
    }
  }

  Future<void> openPermissionSettings() => _service.openPermissionSettings();

  Future<void> setEnabled(bool v) => _save(state.copyWith(enabled: v));

  Future<void> setMinLength(int v) => _save(state.copyWith(minLength: v));

  /// Mengaktifkan peringatan sekaligus meminta izin notifikasi (Android 13+).
  Future<void> setAlerts(bool v) async {
    if (v) await Permission.notification.request();
    await _save(state.copyWith(alerts: v));
  }

  Future<void> _save(WaMonitorState next) async {
    state = next;
    await _service.setConfig(
        enabled: next.enabled, minLength: next.minLength, alerts: next.alerts);
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

// ---- pengaturan (tersimpan di HP) ----
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

  Map<String, dynamic> toJson() =>
      {'theme': theme.name, 'save_history': saveHistory, 'soft_labels': softLabels};

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        theme: ThemeChoice.values.asNameMap()[j['theme']] ?? ThemeChoice.system,
        saveHistory: j['save_history'] as bool? ?? true,
        softLabels: j['soft_labels'] as bool? ?? true,
      );
}

enum ThemeChoice { system, light, dark }

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier(this._store) : super(const AppSettings()) {
    loaded = _load();
  }
  final LocalStore _store;
  static const storageKey = 'settings_v1';

  /// Selesai saat pengaturan tersimpan sudah dimuat dari HP.
  late final Future<void> loaded;

  bool _changedBeforeLoad = false;

  Future<void> _load() async {
    final raw = await _store.read(storageKey);
    // Pilihan pengguna saat proses muat berjalan lebih penting dari data lama.
    if (raw == null || !mounted || _changedBeforeLoad) return;
    try {
      state = AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('Pengaturan tersimpan rusak, pakai default: $e');
    }
  }

  void _set(AppSettings next) {
    _changedBeforeLoad = true;
    state = next;
    _store.write(storageKey, jsonEncode(next.toJson()));
  }

  void setTheme(ThemeChoice t) => _set(state.copyWith(theme: t));
  void toggleSaveHistory(bool v) => _set(state.copyWith(saveHistory: v));
  void toggleSoftLabels(bool v) => _set(state.copyWith(softLabels: v));
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>(
    (ref) => SettingsNotifier(ref.read(localStoreProvider)));
