import 'dart:convert';
import 'dart:typed_data';

import 'book_models.dart';
import 'html_text_pipeline.dart';

class MobiDecoder {
  const MobiDecoder({this.pipeline = const HtmlTextPipeline()});

  final HtmlTextPipeline pipeline;

  ImportedBook decode(String filename, Uint8List bytes) {
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
      if (encryption != 0) {
        throw const BookImportException('加密/DRM MOBI 暂不支持。');
      }
      if (textRecords == 0 || textRecords >= records) {
        throw const BookImportException('MOBI 中没有正文记录。');
      }
      final chunks = <int>[];
      for (var index = 1; index <= textRecords; index++) {
        final remaining = textLength == 0 ? null : textLength - chunks.length;
        if (remaining != null && remaining <= 0) break;
        final recordLimit = remaining == null || remaining > 4096
            ? 4096
            : remaining;
        final start = offsets[index];
        final end = index + 1 < records ? offsets[index + 1] : bytes.length;
        if (start >= end || end > bytes.length) {
          throw const BookImportException('MOBI 正文记录无效。');
        }
        final record = bytes.sublist(start, end);
        final decoded = compression == 2
            ? palmDoc(record, maxOutput: recordLimit)
            : record;
        chunks.addAll(
          decoded.length <= recordLimit
              ? decoded
              : decoded.sublist(0, recordLimit),
        );
      }
      final decodedText = decodeMobiText(chunks, textEncoding);
      final content = pipeline.convert(decodedText, 'mobi.html');
      final paragraphs = content.paragraphs;
      final tocEntries = mobiTocEntries(decodedText, paragraphs, textEncoding);
      final linkTargets = <int, int>{
        for (final entry in content.links.entries)
          if (content.anchors[entry.value] != null)
            entry.key: content.anchors[entry.value]!,
      };
      final firstImage = firstImageRecord(bytes, offsets, textRecords);
      final imageBytes = <int, Uint8List>{};
      if (firstImage != null) {
        for (final entry in content.images.entries) {
          final image = mobiImage(bytes, offsets, firstImage, entry.value);
          if (image != null) imageBytes[entry.key] = image;
        }
      }
      if (paragraphs.isEmpty) {
        throw const BookImportException('MOBI 中没有可阅读的正文。');
      }
      final coverBytes = mobiCover(bytes, data, offsets, header);
      return ImportedBook(
        title: pipeline.titleFromFilename(filename),
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

  int? firstImageRecord(Uint8List bytes, List<int> offsets, int textRecords) {
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

  /// MOBI `recindex` is 1-based: 1 maps to the first image record after text.
  Uint8List? mobiImage(
    Uint8List bytes,
    List<int> offsets,
    int firstImageRecord,
    int imageIndex,
  ) {
    if (imageIndex <= 0) return null;
    final record = firstImageRecord + imageIndex - 1;
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

  Uint8List? mobiCover(
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

  String decodeMobiText(List<int> bytes, int encoding) => encoding == 65001
      ? utf8.decode(bytes, allowMalformed: true)
      : latin1.decode(bytes, allowInvalid: true);

  List<int> palmDoc(List<int> input, {int? maxOutput}) {
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
        if (++index >= input.length) {
          throw const BookImportException('MOBI PalmDOC 引用无效。');
        }
        final pair = (value << 8) | input[index];
        final length = (pair & 0x7) + 3;
        final distance = ((value & 0x3f) << 5) | (input[index] >> 3);
        if (distance == 0 || distance > output.length) {
          throw const BookImportException('MOBI PalmDOC 回溯无效。');
        }
        for (var repeat = 0; repeat < length; repeat++) {
          output.add(output[output.length - distance]);
        }
      } else {
        output
          ..add(0x20)
          ..add(value ^ 0x80);
      }
    }
    return output;
  }

  List<BookTocEntry> mobiTocEntries(
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

    final filePositions = [
      for (final match in matches) int.parse(match.group(1)!),
    ];
    final offsets = encoding == 65001
        ? utf8OffsetsToStringOffsets(source, filePositions)
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
      // Never split a character entity in half.
      final entityStart = marked.lastIndexOf('&', offset);
      final entityEnd = marked.indexOf(';', offset);
      if (entityStart >= 0 &&
          entityStart < offset &&
          entityEnd >= 0 &&
          entityEnd - entityStart < 12) {
        offset = entityEnd + 1;
      }
      marked = marked.replaceRange(offset, offset, '[[vellum-filepos:$index]]');
    }

    final positions = <int, int>{};
    final markerPattern = RegExp(r'\[\[vellum-filepos:(\d+)\]\]');
    final markedParagraphs = pipeline.splitParagraphs(
      pipeline.htmlToText(marked),
    );
    for (var index = 0; index < markedParagraphs.length; index++) {
      for (final marker in markerPattern.allMatches(markedParagraphs[index])) {
        positions[int.parse(marker.group(1)!)] = index;
      }
    }

    // Fill missing hits from the nearest previous known paragraph so a single
    // lost marker does not collapse a chapter onto paragraph 0.
    final resolved = List<int>.filled(matches.length, -1);
    var last = -1;
    for (var index = 0; index < matches.length; index++) {
      final hit = positions[index];
      if (hit != null) {
        last = hit;
        resolved[index] = hit;
      } else {
        resolved[index] = last;
      }
    }
    var next = paragraphs.length - 1;
    for (var index = matches.length - 1; index >= 0; index--) {
      if (positions[index] != null) {
        next = positions[index]!;
      } else if (resolved[index] < 0) {
        resolved[index] = next;
      }
    }

    final entries = <BookTocEntry>[];
    final seen = <int>{};
    for (var index = 0; index < matches.length; index++) {
      final title = pipeline
          .htmlToText(matches[index].group(2)!)
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (title.isEmpty) continue;
      final paragraphIndex = resolved[index].clamp(0, paragraphs.length - 1);
      if (!seen.add(paragraphIndex)) continue;
      entries.add(
        BookTocEntry(title: title, paragraphIndex: paragraphIndex),
      );
    }
    return entries;
  }

  List<int> utf8OffsetsToStringOffsets(
    String source,
    List<int> targets,
  ) {
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
}
