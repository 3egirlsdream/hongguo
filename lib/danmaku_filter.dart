final _ignoredFilterCharacters = RegExp(
  r'[\s\u200b-\u200f\u2060\ufeff\u3000]+',
);

String normalizeDanmakuFilterText(String text) => String.fromCharCodes(
  text.runes.map(
    (rune) => rune >= 0xff01 && rune <= 0xff5e ? rune - 0xfee0 : rune,
  ),
).toLowerCase().replaceAll(_ignoredFilterCharacters, '');

List<String> normalizeDanmakuKeywords(Iterable<String> words) {
  final result = <String>[];
  final seen = <String>{};
  for (final word in words) {
    final cleaned = word.trim();
    final key = normalizeDanmakuFilterText(cleaned);
    if (key.isEmpty || !seen.add(key)) continue;
    if (cleaned.runes.length > 50) {
      throw const FormatException('每个关键词最多 50 个字符');
    }
    result.add(cleaned);
    if (result.length > 100) throw const FormatException('最多设置 100 个关键词');
  }
  return List.unmodifiable(result);
}

class DanmakuKeywordFilter {
  DanmakuKeywordFilter(Iterable<String> words)
    : keywords = normalizeDanmakuKeywords(words)
          .map(normalizeDanmakuFilterText)
          .toList(growable: false);
  final List<String> keywords;
  bool blocks(String text) {
    if (keywords.isEmpty) return false;
    final normalized = normalizeDanmakuFilterText(text);
    return keywords.any(normalized.contains);
  }
}
