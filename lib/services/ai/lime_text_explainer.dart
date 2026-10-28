import 'dart:math';

import '../../models/lime_explanation.dart';

/// Fungsi prediksi: daftar teks -> probabilitas per kelas untuk tiap teks.
typedef ProbaFn = Future<List<List<double>>> Function(List<String> texts);

/// Implementasi LIME untuk teks (Ribeiro dkk., 2016), mengikuti
/// `lime.lime_text.LimeTextExplainer` (bow=True, kernel eksponensial,
/// jarak kosinus, regresi Ridge berbobot).
///
/// Cara kerja: kata-kata unik dihapus secara acak untuk membuat variasi
/// pesan, model memprediksi tiap variasi, lalu model linear lokal dilatih
/// untuk mengukur seberapa besar tiap kata mendorong prediksi.
class LimeTextExplainer {
  final int numSamples;
  final double kernelWidth;
  final double ridgeAlpha;
  final int batchSize;
  final Random _random;

  LimeTextExplainer({
    this.numSamples = 100,
    this.kernelWidth = 25,
    this.ridgeAlpha = 1.0,
    this.batchSize = 16,
    Random? random,
  }) : _random = random ?? Random(42);

  static final _wordRe = RegExp(r'[\p{L}\p{N}_]+', unicode: true);

  /// Mengembalikan [numFeatures] kata paling berpengaruh terhadap
  /// [classIndex]. Bobot positif = mendorong ke kelas tsb (berisiko).
  Future<List<LimeExplanation>> explain(
    String text,
    ProbaFn predict, {
    required int classIndex,
    int numFeatures = 6,
  }) async {
    // Pecah teks jadi potongan kata & pemisah agar bisa disusun ulang.
    final pieces = <String>[];
    final isWord = <bool>[];
    var last = 0;
    for (final m in _wordRe.allMatches(text)) {
      if (m.start > last) {
        pieces.add(text.substring(last, m.start));
        isWord.add(false);
      }
      pieces.add(m.group(0)!);
      isWord.add(true);
      last = m.end;
    }
    if (last < text.length) {
      pieces.add(text.substring(last));
      isWord.add(false);
    }

    final vocab = <String>[];
    final featureOf = List<int>.filled(pieces.length, -1);
    final index = <String, int>{};
    for (var i = 0; i < pieces.length; i++) {
      if (!isWord[i]) continue;
      featureOf[i] = index.putIfAbsent(pieces[i], () {
        vocab.add(pieces[i]);
        return vocab.length - 1;
      });
    }
    final d = vocab.length;
    if (d < 2) return const [];

    // Sampel 0 = teks asli; sisanya menghapus 1..d-1 kata unik secara acak.
    final masks = <List<bool>>[List.filled(d, true)];
    final texts = <String>[text];
    final features = List<int>.generate(d, (i) => i);
    for (var s = 1; s < numSamples; s++) {
      final remove = 1 + _random.nextInt(d - 1);
      features.shuffle(_random);
      final mask = List<bool>.filled(d, true);
      for (var k = 0; k < remove; k++) {
        mask[features[k]] = false;
      }
      masks.add(mask);
      final sb = StringBuffer();
      for (var i = 0; i < pieces.length; i++) {
        if (!isWord[i] || mask[featureOf[i]]) sb.write(pieces[i]);
      }
      texts.add(sb.toString());
    }

    final y = <double>[];
    for (var i = 0; i < texts.length; i += batchSize) {
      final probs = await predict(texts.sublist(i, min(i + batchSize, texts.length)));
      y.addAll(probs.map((p) => p[classIndex]));
    }

    // Bobot sampel: kernel eksponensial atas jarak kosinus ke teks asli * 100.
    final weights = masks.map((mask) {
      final active = mask.where((b) => b).length;
      final cosine = active == 0 ? 0.0 : active / (sqrt(active) * sqrt(d));
      final dist = (1 - cosine) * 100;
      return sqrt(exp(-(dist * dist) / (kernelWidth * kernelWidth)));
    }).toList();

    final x = masks.map((m) => m.map((b) => b ? 1.0 : 0.0).toList()).toList();

    // Pilih fitur dengan |koefisien| terbesar, lalu latih ulang pada fitur itu
    // (setara feature_selection='highest_weights' di LIME).
    final all = _weightedRidge(x, y, weights, List.generate(d, (i) => i));
    final ranked = List<int>.generate(d, (i) => i)
      ..sort((a, b) => all[b].abs().compareTo(all[a].abs()));
    final selected = ranked.take(min(numFeatures, d)).toList();
    final coef = _weightedRidge(x, y, weights, selected);

    final result = [
      for (var j = 0; j < selected.length; j++)
        LimeExplanation(word: vocab[selected[j]], weight: coef[j]),
    ]..sort((a, b) => b.weight.abs().compareTo(a.weight.abs()));
    return result;
  }

  /// Ridge berbobot dengan intercept (setara sklearn.linear_model.Ridge).
  List<double> _weightedRidge(
      List<List<double>> x, List<double> y, List<double> w, List<int> cols) {
    final n = x.length, p = cols.length;
    final wSum = w.fold<double>(0, (a, b) => a + b);
    final xMean = List<double>.filled(p, 0);
    var yMean = 0.0;
    for (var i = 0; i < n; i++) {
      yMean += w[i] * y[i];
      for (var j = 0; j < p; j++) {
        xMean[j] += w[i] * x[i][cols[j]];
      }
    }
    yMean /= wSum;
    for (var j = 0; j < p; j++) {
      xMean[j] /= wSum;
    }

    // (Xcᵀ W Xc + αI) β = Xcᵀ W yc
    final a = List.generate(p, (_) => List<double>.filled(p + 1, 0));
    for (var i = 0; i < n; i++) {
      final xc = [for (var j = 0; j < p; j++) x[i][cols[j]] - xMean[j]];
      final yc = y[i] - yMean;
      for (var r = 0; r < p; r++) {
        final wr = w[i] * xc[r];
        for (var c = r; c < p; c++) {
          a[r][c] += wr * xc[c];
        }
        a[r][p] += wr * yc;
      }
    }
    for (var r = 0; r < p; r++) {
      for (var c = 0; c < r; c++) {
        a[r][c] = a[c][r];
      }
      a[r][r] += ridgeAlpha;
    }
    return _solve(a, p);
  }

  /// Eliminasi Gauss dengan partial pivoting pada matriks augmented [a].
  static List<double> _solve(List<List<double>> a, int p) {
    for (var col = 0; col < p; col++) {
      var pivot = col;
      for (var r = col + 1; r < p; r++) {
        if (a[r][col].abs() > a[pivot][col].abs()) pivot = r;
      }
      final tmp = a[col];
      a[col] = a[pivot];
      a[pivot] = tmp;
      for (var r = col + 1; r < p; r++) {
        final f = a[r][col] / a[col][col];
        if (f == 0) continue;
        for (var c = col; c <= p; c++) {
          a[r][c] -= f * a[col][c];
        }
      }
    }
    final beta = List<double>.filled(p, 0);
    for (var r = p - 1; r >= 0; r--) {
      var s = a[r][p];
      for (var c = r + 1; c < p; c++) {
        s -= a[r][c] * beta[c];
      }
      beta[r] = s / a[r][r];
    }
    return beta;
  }
}
