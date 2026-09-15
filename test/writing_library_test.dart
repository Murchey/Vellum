import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/services/writing_library.dart';

void main() {
  test('writing document serializes with md/txt format', () {
    final created = DateTime(2026, 1, 2, 3, 4, 5);
    final doc = WritingDocument(
      id: 'w_1',
      title: '随笔',
      body: '# 标题\n\n正文内容',
      format: WritingFormat.md,
      createdAt: created,
      updatedAt: created,
    );

    final restored = WritingDocument.fromJson(doc.toJson());
    expect(restored.id, 'w_1');
    expect(restored.title, '随笔');
    expect(restored.body, contains('正文内容'));
    expect(restored.format, WritingFormat.md);
    expect(restored.suggestedFileName, '随笔.md');
  });

  test('txt format suggests .txt extension and counts characters', () {
    final now = DateTime.now();
    final doc = WritingDocument(
      id: 'w_2',
      title: '日记',
      body: '今天写了三段话。',
      format: WritingFormat.txt,
      createdAt: now,
      updatedAt: now,
    );

    expect(doc.suggestedFileName, '日记.txt');
    expect(doc.characterCount, 8);
    expect(doc.wordCount, greaterThan(0));
    expect(doc.displayTitle, '日记');
  });

  test('empty title falls back to 未命名', () {
    final now = DateTime.now();
    final doc = WritingDocument(
      id: 'w_3',
      title: '  ',
      body: '',
      createdAt: now,
      updatedAt: now,
    );
    expect(doc.displayTitle, '未命名');
    expect(doc.preview, '（空白文稿）');
    expect(doc.suggestedFileName, '未命名文稿.md');
  });
}
