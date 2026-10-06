import 'package:flutter/cupertino.dart';

import '../services/book_importer.dart';
import 'reader_markup.dart';
import 'reader_models.dart';
import 'reader_paragraph.dart';

/// Renders the text surface for both scroll and page reading modes.
///
/// Gesture handling and persistence stay in [ReaderPageState]; this widget
/// receives explicit callbacks so the body can be tested independently.
class ReaderPageSurface extends StatelessWidget {
  const ReaderPageSurface({
    required this.book,
    required this.readingMode,
    required this.scrollController,
    required this.pageController,
    required this.pageCount,
    required this.pages,
    required this.currentPage,
    required this.sideInset,
    required this.topInset,
    required this.bottomInset,
    required this.fontSize,
    required this.fontFamily,
    required this.lineSpacing,
    required this.fontWeight,
    required this.ink,
    required this.tocParagraphs,
    required this.paragraphKeys,
    required this.highlights,
    required this.spokenSentence,
    required this.searchHighlight,
    required this.noteCountFor,
    required this.contextMenuBuilder,
    required this.onOpenNotes,
    required this.onJumpToParagraph,
    required this.onBookmarkPull,
    required this.onRestorePage,
    required this.onPageChanged,
    this.selectable = true,
    super.key,
  });

  final ImportedBook book;
  final ReadingMode readingMode;
  final ScrollController scrollController;
  final PageController pageController;
  final int pageCount;
  final List<List<PageFragment>> pages;
  final int currentPage;
  final double sideInset;
  final double topInset;
  final double bottomInset;
  final double fontSize;
  final String fontFamily;
  final ReaderLineSpacing lineSpacing;
  final ReaderFontWeight fontWeight;
  final Color ink;
  final Set<int> tocParagraphs;
  final Map<int, GlobalKey> paragraphKeys;
  final Map<int, List<String>> highlights;
  final String spokenSentence;
  final String searchHighlight;
  final int Function(int paragraphIndex) noteCountFor;
  final EditableTextContextMenuBuilder Function(int paragraphIndex)
      contextMenuBuilder;
  final ValueChanged<int> onOpenNotes;
  final ValueChanged<int> onJumpToParagraph;
  final bool Function(ScrollNotification) onBookmarkPull;
  final VoidCallback onRestorePage;
  final ValueChanged<int> onPageChanged;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    if (readingMode == ReadingMode.scroll) {
      return NotificationListener<ScrollNotification>(
        onNotification: onBookmarkPull,
        child: ListView.builder(
          controller: scrollController,
          padding: EdgeInsets.fromLTRB(
            sideInset,
            topInset,
            sideInset,
            bottomInset,
          ),
          itemCount: book.paragraphs.length + 2,
          itemBuilder: (context, index) {
            if (index == 0) return _title();
            if (index == 1) return const SizedBox(height: 30);
            final paragraphIndex = index - 2;
            final isHeading =
                ReaderMarkup.heading.hasMatch(book.paragraphs[paragraphIndex]) ||
                tocParagraphs.contains(paragraphIndex);
            return KeyedSubtree(
              key: paragraphKeys.putIfAbsent(
                paragraphIndex,
                () => GlobalKey(),
              ),
              child: Padding(
                padding: EdgeInsets.only(bottom: 22, top: isHeading ? 10 : 0),
                child: _paragraph(paragraphIndex),
              ),
            );
          },
        ),
      );
    }

    return Builder(
      builder: (context) {
        onRestorePage();
        return PageView.builder(
          controller: pageController,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          allowImplicitScrolling: true,
          itemCount: pageCount,
          onPageChanged: onPageChanged,
          itemBuilder: (context, index) => Padding(
            padding: EdgeInsets.fromLTRB(
              sideInset,
              topInset,
              sideInset,
              bottomInset,
            ),
            child: buildPage(context, index),
          ),
        );
      },
    );
  }

  Widget _title() => Text(
        book.title,
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: fontSize + 9,
          height: 1.3,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
      );

  Widget _paragraph(int paragraphIndex) => ReaderParagraph(
        book: book,
        paragraph: book.paragraphs[paragraphIndex],
        paragraphIndex: paragraphIndex,
        fontSize: fontSize,
        fontFamily: fontFamily,
        lineSpacing: lineSpacing,
        fontWeight: fontWeight,
        ink: ink,
        contextMenuBuilder: contextMenuBuilder(paragraphIndex),
        highlights: [
          ...?highlights[paragraphIndex],
          if (spokenSentence.isNotEmpty) spokenSentence,
        ],
        searchHighlight: searchHighlight,
        isChapterHeading: tocParagraphs.contains(paragraphIndex),
        noteCount: noteCountFor(paragraphIndex),
        onOpenNotes: () => onOpenNotes(paragraphIndex),
        onJumpToParagraph: onJumpToParagraph,
        selectable: selectable,
      );

  /// Builds a single paginated page for the cover-turn overlay.
  Widget buildPage(BuildContext context, int pageIndex) {
    if (pages.isEmpty) return const SizedBox.shrink();
    final page = pageIndex.clamp(0, pages.length - 1);
    final fragments = pages[page];
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          SizedBox(
            height: constraints.maxHeight,
            child: ClipRect(
              clipBehavior: Clip.hardEdge,
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minHeight: constraints.maxHeight,
                maxHeight: double.infinity,
                maxWidth: constraints.maxWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (page == 0) _title(),
                    if (page == 0) const SizedBox(height: 30),
                    for (var index = 0; index < fragments.length; index++)
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: index == fragments.length - 1
                              ? 0
                              : (fragments[index].compactPadding ? 0 : 22),
                        ),
                        child: ReaderParagraph(
                          book: book,
                          paragraph: fragments[index].text,
                          paragraphIndex: fragments[index].paragraphIndex,
                          fontSize: fontSize,
                          fontFamily: fontFamily,
                          lineSpacing: lineSpacing,
                          fontWeight: fontWeight,
                          ink: ink,
                          contextMenuBuilder:
                              contextMenuBuilder(fragments[index].paragraphIndex),
                          highlights: [
                            ...?highlights[fragments[index].paragraphIndex],
                            if (spokenSentence.isNotEmpty) spokenSentence,
                          ],
                          searchHighlight: searchHighlight,
                          isChapterHeading: tocParagraphs.contains(
                            fragments[index].paragraphIndex,
                          ),
                          noteCount: noteCountFor(fragments[index].paragraphIndex),
                          onOpenNotes: () => onOpenNotes(
                            fragments[index].paragraphIndex,
                          ),
                          showImage: fragments[index].showImage,
                          showLinkAction: fragments[index].showLinkAction,
                          indentFirstLine: fragments[index].indentFirstLine,
                          selectable: selectable,
                          onJumpToParagraph: onJumpToParagraph,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
