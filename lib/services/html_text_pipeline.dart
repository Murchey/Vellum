import 'dart:convert';
import 'dart:typed_data';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:markdown/markdown.dart' as markdown;

import 'book_models.dart';

/// HTML → reader-markup text pipeline shared by MOBI/EPUB.
class HtmlTextPipeline {
  const HtmlTextPipeline();

  HtmlContent convert(String source, String documentPath) {
    final marked = source
        .replaceAllMapped(
          RegExp(
            r'''<img[^>]*recindex\s*=\s*["']?(\d+)["']?[^>]*>''',
            caseSensitive: false,
          ),
          (match) => '[[image:${match.group(1)}]]',
        )
        .replaceAllMapped(
          RegExp(
            r'''<[^>]*\bid\s*=\s*["']([^"']+)["'][^>]*>''',
            caseSensitive: false,
          ),
          (match) =>
              '${match.group(0)}[[anchor:$documentPath#${match.group(1)}]]',
        )
        .replaceAllMapped(
          RegExp(
            r'''<a\b[^>]*\bhref\s*=\s*["']([^"']+)["'][^>]*>''',
            caseSensitive: false,
          ),
          (match) =>
              '[[link:${resolveLink(documentPath, match.group(1)!)}]]${match.group(0)}',
        )
        .replaceAll(RegExp(r'</a\s*>', caseSensitive: false), '[[/link]]');
    final raw = htmlToText(marked);
    final paragraphs = splitParagraphs(raw);
    final anchors = <String, int>{};
    final links = <int, String>{};
    final images = <int, int>{};
    final anchorPattern = RegExp(r'\[\[anchor:([^\]]+)\]\]');
    final linkPattern = RegExp(r'\[\[link:([^\]]+)\]\]');
    final imagePattern = RegExp(r'\[\[image:(\d+)\]\]');
    final metadataPattern = RegExp(r'\[\[(?:anchor|link):[^\]]+\]\]');
    for (var index = 0; index < paragraphs.length; index++) {
      final paragraph = paragraphs[index];
      for (final match in anchorPattern.allMatches(paragraph)) {
        anchors[match.group(1)!] = index;
      }
      final link = linkPattern.firstMatch(paragraph);
      if (link != null) links[index] = link.group(1)!;
      final image = imagePattern.firstMatch(paragraph);
      if (image != null) images[index] = int.parse(image.group(1)!);
      paragraphs[index] = paragraph
          .replaceAll(metadataPattern, '')
          .replaceAll('[[/link]]', '')
          .trim();
    }
    final cleaned = <String>[];
    final oldToNew = <int, int>{};
    for (var index = 0; index < paragraphs.length; index++) {
      if (paragraphs[index].isEmpty && !images.containsKey(index)) continue;
      oldToNew[index] = cleaned.length;
      cleaned.add(paragraphs[index]);
    }
    final remapImages = <int, int>{};
    for (final entry in images.entries) {
      final target = oldToNew[entry.key];
      if (target != null) remapImages[target] = entry.value;
    }
    final remapLinks = <int, String>{};
    for (final entry in links.entries) {
      final target = oldToNew[entry.key];
      if (target != null) remapLinks[target] = entry.value;
    }
    final remapAnchors = <String, int>{};
    for (final entry in anchors.entries) {
      final target = oldToNew[entry.value];
      if (target != null) remapAnchors[entry.key] = target;
    }
    return HtmlContent(
      paragraphs: cleaned,
      anchors: remapAnchors,
      links: remapLinks,
      images: remapImages,
    );
  }

  String resolveLink(String documentPath, String href) {
    if (href.startsWith('#')) return '$documentPath$href';
    final hash = href.indexOf('#');
    if (hash < 0) return href;
    final slash = documentPath.lastIndexOf('/');
    final directory = slash < 0 ? '' : documentPath.substring(0, slash + 1);
    return '$directory$href';
  }

