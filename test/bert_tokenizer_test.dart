import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:social_engineering_detector/services/ai/bert_tokenizer.dart';

/// Memastikan tokenizer Dart menghasilkan id token yang sama persis dengan
/// tokenizer HuggingFace (fixture dibuat oleh ml/export_onnx.py).
void main() {
  final fixture = File('assets/ai/fixtures.json');
  final vocab = File('assets/ai/vocab.txt');

  test('Tokenizer Dart == tokenizer HuggingFace', () {
    final data = jsonDecode(fixture.readAsStringSync()) as Map<String, dynamic>;
    final tokenizer = BertTokenizer.fromVocab(vocab.readAsStringSync());
    final maxLen = data['max_len'] as int;

    for (final c in (data['cases'] as List).cast<Map<String, dynamic>>()) {
      final expected = (c['input_ids'] as List).cast<int>();
      expect(tokenizer.encode(c['text'] as String, maxLen: maxLen), expected,
          reason: 'Teks: "${c['text']}"\nToken HF: ${c['tokens']}');
    }
  }, skip: fixture.existsSync() ? false : 'Jalankan ml/export_onnx.py dulu');

  test('Pesan sangat panjang dipotong ke max_len', () {
    final tokenizer = BertTokenizer.fromVocab(vocab.readAsStringSync());
    final ids = tokenizer.encode(List.filled(600, 'transfer').join(' '),
        maxLen: 256);
    expect(ids.length, 256);
    expect(ids.first, tokenizer.clsId);
    expect(ids.last, tokenizer.sepId);
  }, skip: vocab.existsSync() ? false : 'Jalankan ml/export_onnx.py dulu');
}
