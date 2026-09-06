import 'package:archive/archive.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:markdown/markdown.dart' as markdown;

import 'dart:convert';
import 'dart:typed_data';

enum BookFormat { epub, mobi, txt }

class BookTocEntry {
  const BookTocEntry({required this.title, required this.paragraphIndex});

  final String title;
  final int paragraphIndex;
}

class ImportedBook {
  const ImportedBook({
    required this.title,
    required this.format,
    required this.paragraphs,
    this.coverBytes,
    this.linkTargets = const {},
    this.tocEntries = const [],
    this.imageBytes = const {},
  });

  final String title;
  final BookFormat format;
  final List<String> paragraphs;
  final Uint8List? coverBytes;
  final Map<int, int> linkTargets;
  final List<BookTocEntry> tocEntries;
  final Map<int, Uint8List> imageBytes;
}

class _HtmlContent {
  const _HtmlContent({
    required this.paragraphs,
    required this.anchors,
    required this.links,
    required this.images,
  });

  final List<String> paragraphs;
  final Map<String, int> anchors;
  final Map<int, String> links;
  final Map<int, int> images;
}

class BookImportException implements Exception {
  const BookImportException(this.message);
  final String message;

  @override
  String toString() => message;
}

class BookImporter {
  const BookImporter();

  BookFormat formatForFilename(String filename) {
    final normalized = filename.toLowerCase();
    if (normalized.endsWith('.epub')) return BookFormat.epub;
    if (normalized.endsWith('.mobi')) return BookFormat.mobi;
    if (normalized.endsWith('.txt')) return BookFormat.txt;
    throw const BookImportException('仅支持 EPUB、MOBI 与 TXT 文件。');
  }

  ImportedBook decode({required String filename, required Uint8List bytes}) {
    final format = formatForFilename(filename);
    switch (format) {
      case BookFormat.txt:
        return _decodeTxt(filename, bytes);
      case BookFormat.epub:
        return _decodeEpub(filename, bytes);
      case BookFormat.mobi:
        return _decodeMobi(filename, bytes);
    }
  }

  ImportedBook _decodeMobi(String filename, Uint8List bytes) {
    try {
      if (bytes.length < 100) throw const BookImportException('MOBI 文件不完整。');
      final data = ByteData.sublistView(bytes);
      final records = data.getUint16(76, Endian.big);
      if (records < 2 || bytes.length < 78 + records * 8) {
        throw const BookImportException('MOBI 记录表无效。');
      }
      final offsets = List<int>.generate(
        records,
        (index) => data.getUint32(78 + index * 8, Endian.big),
      );
      final header = offsets.first;
      if (header + 20 > bytes.length ||
          ascii.decode(bytes.sublist(header + 16, header + 20)) != 'MOBI') {
        throw const BookImportException('不是受支持的经典 MOBI 文件。');
      }
      final compression = data.getUint16(header, Endian.big);
      final textLength = data.getUint32(header + 4, Endian.big);
      final textRecords = data.getUint16(header + 8, Endian.big);
      final textEncoding = data.getUint32(header + 28, Endian.big);
      final encryption = data.getUint16(header + 12, Endian.big);
      if (encryption != 0) throw const BookImportException('加密/DRM MOBI 暂不支持。');
      if (textRecords == 0 || textRecords >= records)
        throw const BookImportException('MOBI 中没有正文记录。');
      final chunks = <int>[];
      for (var index = 1; index <= textRecords; index++) {
        final remaining = textLength == 0 ? null : textLength - chunks.length;
        if (remaining != null && remaining <= 0) break;
        final recordLimit = remaining == null || remaining > 4096
            ? 4096
            : remaining;
        final start = offsets[index];
        final end = index + 1 < records ? offsets[index + 1] : bytes.length;
        if (start >= end || end > bytes.length)
          throw const BookImportException('MOBI 正文记录无效。');
        final record = bytes.sublist(start, end);
        final decoded = compression == 2
            ? _palmDoc(record, maxOutput: recordLimit)
            : record;
        chunks.addAll(
          decoded.length <= recordLimit
              ? decoded
              : decoded.sublist(0, recordLimit),
        );
      }
      final decodedText = _decodeMobiText(chunks, textEncoding);
      final content = _htmlContent(decodedText, 'mobi.html');
      final paragraphs = content.paragraphs;
      final tocEntries = _mobiTocEntries(decodedText, paragraphs, textEncoding);
      final linkTargets = <int, int>{
        for (final entry in content.links.entries)
          if (content.anchors[entry.value] != null)
            entry.key: content.anchors[entry.value]!,
      };
      final firstImageRecord = _firstImageRecord(bytes, offsets, textRecords);
      final imageBytes = <int, Uint8List>{};
      if (firstImageRecord != null) {
        for (final entry in content.images.entries) {
          final image = _mobiImage(
            bytes,
            offsets,
            firstImageRecord,
            entry.value,
          );
          if (image != null) imageBytes[entry.key] = image;
        }
      }
      if (paragraphs.isEmpty)
        throw const BookImportException('MOBI 中没有可阅读的正文。');
      final coverBytes = _mobiCover(bytes, data, offsets, header);
      return ImportedBook(
        title: _titleFromFilename(filename),
        format: BookFormat.mobi,
        paragraphs: paragraphs,
        coverBytes: coverBytes,
        linkTargets: linkTargets,
        tocEntries: tocEntries,
        imageBytes: imageBytes,
      );
    } on BookImportException {
      rethrow;
    } catch (_) {
      throw const BookImportException('无法读取此 MOBI 文件。');
    }
  }

