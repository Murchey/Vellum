import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/services/book_importer.dart';

void main() {
  const importer = BookImporter();

  test('imports UTF-8 TXT with normalized paragraphs', () {
    final book = importer.decode(
      filename: '随笔.TXT',
      bytes: Uint8List.fromList(utf8.encode('第一段\r\n\r\n第二段')),
    );

    expect(book.title, '随笔');
    expect(book.format, BookFormat.txt);
    expect(book.paragraphs, ['第一段', '第二段']);
  });

  test('imports EPUB spine text and metadata', () {
    final archive = Archive()
      ..addFile(
        ArchiveFile.string(
          'META-INF/container.xml',
          '<container><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>',
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'OPS/book.opf',
          '<package><metadata><dc:title>测试书</dc:title></metadata><manifest><item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="chapter"/></spine></package>',
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'OPS/chapter.xhtml',
          '<html><body><p><a href="#start">跳到正文</a></p><h1 id="start">第一章</h1><p>这是 EPUB 正文。</p></body></html>',
        ),
      );

    final book = importer.decode(
      filename: 'book.epub',
      bytes: Uint8List.fromList(ZipEncoder().encodeBytes(archive)),
    );

    expect(book.title, '测试书');
    expect(book.format, BookFormat.epub);
    expect(
      book.paragraphs,
      containsAll(['跳到正文', '[[vellum-heading:1]]第一章', '这是 EPUB 正文。']),
    );
    expect(book.linkTargets[0], 1);
  });

  test('rejects unsupported extensions without pretending to import', () {
    expect(
      () => importer.decode(
        filename: 'notes.pdf',
        bytes: Uint8List.fromList([1, 2, 3]),
      ),
      throwsA(isA<BookImportException>()),
    );
  });

  test('accepts filename extensions without case sensitivity', () {
    expect(importer.formatForFilename('BOOK.EpUb'), BookFormat.epub);
  });

  test('decodes UTF-8 MOBI text according to its encoding header', () {
    final text = utf8.encode('测试');
    final bytes = _mobiFixture([text.length, ...text], textLength: text.length);

    final book = importer.decode(filename: 'utf8.mobi', bytes: bytes);

    expect(book.paragraphs, ['测试']);
  });

  test('preserves internal MOBI HTML anchor links', () {
    final text = '<p><a href="#chapter">Go</a></p><p id="chapter">Text</p>';
    final bytes = utf8.encode(text);
    final book = importer.decode(
      filename: 'links.mobi',
      bytes: _mobiFixture(bytes, textLength: bytes.length),
    );

    expect(book.paragraphs, ['Go', 'Text']);
    expect(book.linkTargets, {0: 1});
  });

  test('ignores MOBI text-record data after the declared text length', () {
    final bytes = _mobiFixture([65, 66, 0x80, 0x10, 0x01]);

    final book = importer.decode(filename: 'trailing.mobi', bytes: bytes);

    expect(book.paragraphs, ['ABABA']);
  });

  test('decodes valid PalmDOC back references in MOBI text records', () {
    final bytes = _mobiFixture([65, 66, 0x80, 0x10]);

    final book = importer.decode(filename: 'repeat.mobi', bytes: bytes);

    expect(book.paragraphs, ['ABABA']);
  });

  test('preserves MOBI headings and quotes while removing Markdown syntax', () {
    const source =
        '<h2>HTML 标题</h2><blockquote><blockquote>HTML 引用</blockquote></blockquote>'
        '<p># Markdown 标题</p><p>> Markdown 引用</p>'
        '<p>**强调** 与 [链接标题](https://example.com) 和 `代码`</p>';
    final bytes = utf8.encode(source);

    final book = importer.decode(
      filename: 'format.mobi',
      bytes: _mobiUncompressedFixture(bytes),
    );

    expect(book.paragraphs, [
      '[[vellum-heading:2]]HTML 标题',
      '[[vellum-quote]]HTML 引用',
      '[[vellum-heading:1]]Markdown 标题',
      '[[vellum-quote]]Markdown 引用',
      '[[b]]强调[[/b]] 与 链接标题 和 代码',
    ]);
  });

  test('maps MOBI filepos directory entries to their target paragraphs', () {
    const firstTarget = '第一章正文';
    const secondTarget = '第二章正文';
    const template =
        '<a filepos="00000000">第一章</a><br>'
        '<a filepos="00000000">第二章</a><br><br>'
        '<p>第一章正文</p><p>第二章正文</p>';
    final firstOffset = utf8
        .encode(template.substring(0, template.indexOf(firstTarget)))
        .length;
    final secondOffset = utf8
        .encode(template.substring(0, template.indexOf(secondTarget)))
        .length;
    final text = template
        .replaceFirst('00000000', firstOffset.toString().padLeft(8, '0'))
        .replaceFirst('00000000', secondOffset.toString().padLeft(8, '0'));
    final encoded = utf8.encode(text);

    final book = importer.decode(
      filename: 'toc.mobi',
      bytes: _mobiUncompressedFixture(encoded),
    );

    expect(book.paragraphs, containsAll([firstTarget, secondTarget]));
    expect(book.tocEntries, hasLength(2));
    expect(book.tocEntries[0].title, '第一章');
    expect(book.tocEntries[0].paragraphIndex, 2);
    expect(book.tocEntries[1].title, '第二章');
    expect(book.tocEntries[1].paragraphIndex, 3);
  });

  test('resolves MOBI recindex images with 1-based record mapping', () {
    // 1x1 red JPEG and 1x1 blue JPEG (minimal valid SOI/EOI payloads).
    final jpeg1 = Uint8List.fromList([
      0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
      0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xD9,
    ]);
    final jpeg2 = Uint8List.fromList([
      0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
      0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xDB, 0xFF, 0xD9,
    ]);
    final html = utf8.encode(
      '<p>见图<img recindex="1"></p><p>再看<img recindex="2"></p>',
    );
    final book = importer.decode(
      filename: 'images.mobi',
      bytes: _mobiWithImagesFixture(html, [jpeg1, jpeg2]),
    );

    expect(book.imageBytes[0], isNotNull);
    expect(book.imageBytes[1], isNotNull);
    // recindex=1 must map to the first image record, recindex=2 to the second.
    expect(book.imageBytes[0]!.length, jpeg1.length);
    expect(book.imageBytes[1]!.length, jpeg2.length);
    expect(book.imageBytes[0]![0], 0xFF);
    expect(book.imageBytes[0]![1], 0xD8);
    expect(book.imageBytes[1]!.last, 0xD9);
    expect(
      book.imageBytes[1]!.contains(0xDB),
      isTrue,
      reason: 'second image payload must not be the first record',
    );
  });

  test('decodes HTML entities in large-book fast path', () {
    // Force the >2MB fast path used for large MOBI files.
    final filler = '字' * (2 * 1024 * 1024 + 64);
    final source = '<p>Hello&nbsp;world &amp; friends &#8220;quote&#8221;</p>'
        '<p>$filler</p>';
    final bytes = utf8.encode(source);
    final book = importer.decode(
      filename: 'entities.mobi',
      bytes: _mobiUncompressedFixture(bytes),
    );

    final first = book.paragraphs.first;
    expect(first.contains('&nbsp;'), isFalse);
    expect(first.contains('&#8220;'), isFalse);
    expect(first, contains('Hello world & friends'));
    expect(first, contains('“quote”'));
  });
}