  String htmlToText(String source) {
    if (source.length > 2 * 1024 * 1024) return htmlToTextFast(source);
    final fragment = html_parser.parseFragment(source);
    final output = StringBuffer();

    void paragraphBreak() {
      if (output.isNotEmpty && !output.toString().endsWith('\n\n')) {
        output.write('\n\n');
      }
    }

    void visit(dom.Node node) {
      if (node is dom.Text) {
        output.write(node.data);
        return;
      }
      if (node is! dom.Element) {
        for (final child in node.nodes) {
          visit(child);
        }
        return;
      }
      final tag = node.localName?.toLowerCase() ?? '';
      if (tag == 'script' || tag == 'style' || tag == 'head') return;
      if (tag == 'br') {
        output.write('\n\n');
        return;
      }
      if (tag == 'hr') {
        paragraphBreak();
        return;
      }
      if (tag == 'img') {
        final recindex = node.attributes['recindex'];
        if (recindex != null && recindex.isNotEmpty) {
          output.write('[[image:$recindex]]');
        } else {
          final src = node.attributes['src'] ?? '';
          final fileIndex = RegExp(
            r'(?:^|[/\\])(\d+)\.(?:jpe?g|png|gif)$',
            caseSensitive: false,
          ).firstMatch(src)?.group(1);
          if (fileIndex != null) {
            output.write('[[image:$fileIndex]]');
          }
        }
        return;
      }
      final inlineStyle = (node.attributes['style'] ?? '').toLowerCase();
      final isBoldTag = tag == 'b' || tag == 'strong' || tag == 'th';
      final isItalicTag =
          tag == 'i' || tag == 'em' || tag == 'cite' || tag == 'var';
      final isUnderlineTag = tag == 'u';
      final isCenterTag = tag == 'center';
      final alignAttr = (node.attributes['align'] ?? '').toLowerCase();
      final isCentered =
          isCenterTag ||
          alignAttr == 'center' ||
          RegExp(r'text-align\s*:\s*center').hasMatch(inlineStyle);
      final styleBold = RegExp(
        r'font-weight\s*:\s*(bold|[6-9]00)',
      ).hasMatch(inlineStyle);
      final styleItalic = RegExp(
        r'font-style\s*:\s*italic',
      ).hasMatch(inlineStyle);
      final styleUnderline = RegExp(
        r'text-decoration[^;]*underline',
      ).hasMatch(inlineStyle);
      final openBold = isBoldTag || styleBold;
      final openItalic = isItalicTag || styleItalic;
      final openUnderline = isUnderlineTag || styleUnderline;
      if (openBold) output.write('[[b]]');
      if (openItalic) output.write('[[i]]');
      if (openUnderline) output.write('[[u]]');
      final block = {'p', 'div', 'section', 'article', 'pre', 'table'};
      final heading = RegExp(r'^h[1-6]$').hasMatch(tag);
      final quote = tag == 'blockquote';
      final nestedQuote = quote && node.parent?.localName == 'blockquote';
      final inQuote = node.parent?.localName == 'blockquote';
      final listItem = tag == 'li';
      final needsBreak =
          (block.contains(tag) && !inQuote) ||
          heading ||
          (quote && !nestedQuote) ||
          listItem ||
          isCenterTag;
      if (needsBreak) {
        paragraphBreak();
      }
      if (heading) output.write('[[vellum-heading:${tag.substring(1)}]]');
      if (quote && !nestedQuote) output.write('[[vellum-quote]]');
      if (isCentered && !heading) output.write('[[vellum-center]]');
      if (listItem) output.write('[[vellum-list]]');
      for (final child in node.nodes) {
        visit(child);
      }
      if (openUnderline) output.write('[[/u]]');
      if (openItalic) output.write('[[/i]]');
      if (openBold) output.write('[[/b]]');
      if (needsBreak) {
        paragraphBreak();
      }
    }

    for (final node in fragment.nodes) {
      visit(node);
    }
    return output.toString();
  }

