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

  test('light application shell uses the warm vellum surface', () {
    expect(VellumTheme.paper, const Color(0xfff7e4cf));
    expect(VellumTheme.accent, const Color(0xffa95c46));
    expect(VellumTheme.darkAccent, const Color(0xffd8896c));
    expect(VellumTheme.shellPaper, const Color(0xfff7f3ed));
    expect(VellumTheme.shellCard, const Color(0xfffffdf8));
    expect(VellumTheme.light.scaffoldBackgroundColor, VellumTheme.shellPaper);
    expect(VellumTheme.light.barBackgroundColor, VellumTheme.shellPaper);
  });
}
