import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/services/writing_library.dart';

void main() {
  group('applyNovelFormatting', () {
    test('adds two-em indent and blank line between paragraphs', () {
      const src = '他走进旧书店的时候，雨刚停。\n玻璃上的水痕把街灯揉成一团。\n\n老板娘抬起头说：“在楼下。”';
      final out = applyNovelFormatting(src);
      expect(out.split('\n\n').length, 2);
      expect(out, startsWith('　　'));
      expect(out, contains('　　老板娘抬起头'));
    });

    test('does not double-indent already indented prose', () {
      final out = applyNovelFormatting('　　已经有缩进了。');
      expect(out, '　　已经有缩进了。');
    });

    test('leaves headings and lists alone', () {
      const src = '# 标题\n\n- 列表项\n\n正文段落。';
      final out = applyNovelFormatting(src);
      expect(out, contains('# 标题'));
      expect(out, contains('- 列表项'));
      expect(out, contains('　　正文段落。'));
      expect(out, isNot(contains('　　#')));
      expect(out, isNot(contains('　　-')));
    });

    test('collapses runs of blank lines to one', () {
      final out = applyNovelFormatting('甲。\n\n\n\n乙。');
      expect(out, contains('\n\n　　乙。'));
      expect(out, isNot(contains('\n\n\n')));
    });

    test('keeps fenced code blocks intact', () {
      const src = '```\nint main() {}\n```\n\n正文。';
      final out = applyNovelFormatting(src);
      expect(out, contains('```\nint main() {}\n```'));
      expect(out, contains('　　正文。'));
    });
  });

  group('novel paragraph break (Enter)', () {
    test('a single trailing newline becomes a new indented paragraph', () {
      // Writer pressed Enter at the end of a finished paragraph.
      expect(
        novelParagraphBreak('　　他走进旧书店。'),
        '　　他走进旧书店。\n\n　　',
      );
    });

    test('an existing trailing newline is upgraded, not doubled', () {
      expect(
        novelParagraphBreak('　　他走进旧书店。\n'),
        '　　他走进旧书店。\n\n　　',
      );
    });

    test('a blank line already open only gains the indent', () {
      expect(
        novelParagraphBreak('　　他走进旧书店。\n\n'),
        '　　他走进旧书店。\n\n　　',
      );
      expect(
        novelParagraphBreak('　　他走进旧书店。\n\n　　'),
        '　　他走进旧书店。\n\n　　',
      );
    });

    test('keeps the caret at the end of the inserted indent', () {
      final result = novelParagraphBreakWithCaret('　　一段。');
      expect(result.text, '　　一段。\n\n　　');
      expect(result.caretOffset, result.text.length);
    });

    test('formatting while typing preserves the open line at the end', () {
      // Writer pressed Enter and is sitting on the next line mid-thought.
      const live = '　　第一段。\n\n　　';
      expect(applyNovelFormatting(live, keepTrailingNewlines: true), live);

      const openLine = '　　第一段。\n';
      expect(
        applyNovelFormatting(openLine, keepTrailingNewlines: true),
        openLine,
      );
    });

    test('an indent-only line is an open paragraph, not a blank', () {
      // U+3000 is whitespace to String.trim() — it must not swallow the caret
      // line the writer just opened with Enter. (Do not use trimRight here:
      // that would eat the indent too.)
      final out = applyNovelFormatting(
        '　　第一段。\n\n　　',
        keepTrailingNewlines: true,
      );
      expect(out, '　　第一段。\n\n　　');
    });
  });
}
