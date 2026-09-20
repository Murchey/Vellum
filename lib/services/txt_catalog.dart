import 'dart:convert';
import 'dart:typed_data';

import 'package:charset/charset.dart' show gbk;

import 'html_text_pipeline.dart';

/// One chapter in a TXT book, addressed by **byte offset** in the source file.
///
/// Mirrors Fanqie's `com.ttreader.txtparser.Chapter`
/// (`chapterIdx / startOffset / contentLength / title`): the reader seeks to
/// [startOffset] and reads [byteLength] bytes instead of decoding the whole
/// file.
class TxtChapterRef {
  const TxtChapterRef({
    required this.index,
    required this.title,
    required this.startOffset,
    required this.byteLength,
    required this.paragraphCount,
    this.charCount = 0,
  });

  final int index;
  final String title;

  /// Byte offset of chapter *content* (the title line itself is excluded).
  final int startOffset;
  final int byteLength;

  /// Paragraphs inside this chapter (exact, measured at scan time).
  final int paragraphCount;

  /// Decoded character count (used for remaining-time / progress without
  /// touching every paragraph at open).
  final int charCount;

  bool get isEmptyContent => byteLength <= 0 || paragraphCount == 0;

  Map<String, dynamic> toJson() => {
    'index': index,
    'title': title,
    'startOffset': startOffset,
    'byteLength': byteLength,
    'paragraphCount': paragraphCount,
    'charCount': charCount,
  };

  factory TxtChapterRef.fromJson(Map<String, dynamic> json) => TxtChapterRef(
    index: (json['index'] as num).toInt(),
    title: json['title'] as String? ?? '',
    startOffset: (json['startOffset'] as num).toInt(),
    byteLength: (json['byteLength'] as num).toInt(),
    paragraphCount: (json['paragraphCount'] as num).toInt(),
    charCount: (json['charCount'] as num?)?.toInt() ?? 0,
  );

  TxtChapterRef copyWith({
    int? index,
    String? title,
    int? startOffset,
    int? byteLength,
    int? paragraphCount,
    int? charCount,
  }) => TxtChapterRef(
    index: index ?? this.index,
    title: title ?? this.title,
    startOffset: startOffset ?? this.startOffset,
    byteLength: byteLength ?? this.byteLength,
    paragraphCount: paragraphCount ?? this.paragraphCount,
    charCount: charCount ?? this.charCount,
  );
}

/// Catalog state, paralleling Fanqie's `analyse()` return codes:
/// `0` → ready, `2` → TOC still being filled (synthetic / pending).
enum TxtCatalogStatus { ready, synthetic, pending }

/// Byte-offset catalog for a TXT book.
class TxtCatalog {
  const TxtCatalog({
    required this.encoding,
    required this.chapters,
    required this.status,
  });

  /// Charset name used to decode the file: `utf-8` / `gbk` / `utf-16le` / `utf-16be`.
  final String encoding;
  final List<TxtChapterRef> chapters;
  final TxtCatalogStatus status;

  int get totalParagraphs {
    var sum = 0;
    for (final chapter in chapters) {
      sum += chapter.paragraphCount;
    }
    return sum;
  }

  int get totalCharCount {
    var sum = 0;
    for (final chapter in chapters) {
      sum += chapter.charCount;
    }
    return sum;
  }

  bool get isSynthetic => status == TxtCatalogStatus.synthetic;

  /// Global paragraph index at which [chapterIndex] begins.
  int paragraphStartOf(int chapterIndex) {
    var sum = 0;
    for (var i = 0; i < chapterIndex && i < chapters.length; i++) {
      sum += chapters[i].paragraphCount;
    }
    return sum;
  }

  /// Chapter that contains the given global paragraph index.
  TxtChapterRef chapterForParagraph(int paragraphIndex) {
    var sum = 0;
    for (final chapter in chapters) {
      final end = sum + chapter.paragraphCount;
      if (paragraphIndex < end) return chapter;
      sum = end;
    }
    return chapters.isEmpty
        ? const TxtChapterRef(
            index: 0,
            title: '',
            startOffset: 0,
            byteLength: 0,
            paragraphCount: 0,
          )
        : chapters.last;
  }

  List<MapEntry<int, String>> get tocEntries => [
    for (final chapter in chapters)
      if (chapter.title.isNotEmpty)
        MapEntry(paragraphStartOf(chapter.index), chapter.title),
  ];

  Map<String, dynamic> toJson() => {
    'encoding': encoding,
    'status': status.name,
    'chapters': [for (final chapter in chapters) chapter.toJson()],
  };

  factory TxtCatalog.fromJson(Map<String, dynamic> json) => TxtCatalog(
    encoding: json['encoding'] as String? ?? 'utf-8',
    status: TxtCatalogStatus.values.firstWhere(
      (value) => value.name == json['status'],
      orElse: () => TxtCatalogStatus.ready,
    ),
    chapters: [
      for (final entry in json['chapters'] as List<dynamic>? ?? const [])
        TxtChapterRef.fromJson(entry as Map<String, dynamic>),
    ],
  );
}

