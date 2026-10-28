import 'package:flutter/services.dart';

import '../models/captured_message.dart';

/// Status listener notifikasi WhatsApp di sisi Android.
class WaMonitorStatus {
  final bool granted; // izin "Akses notifikasi" sudah diberikan
  final bool enabled;
  final int minLength; // hanya pesan >= minLength karakter yang di-scan

  const WaMonitorStatus({
    required this.granted,
    required this.enabled,
    required this.minLength,
  });
}

/// Jembatan ke `WaNotificationListener` (Kotlin) lewat platform channel.
///
/// Di platform selain Android, channel tidak tersedia sehingga
/// [getStatus] mengembalikan null.
class WaNotificationService {
  static const _method = MethodChannel('sed/wa_listener');
  static const _events = EventChannel('sed/wa_listener/events');

  const WaNotificationService();

  Future<WaMonitorStatus?> getStatus() async {
    try {
      final map = await _method.invokeMapMethod<String, Object?>('getStatus');
      if (map == null) return null;
      return WaMonitorStatus(
        granted: map['granted'] as bool? ?? false,
        enabled: map['enabled'] as bool? ?? true,
        minLength: (map['minLength'] as num?)?.toInt() ?? 150,
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<void> openPermissionSettings() => _method.invokeMethod('openSettings');

  Future<void> setConfig({required bool enabled, required int minLength}) =>
      _method.invokeMethod('setConfig', {
        'enabled': enabled,
        'minLength': minLength,
      });

  /// Mengambil pesan yang menunggu di antrean native lalu mengosongkannya.
  Future<List<CapturedMessage>> drain() async {
    final list = await _method.invokeListMethod<Map<Object?, Object?>>('drain');
    return (list ?? const []).map(CapturedMessage.fromMap).toList();
  }

  /// Memancarkan event setiap kali ada pesan baru masuk antrean.
  Stream<void> get onNewMessage =>
      _events.receiveBroadcastStream().map((_) {});
}
