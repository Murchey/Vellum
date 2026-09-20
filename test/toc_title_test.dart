import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/reader_toc.dart';
import 'package:vellum/services/book_importer.dart';
import 'package:vellum/services/html_text_pipeline.dart';
import 'package:vellum/services/mobi_decoder.dart';

/// An EPUB whose NCX labels carry the messy markup some generators emit.
Uint8List _dirtyNcxEpub() {
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
        '<package>'
        '<metadata><dc:title>脏目录</dc:title></metadata>'
        '<manifest>'
        '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>'
        '<item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="c2" href="c2.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="c3" href="c3.xhtml" media-type="application/xhtml+xml"/>'
        '</manifest>'
        '<spine toc="ncx"><itemref idref="c1"/><itemref idref="c2"/>'
        '<itemref idref="c3"/></spine>'
        '</package>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OPS/toc.ncx',
        '<ncx><navMap>'
        // Markup that was escaped twice by the generator.
        '<navPoint><navLabel><text>&lt;b&gt;第一章&lt;/b&gt;</text></navLabel>'
        '<content src="c1.xhtml#s1"/></navPoint>'
        // A tag the source never closed.
        '<navPoint><navLabel><text>第二章 <font color="red"</text></navLabel>'
        '<content src="c2.xhtml#s2"/></navPoint>'
        // Nested tags that do close.
        '<navPoint><navLabel><text><span class="n">第三章</span></text></navLabel>'
        '<content src="c3.xhtml#s3"/></navPoint>'
        '</navMap></ncx>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OPS/c1.xhtml',
        '<html><body><h1 id="s1">第一章</h1><p>正文一</p></body></html>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OPS/c2.xhtml',
        '<html><body><h1 id="s2">第二章</h1><p>正文二</p></body></html>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OPS/c3.xhtml',
        '<html><body><h1 id="s3">第三章</h1><p>正文三</p></body></html>',
      ),
    );
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

void main() {
  const pipeline = HtmlTextPipeline();

  group('chapterTitle', () {
    test('strips markup that was escaped in the source', () {
      expect(pipeline.chapterTitle('&lt;b&gt;第一章&lt;/b&gt;'), '第一章');
      expect(
        pipeline.chapterTitle('&lt;span class="x"&gt;第二章&lt;/span&gt;'),
        '第二章',
      );
    });

    test('strips a tag the source never closed', () {
      expect(pipeline.chapterTitle('第 1 章 <font color="red"'), '第 1 章');
      expect(pipeline.chapterTitle('第三章 <a href='), '第三章');
    });

    test('strips outer tags but keeps their text', () {
      expect(pipeline.chapterTitle('<span class="n">第三章</span>'), '第三章');
      expect(pipeline.chapterTitle('<i>Part</i> One'), 'Part One');
    });

    test('drops reader markup that leaked out of htmlToText', () {
      expect(pipeline.chapterTitle('[[vellum-heading:2]]第一章'), '第一章');
      expect(pipeline.chapterTitle('[[vellum-quote]]引文'), '引文');
      expect(pipeline.chapterTitle('[[image:3]]图'), '图');
    });

    test('keeps ordinary labels untouched', () {
      expect(pipeline.chapterTitle('第一章 夜雨'), '第一章 夜雨');
      expect(pipeline.chapterTitle('Tom &amp; Jerry'), 'Tom & Jerry');
      expect(pipeline.chapterTitle('AT&T'), 'AT&T');
      // A bare '<' in prose is not a tag.
      expect(pipeline.chapterTitle('A < B'), 'A < B');
    });

    test('never returns markup for a hopeless label', () {
      expect(pipeline.chapterTitle('<>'), '');
      expect(pipeline.chapterTitle('   '), '');
    });
  });

  group('mobi labels', () {
    test('cleans markup out of anchor titles', () {
      // filepos values are string offsets here, so they are filled in from the
      // real anchor positions (same width, so nothing shifts).
      final anchors = <int>[];
      var source = '<p>前言</p>';
      for (final label in ['<h2>第一章</h2>', '&lt;b&gt;第二章&lt;/b&gt;']) {
        anchors.add(source.length + '<p><a '.length);
        source = '$source<p><a filepos="00000000">$label</a></p><p>正文</p>';
      }
      var cursor = 0;
      source = source.replaceAllMapped(RegExp('filepos="00000000"'), (_) {
        final index = anchors[cursor++];
        return 'filepos="${index.toString().padLeft(8, '0')}"';
      });

      const pipeline = HtmlTextPipeline();
      final paragraphs = pipeline.splitParagraphs(pipeline.htmlToText(source));
      final entries = const MobiDecoder().mobiTocEntries(source, paragraphs, 1252);

      expect(entries.map((entry) => entry.title).toList(), ['第一章', '第二章']);
      expect(
        entries.map((entry) => entry.paragraphIndex).toList(),
        [1, 3],
      );
    });
  });

  group('epub labels', () {
    test('cleans NCX labels end to end', () {
      const importer = BookImporter();
      final book = importer.decode(filename: 'dirty.epub', bytes: _dirtyNcxEpub());

      expect(book.tocEntries, hasLength(3));
      expect(
        book.tocEntries.map((entry) => entry.title).toList(),
        ['第一章', '第二章', '第三章'],
      );
    });

    test('chapterEntries repairs labels stored by older imports', () {
      const book = ImportedBook(
        title: '旧书',
        format: BookFormat.epub,
        paragraphs: ['第一章', '正文', '第二章'],
        tocEntries: [
          BookTocEntry(title: '&lt;b&gt;第一章&lt;/b&gt;', paragraphIndex: 0),
          BookTocEntry(
            title: '<font color="red"第二章',
            paragraphIndex: 2,
          ),
        ],
      );

      final chapters = chapterEntries(book);
      expect(chapters.map((entry) => entry.value).toList(), ['第一章', '第二章']);
    });

    test('heuristic chapters are detected and shown cleaned', () {
      final chapters = heuristicChapterEntries([
        '第一章 夜雨',
        '[[vellum-heading:1]]第二章 晴',
        '第二章 <font color="red"',
      ]);
      expect(
        chapters.map((entry) => entry.value).toList(),
        ['第一章 夜雨', '第二章 晴', '第二章'],
      );
      expect(chapters.map((entry) => entry.key).toList(), [0, 1, 2]);
    });
  });
}