import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/reader_page.dart';
import 'package:vellum/services/book_importer.dart';

void main() {
  testWidgets('diag taps', (tester) async {
    await tester.pumpWidget(
      const CupertinoApp(
        home: ReaderPage(
          book: ImportedBook(
            title: '测试书',
            format: BookFormat.txt,
            paragraphs: ['第一段正文'],
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(400, 300));
    await tester.pumpAndSettle();

    final setFinder = find.text('设置');
    final center = tester.getCenter(setFinder);
    // ignore: avoid_print
    print('设置 center=$center  testSize=${tester.binding.window.physicalSize}');

    await tester.tap(setFinder);
    await tester.pumpAndSettle();
    // ignore: avoid_print
    print(
      'after tap设置: 阅读设置=${find.text('阅读设置').evaluate().length} '
      '上一章=${find.text('上一章').evaluate().length} '
      '设置=${find.text('设置').evaluate().length}',
    );
    // ignore: avoid_print
    print(
      'rects 设置=${tester.getRect(find.text('设置'))} '
      '阅读设置=${tester.getRect(find.text('阅读设置'))} '
      '目录=${tester.getRect(find.text('目录'))}',
    );

    await tester.tap(find.text('目录'));
    await tester.pumpAndSettle();
    // ignore: avoid_print
    print(
      'after tap目录: 阅读设置=${find.text('阅读设置').evaluate().length} '
      '书签=${find.text('书签').evaluate().length} '
      '目录=${find.text('目录').evaluate().length}',
    );

    // Tap the dismiss band between top bar and chrome.
    await tester.tapAt(const Offset(400, 200));
    await tester.pumpAndSettle();
    // ignore: avoid_print
    print(
      'after band tap: 阅读设置=${find.text('阅读设置').evaluate().length} '
      '上一章=${find.text('上一章').evaluate().length} '
      '设置=${find.text('设置').evaluate().length}',
    );
  });
}