  String htmlToTextFast(String source) {
    final withInline = source
        .replaceAllMapped(
          RegExp(r'<(b|strong)\b[^>]*>', caseSensitive: false),
          (_) => '[[b]]',
        )
        .replaceAllMapped(
          RegExp(r'</(b|strong)\s*>', caseSensitive: false),
          (_) => '[[/b]]',
        )
        .replaceAllMapped(
          RegExp(r'<(i|em|cite|var)\b[^>]*>', caseSensitive: false),
          (_) => '[[i]]',
        )
        .replaceAllMapped(
          RegExp(r'</(i|em|cite|var)\s*>', caseSensitive: false),
          (_) => '[[/i]]',
        )
        .replaceAllMapped(
          RegExp(r'<u\b[^>]*>', caseSensitive: false),
          (_) => '[[u]]',
        )
        .replaceAllMapped(
          RegExp(r'</u\s*>', caseSensitive: false),
          (_) => '[[/u]]',
        );
    final withBreaks = withInline
        .replaceAllMapped(
          RegExp(r'<h([1-6])\b[^>]*>', caseSensitive: false),
          (match) => '[[vellum-heading:${match.group(1)}]]',
        )
        .replaceAll(
          RegExp(r'<blockquote\b[^>]*>', caseSensitive: false),
          '[[vellum-quote]]',
        )
        .replaceAll(
          RegExp(r'<li\b[^>]*>', caseSensitive: false),
          '[[vellum-list]]',
        )
        .replaceAll(
          RegExp(
            r'<(br|/p|/h[1-6]|/div|/section|/article|/pre|/table|/li|/blockquote|hr|/center)\b[^>]*>',
            caseSensitive: false,
          ),
          '\n\n',
        )
        .replaceAll(
          RegExp(r'<center\b[^>]*>', caseSensitive: false),
          '\n\n[[vellum-center]]',
        )
        .replaceAll(RegExp(r'<[^>]*>'), '');
    return decodeHtmlEntities(withBreaks);
  }

  static const Map<String, String> _htmlEntities = {
    'nbsp': ' ',
    'amp': '&',
    'lt': '<',
    'gt': '>',
    'quot': '"',
    'apos': "'",
    'mdash': '—',
    'ndash': '–',
    'hellip': '…',
    'lsquo': '‘',
    'rsquo': '’',
    'ldquo': '“',
    'rdquo': '”',
    'sbquo': '‚',
    'bdquo': '„',
    'bull': '•',
    'middot': '·',
    'copy': '©',
    'reg': '®',
    'trade': '™',
    'deg': '°',
    'plusmn': '±',
    'times': '×',
    'divide': '÷',
    'sect': '§',
    'para': '¶',
    'dagger': '†',
    'Dagger': '‡',
    'permil': '‰',
    'euro': '€',
    'pound': '£',
    'yen': '¥',
    'cent': '¢',
    'laquo': '«',
    'raquo': '»',
    'prime': '′',
    'Prime': '″',
    'dArr': '⇓',
    'uArr': '⇑',
    'rArr': '⇒',
    'lArr': '⇐',
    'hArr': '⇔',
    'infin': '∞',
    'ne': '≠',
    'le': '≤',
    'ge': '≥',
    'alpha': 'α',
    'beta': 'β',
    'gamma': 'γ',
    'delta': 'δ',
    'pi': 'π',
    'sigma': 'σ',
    'omega': 'ω',
  };

  String decodeHtmlEntities(String source) {
    if (!source.contains('&')) return source;
    final buffer = StringBuffer();
    var cursor = 0;
    for (final match in RegExp(
      r'&(?:#x[0-9a-fA-F]+|#\d+|[a-zA-Z][a-zA-Z0-9]+);',
    ).allMatches(source)) {
      if (match.start > cursor) {
        buffer.write(source.substring(cursor, match.start));
      }
      buffer.write(_decodeEntity(match.group(0)!));
      cursor = match.end;
    }
    if (cursor < source.length) buffer.write(source.substring(cursor));
    return buffer.toString();
  }

  String _decodeEntity(String entity) {
    if (entity.length < 3 || !entity.endsWith(';')) return entity;
    final body = entity.substring(1, entity.length - 1);
    if (body.startsWith('#')) {
      final isHex = body.length > 2 && (body[1] == 'x' || body[1] == 'X');
      final digits = isHex
          ? (body.length > 2 ? body.substring(2) : '')
          : (body.length > 1 ? body.substring(1) : '');
      final code = int.tryParse(digits, radix: isHex ? 16 : 10);
      if (code == null || code <= 0 || code > 0x10FFFF) return entity;
      return String.fromCharCodes([code]);
    }
    return _htmlEntities[body] ?? _htmlEntities[body.toLowerCase()] ?? entity;
  }

  String decodePlainText(Uint8List bytes) {
    if (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe) {
      return _decodeUtf16(bytes.sublist(2), Endian.little);
    }
    if (bytes.length >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff) {
      return _decodeUtf16(bytes.sublist(2), Endian.big);
    }
    final content =
        bytes.length >= 3 &&
            bytes[0] == 0xef &&
            bytes[1] == 0xbb &&
            bytes[2] == 0xbf
        ? bytes.sublist(3)
        : bytes;
    return utf8.decode(content, allowMalformed: false);
  }

