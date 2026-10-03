import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/reader_models.dart';
import 'package:vellum/reader/reader_pagination.dart';
import 'package:vellum/services/book_importer.dart';

/// A book whose paragraphs are generated on demand, so the book itself costs
/// nothing and only the pager's behaviour is measured.
///
/// This is the 二十四史 shape: hundreds of thousands of paragraphs, which folds to
/// six figures of pages. Measuring that prefix used to take about half a minute
/// and hundreds of megabytes — the "jumping in a big book sometimes crashes"
/// report — so a jump now starts a window at the target paragraph instead.
class _GeneratedParagraphs extends ListBase<String> {
  _GeneratedParagraphs(this.length);

  @override
  final int length;

  @override
  set length(int value) => throw UnsupportedError('read-only');

  @override
  String operator [](int index) => '第${index + 1}段的正文内容，用来产生足够多的页数。';

  @override
  void operator []=(int index, String value) =>
      throw UnsupportedError('read-only');
}

void main() {
  ImportedBook hugeBook({int paragraphs = 300000}) => ImportedBook(
    title: '二十四史',
    format: BookFormat.txt,
    paragraphs: _GeneratedParagraphs(paragraphs),
  );

  PageLayoutConfig config() => const PageLayoutConfig(
    fontSize: 24,
    lineSpacing: ReaderLineSpacing.standard,
    fontFamily: 'Georgia',
    fontWeight: ReaderFontWeight.regular,
    availableHeight: 700,
    contentWidth: 360,
    screenHeight: 800,
    title: '二十四史',
  );

  test('an anchored jump does not measure the prefix', () {
    final pager = ProgressiveBookPager(hugeBook(), config());
    const target = 250000;

    pager.paginateFrom(target, minPages: 50);

    expect(pager.isAnchored, isTrue);
    expect(pager.anchorParagraph, target);
    // Only the jump target onward was measured.
    expect(pager.nextParagraph, greaterThan(target));
    expect(pager.nextParagraph, lessThan(target + 5000));
    expect(pager.pageCount, greaterThanOrEqualTo(50));
  });

  test('the jump target is the first line of the first page', () {
    final pager = ProgressiveBookPager(hugeBook(), config());
    const target = 123456;

    pager.paginateFrom(target, minPages: 4);

    expect(pager.firstParagraphOfPage(0), target);
    // Nothing from before the target leaks into the window.
    for (final fragment in pager.pages[0]) {
      expect(fragment.paragraphIndex, greaterThanOrEqualTo(target));
    }
  });

  test('pages after the anchor are measured and ordered', () {
    final pager = ProgressiveBookPager(hugeBook(), config());
    pager.paginateFrom(1000, minPages: 20);

    var previous = 1000;
    for (var page = 0; page < 10; page++) {
      final first = pager.firstParagraphOfPage(page);
      expect(first, isNotNull);
      expect(first!, greaterThanOrEqualTo(previous));
      previous = first;
    }
    // Absolute page numbers still advance by one per page.
    expect(
      pager.globalPageFor(1) - pager.globalPageFor(0),
      1,
      reason: 'consecutive local pages must map to consecutive book pages',
    );
  });

  test('the book-wide page estimate is close to the measured truth', () {
    // Measure a small book exactly, then place the same window by ratio.
    final book = ImportedBook(
      title: '对照',
      format: BookFormat.txt,
      paragraphs: [
        for (var i = 0; i < 4000; i++) '第${i + 1}段的正文内容，用来产生足够多的页数。',
      ],
    );
    final exact = ProgressiveBookPager(book, config());
    while (exact.paginateSlice(maxParagraphs: 100)) {}
    final truePages = exact.pageCount;

    final anchored = ProgressiveBookPager(book, config());
    anchored.paginateFrom(3600, minPages: 5);
    // The UI widens the sample before showing a page count; do the same here.
    anchored.calibrateEstimate();
    final estimate = anchored.estimatedGlobalPageCount;

    expect(
      (estimate - truePages).abs() / truePages,
      lessThan(0.05),
      reason: 'estimate $estimate vs measured $truePages',
    );
  });

  test('a jump deep into a huge book stays cheap', () {
    final book = hugeBook(paragraphs: 200000);
    final pager = ProgressiveBookPager(book, config());
    final watch = Stopwatch()..start();
    pager.paginateFrom(190000, minPages: 12);
    watch.stop();

    expect(
      watch.elapsedMilliseconds,
      lessThan(2000),
      reason: 'measured ${watch.elapsedMilliseconds}ms',
    );
    expect(pager.nextParagraph - 190000, lessThan(2000));
  });

  test('reset returns the pager to exact, book-wide pagination', () {
    final pager = ProgressiveBookPager(hugeBook(), config());
    pager.paginateFrom(250000, minPages: 10);
    expect(pager.isAnchored, isTrue);

    pager.reset();
    expect(pager.isAnchored, isFalse);
    expect(pager.anchorParagraph, 0);
    expect(pager.nextParagraph, 0);

    pager.paginateSlice(maxParagraphs: 10);
    expect(pager.firstParagraphOfPage(0), 0);
  });

  test('a jump past the end is clamped to the last paragraph', () {
    final book = hugeBook(paragraphs: 500);
    final pager = ProgressiveBookPager(book, config());
    pager.paginateFrom(999999, minPages: 2);
    expect(pager.anchorParagraph, 499);
  });
}
