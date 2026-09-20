Uri buildBingSearchUri(String query) {
  final encodedQuery = Uri.encodeQueryComponent(query.trim());
  return Uri.parse('https://cn.bing.com/search?q=$encodedQuery&form=QBLH');
}

/// Safe slice of [plain] using offsets measured on indent+plain display text.
/// [indentPrefixLength] is how many display characters were prefixed before
/// [plain] when measuring (2 for `　　`, 0 when the paragraph will not indent).
/// Prevents RangeError when TextPainter offsets are reversed or out of range.
String sliceDisplayText(
  String plain,
  int displayStart,
  int displayEnd, {
  int indentPrefixLength = 2,
}) {
  final start = (displayStart - indentPrefixLength).clamp(0, plain.length);
  final end = (displayEnd - indentPrefixLength).clamp(start, plain.length);
  return plain.substring(start, end);
}

/// Never throws on out-of-range [start]/[end]; returns '' when unusable.
String safeSubstring(String source, int start, [int? end]) {
  if (source.isEmpty) return '';
  final from = start.clamp(0, source.length);
  final to = (end ?? source.length).clamp(from, source.length);
  return source.substring(from, to);
}