  int? _firstImageRecord(Uint8List bytes, List<int> offsets, int textRecords) {
    for (var record = textRecords + 1; record < offsets.length; record++) {
      final start = offsets[record];
      final end = record + 1 < offsets.length
          ? offsets[record + 1]
          : bytes.length;
      if (start >= end || end > bytes.length) continue;
      final data = bytes.sublist(start, end);
      if ((data.length > 3 && data[0] == 0xff && data[1] == 0xd8) ||
          (data.length > 8 && data[0] == 0x89 && data[1] == 0x50) ||
          (data.length > 6 && data[0] == 0x47 && data[1] == 0x49)) {
        return record;
      }
    }
    return null;
  }

  Uint8List? _mobiImage(
    Uint8List bytes,
    List<int> offsets,
    int firstImageRecord,
    int imageIndex,
  ) {
    final record = firstImageRecord + imageIndex;
    if (record <= 0 || record >= offsets.length) return null;
    final start = offsets[record];
    final end = record + 1 < offsets.length
        ? offsets[record + 1]
        : bytes.length;
    if (start >= end || end > bytes.length) return null;
    final image = Uint8List.fromList(bytes.sublist(start, end));
    final jpeg = image.length > 3 && image[0] == 0xff && image[1] == 0xd8;
    final png = image.length > 8 && image[0] == 0x89 && image[1] == 0x50;
    final gif = image.length > 6 && image[0] == 0x47 && image[1] == 0x49;
    return jpeg || png || gif ? image : null;
  }

  Uint8List? _mobiCover(
    Uint8List bytes,
    ByteData data,
    List<int> offsets,
    int header,
  ) {
    if (header + 112 > bytes.length) return null;
    final record = data.getUint32(header + 108, Endian.big);
    if (record == 0 || record >= offsets.length) return null;
    final start = offsets[record];
    final end = record + 1 < offsets.length
        ? offsets[record + 1]
        : bytes.length;
    if (start >= end || end > bytes.length) return null;
    final image = Uint8List.fromList(bytes.sublist(start, end));
    final isJpeg = image.length > 3 && image[0] == 0xff && image[1] == 0xd8;
    final isPng = image.length > 8 && image[0] == 0x89 && image[1] == 0x50;
    return isJpeg || isPng ? image : null;
  }

  String _decodeMobiText(List<int> bytes, int encoding) => encoding == 65001
      ? utf8.decode(bytes, allowMalformed: true)
      : latin1.decode(bytes, allowInvalid: true);