Uint8List _mobiUncompressedFixture(List<int> text) {
  final bytes = Uint8List(140 + text.length);
  final data = ByteData.sublistView(bytes);
  data.setUint16(76, 2, Endian.big);
  data.setUint32(78, 100, Endian.big);
  data.setUint32(86, 140, Endian.big);
  data.setUint16(100, 1, Endian.big);
  data.setUint32(104, text.length, Endian.big);
  data.setUint16(108, 1, Endian.big);
  data.setUint16(112, 0, Endian.big);
  data.setUint32(128, 65001, Endian.big);
  bytes.setRange(116, 120, [0x4d, 0x4f, 0x42, 0x49]);
  bytes.setRange(140, 140 + text.length, text);
  return bytes;
}

/// Builds a MOBI with one text record followed by [images] image records.
Uint8List _mobiWithImagesFixture(List<int> text, List<List<int>> images) {
  // 4+ records need a record list that does not overlap the PalmDOC header.
  const headerOffset = 128;
  final textOffset = headerOffset + 40;
  final imageBytes = images.expand((image) => image).toList();
  final total = textOffset + text.length + imageBytes.length;
  final bytes = Uint8List(total);
  final data = ByteData.sublistView(bytes);
  final recordCount = 2 + images.length;
  data.setUint16(76, recordCount, Endian.big);
  data.setUint32(78, headerOffset, Endian.big);
  data.setUint32(86, textOffset, Endian.big);
  var offset = textOffset + text.length;
  for (var index = 0; index < images.length; index++) {
    data.setUint32(94 + index * 8, offset, Endian.big);
    offset += images[index].length;
  }
  data.setUint16(headerOffset, 1, Endian.big); // uncompressed
  data.setUint32(headerOffset + 4, text.length, Endian.big);
  data.setUint16(headerOffset + 8, 1, Endian.big); // textRecords
  data.setUint16(headerOffset + 12, 0, Endian.big); // no encryption
  data.setUint32(headerOffset + 28, 65001, Endian.big); // UTF-8
  bytes.setRange(headerOffset + 16, headerOffset + 20, [
    0x4d,
    0x4f,
    0x42,
    0x49,
  ]);
  bytes.setRange(textOffset, textOffset + text.length, text);
  var cursor = textOffset + text.length;
  for (final image in images) {
    bytes.setRange(cursor, cursor + image.length, image);
    cursor += image.length;
  }
  return bytes;
}

Uint8List _mobiFixture(List<int> compressedText, {int textLength = 5}) {
  final bytes = Uint8List(140 + compressedText.length);
  final data = ByteData.sublistView(bytes);
  data.setUint16(76, 2, Endian.big);
  data.setUint32(78, 100, Endian.big);
  data.setUint32(86, 140, Endian.big);

  data.setUint16(100, 2, Endian.big);
  data.setUint32(104, textLength, Endian.big);
  data.setUint16(108, 1, Endian.big);
  data.setUint16(112, 0, Endian.big);
  data.setUint32(128, 65001, Endian.big);
  bytes.setRange(116, 120, [0x4d, 0x4f, 0x42, 0x49]);
  bytes.setRange(140, 140 + compressedText.length, compressedText);
  return bytes;
}
