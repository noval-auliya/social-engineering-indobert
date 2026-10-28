import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Penyimpanan key-value kecil di HP (riwayat & pengaturan).
///
/// Dibungkus agar test bisa memakai [MemoryLocalStore] tanpa plugin native.
abstract class LocalStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

/// Implementasi di HP: SharedPreferences. Kegagalan plugin tidak membuat
/// aplikasi crash; data hanya tidak tersimpan (dicatat di log).
class PrefsLocalStore implements LocalStore {
  Future<SharedPreferences>? _prefs;
  Future<SharedPreferences> get _p => _prefs ??= SharedPreferences.getInstance();

  @override
  Future<String?> read(String key) async {
    try {
      return (await _p).getString(key);
    } catch (e) {
      debugPrint('LocalStore.read($key) gagal: $e');
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await (await _p).setString(key, value);
    } catch (e) {
      debugPrint('LocalStore.write($key) gagal: $e');
    }
  }

  @override
  Future<void> remove(String key) async {
    try {
      await (await _p).remove(key);
    } catch (e) {
      debugPrint('LocalStore.remove($key) gagal: $e');
    }
  }
}

/// Implementasi di memori, untuk test.
class MemoryLocalStore implements LocalStore {
  final Map<String, String> data;
  MemoryLocalStore([Map<String, String>? initial]) : data = {...?initial};

  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> remove(String key) async => data.remove(key);
}
