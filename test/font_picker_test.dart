import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/reader_font_picker.dart';
import 'package:vellum/services/book_library.dart';
import 'package:vellum/theme/vellum_theme.dart';

const _font = InstalledFont(
  name: 'demo-font',
  family: 'Font_demo',
  displayName: '示例字体',
);

/// `activeFamily` deliberately matches no row so ink assertions read the
/// unselected style rather than the orange selected style.
const _unselectedFamily = 'Font_absent';

void main() {
  test('font catalog preserves the Fanqie order and labels', () {
    expect(fanqieReaderFonts.first.family, 'Default');
    expect(fanqieReaderFonts.first.title, '系统字体');
    expect(fanqieReaderFonts.length, 1);
  });

  testWidgets(
    'font picker uses the reader surface instead of app shell color',
    (tester) async {
      await tester.pumpWidget(
        const CupertinoApp(
          home: CupertinoPageScaffold(
            child: ReaderFontPickerSheet(
              installedFonts: [],
              activeFamily: _unselectedFamily,
              onSelectSystemFont: _noop,
              onSelectImportedFont: _noopFont,
            ),
          ),
        ),
      );

      expect(_sheetColor(tester), VellumTheme.readerWhite);
      expect(_sheetColor(tester), isNot(VellumTheme.paper));
    },
  );

  testWidgets('font picker follows the active paper in light and dark', (
    tester,
  ) async {
    for (final surface in [
      VellumTheme.readerWhite,
      VellumTheme.readerSepia,
      VellumTheme.readerMint,
      VellumTheme.readerBlue,
      VellumTheme.readerNight,
      VellumTheme.readerCharcoal,
    ]) {
      await tester.pumpWidget(
        CupertinoApp(
          home: CupertinoPageScaffold(
            child: ReaderFontPickerSheet(
              surface: surface,
              installedFonts: const [],
              activeFamily: _unselectedFamily,
              onSelectSystemFont: _noop,
              onSelectImportedFont: _noopFont,
            ),
          ),
        ),
      );

      final ink = VellumTheme.readerChromeInk(surface);
      expect(
        _sheetColor(tester),
        surface,
        reason: 'picker surface must equal the reading paper $surface',
      );
      expect(tester.widget<Text>(find.text('选择字体')).style!.color, ink);
      expect(tester.widget<Text>(find.text('系统字体')).style!.color, ink);
    }
  });

  testWidgets('font picker preview ink follows the active paper', (
    tester,
  ) async {
    await tester.pumpWidget(
      const CupertinoApp(
        home: CupertinoPageScaffold(
          child: ReaderFontPickerSheet(
            surface: VellumTheme.readerNight,
            installedFonts: [_font],
            activeFamily: _unselectedFamily,
            onSelectSystemFont: _noop,
            onSelectImportedFont: _noopFont,
          ),
        ),
      ),
    );

    final ink = VellumTheme.readerChromeInk(VellumTheme.readerNight);
    final preview = tester.widget<Text>(find.text('永'));
    expect(preview.style!.fontFamily, _font.family);
    expect(preview.style!.color, ink.withValues(alpha: .55));
  });
}

Color _sheetColor(WidgetTester tester) {
  final sheet = tester.widget<Container>(
    find
        .descendant(
          of: find.byType(ReaderFontPickerSheet),
          matching: find.byType(Container),
        )
        .first,
  );
  return (sheet.decoration! as BoxDecoration).color!;
}

void _noop(String value) {}
Future<void> _noopFont(InstalledFont value) async {}
