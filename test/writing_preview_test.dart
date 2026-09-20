import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/pages/writing_page.dart';
import 'package:vellum/services/writing_library.dart';
import 'package:vellum/widgets/markdown_preview.dart';

void main() {
  group('markdownPreviewParagraphs', () {
    test('renders headings, emphasis, lists and quotes as reader markup', () {
      final paragraphs = markdownPreviewParagraphs('''
# 第一章 起风

这是**粗体**、*斜体*和 `行内代码` 混排的一段。

- 无序项

1. 有序项

> 引用一行
''');

      expect(paragraphs[0], '[[vellum-heading:1]]第一章 起风');
      expect(paragraphs[1], contains('这是[[b]]粗体[[/b]]'));
      expect(paragraphs[1], contains('[[i]]斜体[[/i]]'));
      // Inline code keeps its text and drops the backticks.
      expect(paragraphs[1], contains('行内代码'));
      expect(paragraphs[1], isNot(contains('`')));
      expect(
        paragraphs.where((p) => p.startsWith('[[vellum-list]]')).length,
        2,
      );
      expect(
        paragraphs.where((p) => p.startsWith('[[vellum-quote]]')).length,
        1,
      );
    });

    test('keeps link text without leaking markup or targets', () {
      final paragraphs = markdownPreviewParagraphs(
        '见[示例](https://example.com/page)。',
      );

      expect(paragraphs, hasLength(1));
      expect(paragraphs.single, contains('示例'));
      expect(paragraphs.single, isNot(contains('[[link:')));
      expect(paragraphs.single, isNot(contains('example.com')));
    });

    test('keeps text that merely contains a bracket', () {
      final paragraphs = markdownPreviewParagraphs(
        '普通段落，带 <尖括号> 与 A < B。',
      );

      expect(paragraphs.single, '普通段落，带 <尖括号> 与 A < B。');
    });

    test('renders raw HTML blocks the way other previewers do', () {
      final paragraphs = markdownPreviewParagraphs('<div>块内容</div>');

      expect(paragraphs, ['块内容']);
    });

    test('empty drafts render no paragraphs', () {
      expect(markdownPreviewParagraphs(''), isEmpty);
      expect(markdownPreviewParagraphs('   \n  '), isEmpty);
    });
  });

  group('writing editor preview', () {
    WritingDocument draft(WritingFormat format) {
      final now = DateTime.now();
      return WritingDocument(
        id: 'w_test',
        title: '草稿',
        body: '# 起风\n\n**粗体**内容',
        format: format,
        createdAt: now,
        updatedAt: now,
      );
    }

    testWidgets('markdown drafts toggle between source and preview', (
      tester,
    ) async {
      await tester.pumpWidget(
        CupertinoApp(home: WritingEditorPage(document: draft(WritingFormat.md))),
      );
      await tester.pump();

      expect(find.text('预览'), findsOneWidget);
      expect(find.textContaining('# 起风'), findsOneWidget);
      expect(find.byType(SelectableText), findsNothing);

      await tester.tap(find.text('预览'));
      await tester.pumpAndSettle();

      // Source hidden, rendered text on screen.
      expect(find.textContaining('# 起风'), findsNothing);
      expect(find.byType(SelectableText), findsWidgets);
      expect(find.text('编辑'), findsOneWidget);

      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();

      expect(find.textContaining('# 起风'), findsOneWidget);
      expect(find.byType(SelectableText), findsNothing);
    });

    testWidgets('plain text drafts offer no preview', (tester) async {
      await tester.pumpWidget(
        CupertinoApp(home: WritingEditorPage(document: draft(WritingFormat.txt))),
      );
      await tester.pump();

      expect(find.text('预览'), findsNothing);
      expect(find.text('纯文本'), findsWidgets);
    });
  });
}