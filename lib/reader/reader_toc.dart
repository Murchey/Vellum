import '../services/book_importer.dart';

/// Chapter entries from TOC or Chinese chapter-title heuristics.
List<MapEntry<int, String>> chapterEntries(ImportedBook book) {
  if (book.tocEntries.isNotEmpty) {
    return book.tocEntries
        .map((entry) => MapEntry(entry.paragraphIndex, entry.title))
        .toList();
  }
  final chapter = RegExp(r'^\s*第[0-9一二三四五六七八九十百千万零〇]+[章节回].*');
  final entries = <MapEntry<int, String>>[];
  for (var index = 0; index < book.paragraphs.length; index++) {
    final value = book.paragraphs[index].trim();
    if (chapter.hasMatch(value)) entries.add(MapEntry(index, value));
  }
  return entries;
}

Map<int, int> chapterStartPages(
  List<MapEntry<int, String>> chapters,
  int Function(int paragraphIndex) pageForParagraph,
) => {
  for (final entry in chapters) entry.key: pageForParagraph(entry.key) + 1,
};
