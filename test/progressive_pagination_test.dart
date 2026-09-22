import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/reader_markup.dart';
import 'package:vellum/reader/reader_models.dart';
import 'package:vellum/reader/reader_pagination.dart';
import 'package:vellum/reader/reader_toc.dart';
import 'package:vellum/services/book_importer.dart';

void main() {
  PageLayoutConfig config() => const PageLayoutConfig(
    fontSize: 18,
    lineSpacing: ReaderLineSpacing.standard,
    fontFamily: 'Georgia',
    fontWeight: ReaderFontWeight.regular,
    availableHeight: 520,
    contentWidth: 320,
    screenHeight: 720,
    title: '渐进分页',
  );

  ImportedBook longBook(int paragraphs) => ImportedBook(
    title: '渐进分页',
    format: BookFormat.txt,
    paragraphs: List.generate(
      paragraphs,
      (i) =>
          '[[vellum-heading:2]]第${i + 1}节\n'
          '${List.filled(12, '这是第${i + 1}节的正文内容，用于产生多页排版。').join()}',
    ),
  );

  test('progressive pager fills pages ahead without finishing the book', () {
    final book = longBook(80);
    final pager = ProgressiveBookPager(book, config());
    pager.paginateUntilPages(12);

    expect(pager.pageCount, greaterThanOrEqualTo(12));
    expect(pager.fullyPaginated, isFalse);
    expect(pager.nextParagraph, lessThan(book.paragraphs.length));

    final early = pager.exactPageForParagraph(0);
    expect(early, isNotNull);
    final lateRef = pager.pageRefForParagraph(book.paragraphs.length - 1);
    expect(lateRef.exact, isFalse);
  });

  test('pagination extends until fully measured', () {
    final book = longBook(30);
    final pager = ProgressiveBookPager(book, config());
    pager.paginateUntilPages(3);
    expect(pager.fullyPaginated, isFalse);
    while (pager.paginateSlice(maxParagraphs: 10)) {}
    expect(pager.fullyPaginated, isTrue);
    expect(pager.exactPageForParagraph(book.paragraphs.length - 1), isNotNull);
    expect(pager.pageRefForParagraph(0).exact, isTrue);
  });

  test('chapter page label marks estimates while paginating', () {
    final book = longBook(40);
    final pager = ProgressiveBookPager(book, config());
    pager.paginateUntilPages(5);
    final exact = chapterPageLabel(
      paragraphIndex: 0,
      exactPageForParagraph: (p) => pager.exactPageForParagraph(p) ?? -1,
      estimatedPageForParagraph: (p) => pager.pageRefForParagraph(p).page1 - 1,
      fullyPaginated: pager.fullyPaginated,
    );
    expect(exact, startsWith('第'));
    expect(exact, isNot(contains('约')));

    final estimated = chapterPageLabel(
      paragraphIndex: book.paragraphs.length - 1,
      exactPageForParagraph: (p) => pager.exactPageForParagraph(p) ?? -1,
      estimatedPageForParagraph: (p) => pager.pageRefForParagraph(p).page1 - 1,
      fullyPaginated: pager.fullyPaginated,
    );
    expect(estimated, contains('约'));
  });

  test('ReaderMarkup still strips heading markers for measurement', () {
    expect(ReaderMarkup.readerText('[[vellum-heading:2]]标题'), '标题');
  });
}
