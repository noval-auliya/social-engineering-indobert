import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'bert_tokenizer.dart';

/// Model IndoBERT (ONNX int8) yang berjalan sepenuhnya di HP.
///
/// Aset dibuat oleh `ml/export_onnx.py`:
///   assets/ai/config.json, assets/ai/vocab.txt, assets/ai/<model_file>.onnx
class IndoBertClassifier {
  static const _assetDir = 'assets/ai';

  final OrtSession _session;
  final BertTokenizer tokenizer;
  final List<String> labels;
  final int riskIndex;
  final int maxLen;

  IndoBertClassifier._(
      this._session, this.tokenizer, this.labels, this.riskIndex, this.maxLen);

  static Future<IndoBertClassifier> load() async {
    final config = jsonDecode(
        await rootBundle.loadString('$_assetDir/config.json')) as Map<String, dynamic>;
    final labels = (config['labels'] as List).cast<String>();
    final tokenizer = BertTokenizer.fromVocab(
      await rootBundle.loadString('$_assetDir/vocab.txt'),
      doLowerCase: config['do_lower_case'] as bool? ?? true,
    );
    final session = await OnnxRuntime().createSessionFromAsset(
      '$_assetDir/${config['model_file']}',
      options: OrtSessionOptions(intraOpNumThreads: 4),
    );
    return IndoBertClassifier._(
      session,
      tokenizer,
      labels,
      labels.indexOf(config['risk_label'] as String),
      (config['max_len'] as num).toInt(),
    );
  }

  /// Probabilitas tiap label untuk setiap teks (satu batch, padding dinamis).
  Future<List<List<double>>> predict(List<String> texts) async {
    if (texts.isEmpty) return const [];
    final encoded = [for (final t in texts) tokenizer.encode(t, maxLen: maxLen)];
    final seq = encoded.map((e) => e.length).reduce(max);
    final ids = Int32List(texts.length * seq);
    final mask = Int32List(texts.length * seq);
    for (var b = 0; b < encoded.length; b++) {
      for (var i = 0; i < seq; i++) {
        final has = i < encoded[b].length;
        ids[b * seq + i] = has ? encoded[b][i] : tokenizer.padId;
        mask[b * seq + i] = has ? 1 : 0;
      }
    }

    final inputIds = await OrtValue.fromList(ids, [texts.length, seq]);
    final attention = await OrtValue.fromList(mask, [texts.length, seq]);
    try {
      final outputs = await _session.run({
        'input_ids': inputIds,
        'attention_mask': attention,
      });
      final probs = outputs['probs']!;
      final flat = (await probs.asFlattenedList()).cast<num>();
      for (final v in outputs.values) {
        await v.dispose();
      }
      final n = labels.length;
      return [
        for (var b = 0; b < texts.length; b++)
          [for (var k = 0; k < n; k++) flat[b * n + k].toDouble()],
      ];
    } finally {
      await inputIds.dispose();
      await attention.dispose();
    }
  }

  Future<void> close() => _session.close();
}
