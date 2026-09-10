import 'package:flutter/cupertino.dart';

import '../services/book_importer.dart';
import '../util/text_slices.dart';
import 'reader_markup.dart';
import 'reader_models.dart';

/// Immutable layout inputs for page-mode pagination.
class PageLayoutConfig {
  const PageLayoutConfig({
    required this.fontSize,
    required this.lineSpacing,
    required this.fontFamily,
    required this.fontWeight,
    required this.availableHeight,
    required this.contentWidth,
    required this.screenHeight,
    required this.title,
  });

  final double fontSize;
  final ReaderLineSpacing lineSpacing;
  final String fontFamily;
  final ReaderFontWeight fontWeight;
  final double availableHeight;
  final double contentWidth;
  final double screenHeight;
  final String title;

  double get lineHeight => fontSize * lineSpacing.height;

  TextStyle get measureStyle => TextStyle(
    fontFamily: fontFamily,
    fontSize: fontSize,
    height: lineSpacing.height,
    fontWeight: fontWeight.value,
  );
}

/// Exact or estimated pagination for [book] under [config].
List<List<PageFragment>> computeBookPages(
  ImportedBook book,
  PageLayoutConfig config,
) {
  if (book.paragraphs.length > 2000) {
    return _estimateLargeBookPages(book, config);
  }
  return _exactPages(book, config);
}