  String _decodeUtf16(List<int> bytes, Endian endian) {
    final units = <int>[];
    final data = ByteData.sublistView(
      bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
    );
    for (var index = 0; index + 1 < bytes.length; index += 2) {
      units.add(data.getUint16(index, endian));
    }
    return String.fromCharCodes(units);
  }

  List<String> splitParagraphs(String text) {
    final paragraphPattern = RegExp(r'\n\s*\n');
    final whitespacePattern = RegExp(r'\s+');
    return text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split(paragraphPattern)
        .map(
          (paragraph) => normalizeReaderMarkup(
            paragraph.replaceAll(whitespacePattern, ' ').trim(),
          ),
        )
        .where((paragraph) => paragraph.isNotEmpty)
        .toList();
  }

  String normalizeReaderMarkup(String paragraph) {
    final looksMarkdown = RegExp(
      r'^(?:#{1,6}\s+|>\s*|[-*+]\s+|\d+[.)]\s+)|!?(?:\[[^\]]+\]\([^)]*\))|(?:\*{1,3}|_{1,3}|`)',
    ).hasMatch(paragraph);
    if (looksMarkdown) {
      final parsed = markdown.markdownToHtml(paragraph);
      if (parsed.isNotEmpty) {
        final semanticText = htmlToText(
          parsed,
        ).replaceAll(RegExp(r'\s+'), ' ').trim();
        return semanticText.replaceAllMapped(
          RegExp(r'(\[\[vellum-(?:quote|list|heading:[1-6])\]\])\s+'),
          (match) => match.group(1)!,
        );
      }
    }
    var value = paragraph;
    final heading = RegExp(r'^(#{1,6})\s+').firstMatch(value);
    if (heading != null) {
      value =
          '[[vellum-heading:${heading.group(1)!.length}]]'
          '${value.substring(heading.end)}';
    } else if (value.startsWith('>')) {
      value = '[[vellum-quote]]${value.substring(1).trimLeft()}';
    } else if (RegExp(r'^(?:[-*+]\s+|\d+[.)]\s+)').hasMatch(value)) {
      value =
          '[[vellum-list]]${value.replaceFirst(RegExp(r'^(?:[-*+]\s+|\d+[.)]\s+)'), '')}';
    }
    value = value
        .replaceAll(RegExp(r'^(?:\[\[vellum-quote\]\])+'), '[[vellum-quote]]')
        .replaceAll(RegExp(r'^(?:\[\[vellum-list\]\])+'), '[[vellum-list]]');
    value = value.replaceAllMapped(
      RegExp(r'!?\[([^\]]*)\]\([^)]*\)'),
      (match) => match.group(1) ?? '',
    );
    value = value
        .replaceAllMapped(
          RegExp(r'(?<!\*)\*\*\*([^*]+)\*\*\*'),
          (match) => '[[b]][[i]]${match.group(1)!}[[/i]][[/b]]',
        )
        .replaceAllMapped(
          RegExp(r'(?<!\*)\*\*([^*]+)\*\*'),
          (match) => '[[b]]${match.group(1)!}[[/b]]',
        )
        .replaceAllMapped(
          RegExp(r'(?<!\*)\*([^*]+)\*'),
          (match) => '[[i]]${match.group(1)!}[[/i]]',
        )
        .replaceAllMapped(
          RegExp(r'(?<!_)___([^_]+)___'),
          (match) => '[[b]][[i]]${match.group(1)!}[[/i]][[/b]]',
        )
        .replaceAllMapped(
          RegExp(r'(?<!_)__([^_]+)__'),
          (match) => '[[b]]${match.group(1)!}[[/b]]',
        )
        .replaceAllMapped(
          RegExp(r'(?<!_)_([^_]+)_'),
          (match) => '[[i]]${match.group(1)!}[[/i]]',
        )
        .replaceAllMapped(
          RegExp(r'`([^`]+)`'),
          (match) => match.group(1) ?? '',
        );
    return value.trim();
  }

  String titleFromFilename(String filename) {
    final separator = filename.lastIndexOf('.');
    return separator > 0 ? filename.substring(0, separator) : filename;
  }
}
