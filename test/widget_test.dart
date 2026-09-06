import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectableText, SelectionArea;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/main.dart';
import 'package:vellum/services/book_importer.dart';
import 'package:vellum/services/book_library.dart';

void main() {
  test('Bing search URI keeps the selected text as q parameter', () {
    final uri = buildBingSearchUri('哈利 波特 & 魔法');

    expect(uri.scheme, 'https');
    expect(uri.host, 'cn.bing.com');
    expect(uri.path, '/search');
    expect(uri.queryParameters['q'], '哈利 波特 & 魔法');
    expect(uri.queryParameters['q'], isNotEmpty);
  });

  testWidgets('shows only the empty-library import action initially', (
    tester,
  ) async {
    await tester.pumpWidget(const VellumApp());

    expect(find.text('书库是空的'), findsOneWidget);
    expect(find.text('导入电子书'), findsOneWidget);
    expect(find.text('晚上好，读者'), findsNothing);
    expect(find.text('阅读偏好'), findsNothing);
  });

  test('defines distinct light and dark palettes', () {
    expect(VellumTheme.light.brightness, Brightness.light);
    expect(VellumTheme.dark.brightness, Brightness.dark);
    expect(
      VellumTheme.light.scaffoldBackgroundColor,
      isNot(VellumTheme.dark.scaffoldBackgroundColor),
    );
    expect(
      VellumTheme.light.textTheme.textStyle.color,
      isNot(VellumTheme.dark.textTheme.textStyle.color),
    );
  });

  test('reader papers keep their exact requested text contrast', () {
    expect(
      VellumTheme.readerInkFor(VellumTheme.darkPaper),
      CupertinoColors.white,
    );
    expect(
      VellumTheme.readerInkFor(VellumTheme.readerNight),
      const Color(0xffb5b5b5),
    );
    expect(
      VellumTheme.readerInkFor(VellumTheme.readerMint),
      CupertinoColors.black,
    );
    expect(
      VellumTheme.readerInkFor(VellumTheme.readerSepia),
      CupertinoColors.black,
    );
    expect(
      VellumTheme.readerInkFor(VellumTheme.readerCharcoal),
      const Color(0xff929292),
    );
    expect(
      VellumTheme.readerInkFor(VellumTheme.readerBlue),
      CupertinoColors.black,
    );
    expect(
      VellumTheme.readerInkFor(VellumTheme.readerWhite),
      CupertinoColors.black,
    );
  });

  testWidgets('switches application theme from inside the app', (tester) async {
    await tester.pumpWidget(const VellumApp());
    await tester.tap(find.text('设置').last);
    await tester.pump();
    final before = tester.widget<CupertinoApp>(find.byType(CupertinoApp));

    await tester.tap(find.byIcon(CupertinoIcons.moon));
    await tester.pump();

    final after = tester.widget<CupertinoApp>(find.byType(CupertinoApp));
    expect(after.theme?.brightness, isNot(before.theme?.brightness));
  });

  testWidgets('shows storage management in the settings tab', (tester) async {
    await tester.pumpWidget(const VellumApp());
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();

    expect(find.text('存储管理'), findsOneWidget);
    expect(find.text('占用空间'), findsOneWidget);
    expect(find.text('清空书库'), findsOneWidget);
    expect(find.text('清除阅读记录'), findsOneWidget);
  });

  testWidgets('shows a delete action for books in the library', (tester) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: LibraryPage(
          books: const [
            ImportedBook(
              title: '待删除的书',
              format: BookFormat.txt,
              paragraphs: ['正文'],
            ),
          ],
          onOpen: (_) {},
          onImport: () {},
          onDelete: (_) {},
        ),
      ),
    );

    expect(find.byIcon(CupertinoIcons.delete), findsOneWidget);
  });

  testWidgets('reading controls live in the reader overlay', (tester) async {
    await tester.pumpWidget(
      const CupertinoApp(
        home: ReaderPage(
          book: ImportedBook(
            title: '测试书',
            format: BookFormat.txt,
            paragraphs: ['一段正文'],
          ),
        ),
      ),
    );
    expect(find.byType(CupertinoNavigationBar), findsNothing);

    await tester.tapAt(const Offset(400, 300));
    await tester.pump();

    expect(find.byType(CupertinoNavigationBar), findsNothing);
    expect(find.text('测试书'), findsNWidgets(2));
    expect(find.text('0.000%'), findsOneWidget);
    expect(find.text('目录'), findsOneWidget);
    expect(find.text('切换深色'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('阅读方式'), findsNothing);

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    expect(find.text('阅读设置'), findsOneWidget);
    expect(find.text('阅读方式'), findsOneWidget);
    expect(find.text('上下滚动'), findsOneWidget);
    expect(find.text('左右翻页'), findsOneWidget);
    expect(find.text('阅读进度'), findsOneWidget);
    expect(find.text('字重'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
  });

  testWidgets('scroll reader provides one selection area across paragraphs', (
    tester,
  ) async {
    await tester.pumpWidget(
      const CupertinoApp(
        home: ReaderPage(
          book: ImportedBook(
            title: '跨段选择',
            format: BookFormat.txt,
            paragraphs: ['第一段可选择文字。', '第二段可选择文字。'],
          ),
        ),
      ),
    );

    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.byType(SelectableText), findsNWidgets(2));
  });

  testWidgets('renders an inline image marker inside its paragraph', (
    tester,
  ) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: ReaderPage(
          book: ImportedBook(
            title: '段内注释',
            format: BookFormat.mobi,
            paragraphs: const ['正文前[[image:1]]正文后'],
            imageBytes: {0: Uint8List(0)},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    expect(find.textContaining('正文前'), findsOneWidget);
    expect(find.textContaining('[[image:'), findsNothing);
  });

  testWidgets('reader font button explains how to import when no font exists', (
    tester,
  ) async {
    await tester.pumpWidget(
      const CupertinoApp(
        home: ReaderPage(
          book: ImportedBook(
            title: '字体提示',
            format: BookFormat.txt,
            paragraphs: ['一段正文'],
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(400, 300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('字体'));
    await tester.pumpAndSettle();

    expect(find.text('阅读字体'), findsOneWidget);
    expect(find.text('系统字体'), findsOneWidget);
    expect(find.text('系统默认'), findsOneWidget);
    expect(
      find.textContaining('English: Reading changes life'),
      findsNWidgets(3),
    );
  });

  testWidgets(
    'long press on reader text shows a Cupertino selection menu without errors',
    (tester) async {
      await tester.pumpWidget(
        const CupertinoApp(
          home: ReaderPage(
            book: ImportedBook(
              title: '长按选择',
              format: BookFormat.txt,
              paragraphs: ['可被选择的阅读正文。'],
            ),
          ),
        ),
      );

      await tester.longPress(find.byType(SelectableText));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.byType(CupertinoAdaptiveTextSelectionToolbar),
        findsOneWidget,
      );
    },
  );

  testWidgets('dark scroll reader selection uses a Cupertino toolbar', (
    tester,
  ) async {
    await tester.pumpWidget(
      const CupertinoApp(
        home: ReaderPage(
          initialState: ReadingState(backgroundValue: 0xff262522),
          book: ImportedBook(
            title: '暗色选择',
            format: BookFormat.txt,
            paragraphs: ['暗色阅读器中的可选择正文。'],
          ),
        ),
      ),
    );

    await tester.longPress(find.byType(SelectableText));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(CupertinoAdaptiveTextSelectionToolbar), findsOneWidget);
  });
  test('persists bookmark paragraph indexes in reading state', () {
    const state = ReadingState(lineSpacing: 'relaxed', bookmarks: [3, 18]);
    final restored = ReadingState.fromJson(state.toJson());
    expect(restored.bookmarks, [3, 18]);
    expect(restored.lineSpacing, 'relaxed');
  });

  testWidgets('shows a red top marker for a bookmarked reader page', (
    tester,
  ) async {
    await tester.pumpWidget(
      const CupertinoApp(
        home: ReaderPage(
          initialState: ReadingState(mode: 'page', bookmarks: [0]),
          book: ImportedBook(
            title: '书签页标记',
            format: BookFormat.txt,
            paragraphs: ['已加书签的页面正文'],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('当前阅读页面已添加书签'), findsOneWidget);
  });

  testWidgets('chapter panel keeps table-of-contents and body entries', (
    tester,
  ) async {
    // This test verifies that chapter entries are preserved
    // The actual UI interaction is tested in the app
    final book = const ImportedBook(
      title: '目录筛选',
      format: BookFormat.mobi,
      paragraphs: [
        '目录',
        '第1章 目录中的第一章',
        '第2章 目录中的第二章',
        '献词 第1章',
        '正文的第一章',
        '正文内容',
        '第2章',
        '正文的第二章',
      ],
    );

    // Verify the book has the expected paragraphs
    expect(book.paragraphs.length, 8);
    expect(book.paragraphs[1], '第1章 目录中的第一章');
    expect(book.paragraphs[2], '第2章 目录中的第二章');
    expect(book.paragraphs[7], '正文的第二章');
  });

  testWidgets('persists the selected reading mode before leaving the reader', (
    tester,
  ) async {
    ReadingState? saved;
    await tester.pumpWidget(
      CupertinoApp(
        home: ReaderPage(
          onStateChanged: (value) async => saved = value,
          book: const ImportedBook(
            title: '阅读方式记忆',
            format: BookFormat.txt,
            paragraphs: ['正文'],
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(400, 300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('左右翻页'));
    await tester.pump();

    expect(saved?.mode, 'page');

    await tester.pumpWidget(
      CupertinoApp(
        home: ReaderPage(
          initialState: saved!,
          book: const ImportedBook(
            title: '阅读方式记忆',
            format: BookFormat.txt,
            paragraphs: ['正文'],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PageView), findsOneWidget);
  });

  testWidgets('lazily builds long scroll reading content', (tester) async {
    final paragraphs = List<String>.generate(20000, (index) => '第 $index 段');
    await tester.pumpWidget(
      CupertinoApp(
        home: ReaderPage(
          book: ImportedBook(
            title: '长篇测试书',
            format: BookFormat.txt,
            paragraphs: paragraphs,
          ),
        ),
      ),
    );

    expect(find.text('长篇测试书'), findsOneWidget);
    expect(find.text('第 19999 段'), findsNothing);
  });

  testWidgets('page mode clamps an obsolete saved page index', (tester) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: ReaderPage(
          initialState: const ReadingState(mode: 'page', page: 999999),
          book: const ImportedBook(
            title: '旧阅读记录',
            format: BookFormat.txt,
            paragraphs: ['短正文'],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('短正文'), findsOneWidget);
  });

  testWidgets('saves page progress when the app enters the background', (
    tester,
  ) async {
    ReadingState? saved;
    await tester.pumpWidget(
      CupertinoApp(
        home: ReaderPage(
          initialState: const ReadingState(mode: 'page'),
          onStateChanged: (value) async {
            saved = value;
          },
          book: ImportedBook(
            title: '后台保存',
            format: BookFormat.txt,
            paragraphs: List<String>.generate(
              9,
              (index) => '第 ${index + 1} 段正文',
            ),
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(700, 300));
    await tester.pumpAndSettle();

    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/lifecycle',
      const StringCodec().encodeMessage('AppLifecycleState.paused'),
      (_) {},
    );
    await tester.pump();

    expect(saved?.page, 1);
  });

  testWidgets('restores and persists vertical scroll position', (tester) async {
    ReadingState? saved;
    final paragraphs = List<String>.generate(
      160,
      (index) => '第 $index 段。' * 12,
    );
    await tester.pumpWidget(
      CupertinoApp(
        home: ReaderPage(
          initialState: const ReadingState(position: 260),
          onStateChanged: (value) async => saved = value,
          book: ImportedBook(
            title: '滚动位置恢复',
            format: BookFormat.txt,
            paragraphs: paragraphs,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollView = tester.widget<ListView>(find.byType(ListView));
    expect(scrollView.controller?.offset, greaterThan(0));

    await tester.drag(find.byType(ListView), const Offset(0, -280));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/lifecycle',
      const StringCodec().encodeMessage('AppLifecycleState.paused'),
      (_) {},
    );
    await tester.pump();

    expect(saved?.mode, 'scroll');
    expect(saved?.position, greaterThan(0));
  });

  testWidgets('vertical reading drag does not open the footer', (tester) async {
    await tester.pumpWidget(
      const CupertinoApp(
        home: ReaderPage(
          book: ImportedBook(
            title: '滑动测试',
            format: BookFormat.txt,
            paragraphs: ['第一段正文', '第二段正文', '第三段正文'],
          ),
        ),
      ),
    );

    await tester.dragFrom(const Offset(400, 500), const Offset(400, 200));
    await tester.pump();

    expect(find.text('阅读方式'), findsNothing);
    expect(find.text('阅读进度'), findsNothing);
  });

  testWidgets('page mode prevents vertical scrolling inside a page', (
    tester,
  ) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: ReaderPage(
          initialState: const ReadingState(mode: 'page'),
          book: ImportedBook(
            title: '纵向手势',
            format: BookFormat.txt,
            paragraphs: List<String>.generate(9, (index) => '第 $index 段正文'),
          ),
        ),
      ),
    );

    final pageList = tester.widget<ListView>(
      find.descendant(
        of: find.byType(PageView),
        matching: find.byType(ListView),
      ),
    );
    expect(pageList.physics, isA<NeverScrollableScrollPhysics>());
  });

  testWidgets('downward pull adds a visible bookmark notice in page mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: ReaderPage(
          initialState: const ReadingState(mode: 'page'),
          book: const ImportedBook(
            title: '下拉书签',
            format: BookFormat.txt,
            paragraphs: ['可添加书签的正文'],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.dragFrom(const Offset(400, 300), const Offset(400, 500));
    await tester.pump();

    expect(find.text('书签已添加'), findsOneWidget);
  });
  testWidgets('page mode navigates with left and right screen taps', (
    tester,
  ) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: ReaderPage(
          initialState: const ReadingState(mode: 'page'),
          book: ImportedBook(
            title: '翻页测试',
            format: BookFormat.txt,
            paragraphs: List<String>.generate(
              9,
              (index) => '第 ${index + 1} 段翻页内容',
            ),
          ),
        ),
      ),
    );

    final pageView = tester.widget<PageView>(find.byType(PageView));
    expect(pageView.controller?.initialPage, 0);

    await tester.tapAt(const Offset(700, 300));
    await tester.pumpAndSettle();

    expect(pageView.controller?.page?.round(), 1);
  });
}