/// Scans raw TXT bytes into a [TxtCatalog].
///
/// Algorithm (Fanqie `TxtParser.analyse` + `TTTxtCatalogHelper`):
/// 1. Detect encoding (BOM → UTF-8 probe → GBK).
/// 2. Walk the file line by line, recording byte offsets of chapter titles.
/// 3. Post-process: name a content-only opening「前言」, merge empty chapters.
/// 4. Measure each chapter's paragraph count (decode that range only).
/// 5. If no title was recognised, synthesise `第N章` every
///    [syntheticChapterBytes] bytes (Fanqie uses 5000).
TxtCatalog scanTxtCatalog(
  Uint8List bytes, {
  HtmlTextPipeline pipeline = const HtmlTextPipeline(),
  int syntheticChapterBytes = 5000,
  int maxTitleLength = 40,
}) {
  if (bytes.isEmpty) {
    return const TxtCatalog(
      encoding: 'utf-8',
      chapters: [],
      status: TxtCatalogStatus.synthetic,
    );
  }
  final encoding = detectTxtEncoding(bytes);
  final codec = _codecFor(encoding);

  // --- 2. Line scan: find chapter title byte offsets ---
  final titleAt = <({String title, int contentStart})>[];
  var pos = 0;
  while (pos < bytes.length) {
    var nl = bytes.indexOf(0x0A, pos);
    if (nl < 0) nl = bytes.length;
    final lineBytes = nl > pos
        ? Uint8List.sublistView(bytes, pos, nl)
        : Uint8List(0);
    final line = _decodeLine(lineBytes, encoding, codec);
    if (line != null && _isChapterTitle(line, pipeline, maxTitleLength)) {
      titleAt.add((
        title: pipeline.chapterTitle(line),
        contentStart: nl < bytes.length ? nl + 1 : nl,
      ));
    }
    pos = nl < bytes.length ? nl + 1 : bytes.length;
  }

  // --- 3. Build raw chapter ranges ---
  var raw = <({String title, int start, int end})>[];
  if (titleAt.isEmpty) {
    raw = _syntheticRanges(bytes.length, syntheticChapterBytes);
  } else {
    // Content sitting before the first title line: Fanqie names it「前言」.
    final firstTitleLineStart = _lineStartBefore(
      bytes,
      titleAt.first.contentStart,
    );
    if (firstTitleLineStart > 0 &&
        _hasVisibleContent(bytes, 0, firstTitleLineStart)) {
      raw.add((title: '前言', start: 0, end: firstTitleLineStart));
    }
    for (var i = 0; i < titleAt.length; i++) {
      final start = titleAt[i].contentStart;
      final end = i + 1 < titleAt.length
          ? _lineStartBefore(bytes, titleAt[i + 1].contentStart)
          : bytes.length;
      raw.add((
        title: titleAt[i].title,
        start: start,
        end: end > start ? end : start,
      ));
    }
  }

  // --- 4. Measure paragraphs + merge empty chapters (Fanqie t()) ---
  final measured = <TxtChapterRef>[];
  for (var i = 0; i < raw.length; i++) {
    final range = raw[i];
    final length = range.end - range.start;
    final text = length > 0
        ? _sanitize(
            pipeline.decodePlainText(
              Uint8List.sublistView(bytes, range.start, range.end),
            ),
          )
        : '';
    final paragraphs = text.isEmpty
        ? const <String>[]
        : pipeline.splitParagraphs(text);
    measured.add(
      TxtChapterRef(
        index: i,
        title: range.title,
        startOffset: range.start,
        byteLength: length,
        paragraphCount: paragraphs.length,
        charCount: text.length,
      ),
    );
  }

  final merged = _mergeEmptyChapters(measured);
  final reindexed = [
    for (var i = 0; i < merged.length; i++) merged[i].copyWith(index: i),
  ];

  // Empty/untitled first chapter →「前言」(Fanqie naming rule).
  final named = <TxtChapterRef>[];
  for (var i = 0; i < reindexed.length; i++) {
    var chapter = reindexed[i];
    if (i == 0 && chapter.title.isEmpty) {
      chapter = chapter.copyWith(title: '前言');
    }
    named.add(chapter);
  }

  final status = titleAt.isEmpty
      ? TxtCatalogStatus.synthetic
      : TxtCatalogStatus.ready;
  return TxtCatalog(encoding: encoding, chapters: named, status: status);
}

/// Fanqie-compatible encoding detection (`pt5/h.java` + ICU in libTxtParser).
String detectTxtEncoding(Uint8List bytes) {
  if (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe) {
    return 'utf-16le';
  }
  if (bytes.length >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff) {
    return 'utf-16be';
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xef &&
      bytes[1] == 0xbb &&
      bytes[2] == 0xbf) {
    return 'utf-8';
  }
  final content = bytes.length >= 3 &&
          bytes[0] == 0xef &&
          bytes[1] == 0xbb &&
          bytes[2] == 0xbf
      ? bytes.sublist(3)
      : bytes;
  return _looksLikeUtf8(content) ? 'utf-8' : 'gbk';
}

