import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Setiap file di assets/ harus terdaftar di pubspec.yaml, kalau tidak file
/// itu tidak ikut masuk APK ("Unable to load asset" saat aplikasi berjalan).
void main() {
  test('Semua file di assets/ terdaftar di pubspec.yaml', () {
    final declared = RegExp(r'^\s+-\s+(assets/\S*)', multiLine: true)
        .allMatches(File('pubspec.yaml').readAsStringSync())
        .map((m) => m.group(1)!)
        .toList();

    final missing = [
      for (final f in Directory('assets').listSync(recursive: true).whereType<File>())
        if (!declared.any((d) {
          final path = f.path.replaceAll(r'\', '/');
          return d.endsWith('/') ? File(path).parent.path.replaceAll(r'\', '/') + '/' == d : path == d;
        }))
          f.path,
    ];
    expect(missing, isEmpty, reason: 'Tambahkan ke bagian flutter: assets: di pubspec.yaml');
  });
}
