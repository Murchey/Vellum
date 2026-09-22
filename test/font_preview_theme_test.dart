import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/services/book_library.dart';
import 'package:vellum/theme/vellum_theme.dart';
import 'package:vellum/widgets/font_preview.dart';

void main() {
  testWidgets(
    'imported font preview binds both glyph samples to its font family',
    (tester) async {
      const font = InstalledFont(
        name: 'reader-font',
        family: 'Font_123',
        displayName: '阅读字体',
      );
      await tester.pumpWidget(
        const CupertinoApp(home: FontPreview(font: font, compact: true)),
      );

      for (final text in ['永', 'Aa']) {
        expect(
          tester.widget<Text>(find.text(text)).style!.fontFamily,
          font.family,
        );
      }
    },
  );

  test('light application shell uses the requested warm paper', () {
    expect(VellumTheme.paper, const Color(0xfff7e4cf));
    expect(VellumTheme.light.scaffoldBackgroundColor, VellumTheme.paper);
    expect(VellumTheme.light.barBackgroundColor, VellumTheme.paper);
  });
}
