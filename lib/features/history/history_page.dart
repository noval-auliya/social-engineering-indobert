import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../models/history_item.dart';
import '../../providers/providers.dart';
import '../../widgets/scan_progress_banner.dart';
import 'history_detail_page.dart';
import 'history_query.dart';

/// Riwayat deteksi: cari, saring, tarik-untuk-segarkan, dan dimuat bertahap
/// ([historyPageSize] entri) saat menggulir ke bawah.
class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  String _query = '';
  HistoryFilter _filter = HistoryFilter.all;
  int _visible = historyPageSize;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Muat halaman berikutnya saat mendekati ujung bawah daftar.
  void _maybeLoadMore() {
    if (!_scroll.hasClients || _visible >= _total) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 300) {
      setState(() => _visible += historyPageSize);
    }
  }

  /// Jumlah hasil setelah filter (diperbarui di build) untuk batas halaman.
  int _total = 0;

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {
        _query = v;
        _visible = historyPageSize;
      });
    });
  }

  void _setFilter(HistoryFilter f) => setState(() {
        _filter = f;
        _visible = historyPageSize;
      });

  Future<void> _refresh() async {
    await Future.wait([
      ref.read(historyProvider.notifier).reload(),
      ref.read(waMonitorProvider.notifier).refresh(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final history = ref.watch(historyProvider);
    final unseen = ref.watch(unseenHistoryProvider);
    final scan = ref.watch(scanProgressProvider);
    final soft = ref.watch(settingsProvider.select((s) => s.softLabels));
    final results = filterHistory(history, query: _query, filter: _filter);
    _total = results.length;
    final shown = results.take(_visible).toList();
    final hasMore = shown.length < results.length;
    final df = DateFormat('dd MMM, HH:mm');

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.ember,
          onRefresh: _refresh,
          child: CustomScrollView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Riwayat deteksi', style: theme.textTheme.titleLarge),
                            Text(
                              '${history.length} hasil tersimpan',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      if (history.isNotEmpty)
                        IconButton(
                          tooltip: 'Hapus semua',
                          icon: const Icon(Icons.delete_sweep_outlined),
                          onPressed: _confirmClear,
                        ),
                    ],
                  ),
                ),
              ),
              // Kolom cari menempel di atas saat menggulir riwayat yang panjang.
              SliverPersistentHeader(
                pinned: true,
                delegate: _PinnedSearch(
                  background: Color.lerp(AppColors.pageGradient(theme.brightness).first,
                      AppColors.pageGradient(theme.brightness).last, 0.4)!,
                  child: TextField(
                    controller: _search,
                    onChanged: _onSearch,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Cari pengirim, isi pesan, atau nama APK',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Hapus pencarian',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () {
                                _search.clear();
                                _onSearch('');
                              },
                            ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 56,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
                    children: [
                      for (final f in HistoryFilter.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(f.label),
                            selected: _filter == f,
                            showCheckmark: false,
                            onSelected: (_) => _setFilter(f),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  child: scan.active
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ScanProgressBanner(progress: scan),
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ),
              if (results.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(
                    searching: _query.isNotEmpty || _filter != HistoryFilter.all,
                    onReset: () {
                      _search.clear();
                      setState(() {
                        _query = '';
                        _filter = HistoryFilter.all;
                      });
                    },
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  sliver: SliverList.separated(
                    itemCount: shown.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _HistoryTile(
                      item: shown[i],
                      isNew: unseen.contains(shown[i]),
                      soft: soft,
                      date: df.format(shown[i].createdAt),
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
                  // Penghitung hanya berguna bila daftarnya lebih dari 1 halaman.
                  child: results.length <= historyPageSize
                      ? const SizedBox.shrink()
                      : Center(
                          // Data ada di memori: tanpa spinner palsu. Halaman
                          // berikut dimuat otomatis saat menggulir, atau lewat
                          // tombol ini (juga untuk pembaca layar).
                          child: hasMore
                              ? TextButton(
                                  onPressed: () =>
                                      setState(() => _visible += historyPageSize),
                                  child: Text(
                                      'Muat ${(results.length - shown.length).clamp(0, historyPageSize)} lagi '
                                      '(${shown.length} dari ${results.length})'),
                                )
                              : Text(
                                  'Menampilkan ${results.length} dari ${history.length} hasil',
                                  style: theme.textTheme.bodySmall),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmClear() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus riwayat?'),
        content: const Text(
            'Semua entri riwayat akan dihapus, termasuk yang tersimpan di HP.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.crimson, minimumSize: const Size(0, 44)),
            onPressed: () {
              ref.read(historyProvider.notifier).clear();
              ref.read(unseenHistoryProvider.notifier).state = {};
              Navigator.pop(dialogContext);
            },
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }
}

class _PinnedSearch extends SliverPersistentHeaderDelegate {
  final Widget child;
  final Color background;
  _PinnedSearch({required this.child, required this.background});

  static const _height = 74.0;

  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      Container(
        color: overlapsContent || shrinkOffset > 0 ? background : Colors.transparent,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
        alignment: Alignment.center,
        child: child,
      );

  @override
  bool shouldRebuild(_PinnedSearch old) => old.child != child || old.background != background;
}

class _HistoryTile extends StatelessWidget {
  final HistoryItem item;
  final bool isNew;
  final bool soft;
  final String date;
  const _HistoryTile(
      {required this.item, required this.isNew, required this.soft, required this.date});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = AppTheme.severityColor(item.severity);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: isNew
            ? const BorderSide(color: AppColors.ember, width: 1.5)
            : BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: InkWell(
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => HistoryDetailPage(item: item))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: color.withValues(alpha: 0.12),
                child: Icon(
                  item.kind == HistoryKind.message
                      ? Icons.chat_bubble_outline_rounded
                      : Icons.android_rounded,
                  color: color,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (isNew)
                          Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding:
                                const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.ember,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('BARU',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800)),
                          ),
                        Flexible(
                          child: Text(item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(item.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 6),
                    Text(date,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: theme.colorScheme.outline)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(item.badge(soft: soft),
                    style: TextStyle(
                        color: color, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool searching;
  final VoidCallback onReset;
  const _EmptyState({required this.searching, required this.onReset});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 120),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(searching ? Icons.search_off_rounded : Icons.inbox_outlined,
              size: 44, color: theme.colorScheme.outline),
          const SizedBox(height: 10),
          Text(searching ? 'Tidak ada hasil yang cocok' : 'Belum ada riwayat',
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            searching
                ? 'Coba kata lain atau tampilkan semua jenis.'
                : 'Hasil analisis pesan dan APK akan muncul di sini.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          if (searching) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onReset, child: const Text('Tampilkan semua')),
          ],
        ],
      ),
    );
  }
}