double measureTitleHeight(PageLayoutConfig config) {
  final painter = TextPainter(
    text: TextSpan(
      text: config.title,
      style: TextStyle(
        fontFamily: config.fontFamily,
        fontSize: config.fontSize + 9,
        height: 1.3,
        fontWeight: FontWeight.w600,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: config.contentWidth);
  return painter.height;
}

List<List<PageFragment>> _exactPages(
  ImportedBook book,
  PageLayoutConfig config,
) {
  final size = Size(config.contentWidth, config.screenHeight);
  final availableHeight = config.availableHeight;
  final contentWidth = config.contentWidth;
  final pages = <List<PageFragment>>[[]];
  var usedHeight = measureTitleHeight(config) + 30;

  void newPage() {
    pages.add([]);
    usedHeight = 0;
  }

  for (var index = 0; index < book.paragraphs.length; index++) {
    final source = book.paragraphs[index];
    final hasImage = book.imageBytes[index] != null;
    final hasBlockImage =
        hasImage && ReaderMarkup.isStandaloneImageParagraph(source);
    final hasLink = book.linkTargets[index] != null;
    final imageHeight = hasBlockImage ? size.height * .36 + 12 : 0.0;
    final linkHeight = hasLink ? 30.0 : 0.0;
    final headingLevel = int.tryParse(
      ReaderMarkup.heading.firstMatch(source)?.group(1) ?? '',
    );
    if (headingLevel != null && headingLevel <= 2 && pages.last.isNotEmpty) {
      newPage();
    }

    if (source.isEmpty) {
      final needed = imageHeight + linkHeight + 22;
      if (usedHeight + needed > availableHeight && pages.last.isNotEmpty) {
        newPage();
      }
      pages.last.add(
        PageFragment(
          paragraphIndex: index,
          text: '',
          showImage: hasImage,
          showLinkAction: hasLink,
        ),
      );
      usedHeight += needed;
      continue;
    }

    final plainSource = ReaderMarkup.stripAllMarkers(source);
    final displaySource = plainSource.isEmpty
        ? plainSource
        : '　　$plainSource';
    final painter = TextPainter(
      text: TextSpan(text: displaySource, style: config.measureStyle),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: contentWidth);
    final lines = painter.computeLineMetrics();
    var lineStart = 0;
    var firstFragment = true;

    for (var lineIndex = 0; lineIndex < lines.length;) {
      final fragmentStart = lineStart;
      var fragmentHeight = 0.0;
      var fragmentEnd = lineStart;
      final prefixHeight = firstFragment ? imageHeight : 0.0;

      while (lineIndex < lines.length) {
        final nextHeight = fragmentHeight + lines[lineIndex].height;
        final isLastLine = lineIndex == lines.length - 1;
        final suffixHeight = 22 + (isLastLine ? linkHeight : 0.0);
        final wouldFit =
            usedHeight + prefixHeight + nextHeight + suffixHeight <=
            availableHeight;
        if (!wouldFit && fragmentEnd != fragmentStart) break;
        fragmentHeight = nextHeight;
        fragmentEnd = painter
            .getPositionForOffset(
              Offset(contentWidth, lines[lineIndex].baseline),
            )
            .offset;
        lineIndex++;
        if (!wouldFit ||
            usedHeight + prefixHeight + fragmentHeight + 22 >= availableHeight) {
          break;
        }
      }

      if (fragmentEnd == fragmentStart) {
        newPage();
        continue;
      }

      final isLastFragment = lineIndex == lines.length;
      final needed =
          prefixHeight +
          fragmentHeight +
          22 +
          (isLastFragment ? linkHeight : 0.0);
      if (usedHeight + needed > availableHeight && pages.last.isNotEmpty) {
        lineStart = fragmentStart;
        final retryLine = lines.indexWhere(
          (line) =>
              painter
                  .getPositionForOffset(Offset(contentWidth, line.baseline))
                  .offset >
              fragmentStart,
        );
        lineIndex = retryLine < 0 ? lineIndex : retryLine;
        newPage();
        continue;
      }

      pages.last.add(
        PageFragment(
          paragraphIndex: index,
          text: sliceDisplayText(plainSource, fragmentStart, fragmentEnd),
          indentFirstLine: firstFragment,
          showImage: firstFragment && hasImage,
          showLinkAction: isLastFragment && hasLink,
        ),
      );
      usedHeight += needed;
      lineStart = fragmentEnd;
      firstFragment = false;
    }
  }
  return pages;
}

List<List<PageFragment>> _estimateLargeBookPages(
  ImportedBook book,
  PageLayoutConfig config,
) {
  final availableHeight = config.availableHeight;
  final lineHeight = config.lineHeight;
  final guardedHeight = (availableHeight - 12).clamp(
    lineHeight * 2,
    availableHeight,
  );
  final avgCharWidth = _estimateAverageCharWidth(
    book.paragraphs.take(40).join(),
  );
  final charsPerLine = (config.contentWidth / (config.fontSize * avgCharWidth))
      .floor()
      .clamp(8, 96);
  final linesPerPage = (guardedHeight / lineHeight).floor().clamp(1, 80);
  final imageReserveLines =
      ((config.screenHeight * .36 + 16) / lineHeight).ceil() + 1;
  final titleLines =
      (measureTitleHeight(config) / lineHeight).ceil() + 1;
  final regularCapacity = charsPerLine * linesPerPage;
  final pages = <List<PageFragment>>[[]];
  var used = titleLines;
  for (var index = 0; index < book.paragraphs.length; index++) {
    final source = book.paragraphs[index];
    final hasImage = book.imageBytes[index] != null;
    final hasBlockImage =
        hasImage && ReaderMarkup.isStandaloneImageParagraph(source);
    if (source.isEmpty && !hasBlockImage) continue;

    var start = 0;
    var firstPart = true;
    do {
      final imageLines = firstPart && hasBlockImage ? imageReserveLines : 0;
      var availableLines = linesPerPage - used - imageLines;
      if (availableLines <= 0 && pages.last.isNotEmpty) {
        pages.add([]);
        used = 0;
        availableLines = linesPerPage - imageLines;
      }
      final indentChars = firstPart ? 2 : 0;
      final capacity = (availableLines * charsPerLine - indentChars).clamp(
        1,
        regularCapacity,
      );
      final safeStart = start.clamp(0, source.length);
      var safeEnd = source.isEmpty
          ? 0
          : _estimateBreakOffset(source, safeStart, capacity);
      if (safeEnd < safeStart) safeEnd = safeStart;
      if (safeEnd == safeStart && safeStart < source.length) {
        safeEnd = (safeStart + 1).clamp(0, source.length);
      }
      final text = source.isEmpty
          ? ''
          : safeSubstring(source, safeStart, safeEnd);
      final textLines = source.isEmpty
          ? 0
          : ((text.length + indentChars) / charsPerLine).ceil().clamp(
              1,
              availableLines,
            );
      final need = textLines + imageLines;
      pages.last.add(
        PageFragment(
          paragraphIndex: index,
          text: text,
          indentFirstLine: firstPart,
          showImage: firstPart && hasImage,
          compactPadding: true,
        ),
      );
      used += need;
      start = safeEnd;
      firstPart = false;
    } while (start < source.length);
  }
  return pages;
}

double _estimateAverageCharWidth(String sample) {
  if (sample.isEmpty) return .92;
  var cjk = 0;
  var latin = 0;
  var spaces = 0;
  for (final rune in sample.runes) {
    if (rune == 0x20 || rune == 0x3000) {
      spaces++;
    } else if (rune >= 0x2E80 && rune <= 0x9FFF ||
        rune >= 0xF900 && rune <= 0xFAFF ||
        rune >= 0xFF00 && rune <= 0xFFEF) {
      cjk++;
    } else {
      latin++;
    }
  }
  final total = (cjk + latin + spaces).clamp(1, sample.length);
  final weighted = cjk * 1.0 + latin * .52 + spaces * .3;
  return (weighted / total).clamp(.45, 1.05);
}

int _estimateBreakOffset(String source, int start, int capacity) {
  if (source.isEmpty || start >= source.length) return source.length;
  final hardEnd = (start + capacity).clamp(start, source.length);
  if (hardEnd >= source.length) return source.length;
  final windowStart = start + (capacity * .82).floor();
  for (var index = hardEnd; index > windowStart; index--) {
    if (index - 1 < start || index - 1 >= source.length) continue;
    final unit = source.codeUnitAt(index - 1);
    if (unit == 0x3002 ||
        unit == 0xFF01 ||
        unit == 0xFF1F ||
        unit == 0x21 ||
        unit == 0x3F ||
        unit == 0x2E) {
      return index;
    }
  }
  return hardEnd;
}
