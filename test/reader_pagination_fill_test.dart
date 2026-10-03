import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/reader_models.dart';
import 'package:vellum/reader/reader_pagination.dart';
import 'package:vellum/services/book_importer.dart';

void main() {
  PageLayoutConfig config({double height = 800}) => PageLayoutConfig(
        fontSize: 24,
        lineSpacing: ReaderLineSpacing.standard,
        fontFamily: 'Roboto',
        fontWeight: ReaderFontWeight.regular,
        availableHeight: height,
        contentWidth: 320,
        screenHeight: 800,
        title: '长句填页',
      );

  test('a long sentence fills the page instead of leaving a 22px dead zone', () {
    // ~40 chars/line at 24dp × 320w ≈ 8–10 lines; one huge paragraph.
    final long = '这是一句会被拆到下一页的超长句子' * 20;
    final book = ImportedBook(
      title: '长句填页',
      format: BookFormat.txt,
      paragraphs: [long],
    );
    final cfg = config();
    final pager = ProgressiveBookPager(book, cfg);
    pager.paginateUntilPages(2);

    final first = pager.pages.first;
    expect(first, isNotEmpty);
    final fragmentText = first.map((f) => f.text).join();
    // Page 1 must keep a large share of the sentence — not stop early.
    expect(fragmentText.length, greaterThan(long.length * 0.15));

    // Last fragment on the page has no trailing paragraph gap in the model
    // (render gives it 0 bottom padding).
    expect(first.last.compactPadding || first.length == 1, isTrue);
  });

  test('continuation fragments skip the inter-paragraph gap', () {
    final long = '第二段同样很长' * 30;
    final book = ImportedBook(
      title: '续段',
      format: BookFormat.txt,
      paragraphs: ['前一段。', long],
    );
    final pager = ProgressiveBookPager(book, config());
    while (pager.paginateSlice(maxParagraphs: 25)) {}
    expect(pager.pageCount, greaterThanOrEqualTo(2));

    final page0 = pager.pages.first;
    expect(page0.length, 2, reason: 'the short paragraph plus the first slice');

    // A paragraph split across pages must hand over every character once: the
    // slice bounds are measured on indent-prefixed display text, and the first
    // fragment used to lose that prefix on the way out.
    final whole = page0
        .where((f) => f.paragraphIndex == 1)
        .map((f) => f.text)
        .join();
    final rest = pager.pages
        .skip(1)
        .expand((page) => page)
        .where((f) => f.paragraphIndex == 1)
        .map((f) => f.text)
        .join();
    expect(whole + rest, long);

    // Continuations (anything but a paragraph's first fragment) skip the
    // inter-paragraph 22px step.
    expect(page0.last.paragraphIndex, 1);
    expect(page0.last.compactPadding, isFalse);
    expect(pager.pages.skip(1).expand((page) => page).isNotEmpty, isTrue);
    for (final page in pager.pages.skip(1)) {
      for (final fragment in page) {
        expect(
          fragment.compactPadding,
          isTrue,
          reason: 'a continuation must not charge the paragraph gap',
        );
      }
    }
  });
}
