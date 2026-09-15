import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/vellum.dart';

void main() {
  testWidgets('writing tab shows empty state and new draft action', (
    tester,
  ) async {
    await tester.pumpWidget(
      const CupertinoApp(home: WritingPage(initialDocuments: [])),
    );
    await tester.pump();

    expect(find.text('开始写作'), findsOneWidget);
    expect(find.text('新建文稿'), findsOneWidget);
  });

  testWidgets('writing editor opens with title and body fields', (
    tester,
  ) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      CupertinoApp(
        home: WritingEditorPage(
          document: WritingDocument(
            id: 'w_test',
            title: '草稿',
            body: '第一段',
            format: WritingFormat.md,
            createdAt: now,
            updatedAt: now,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Markdown'), findsWidgets);
    expect(find.text('纯文本'), findsWidgets);
    expect(find.text('草稿'), findsOneWidget);
    expect(find.text('第一段'), findsOneWidget);
    expect(find.textContaining('字'), findsWidgets);
  });
}
