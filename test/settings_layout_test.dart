import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/pages/settings_page.dart';
import 'package:vellum/services/book_library.dart';
import 'package:vellum/services/notes_import.dart';

/// Narrow phones and enlarged system text are where fixed rows overflow.
///
/// `CupertinoListTile` lays `additionalInfo` out at its intrinsic width, so a
/// long trailing value (`今日 0 秒 · 累计 0 秒`, `JSON / 文本`) used to push the row
/// past the tile and paint a horizontal overflow stripe.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required Size size,
    double textScale = 1,
    List<BookMatchCandidate> books = const [],
  }) async {
    await tester.binding.setSurfaceSize(size);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: CupertinoApp(
          home: SettingsPage(
            onCycleTheme: () {},
            themeModeLabel: '跟随系统',
            isDark: false,
            installedFonts: const [],
            activeFontName: '',
            useFontForUi: false,
            useFontForContent: false,
            onImportFonts: () async {},
            onActivateFont: (_) async {},
            onDeleteFont: (_) async {},
            onFontUsageChanged:
                ({required useForUi, required useForContent}) async {},
            storageUsage: () async => const StorageUsage(
              libraryBytes: 0,
              readingStateBytes: 0,
              fontBytes: 0,
            ),
            onClearBooks: () async {},
            onClearReadingStates: () async {},
            availableBooks: books,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('renders without overflow on narrow and wide viewports', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final size in const [
      Size(390, 844),
      Size(390, 560),
      Size(320, 568),
      Size(700, 400),
    ]) {
      await pump(tester, size: size);
      expect(
        tester.takeException(),
        isNull,
        reason: 'settings overflowed at $size',
      );
    }
  });

  testWidgets('renders without overflow at enlarged system text', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final scale in const [1.15, 1.3, 1.5, 1.8]) {
      await pump(tester, size: const Size(360, 640), textScale: scale);
      expect(
        tester.takeException(),
        isNull,
        reason: 'settings overflowed at text scale $scale',
      );
    }
  });

  testWidgets('the notes entries stay reachable on a narrow phone', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pump(
      tester,
      size: const Size(320, 568),
      books: [
        for (var i = 0; i < 20; i++)
          BookMatchCandidate(id: 'b$i', title: '第$i本书'),
      ],
    );

    await tester.scrollUntilVisible(
      find.text('导入阅读笔记'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('导入阅读笔记'), findsOneWidget);
    expect(find.text('未关联笔记'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
