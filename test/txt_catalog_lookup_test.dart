import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/services/txt_catalog.dart';

/// The catalog resolves every `book.paragraphs[i]` on a seek-backed TXT book, so
/// its lookups sit on the reader's hottest path: one call per paragraph while
/// paginating. These tests pin the fast implementation to the results of the
/// original linear walk it replaced.
void main() {
  TxtCatalog catalogOf(List<int> chapterParagraphCounts) => TxtCatalog(
    encoding: 'utf-8',
    status: TxtCatalogStatus.ready,
    chapters: [
      for (var i = 0; i < chapterParagraphCounts.length; i++)
        TxtChapterRef(
          index: i,
          title: '第${i + 1}章',
          startOffset: i * 1024,
          byteLength: 1024,
          paragraphCount: chapterParagraphCounts[i],
          charCount: 100 * chapterParagraphCounts[i],
        ),
    ],
  );

  /// The original implementation, kept as the oracle.
  int referenceStartOf(List<TxtChapterRef> chapters, int chapterIndex) {
    var sum = 0;
    for (var i = 0; i < chapterIndex && i < chapters.length; i++) {
      sum += chapters[i].paragraphCount;
    }
    return sum;
  }

  TxtChapterRef referenceChapterFor(
    List<TxtChapterRef> chapters,
    int paragraphIndex,
  ) {
    var sum = 0;
    for (final chapter in chapters) {
      final end = sum + chapter.paragraphCount;
      if (paragraphIndex < end) return chapter;
      sum = end;
    }
    return chapters.isEmpty
        ? const TxtChapterRef(
            index: 0,
            title: '',
            startOffset: 0,
            byteLength: 0,
            paragraphCount: 0,
          )
        : chapters.last;
  }

  test('totals and lookups match the linear walk they replaced', () {
    final catalog = catalogOf([3, 0, 5, 1, 0, 0, 7, 2]);
    final total = catalog.totalParagraphs;
    expect(total, 18);
    expect(catalog.totalCharCount, 1800);

    for (var i = 0; i < catalog.chapters.length; i++) {
      expect(
        catalog.paragraphStartOf(i),
        referenceStartOf(catalog.chapters, i),
        reason: 'start of chapter $i',
      );
    }

    // Every paragraph index, plus the out-of-range ends.
    for (var index = 0; index <= total + 2; index++) {
      expect(
        catalog.chapterForParagraph(index).index,
        referenceChapterFor(catalog.chapters, index).index,
        reason: 'paragraph $index',
      );
    }
  });

  test('an empty catalog is safe', () {
    final catalog = catalogOf([]);
    expect(catalog.totalParagraphs, 0);
    expect(catalog.paragraphStartOf(0), 0);
    expect(catalog.chapterForParagraph(0).index, 0);
    expect(catalog.chapterForParagraph(999).paragraphCount, 0);
  });

  test('out-of-range chapter lookups clamp instead of throwing', () {
    final catalog = catalogOf([2, 2]);
    expect(catalog.paragraphStartOf(-5), 0);
    expect(catalog.paragraphStartOf(99), 4);
  });

  test('paragraph lookup stays fast on a chapter-heavy book', () {
    final catalog = catalogOf(List<int>.filled(3000, 4));
    final total = catalog.totalParagraphs;
    expect(total, 12000);

    final watch = Stopwatch()..start();
    var sink = 0;
    for (var i = 0; i < total; i++) {
      final chapter = catalog.chapterForParagraph(i);
      sink += catalog.paragraphStartOf(chapter.index);
    }
    watch.stop();
    debugPrint('catalog lookups: $total paragraphs in ${watch.elapsedMilliseconds}ms');

    // The linear version took ~60 ms here; a regression to O(chapters) per
    // lookup blows straight past this ceiling.
    expect(sink, greaterThan(0));
    expect(
      watch.elapsedMilliseconds,
      lessThan(40),
      reason: 'paragraph lookup regressed to a linear chapter scan',
    );
  });
}
