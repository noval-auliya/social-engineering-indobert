import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/analysis_result.dart';
import '../models/lime_explanation.dart';
import 'ai/indobert_classifier.dart';
import 'ai/lime_text_explainer.dart';

/// Status mesin AI untuk ditampilkan di Pengaturan.
class AiEngineStatus {
  final bool ready;
  final String detail;
  const AiEngineStatus(this.ready, this.detail);
}

/// Analisis pesan social engineering.
///
/// Utama: IndoBERT fine-tuned (ONNX int8) + LIME, semuanya berjalan di HP.
/// Cadangan: heuristik kata kunci, dipakai bila model tidak bisa dimuat
/// (mis. saat unit test atau aset model belum dibuat).
class AnalysisService {
  static const aiEngine = 'IndoBERT (on-device)';
  static const keywordEngine = 'Kata kunci (cadangan)';

  /// Jumlah variasi pesan untuk LIME: makin besar makin stabil, makin lambat.
  static const limeSamples = 100;

  /// Kata kunci social engineering (bahasa Indonesia) -> bobot indikatif.
  static const Map<String, double> _keywords = {
    'hadiah': 0.31,
    'menang': 0.30,
    'selamat': 0.18,
    'gratis': 0.22,
    'klik': 0.21,
    'link': 0.20,
    'verifikasi': 0.26,
    'verif': 0.24,
    'akun': 0.14,
    'diblokir': 0.28,
    'blokir': 0.26,
    'segera': 0.19,
    'sekarang': 0.12,
    'urgent': 0.24,
    'penting': 0.10,
    'klaim': 0.25,
    'transfer': 0.27,
    'rekening': 0.23,
    'saldo': 0.18,
    'pulsa': 0.20,
    'otp': 0.33,
    'kode': 0.17,
    'password': 0.32,
    'sandi': 0.30,
    'pin': 0.22,
    'undian': 0.26,
    'kurir': 0.16,
    'paket': 0.12,
    'pajak': 0.18,
    'admin': 0.14,
    'wa.me': 0.17,
    'http': 0.19,
    'https': 0.15,
  };

  AnalysisService({Future<IndoBertClassifier> Function()? loadModel})
      : _loadModel = loadModel ?? IndoBertClassifier.load;

  final Future<IndoBertClassifier> Function() _loadModel;
  Future<IndoBertClassifier?>? _model;
  String _loadError = '';

  /// Memuat model sekali; null jika gagal (alasan disimpan di [_loadError]).
  Future<IndoBertClassifier?> _ensureModel() => _model ??= () async {
        try {
          return await _loadModel();
        } catch (e) {
          _loadError = '$e';
          debugPrint('IndoBERT tidak bisa dimuat, pakai kata kunci: $e');
          return null;
        }
      }();

  Future<AiEngineStatus> status() async {
    final model = await _ensureModel();
    return model != null
        ? AiEngineStatus(true, '$aiEngine · ${model.labels.join(' / ')}')
        : AiEngineStatus(false, 'Model tidak tersedia: $_loadError');
  }

  /// [explain] = false: hanya skor (~0,1 dtk), penjelasan LIME dihitung
  /// belakangan lewat [explain]. Dipakai untuk scan otomatis & tampilan cepat.
  Future<AnalysisResult> analyzeMessage(String message,
      {bool explain = true}) async {
    final model = await _ensureModel();
    if (model == null) return _analyzeKeywords(message);
    try {
      final scored = await _scoreModel(model, message.trim());
      return explain ? await _explainWith(model, scored) : scored;
    } catch (e) {
      debugPrint('Inferensi IndoBERT gagal, pakai kata kunci: $e');
      return _analyzeKeywords(message);
    }
  }

  /// Melengkapi hasil tanpa penjelasan dengan LIME (5–15 dtk di HP).
  Future<AnalysisResult> explain(AnalysisResult r) async {
    if (!r.explanationPending) return r;
    final model = await _ensureModel();
    if (model == null) return r;
    return _explainWith(model, r);
  }

  Future<AnalysisResult> _scoreModel(
      IndoBertClassifier model, String message) async {
    final probs = (await model.predict([message])).first;
    final score = probs[model.riskIndex];
    return AnalysisResult(
      message: message,
      riskLevel: _levelFor(score),
      score: score,
      confidence: probs.reduce(max),
      explanation: const [],
      explanationPending: true,
      createdAt: DateTime.now(),
      engine: aiEngine,
      probabilities: {
        for (var i = 0; i < model.labels.length; i++) model.labels[i]: probs[i],
      },
    );
  }

  Future<AnalysisResult> _explainWith(
      IndoBertClassifier model, AnalysisResult r) async {
    final explanation = await LimeTextExplainer(numSamples: limeSamples)
        .explain(r.message, model.predict, classIndex: model.riskIndex);
    return r.withExplanation(explanation.isNotEmpty
        ? explanation
        : const [LimeExplanation(word: '(pesan terlalu pendek)', weight: 0)]);
  }

  static RiskLevel _levelFor(double score) => switch (score) {
        >= 0.75 => RiskLevel.malicious,
        >= 0.5 => RiskLevel.high,
        >= 0.25 => RiskLevel.suspicious,
        _ => RiskLevel.safe,
      };

  AnalysisResult _analyzeKeywords(String message) {
    final lower = message.toLowerCase();
    final found = <LimeExplanation>[];
    double raw = 0;

    _keywords.forEach((word, weight) {
      if (lower.contains(word)) {
        found.add(LimeExplanation(word: word, weight: weight));
        raw += weight;
      }
    });

    // Sinyal tambahan: tanda seru = sedikit menaikkan skor.
    final bangs = '!'.allMatches(message).length;
    if (bangs > 0) raw += min(bangs, 3) * 0.03;

    // Normalisasi ke 0..1.
    final score = (raw / 1.4).clamp(0.0, 0.99).toDouble();

    // Ambil kontribusi teratas (maks 6), urut dari paling besar.
    found.sort((a, b) => b.weight.compareTo(a.weight));
    final top = found.take(6).toList();

    // Confidence: makin jauh dari ambang 0.5, makin yakin.
    final confidence = (0.55 + (score - 0.5).abs() * 0.9).clamp(0.5, 0.99);

    return AnalysisResult(
      message: message.trim(),
      riskLevel: _levelFor(score),
      score: score,
      confidence: confidence.toDouble(),
      explanation: top.isNotEmpty
          ? top
          : const [LimeExplanation(word: '(tidak ada indikator)', weight: 0.02)],
      createdAt: DateTime.now(),
      engine: keywordEngine,
    );
  }
}
