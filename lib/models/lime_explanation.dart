/// Satu kontribusi kata/fitur dari penjelasan LIME.
class LimeExplanation {
  final String word;
  final double weight;

  const LimeExplanation({
    required this.word,
    required this.weight,
  });

  /// Positif = mendorong ke "berisiko", negatif = mendorong ke "aman".
  bool get isRisky => weight >= 0;

  factory LimeExplanation.fromJson(Map<String, dynamic> json) {
    return LimeExplanation(
      word: json['word'] as String,
      weight: (json['weight'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {'word': word, 'weight': weight};
}
