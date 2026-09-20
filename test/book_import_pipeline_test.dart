import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/services/book_importer.dart';
import 'package:vellum/services/book_library.dart';
import 'package:vellum/services/html_text_pipeline.dart';
import 'package:vellum/services/mobi_decoder.dart';

void main() {
  group('book content JSON streaming encoder', () {
    final book = ImportedBook(
      id: 'mobi_test',
      title: '带 "引号"\n和换行 \\ 反斜杠',
      format: BookFormat.mobi,
      paragraphs: ['普通段落', '含 [[b]] 标记', '带 " 双引号 \t 制表符'],
      linkTargets: {2: 0, 5: 1},
      tocEntries: [
        BookTocEntry(title: '第一章', paragraphIndex: 0),
        BookTocEntry(title: '第二章 "引"', paragraphIndex: 2),
      ],
      imageBytes: {1: Uint8List.fromList([1, 2, 3, 255])},
    );

    test('round-trips every field through chunked JSON', () {
      final chunks = <String>[];
      writeBookContentJson(book, chunks.add);
      final decoded = jsonDecode(chunks.join()) as Map<String, dynamic>;

      expect(decoded['id'], 'mobi_test');
      expect(decoded['title'], book.title);
      expect(decoded['format'], 'mobi');
      expect((decoded['paragraphs'] as List).cast<String>(), book.paragraphs);
      expect(decoded['linkTargets'], {'2': 0, '5': 1});
      expect(decoded['tocEntries'], [
        {'title': '第一章', 'paragraphIndex': 0},
        {'title': '第二章 "引"', 'paragraphIndex': 2},
      ]);
      expect(decoded['imageBytes'], {'1': base64Encode([1, 2, 3, 255])});
    });

    test('streams a large book instead of buffering one string', () {
      final large = ImportedBook(
        title: '大书',
        format: BookFormat.txt,
        paragraphs: [
          for (var index = 0; index < 40000; index++) '第 $index 段，' * 40,
        ],
      );
      final chunks = <String>[];
      writeBookContentJson(large, chunks.add);

      expect(chunks.length, greaterThan(1));
      for (final chunk in chunks) {
        expect(chunk.length, lessThanOrEqualTo(1 << 21));
      }
      final decoded = jsonDecode(chunks.join()) as Map<String, dynamic>;
      expect((decoded['paragraphs'] as List).length, 40000);
      expect(decoded['paragraphs'][39999], large.paragraphs[39999]);
    });
  });

  group('reader markup fast path', () {
    const pipeline = HtmlTextPipeline();

    test('leaves plain prose untouched', () {
      const plain = '他只是站在那里，看着窗外。';
      expect(pipeline.normalizeReaderMarkup(plain), plain);
      expect(
        pipeline.splitParagraphs('第一段\n\n第二段'),
        ['第一段', '第二段'],
      );
    });

    test('still rewrites markup hints', () {
      expect(
        pipeline.normalizeReaderMarkup('## 标题'),
        '[[vellum-heading:2]]标题',
      );
      expect(pipeline.normalizeReaderMarkup('> 引用'), '[[vellum-quote]]引用');
      expect(pipeline.normalizeReaderMarkup('- 列表项'), '[[vellum-list]]列表项');
      expect(pipeline.normalizeReaderMarkup('**粗体**'), '[[b]]粗体[[/b]]');
      expect(pipeline.normalizeReaderMarkup('_斜体_'), '[[i]]斜体[[/i]]');
      expect(
        pipeline.normalizeReaderMarkup('见 [来源](http://example.com)。'),
        '见 来源。',
      );
    });
  });

  group('mobi table of contents markers', () {
    test('maps scattered filepos anchors onto their own paragraphs', () {
      final titles = ['第一章', '第二章', '第三章'];
      var source = '<p>前言</p>';
      for (final title in titles) {
        source += '<p><a filepos="000000">$title</a></p><p>正文</p>';
      }
      // The placeholder and the real value share a width, so replacing in place
      // keeps every following offset valid.
      final starts = <int>[];
      for (final match in RegExp('<a filepos=').allMatches(source)) {
        starts.add(match.start);
      }
      var cursor = 0;
      source = source.replaceAllMapped(RegExp('filepos="000000"'), (match) {
        final index = starts[cursor++];
        return 'filepos="${index.toString().padLeft(6, '0')}"';
      });

      final pipeline = const HtmlTextPipeline();
      final paragraphs = pipeline.splitParagraphs(pipeline.htmlToText(source));
      final entries = const MobiDecoder().mobiTocEntries(source, paragraphs, 1252);

      expect(entries.map((entry) => entry.title).toList(), titles);
      expect(
        entries.map((entry) => entry.paragraphIndex).toList(),
        [1, 3, 5],
      );
    });

    test('keeps hundreds of anchors ordered', () {
      var source = '';
      final starts = <int>[];
      for (var index = 0; index < 300; index++) {
        final anchor = '<p><a filepos="000000">章节 $index</a></p>';
        starts.add(source.length + '<p>'.length);
        source += '$anchor<p>正文 $index</p>';
      }
      var cursor = 0;
      source = source.replaceAllMapped(RegExp('filepos="000000"'), (match) {
        final index = starts[cursor++];
        return 'filepos="${index.toString().padLeft(6, '0')}"';
      });

      final pipeline = const HtmlTextPipeline();
      final paragraphs = pipeline.splitParagraphs(pipeline.htmlToText(source));
      final entries = const MobiDecoder().mobiTocEntries(source, paragraphs, 1252);

      expect(entries.length, 300);
      for (var index = 1; index < entries.length; index++) {
        expect(
          entries[index].paragraphIndex,
          greaterThan(entries[index - 1].paragraphIndex),
        );
      }
    });
  });
}