/// Decodes a full buffer with a catalog-recorded encoding.
String decodeTxtWithEncoding(Uint8List bytes, String encoding) {
  switch (encoding) {
    case 'utf-16le':
    case 'utf-16be':
      final endian = encoding == 'utf-16le' ? Endian.little : Endian.big;
      final body = bytes.length >= 2 ? bytes.sublist(2) : bytes;
      final units = <int>[];
      final data = ByteData.sublistView(body);
      for (var i = 0; i + 1 < body.length; i += 2) {
        units.add(data.getUint16(i, endian));
      }
      return _sanitize(String.fromCharCodes(units));
    case 'gbk':
      return _sanitize(gbk.decode(bytes, allowMalformed: true));
    case 'utf-8':
    default:
      return _sanitize(utf8.decode(bytes, allowMalformed: true));
  }
}

String _sanitize(String text) => text
    .replaceAll('﻿', '')
    .replaceAll('　', ' ');

Object _codecFor(String encoding) => encoding;

String? _decodeLine(Uint8List lineBytes, String encoding, Object _) {
  if (lineBytes.isEmpty) return '';
  try {
    return decodeTxtWithEncoding(lineBytes, encoding).trim();
  } catch (_) {
    return null;
  }
}

bool _isChapterTitle(
  String line,
  HtmlTextPipeline pipeline,
  int maxTitleLength,
) {
  if (line.isEmpty || line.length > maxTitleLength) return false;
  final value = pipeline.chapterTitle(line);
  if (value.isEmpty || value.length > maxTitleLength) return false;
  if (value.contains('。') ||
      value.contains('，') ||
      value.contains(',') ||
      value.contains('！') ||
      value.contains('？')) {
    return false;
  }
  return HtmlTextPipeline.chapterPattern.hasMatch(value);
}

List<({String title, int start, int end})> _syntheticRanges(
  int totalBytes,
  int stride,
) {
  final ranges = <({String title, int start, int end})>[];
  if (totalBytes <= 0) return ranges;
  final step = stride < 1 ? 1 : stride;
  var offset = 0;
  var number = 1;
  while (offset < totalBytes) {
    var end = offset + step;
    if (end > totalBytes) end = totalBytes;
    ranges.add((title: '第$number章', start: offset, end: end));
    offset = end;
    number++;
  }
  return ranges;
}

/// Merges chapters that carry a title but no readable content into the next
/// one (Fanqie `t()`). The empty chapter's title is dropped; its byte range is
/// absorbed so nothing is skipped when seeking. Trailing empty chapters are
/// dropped.
List<TxtChapterRef> _mergeEmptyChapters(List<TxtChapterRef> chapters) {
  if (chapters.length <= 1) return chapters;
  final result = <TxtChapterRef>[];
  var i = 0;
  while (i < chapters.length) {
    if (!chapters[i].isEmptyContent) {
      result.add(chapters[i]);
      i++;
      continue;
    }
    // Collect a run of empty chapters and fold them into the next non-empty.
    var j = i + 1;
    while (j < chapters.length && chapters[j].isEmptyContent) {
      j++;
    }
    if (j >= chapters.length) break; // trailing empties → drop
    final target = chapters[j];
    final start = chapters[i].startOffset;
    final end = target.startOffset + target.byteLength;
    result.add(
      target.copyWith(startOffset: start, byteLength: end > start ? end - start : 0),
    );
    i = j + 1;
  }
  return result.isEmpty ? chapters : result;
}

bool _hasVisibleContent(Uint8List bytes, int start, int end) {
  if (end <= start) return false;
  for (var i = start; i < end && i < bytes.length; i++) {
    final b = bytes[i];
    // Whitespace only: space, tab, CR, LF.
    if (b == 0x20 || b == 0x09 || b == 0x0D || b == 0x0A) continue;
    return true;
  }
  return false;
}

int _lineStartBefore(Uint8List bytes, int contentStart) {
  // Walk back to just after the previous newline (or 0).
  var i = contentStart - 1;
  while (i > 0 && bytes[i - 1] != 0x0A) {
    i--;
  }
  return i < 0 ? 0 : i;
}

bool _looksLikeUtf8(List<int> bytes) {
  const limitProbe = 64 * 1024;
  final limit = bytes.length < limitProbe ? bytes.length : limitProbe;
  var index = 0;
  while (index < limit) {
    final byte = bytes[index];
    if (byte <= 0x7f) {
      index++;
      continue;
    }
    if (byte >= 0xf5) return false;
    var continuation = 0;
    if (byte >= 0xe0 && byte <= 0xef) {
      continuation = 2;
    } else if (byte >= 0xc0 && byte <= 0xdf) {
      continuation = 1;
    } else {
      return false;
    }
    if (index + continuation >= limit) return true;
    for (var step = 1; step <= continuation; step++) {
      final next = bytes[index + step];
      if (next < 0x80 || next > 0xbf) return false;
    }
    index += continuation + 1;
  }
  return true;
}
