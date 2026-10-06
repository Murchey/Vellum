import '../services/book_models.dart';
import '../services/library_models.dart';
import 'reader_toc.dart';

/// Chapter and durable-position rules shared by the reader footer and menu.
///
/// The controller is intentionally independent from pagination and Flutter
/// widgets. Page counts and visual progress are supplied by the page state.
class ReaderProgressController {
  ReaderProgressController({
    required ImportedBook book,
    required ReadingState initialState,
  })  : book = book,
        chapters = chapterEntries(book),
        chapterPositions = {...initialState.chapterPositions},
        resumeParagraphIndex = initialState.paragraphIndex;

  final ImportedBook book;
  final List<MapEntry<int, String>> chapters;
  final Map<int, ChapterReadingPosition> chapterPositions;
  int resumeParagraphIndex;

  Set<int> get tocParagraphs => {for (final entry in chapters) entry.key};

  int chapterIndexFor(int paragraph) {
    var low = 0;
    var high = chapters.length - 1;
    var found = -1;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      if (chapters[mid].key <= paragraph) {
        found = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return found;
  }

  int chapterStartForParagraph(int paragraph) {
    final index = chapterIndexFor(paragraph);
    return index < 0 ? 0 : chapters[index].key;
  }

  String chapterLabelForParagraph(int paragraph) {
    if (chapters.isEmpty) return '';
    final index = chapterIndexFor(paragraph);
    if (index < 0) return '开篇';
    return chapters[index].value;
  }

  double chapterProgressForParagraph(int paragraph, double bookProgress) {
    if (chapters.isEmpty) return bookProgress;
    final index = chapterIndexFor(paragraph);
    if (index < 0) return 0;
    final start = chapters[index].key;
    final end = index + 1 < chapters.length
        ? chapters[index + 1].key
        : book.paragraphs.length;
    if (end <= start + 1) return paragraph >= start ? 1 : 0;
    return ((paragraph - start) / (end - start - 1)).clamp(0.0, 1.0);
  }

  void rememberCurrentChapterPosition({
    required int paragraph,
    required double scrollOffset,
    required int page,
    required bool restored,
  }) {
    if (!restored || chapters.isEmpty) return;
    final safe = paragraph.clamp(
      0,
      book.paragraphs.isEmpty ? 0 : book.paragraphs.length - 1,
    );
    final start = chapterStartForParagraph(safe);
    chapterPositions[start] = ChapterReadingPosition(
      position: scrollOffset,
      page: page,
      paragraphIndex: safe,
    );
  }
}
