import 'package:flutter_test/flutter_test.dart';
import 'package:social_engineering_detector/services/ai/lime_text_explainer.dart';

void main() {
  // Model palsu dengan efek kata yang diketahui:
  // "hadiah" +0.4, "klik" +0.3, "rapat" -0.2 terhadap probabilitas penipuan.
  Future<List<List<double>>> fakeModel(List<String> texts) async => [
        for (final t in texts)
          () {
            final words = t.toLowerCase().split(RegExp(r'\W+'));
            var p = 0.3;
            if (words.contains('hadiah')) p += 0.4;
            if (words.contains('klik')) p += 0.3;
            if (words.contains('rapat')) p -= 0.2;
            return [1 - p, p, 0.0];
          }(),
      ];

  test('LIME menemukan kembali kata yang memengaruhi model', () async {
    final explainer = LimeTextExplainer(numSamples: 300);
    final result = await explainer.explain(
      'Selamat, hadiah menanti! Klik link ini setelah rapat kantor besok.',
      fakeModel,
      classIndex: 1,
      numFeatures: 4,
    );

    final byWord = {for (final e in result) e.word.toLowerCase(): e.weight};
    expect(result.first.word.toLowerCase(), 'hadiah');
    expect(byWord['hadiah'], closeTo(0.4, 0.08));
    expect(byWord['klik'], closeTo(0.3, 0.08));
    expect(byWord['rapat'], closeTo(-0.2, 0.08));
  });

  test('LIME aman untuk teks satu kata', () async {
    final result = await LimeTextExplainer()
        .explain('halo', fakeModel, classIndex: 1);
    expect(result, isEmpty);
  });
}
