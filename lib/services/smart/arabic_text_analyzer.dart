/// Deterministic Arabic/Latin text analysis used by the smart search,
/// keyword affinity and duplicate detection engines. Pure functions only —
/// no IO, no clocks, no randomness — so everything is unit-testable.
library;

/// Characters stripped during normalization.
const String _diacritics =
    '\u064B\u064C\u064D\u064E\u064F\u0650\u0651\u0652\u0653\u0654\u0655\u0670'
    '\u06D6\u06D7\u06D8\u06D9\u06DA\u06DB\u06DC\u06DF\u06E0\u06E1\u06E2\u06E3'
    '\u06E4\u06E7\u06E8\u06EA\u06EB\u06EC\u06ED';

const String _tatweel = '\u0640';

/// Very small Arabic + English stopword list for keyword extraction.
/// Kept intentionally tiny and deterministic (no network dictionaries).
const Set<String> arabicStopwords = {
  'في', 'من', 'على', 'عن', 'الى', 'إلى', 'مع', 'هذا', 'هذه', 'ذلك', 'التي',
  'الذي', 'الذين', 'كان', 'كانت', 'يكون', 'ما', 'لا', 'لم', 'لن', 'ان', 'أن',
  'إن', 'او', 'أو', 'ثم', 'قد', 'كل', 'بعد', 'قبل', 'بين', 'حتى', 'لكن',
  'عند', 'هو', 'هي', 'هم', 'انا', 'أنا', 'انت', 'أنت', 'كما', 'ليس', 'هل',
  'the', 'a', 'an', 'of', 'in', 'on', 'and', 'or', 'to', 'for', 'with',
  'is', 'are', 'was', 'were', 'be', 'at', 'by', 'it', 'this', 'that',
};

class ArabicTextAnalyzer {
  const ArabicTextAnalyzer();

  /// Aggressive normalization for matching:
  /// - strips diacritics (تشكيل) and tatweel (تطويل)
  /// - unifies alef/hamza forms  أ إ آ ٱ → ا
  /// - ة → ه , ى → ي , ؤ → و , ئ → ي
  /// - lowercases Latin, collapses whitespace, drops punctuation/symbols
  /// Returns a canonical string safe to compare with ==.
  String normalize(String input) {
    if (input.isEmpty) return '';
    final buffer = StringBuffer();
    for (final ch in input.runes) {
      final c = String.fromCharCode(ch);
      if (_diacritics.contains(c) || c == _tatweel) continue;
      String out;
      switch (c) {
        case 'أ':
        case 'إ':
        case 'آ':
        case 'ٱ':
          out = 'ا';
        case 'ة':
          out = 'ه';
        case 'ى':
          out = 'ي';
        case 'ؤ':
          out = 'و';
        case 'ئ':
          out = 'ي';
        default:
          out = c;
      }
      buffer.write(out);
    }
    final collapsed = buffer
        .toString()
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return collapsed;
  }

  /// Word tokens from [normalize]; single letters removed, optionally
  /// dropping stopwords. A leading definite article "ال" is stripped from
  /// words long enough to remain meaningful (light stemming for matching).
  List<String> tokenize(String input, {bool dropStopwords = false}) {
    final norm = normalize(input);
    if (norm.isEmpty) return const [];
    final words =
        norm.split(' ').where((w) => w.length > 1).map(_stripArticle).toList();
    if (!dropStopwords) return words;
    return words
        .where((w) => w.length > 1 && !arabicStopwords.contains(w))
        .toList();
  }

  /// Removes the leading definite article "ال" when the remainder is at
  /// least 3 characters (e.g. المغامرة → مغامرة) — a cheap, safe light stem.
  String _stripArticle(String w) {
    if (w.startsWith('ال') && w.length >= 5) return w.substring(2);
    return w;
  }

  /// Character trigrams of the normalized text (padded so short words still
  /// produce usable signatures).
  Set<String> trigrams(String input) {
    final norm = normalize(input).replaceAll(' ', '');
    if (norm.isEmpty) return const {};
    final padded = '  $norm  ';
    final grams = <String>{};
    for (var i = 0; i + 3 <= padded.length; i++) {
      grams.add(padded.substring(i, i + 3));
    }
    return grams;
  }

  /// Similarity in 0..1 blending the Dice coefficient of trigrams (65%) with
  /// a normalized Levenshtein ratio (35%). Cheap and deterministic.
  double similarity(String a, String b) {
    final na = normalize(a);
    final nb = normalize(b);
    if (na.isEmpty || nb.isEmpty) return 0;
    if (na == nb) return 1;

    final dice = _dice(trigrams(na), trigrams(nb));

    final lev = _levenshtein(na, nb).toDouble();
    final maxLen = na.length > nb.length ? na.length : nb.length;
    final levRatio = 1 - lev / maxLen;

    return ((dice * 0.65) + (levRatio * 0.35)).clamp(0.0, 1.0);
  }

  /// Dice coefficient over two trigram sets: 2|A∩B| / (|A|+|B|).
  double _dice(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    var inter = 0;
    for (final g in a) {
      if (b.contains(g)) inter++;
    }
    return (2 * inter) / (a.length + b.length);
  }

  /// Classic dynamic-programming edit distance.
  int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    var prev = List<int>.generate(b.length + 1, (i) => i);
    var cur = List<int>.filled(b.length + 1, 0);
    for (var i = 0; i < a.length; i++) {
      cur[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
        var best = cur[j] + 1; // insertion
        if (prev[j + 1] + 1 < best) best = prev[j + 1] + 1; // deletion
        if (prev[j] + cost < best) best = prev[j] + cost; // substitution
        cur[j + 1] = best;
      }
      final tmp = prev;
      prev = cur;
      cur = tmp; // recycled next iteration
    }
    return prev[b.length];
  }

  /// Shared keywords between two free texts (normalized tokens, stopwords
  /// dropped, min length 3). Sorted alphabetically for deterministic tests.
  List<String> sharedKeywords(String a, String b) {
    final ta =
        tokenize(a, dropStopwords: true).where((w) => w.length >= 3).toSet();
    final tb =
        tokenize(b, dropStopwords: true).where((w) => w.length >= 3).toSet();
    final shared = ta.intersection(tb).toList()..sort();
    return shared;
  }
}
