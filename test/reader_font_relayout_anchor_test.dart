import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/reader_page.dart';
import 'package:vellum/services/book_importer.dart';
import 'package:vellum/services/library_models.dart';

/// Changing a layout input — a font family in particular — rebuilds the pager
/// from paragraph 0, so the reader has to re-anchor on the paragraph it is
/// actually showing. Two bugs lived here:
///
/// * the anchor was read *after* the pager had been replaced, so it always came
///   from the empty new page list and fell back to the paragraph the book was
///   opened at — every font switch threw the reader back to the beginning;
/// * a page that carries no text (an image-only spread) reports paragraph 0, so
///   anchoring on it sent the reader to the very first page.
void main() {
  ImportedBook longBook({int paragraphs = 400}) => ImportedBook(
    title: '大书',
    format: BookFormat.txt,
    paragraphs: [
      for (var i = 0; i < paragraphs; i++)
        '第${i + 1}段的正文内容，用来产生足够多的页数。'
            '${List.filled(6, '这是同一段里用于换行的更多文字。').join()}',
    ],
  );

  Future<void> pumpReader(WidgetTester tester, ImportedBook book) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: ReaderPage(
          book: book,
          initialState: const ReadingState(
            mode: 'page',
            paragraphIndex: 40,
            pageTurn: 'none',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ReaderPageState stateOf(WidgetTester tester) =>
      tester.state(find.byType(ReaderPage)) as ReaderPageState;

  testWidgets('a layout change keeps the reading position', (tester) async {
    await pumpReader(tester, longBook());
    final state = stateOf(tester);

    final openedAt = state.debugCurrentPageParagraph;
    expect(openedAt, greaterThan(0));
    expect(state.debugPageCount, greaterThan(20));

    // Read on, well past the opening position.
    state.debugJumpToPage(state.debugPageCount - 6);
    await tester.pumpAndSettle();

    final before = state.debugCurrentPageParagraph;
    expect(
      before,
      greaterThan(openedAt),
      reason: 'the setup must move the reader forward first',
    );

    // Re-layout, exactly as a font switch does.
    state.debugSetFontSize(28);
    await tester.pumpAndSettle();

    final after = stateOf(tester).debugCurrentPageParagraph;
    expect(
      after,
      greaterThan(openedAt),
      reason: 'a layout change must not send the reader back to the paragraph '
          'the book was opened at ($openedAt): it was at $before and landed '
          'on $after',
    );
    // Re-flow moves the paragraph by a line or two, never by a whole page.
    expect(
      (after - before).abs(),
      lessThan(12),
      reason: 're-anchor drifted from $before to $after',
    );
  });

  testWidgets('emphasis and de-emphasis both re-anchor in place', (
    tester,
  ) async {
    await pumpReader(tester, longBook());
    final state = stateOf(tester);

    state.debugJumpToPage(state.debugPageCount - 10);
    await tester.pumpAndSettle();
    final before = stateOf(tester).debugCurrentPageParagraph;
    final basePages = stateOf(tester).debugPageCount;

    // Bigger body text: more pages for the same book, reader stays put.
    stateOf(tester).debugSetFontSize(30);
    await tester.pumpAndSettle();
    final biggerPages = stateOf(tester).debugPageCount;
    expect(biggerPages, greaterThan(basePages));
    expect(
      (stateOf(tester).debugCurrentPageParagraph - before).abs(),
      lessThan(12),
      reason: 'bigger text rewound the reader',
    );

    // Then smaller: fewer pages, and still the same place in the book.
    stateOf(tester).debugSetFontSize(14);
    await tester.pumpAndSettle();
    expect(stateOf(tester).debugPageCount, lessThan(biggerPages));
    expect(
      (stateOf(tester).debugCurrentPageParagraph - before).abs(),
      lessThan(12),
      reason: 'smaller text rewound the reader',
    );
  });
}