  List<int> _palmDoc(List<int> input, {int? maxOutput}) {
    final output = <int>[];
    for (
      var index = 0;
      index < input.length && (maxOutput == null || output.length < maxOutput);
      index++
    ) {
      final value = input[index];
      if (value == 0) {
        output.add(value);
      } else if (value <= 8) {
        if (index + value >= input.length) {
          throw const BookImportException('MOBI PalmDOC 压缩数据无效。');
        }
        output.addAll(input.sublist(++index, index + value));
        index += value - 1;
      } else if (value <= 0x7f) {
        output.add(value);
      } else if (value <= 0xbf) {
        if (++index >= input.length)
          throw const BookImportException('MOBI PalmDOC 引用无效。');
        final pair = (value << 8) | input[index];
        final length = (pair & 0x7) + 3;
        final distance = ((value & 0x3f) << 5) | (input[index] >> 3);
        if (distance == 0 || distance > output.length)
          throw const BookImportException('MOBI PalmDOC 回溯无效。');
        for (var repeat = 0; repeat < length; repeat++)
          output.add(output[output.length - distance]);
      } else {
        output
          ..add(0x20)
          ..add(value ^ 0x80);
      }
    }
    return output;
  }

  ImportedBook _decodeTxt(String filename, Uint8List bytes) {
    final paragraphs = _paragraphs(_decodeText(bytes));
    if (paragraphs.isEmpty) {
      throw const BookImportException('文件中没有可阅读的文字。');
    }
    return ImportedBook(
      title: _titleFromFilename(filename),
      format: BookFormat.txt,
      paragraphs: paragraphs,
    );
  }

