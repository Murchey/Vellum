import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/reader_font_picker.dart';
import 'package:vellum/services/book_library.dart';
import 'package:vellum/theme/vellum_theme.dart';

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
              activeFamily: 'Georgia',
              onSelectSystemFont: _noop,
              onSelectImportedFont: _noopFont,
            ),
          ),
        ),
      );

      final sheet = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(ReaderFontPickerSheet),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = sheet.decoration! as BoxDecoration;
      expect(decoration.color, VellumTheme.readerWhite);
      expect(decoration.color, isNot(VellumTheme.paper));
    },
  );
}

void _noop(String value) {}
Future<void> _noopFont(InstalledFont value) async {}
