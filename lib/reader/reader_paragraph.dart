import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectableText;

import '../services/book_importer.dart';
import '../theme/vellum_theme.dart';
import '../util/text_slices.dart';
import 'reader_markup.dart';
import 'reader_models.dart';

/// Renders one reader paragraph (body, heading, quote, list, image, link).
class ReaderParagraph extends StatelessWidget {
  const ReaderParagraph({
    required this.book,
    required this.paragraph,
    required this.paragraphIndex,
    required this.fontSize,
    required this.fontFamily,
    required this.lineSpacing,
    required this.fontWeight,
    required this.ink,
    required this.contextMenuBuilder,
    this.showImage = true,
    this.showLinkAction = true,
    this.indentFirstLine = true,
    this.onJumpToParagraph,
    super.key,
  });

  final ImportedBook book;
  final String paragraph;
  final int paragraphIndex;
  final double fontSize;
  final String fontFamily;
  final ReaderLineSpacing lineSpacing;
  final ReaderFontWeight fontWeight;
  final Color ink;
  final EditableTextContextMenuBuilder contextMenuBuilder;
  final bool showImage;
  final bool showLinkAction;
  final bool indentFirstLine;
  final ValueChanged<int>? onJumpToParagraph;

  @override
  Widget build(BuildContext context) {
    final image = showImage ? book.imageBytes[paragraphIndex] : null;
    final target = showLinkAction ? book.linkTargets[paragraphIndex] : null;
    final standaloneImage = ReaderMarkup.isStandaloneImageParagraph(paragraph);
    final blockImage = image != null && standaloneImage;
    final fullParagraph =
        paragraphIndex >= 0 && paragraphIndex < book.paragraphs.length
        ? book.paragraphs[paragraphIndex]
        : paragraph;
    final heading =
        ReaderMarkup.heading.firstMatch(paragraph) ??
        ReaderMarkup.heading.firstMatch(fullParagraph);
    final isQuote =
        ReaderMarkup.quote.hasMatch(paragraph) ||
        ReaderMarkup.quote.hasMatch(fullParagraph);
    final isList =
        ReaderMarkup.list.hasMatch(paragraph) ||
        ReaderMarkup.list.hasMatch(fullParagraph);
    final isCenter =
        ReaderMarkup.center.hasMatch(paragraph) ||
        ReaderMarkup.center.hasMatch(fullParagraph);
    final isTocHeading = book.tocEntries.any(
      (entry) => entry.paragraphIndex == paragraphIndex,
    );
    final headingLevel = int.tryParse(heading?.group(1) ?? '');
    final effectiveHeading = headingLevel ?? (isTocHeading ? 2 : null);
    final scale = effectiveHeading == null
        ? 1.0
        : ReaderMarkup.headingFontScale(effectiveHeading);
    final displayFontSize = fontSize * scale;
    final bodyInk = target == null
        ? ink
        : VellumTheme.accentOf(context);
    final textStyle = TextStyle(
      fontFamily: fontFamily,
      fontSize: displayFontSize,
      height: effectiveHeading == null
          ? lineSpacing.height
          : ReaderMarkup.headingLineHeight(effectiveHeading),
      fontWeight: effectiveHeading == null
          ? fontWeight.value
          : FontWeight.w700,
      fontStyle: isQuote ? FontStyle.italic : null,
      color: bodyInk,
      decoration: target == null ? null : TextDecoration.underline,
    );
    final needsFirstLineIndent =
        indentFirstLine &&
        effectiveHeading == null &&
        !isQuote &&
        !isList &&
        !isCenter;
    final plain = ReaderMarkup.readerText(paragraph);
    final spans = <InlineSpan>[
      // Text indent, not WidgetSpan: a leading WidgetSpan breaks SelectionArea
      // offsets and can throw RangeError(start) = -1 while selecting text.
      if (needsFirstLineIndent)
        TextSpan(
          text: '　　',
          style: TextStyle(
            fontSize: displayFontSize,
            height: effectiveHeading == null
                ? lineSpacing.height
                : ReaderMarkup.headingLineHeight(effectiveHeading),
          ),
        ),
      ..._richInlineSpans(plain, image: image),
    ];
    final alignment = effectiveHeading != null
        ? (plain.trim().length <= 28 ? TextAlign.center : TextAlign.start)
        : isCenter
        ? TextAlign.center
        : TextAlign.start;
    final text = SelectableText.rich(
      TextSpan(style: textStyle, children: spans),
      contextMenuBuilder: contextMenuBuilder,
      textAlign: alignment,
    );
    final formattedText = isQuote
        ? Container(
            padding: const EdgeInsets.only(left: 14),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: VellumTheme.accentOf(context).withValues(alpha: .7),
                  width: 3,
                ),
              ),
            ),
            child: text,
          )
        : effectiveHeading != null
        ? Padding(
            padding: EdgeInsets.only(
              top: effectiveHeading <= 2 ? 10 : 6,
              bottom: 8,
            ),
            child: text,
          )
        : text;
    final content = <Widget>[
      if (blockImage)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Image.memory(
            image,
            fit: BoxFit.contain,
            width: double.infinity,
            height: MediaQuery.sizeOf(context).height * .36,
            cacheWidth: (MediaQuery.sizeOf(context).width * 2).round(),
            errorBuilder: (context, error, stackTrace) =>
                const SizedBox.shrink(),
          ),
        ),
      if (ReaderMarkup.layoutText(paragraph).isNotEmpty) formattedText,
    ];
    if (target == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: content,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...content,
        CupertinoButton(
          padding: const EdgeInsets.only(top: 2),
          minimumSize: const Size(0, 28),
          onPressed: () => onJumpToParagraph?.call(target),
          child: const Text('跳转至书内链接'),
        ),
      ],
    );
  }

  List<InlineSpan> _richInlineSpans(String source, {Uint8List? image}) {
    final spans = <InlineSpan>[];
    final buffer = StringBuffer();
    var bold = false;
    var italic = false;
    var underline = false;

    void flush() {
      if (buffer.isEmpty) return;
      spans.add(
        TextSpan(
          text: buffer.toString(),
          style: TextStyle(
            fontWeight: bold ? FontWeight.w700 : null,
            fontStyle: italic ? FontStyle.italic : null,
            decoration: underline ? TextDecoration.underline : null,
          ),
        ),
      );
      buffer.clear();
    }

    var cursor = 0;
    for (final match in ReaderMarkup.inlineTag.allMatches(source)) {
      if (match.start > cursor) {
        buffer.write(safeSubstring(source, cursor, match.start));
      }
      final token = match.group(0)!;
      if (token == '[[b]]') {
        flush();
        bold = true;
      } else if (token == '[[/b]]') {
        flush();
        bold = false;
      } else if (token == '[[i]]') {
        flush();
        italic = true;
      } else if (token == '[[/i]]') {
        flush();
        italic = false;
      } else if (token == '[[u]]') {
        flush();
        underline = true;
      } else if (token == '[[/u]]') {
        flush();
        underline = false;
      }
      cursor = match.end;
    }
    if (cursor < source.length) {
      buffer.write(safeSubstring(source, cursor));
    }
    flush();

    if (image != null && source.contains('[[image:')) {
      final rebuilt = <InlineSpan>[];
      for (final span in spans) {
        final text = span is TextSpan ? (span.text ?? '') : '';
        if (!text.contains('[[image:')) {
          rebuilt.add(span);
          continue;
        }
        var pos = 0;
        for (final marker in ReaderMarkup.inlineImage.allMatches(text)) {
          if (marker.start > pos) {
            rebuilt.add(
              TextSpan(
                text: safeSubstring(text, pos, marker.start),
                style: span is TextSpan ? span.style : null,
              ),
            );
          }
          rebuilt.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Image.memory(
                  image,
                  width: fontSize * 1.05,
                  height: fontSize * 1.05,
                  fit: BoxFit.contain,
                  cacheWidth: (fontSize * 2.2).round(),
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          );
          pos = marker.end;
        }
        if (pos < text.length) {
          rebuilt.add(
            TextSpan(
              text: safeSubstring(text, pos),
              style: span is TextSpan ? span.style : null,
            ),
          );
        }
      }
      return rebuilt;
    }

    if (spans.isEmpty) spans.add(TextSpan(text: source));
    return spans;
  }
}
