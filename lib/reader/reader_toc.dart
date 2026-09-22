import '../services/book_importer.dart';
import '../services/html_text_pipeline.dart';

const _pipeline = HtmlTextPipeline();

/// Chapter entries from structured TOC or Chinese chapter-title heuristics.
///
/// Titles are cleaned here rather than only in the decoders, so books imported
/// before that cleanup existed are repaired as well.
List<MapEntry<int, String>> chapterEntries(ImportedBook book) {
  if (book.tocEntries.isNotEmpty) {
    final entries = book.tocEntries
        .map(
          (entry) => MapEntry(
            entry.paragraphIndex,
            _pipeline.chapterTitle(entry.title),
          ),
        )
        .where((entry) => entry.value.isNotEmpty)
        .toList();
    // Keep first occurrence per paragraph, preserve order, drop jumps to 0
    // unless the book truly starts there.
    final seen = <int>{};
    final cleaned = <MapEntry<int, String>>[];
    for (final entry in entries) {
      if (!seen.add(entry.key)) continue;
      cleaned.add(entry);
    }
    cleaned.sort((a, b) => a.key.compareTo(b.key));
    return cleaned;
  }
  return heuristicChapterEntries(book.paragraphs);
}

/// Detects chapter headings from paragraph text alone.
///
/// Pattern aligned with Fanqie's TXT chapter regex (`ar5/a.java`): 第 + CJK or
/// Arabic numerals + 册/卷/部/章/回/节/回合. Fanqie also caps the title at ~30
/// chars and rejects lines that look like body prose.
List<MapEntry<int, String>> heuristicChapterEntries(List<String> paragraphs) {
  final patterns = <RegExp>[
    RegExp(
      r'^\s*.{0,20}第[0-9一二三四五六七八九十百千万零〇两壹贰叁肆伍陆柒捌玖拾]*'
      r'(章节|章|册|卷|部|回|节|回合|集|篇)',
    ),
    RegExp(r'^\s*(?:Chapter|CHAPTER|Part|PART)\s+\d+'),
    RegExp(r'^\s*[0-9]{1,3}\s*[\.、．]\s*\S'),
    RegExp(r'^\s*[【\[][^】\]]{1,24}[】\]]\s*$'),
  ];
  final entries = <MapEntry<int, String>>[];
  for (var index = 0; index < paragraphs.length; index++) {
    // Labels are matched after cleanup so a heading that still carries reader
    // markup ([[vellum-heading:1]]第二章) is still recognised.
    final value = _pipeline.chapterTitle(paragraphs[index]);
    if (value.isEmpty || value.length > 40) continue;
    // Skip body-looking lines that merely start with a number.
    if (value.contains('。') ||
        value.contains('，') ||
        value.contains(',') ||
        value.contains('！') ||
        value.contains('？')) {
      continue;
    }
    for (final pattern in patterns) {
      if (pattern.hasMatch(value)) {
        entries.add(MapEntry(index, value));
        break;
      }
    }
  }
  return entries;
}

Map<int, int> chapterStartPages(
  List<MapEntry<int, String>> chapters,
  int Function(int paragraphIndex) pageForParagraph,
) => {for (final entry in chapters) entry.key: pageForParagraph(entry.key) + 1};

/// 1-based page label for a chapter, marking estimates while paginating.
String chapterPageLabel({
  required int paragraphIndex,
  required int Function(int) exactPageForParagraph,
  required int Function(int) estimatedPageForParagraph,
  required bool fullyPaginated,
}) {
  if (fullyPaginated) {
    return '第 ${exactPageForParagraph(paragraphIndex) + 1} 页';
  }
  final exact = exactPageForParagraph(paragraphIndex);
  if (exact >= 0) return '第 ${exact + 1} 页';
  return '约第 ${estimatedPageForParagraph(paragraphIndex) + 1} 页';
}
