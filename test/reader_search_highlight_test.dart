import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show EditableTextState;
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/reader_controls.dart';
import 'package:vellum/reader/reader_models.dart';
import 'package:vellum/reader/reader_paragraph.dart';
import 'package:vellum/services/book_importer.dart';
import 'package:vellum/services/reader_background.dart';

/// Two regressions in the reader menu:
///
/// * the sheet was sized from `MediaQuery.size`, so once the soft keyboard made
///   the overlay's own box smaller than the media size, the sheet ran past its
///   bottom and painted the overflow block — measured at 18 px with a 420 px
///   keyboard;
/// * a search result jumped to the paragraph but the query was dropped with the
///   closed panel, so nothing on the page showed what was being searched for.
void main() {
  const paragraphs = ['第一章 起兵', '太祖本纪，岁在甲子，天下大乱，群雄并起。', '天下既定，乃修文德。'];

  Future<void> pumpMenu(
    WidgetTester tester, {
    required double height,
    double keyboard = 0,
  }) async {
    await tester.binding.setSurfaceSize(Size(390, height + keyboard));
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: Size(390, height + keyboard),
          viewInsets: EdgeInsets.only(bottom: keyboard),
        ),
        child: CupertinoApp(
          home: CupertinoPageScaffold(
            child: SizedBox(
              height: height,
              child: Stack(
                children: [
                  ReaderMenu(
                    visible: true,
                    bookmarked: false,
                    onBack: () {},
                    onToggleBookmark: () {},
                    progress: 0.2,
                    chapterCount: 1,
                    currentChapterIndex: 0,
                    chapterTitle: '第一章 起兵',
                    canSeek: true,
                    onSeekProgress: (_) {},
                    onSeekChapter: (_) {},
                    fontSize: 24,
                    readerFontWeight: ReaderFontWeight.regular,
                    lineSpacing: ReaderLineSpacing.standard,
                    background: const ReaderBackground(),
                    readingMode: ReadingMode.page,
                    pageTurnStyle: PageTurnStyle.cover,
                    brightness: 1,
                    eyeCare: ReaderEyeCare.off,
                    keepScreenOn: true,
                    volumeKeys: false,
                    chapters: const [MapEntry(0, '第一章 起兵')],
                    chapterPageLabels: const {},
                    bookmarks: const [],
                    notes: const [],
                    paragraphs: paragraphs,
                    currentParagraph: 0,
                    bookTitle: '测试书',
                    onJumpToParagraph: (_) {},
                    onRemoveBookmark: (_) async {},
                    onRemoveNote: (_) async {},
                    onFontSize: (_) {},
                    onReaderFontWeight: (_) {},
                    onLineSpacing: (_) {},
                    onBackground: (_) {},
                    onReadingMode: (_) {},
                    onPageTurnStyle: (_) {},
                    onBrightness: (_) {},
                    onEyeCare: (_) {},
                    onKeepScreenOn: (_) {},
                    onVolumeKeys: (_) {},
                    onShowFonts: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the sheet stays inside a keyboard-shrunk overlay', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Keyboard sizes that previously overflowed by 18–39 px.
    for (final keyboard in const [120.0, 300.0, 360.0, 420.0]) {
      await pumpMenu(tester, height: 844 - keyboard, keyboard: keyboard);
      // The reader action bar also carries a 目录 label; pick the tab.\r\n      await tester.tap(find.text('目录').first);
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'catalogue overflowed with a $keyboard px keyboard',
      );

      final icon = find.byIcon(CupertinoIcons.search);
      if (icon.evaluate().isEmpty) continue;
      await tester.tap(icon);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(CupertinoTextField), '天下');
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        tester.takeException(),
        isNull,
        reason: 'search overflowed with a $keyboard px keyboard',
      );
    }
  });

  testWidgets('a search result marks the query inside the paragraph', (
    tester,
  ) async {
    // The renderer marks every occurrence of the term it is given.
    await tester.pumpWidget(
      const CupertinoApp(
        home: CupertinoPageScaffold(
          child: ReaderParagraph(
            book: _Book(),
            paragraph: '太祖本纪，岁在甲子，天下大乱，群雄并起。',
            paragraphIndex: 0,
            fontSize: 20,
            fontFamily: 'Georgia',
            lineSpacing: ReaderLineSpacing.standard,
            fontWeight: ReaderFontWeight.regular,
            ink: Color(0xFF000000),
            contextMenuBuilder: _noContextMenu,
            selectable: false,
            searchHighlight: '天下',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rich = tester.widget<Text>(find.byType(Text).first);
    final marked = <String>[];
    void collect(InlineSpan span) {
      if (span is TextSpan) {
        if (span.style?.backgroundColor != null) marked.add(span.text ?? '');
        for (final child in span.children ?? const <InlineSpan>[]) {
          collect(child);
        }
      }
    }

    collect(rich.textSpan!);
    expect(
      marked,
      contains('天下'),
      reason: 'the searched term must be marked in the body',
    );
  });

  testWidgets('without a search term nothing is marked', (tester) async {
    await tester.pumpWidget(
      const CupertinoApp(
        home: CupertinoPageScaffold(
          child: ReaderParagraph(
            book: _Book(),
            paragraph: '太祖本纪，岁在甲子，天下大乱。',
            paragraphIndex: 0,
            fontSize: 20,
            fontFamily: 'Georgia',
            lineSpacing: ReaderLineSpacing.standard,
            fontWeight: ReaderFontWeight.regular,
            ink: Color(0xFF000000),
            contextMenuBuilder: _noContextMenu,
            selectable: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rich = tester.widget<Text>(find.byType(Text).first);
    final marked = <String>[];
    void collect(InlineSpan span) {
      if (span is TextSpan) {
        if (span.style?.backgroundColor != null) marked.add(span.text ?? '');
        for (final child in span.children ?? const <InlineSpan>[]) {
          collect(child);
        }
      }
    }

    collect(rich.textSpan!);
    expect(marked, isEmpty);
  });
}

Widget _noContextMenu(BuildContext context, EditableTextState state) =>
    const SizedBox.shrink();

class _Book extends ImportedBook {
  const _Book()
    : super(
        title: '测试书',
        format: BookFormat.txt,
        paragraphs: const ['太祖本纪，岁在甲子，天下大乱，群雄并起。'],
      );
}
