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
        '<h2>HTML 标题</h2><blockquote>HTML 引用</blockquote>'
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
      '强调 与 链接标题 和 代码',
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