  ImportedBook _decodeEpub(String filename, Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes, verify: true);
      final container = _fileText(archive, 'META-INF/container.xml');
      final packagePath = _attribute(container, 'rootfile', 'full-path');
      if (packagePath == null) {
        throw const BookImportException('EPUB 缺少 OPF 书籍目录。');
      }
      final opf = _fileText(archive, packagePath);
      final title =
          _elementText(opf, 'dc:title') ?? _titleFromFilename(filename);
      final manifest = <String, String>{};
      for (final match in RegExp(
        r'<item\b[^>]*>',
        caseSensitive: false,
      ).allMatches(opf)) {
        final item = match.group(0)!;
        final id = _attributeInTag(item, 'id');
        final href = _attributeInTag(item, 'href');
        if (id != null && href != null) manifest[id] = href;
      }
      final base = packagePath.substring(0, packagePath.lastIndexOf('/') + 1);
      final contents = <_HtmlContent>[];
      for (final match in RegExp(
        r'<itemref\b[^>]*>',
        caseSensitive: false,
      ).allMatches(opf)) {
        final id = _attributeInTag(match.group(0)!, 'idref');
        final href = id == null ? null : manifest[id];
        if (href != null) {
          final documentPath = '$base$href';
          contents.add(
            _htmlContent(_fileText(archive, documentPath), documentPath),
          );
        }
      }
      final paragraphs = <String>[];
      final anchors = <String, int>{};
      final unresolvedLinks = <int, String>{};
      for (final content in contents) {
        final offset = paragraphs.length;
        paragraphs.addAll(content.paragraphs);
        for (final entry in content.anchors.entries) {
          anchors[entry.key] = offset + entry.value;
        }
        for (final entry in content.links.entries) {
          unresolvedLinks[offset + entry.key] = entry.value;
        }
      }
      final linkTargets = <int, int>{
        for (final entry in unresolvedLinks.entries)
          if (anchors[entry.value] != null) entry.key: anchors[entry.value]!,
      };
      if (paragraphs.isEmpty) {
        throw const BookImportException('EPUB 中没有可阅读的正文。');
      }
      return ImportedBook(
        title: title,
        format: BookFormat.epub,
        paragraphs: paragraphs,
        linkTargets: linkTargets,
      );
    } on BookImportException {
      rethrow;
    } catch (_) {
      throw const BookImportException('无法读取此 EPUB 文件。');
    }
  }

  String _fileText(Archive archive, String name) {
    final file = archive.findFile(name);
    if (file == null || !file.isFile) {
      throw BookImportException('EPUB 缺少文件：$name');
    }
    return utf8.decode(file.readBytes()!, allowMalformed: false);
  }

  String? _attribute(String source, String tag, String attribute) {
    final match = RegExp(
      '<$tag\\b[^>]*>',
      caseSensitive: false,
    ).firstMatch(source);
    return match == null ? null : _attributeInTag(match.group(0)!, attribute);
  }

  String? _attributeInTag(String tag, String attribute) => RegExp(
    '$attribute\\s*=\\s*["\\\']([^"\\\']+)["\\\']',
    caseSensitive: false,
  ).firstMatch(tag)?.group(1);

  String? _elementText(String source, String tag) => RegExp(
    '<$tag\\b[^>]*>([\\s\\S]*?)</$tag>',
    caseSensitive: false,
  ).firstMatch(source)?.group(1)?.trim();

  List<BookTocEntry> _mobiTocEntries(
    String source,
    List<String> paragraphs,
    int encoding,
  ) {
    final pattern = RegExp(
      r'''<a\b[^>]*\bfilepos\s*=\s*["']?(\d+)["']?[^>]*>([\s\S]*?)</a\s*>''',
      caseSensitive: false,
    );
    final matches = pattern.allMatches(source).toList();
    if (matches.isEmpty || paragraphs.isEmpty) return const [];

    // Some MOBIs contain hundreds of filepos entries. The old implementation
    // re-encoded and re-cleaned the entire book once per entry, which becomes
    // O(entry count × book length) and makes a large import look frozen.
    // Place durable text markers at all file positions, then strip HTML and
    // split paragraphs exactly once.
    final filePositions = [
      for (final match in matches) int.parse(match.group(1)!),
    ];
    final offsets = encoding == 65001
        ? _utf8OffsetsToStringOffsets(source, filePositions)
        : [
            for (final position in filePositions)
              position.clamp(0, source.length),
          ];
    var marked = source;
    for (var index = offsets.length - 1; index >= 0; index--) {
      var offset = offsets[index].clamp(0, marked.length);
      final lastOpen = marked.lastIndexOf('<', offset);
      final lastClose = marked.lastIndexOf('>', offset);
      if (lastOpen > lastClose) {
        final closing = marked.indexOf('>', offset);
        offset = closing < 0 ? marked.length : closing + 1;
      }
      marked = marked.replaceRange(offset, offset, '[[vellum-filepos:$index]]');
    }

    final positions = <int, int>{};
    final markerPattern = RegExp(r'\[\[vellum-filepos:(\d+)\]\]');
    final markedParagraphs = _paragraphs(_htmlToText(marked));
    for (var index = 0; index < markedParagraphs.length; index++) {
      for (final marker in markerPattern.allMatches(markedParagraphs[index])) {
        positions[int.parse(marker.group(1)!)] = index;
      }
    }

    return [
      for (var index = 0; index < matches.length; index++)
        BookTocEntry(
          title: _htmlToText(matches[index].group(2)!).trim(),
          paragraphIndex: (positions[index] ?? 0).clamp(
            0,
            paragraphs.length - 1,
          ),
        ),
    ].where((entry) => entry.title.isNotEmpty).toList();
  }

  List<int> _utf8OffsetsToStringOffsets(String source, List<int> targets) {
    final ordered = <({int target, int original})>[
      for (var index = 0; index < targets.length; index++)
        (target: targets[index].clamp(0, 1 << 62), original: index),
    ]..sort((a, b) => a.target.compareTo(b.target));
    final result = List<int>.filled(targets.length, source.length);
    var targetIndex = 0;
    var byteOffset = 0;
    var stringOffset = 0;
    for (final rune in source.runes) {
      while (targetIndex < ordered.length &&
          ordered[targetIndex].target <= byteOffset) {
        result[ordered[targetIndex].original] = stringOffset;
        targetIndex++;
      }
      byteOffset += rune <= 0x7f
          ? 1
          : rune <= 0x7ff
          ? 2
          : rune <= 0xffff
          ? 3
          : 4;
      stringOffset += rune > 0xffff ? 2 : 1;
    }
    while (targetIndex < ordered.length) {
      result[ordered[targetIndex].original] = source.length;
      targetIndex++;
    }
    return result;
  }

  _HtmlContent _htmlContent(String source, String documentPath) {
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
              '[[link:${_resolveLink(documentPath, match.group(1)!)}]]${match.group(0)}',
        )
        .replaceAll(RegExp(r'</a\s*>', caseSensitive: false), '[[/link]]');
    final raw = _htmlToText(marked);
    final paragraphs = _paragraphs(raw);
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
    return _HtmlContent(
      paragraphs: cleaned,
      anchors: remapAnchors,
      links: remapLinks,
      images: remapImages,
    );
  }

  String _resolveLink(String documentPath, String href) {
    if (href.startsWith('#')) return '$documentPath$href';
    final hash = href.indexOf('#');
    if (hash < 0) return href;
    final directory = documentPath.substring(
      0,
      documentPath.lastIndexOf('/') + 1,
    );
    return '$directory$href';
  }

  String _htmlToText(String source) {
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
      if (tag == 'img') {
        final recindex = node.attributes['recindex'];
        if (recindex != null && recindex.isNotEmpty) {
          output.write('[[image:$recindex]]');
        }
        return;
      }
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
          listItem;
      if (needsBreak) {
        paragraphBreak();
      }
      if (heading) output.write('[[vellum-heading:${tag.substring(1)}]]');
      if (quote && !nestedQuote) output.write('[[vellum-quote]]');
      if (listItem) output.write('[[vellum-list]]');
      for (final child in node.nodes) {
        visit(child);
      }
      if (needsBreak) {
        paragraphBreak();
      }
    }

    for (final node in fragment.nodes) {
      visit(node);
    }
    return output.toString();
  }

  String _decodeText(Uint8List bytes) {
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

  String _decodeUtf16(Uint8List bytes, Endian endian) {
    final units = <int>[];
    final data = ByteData.sublistView(bytes);
    for (var index = 0; index + 1 < bytes.length; index += 2) {
      units.add(data.getUint16(index, endian));
    }
    return String.fromCharCodes(units);
  }

  List<String> _paragraphs(String text) {
    final paragraphPattern = RegExp(r'\n\s*\n');
    final whitespacePattern = RegExp(r'\s+');
    return text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split(paragraphPattern)
        .map(
          (paragraph) => _normalizeReaderMarkup(
            paragraph.replaceAll(whitespacePattern, ' ').trim(),
          ),
        )
        .where((paragraph) => paragraph.isNotEmpty)
        .toList();
  }

  String _normalizeReaderMarkup(String paragraph) {
    final looksMarkdown = RegExp(
      r'^(?:#{1,6}\s+|>\s*|[-*+]\s+|\d+[.)]\s+)|!?(?:\[[^\]]+\]\([^)]*\))|(?:\*{1,3}|_{1,3}|`)',
    ).hasMatch(paragraph);
    if (looksMarkdown) {
      final parsed = markdown.markdownToHtml(paragraph);
      if (parsed.isNotEmpty) {
        final semanticText = _htmlToText(
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
          RegExp(r'(?<!\*)\*{1,3}([^*]+)\*{1,3}'),
          (match) => match.group(1) ?? '',
        )
        .replaceAllMapped(
          RegExp(r'(?<!_)_{1,3}([^_]+)_{1,3}'),
          (match) => match.group(1) ?? '',
        )
        .replaceAllMapped(
          RegExp(r'`([^`]+)`'),
          (match) => match.group(1) ?? '',
        );
    return value.trim();
  }

  String _titleFromFilename(String filename) {
    final separator = filename.lastIndexOf('.');
    return separator > 0 ? filename.substring(0, separator) : filename;
  }
}
