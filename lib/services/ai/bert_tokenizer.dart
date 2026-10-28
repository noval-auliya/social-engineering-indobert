/// Port Dart dari `BertTokenizer` HuggingFace (BasicTokenizer + WordPiece)
/// untuk IndoBERT (`indobenchmark/indobert-base-p1`, uncased).
///
/// Kesesuaian dengan tokenizer Python diuji oleh
/// `test/bert_tokenizer_test.dart` memakai fixture dari `ml/export_onnx.py`.
class BertTokenizer {
  final Map<String, int> _vocab;
  final bool doLowerCase;
  final int clsId;
  final int sepId;
  final int unkId;
  final int padId;

  static const _maxCharsPerWord = 100;

  BertTokenizer._(this._vocab, this.doLowerCase)
      : clsId = _vocab['[CLS]']!,
        sepId = _vocab['[SEP]']!,
        unkId = _vocab['[UNK]']!,
        padId = _vocab['[PAD]']!;

  /// [vocabText] = isi `vocab.txt` (satu token per baris, id = nomor baris).
  factory BertTokenizer.fromVocab(String vocabText, {bool doLowerCase = true}) {
    final vocab = <String, int>{};
    final lines = vocabText.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final token = lines[i].replaceAll('\r', '');
      if (token.isEmpty && i == lines.length - 1) break;
      vocab.putIfAbsent(token, () => i);
    }
    return BertTokenizer._(vocab, doLowerCase);
  }

  /// `[CLS] token... [SEP]`, dipotong agar panjang total <= [maxLen].
  List<int> encode(String text, {int maxLen = 256}) {
    final ids = <int>[];
    for (final word in _basicTokenize(text)) {
      ids.addAll(_wordPiece(word));
      if (ids.length >= maxLen - 2) break;
    }
    final body = ids.length > maxLen - 2 ? ids.sublist(0, maxLen - 2) : ids;
    return [clsId, ...body, sepId];
  }

  // ---- BasicTokenizer ----

  List<String> _basicTokenize(String text) {
    final cleaned = StringBuffer();
    for (final cp in text.runes) {
      if (cp == 0 || cp == 0xFFFD || _isControl(cp)) continue;
      if (_isWhitespace(cp)) {
        cleaned.write(' ');
      } else if (_isCjk(cp)) {
        cleaned
          ..write(' ')
          ..writeCharCode(cp)
          ..write(' ');
      } else {
        cleaned.writeCharCode(cp);
      }
    }

    final out = <String>[];
    for (var token in cleaned.toString().split(' ')) {
      if (token.isEmpty) continue;
      if (doLowerCase) token = _stripAccents(token.toLowerCase());
      out.addAll(_splitOnPunctuation(token));
    }
    return out;
  }

  List<String> _splitOnPunctuation(String token) {
    final out = <String>[];
    final current = StringBuffer();
    for (final cp in token.runes) {
      if (_isPunctuation(cp)) {
        if (current.isNotEmpty) {
          out.add(current.toString());
          current.clear();
        }
        out.add(String.fromCharCode(cp));
      } else {
        current.writeCharCode(cp);
      }
    }
    if (current.isNotEmpty) out.add(current.toString());
    return out;
  }

  // ---- WordPiece (greedy longest-match-first) ----

  List<int> _wordPiece(String word) {
    final chars = word.runes.toList();
    if (chars.length > _maxCharsPerWord) return [unkId];
    final pieces = <int>[];
    var start = 0;
    while (start < chars.length) {
      var end = chars.length;
      int? found;
      while (start < end) {
        var sub = String.fromCharCodes(chars.sublist(start, end));
        if (start > 0) sub = '##$sub';
        found = _vocab[sub];
        if (found != null) break;
        end--;
      }
      if (found == null) return [unkId];
      pieces.add(found);
      start = end;
    }
    return pieces;
  }

  // ---- klasifikasi karakter (setara unicodedata Python) ----

  static bool _isWhitespace(int cp) =>
      cp == 0x20 ||
      cp == 0x09 ||
      cp == 0x0A ||
      cp == 0x0D ||
      cp == 0xA0 ||
      cp == 0x1680 ||
      (cp >= 0x2000 && cp <= 0x200A) ||
      cp == 0x202F ||
      cp == 0x205F ||
      cp == 0x3000;

  /// Kategori Unicode "C*" (Cc, Cf) kecuali \t \n \r.
  static bool _isControl(int cp) {
    if (cp == 0x09 || cp == 0x0A || cp == 0x0D) return false;
    return cp < 0x20 ||
        (cp >= 0x7F && cp <= 0x9F) ||
        cp == 0xAD ||
        (cp >= 0x600 && cp <= 0x605) ||
        cp == 0x61C ||
        cp == 0x6DD ||
        cp == 0x70F ||
        cp == 0x180E ||
        (cp >= 0x200B && cp <= 0x200F) ||
        (cp >= 0x202A && cp <= 0x202E) ||
        (cp >= 0x2060 && cp <= 0x206F) ||
        cp == 0xFEFF ||
        (cp >= 0xFFF9 && cp <= 0xFFFB) ||
        (cp >= 0xE000 && cp <= 0xF8FF);
  }

  /// ASCII non-alfanumerik dianggap tanda baca (sama seperti HF), plus
  /// blok tanda baca Unicode yang umum.
  static bool _isPunctuation(int cp) {
    if ((cp >= 33 && cp <= 47) ||
        (cp >= 58 && cp <= 64) ||
        (cp >= 91 && cp <= 96) ||
        (cp >= 123 && cp <= 126)) {
      return true;
    }
    return cp == 0xA1 ||
        cp == 0xA7 ||
        cp == 0xAB ||
        cp == 0xB6 ||
        cp == 0xB7 ||
        cp == 0xBB ||
        cp == 0xBF ||
        cp == 0x37E ||
        cp == 0x387 ||
        (cp >= 0x2010 && cp <= 0x2027) ||
        (cp >= 0x2030 && cp <= 0x2043) ||
        (cp >= 0x2045 && cp <= 0x2051) ||
        (cp >= 0x2053 && cp <= 0x205E) ||
        (cp >= 0x3001 && cp <= 0x3003) ||
        (cp >= 0x3008 && cp <= 0x3011) ||
        (cp >= 0xFF01 && cp <= 0xFF03) ||
        (cp >= 0xFF05 && cp <= 0xFF0A) ||
        (cp >= 0xFF0C && cp <= 0xFF0F);
  }

  static bool _isCjk(int cp) =>
      (cp >= 0x4E00 && cp <= 0x9FFF) ||
      (cp >= 0x3400 && cp <= 0x4DBF) ||
      (cp >= 0x20000 && cp <= 0x2A6DF) ||
      (cp >= 0x2A700 && cp <= 0x2CEAF) ||
      (cp >= 0xF900 && cp <= 0xFAFF) ||
      (cp >= 0x2F800 && cp <= 0x2FA1F);

  /// NFD + buang tanda diakritik (kategori Mn), untuk huruf Latin umum.
  static String _stripAccents(String s) {
    final out = StringBuffer();
    for (final cp in s.runes) {
      if ((cp >= 0x300 && cp <= 0x36F) ||
          (cp >= 0xFE00 && cp <= 0xFE0F) ||
          (cp >= 0x20D0 && cp <= 0x20FF)) {
        continue;
      }
      final base = _accentBase[cp];
      if (base != null) {
        out.write(base);
      } else {
        out.writeCharCode(cp);
      }
    }
    return out.toString();
  }

  static final Map<int, String> _accentBase = () {
    const groups = {
      'a': 'àáâãäåāăą',
      'c': 'çćĉċč',
      'd': 'ď',
      'e': 'èéêëēĕėęě',
      'g': 'ĝğġģ',
      'h': 'ĥ',
      'i': 'ìíîïĩīĭįı',
      'j': 'ĵ',
      'k': 'ķ',
      'l': 'ĺļľ',
      'n': 'ñńņňŉ',
      'o': 'òóôõöōŏő',
      'r': 'ŕŗř',
      's': 'śŝşš',
      't': 'ţť',
      'u': 'ùúûüũūŭůűų',
      'w': 'ŵ',
      'y': 'ýÿŷ',
      'z': 'źżž',
    };
    final map = <int, String>{};
    groups.forEach((base, chars) {
      for (final cp in chars.runes) {
        map[cp] = base;
      }
    });
    return map;
  }();
}
