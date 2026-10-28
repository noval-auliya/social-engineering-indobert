import '../../models/history_item.dart';
import '../../models/malware_result.dart';

enum HistoryFilter { all, messages, apks, risky }

extension HistoryFilterX on HistoryFilter {
  String get label => switch (this) {
        HistoryFilter.all => 'Semua',
        HistoryFilter.messages => 'Pesan',
        HistoryFilter.apks => 'APK',
        HistoryFilter.risky => 'Berisiko',
      };
}

/// Jumlah entri per "halaman" saat menggulir Riwayat.
const historyPageSize = 20;

/// Filter + pencarian riwayat. Setiap kata di [query] harus muncul di salah
/// satu bagian entri (judul/pengirim, isi pesan, nama/paket APK, label risiko),
/// tanpa membedakan huruf besar-kecil. Urutan [items] dipertahankan.
List<HistoryItem> filterHistory(
  List<HistoryItem> items, {
  String query = '',
  HistoryFilter filter = HistoryFilter.all,
}) {
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  bool matchesFilter(HistoryItem h) => switch (filter) {
        HistoryFilter.all => true,
        HistoryFilter.messages => h.kind == HistoryKind.message,
        HistoryFilter.apks => h.kind == HistoryKind.malware,
        HistoryFilter.risky => h.severity.index >= Severity.high.index,
      };
  String haystack(HistoryItem h) => [
        h.title,
        h.subtitle,
        h.badge(),
        h.badge(soft: true),
        h.malware?.appName ?? '',
        h.malware?.packageName ?? '',
      ].join(' ').toLowerCase();

  return [
    for (final h in items)
      if (matchesFilter(h) && words.every(haystack(h).contains)) h,
  ];
}
