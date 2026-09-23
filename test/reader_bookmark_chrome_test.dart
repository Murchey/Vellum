import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/reader_chrome.dart';
import 'package:vellum/theme/vellum_theme.dart';

void main() {
  testWidgets(
    'saved bookmark is a right-edge hanging ribbon without a caption',
    (tester) async {
      await tester.pumpWidget(
        const CupertinoApp(
          home: SizedBox.expand(
            child: BookmarkRibbon(
              progress: 1,
              armed: false,
              alreadyBookmarked: true,
              label: '',
              pinned: true,
              showLabel: false,
            ),
          ),
        ),
      );

      expect(find.byType(ClipPath), findsOneWidget);
      expect(find.text('书签已添加'), findsNothing);
      final ribbon = tester.getRect(find.byType(ClipPath));
      final screen = tester.getRect(find.byType(SizedBox).first);
      expect(ribbon.right, screen.right);
      expect(ribbon.height, greaterThan(60));
    },
  );

  testWidgets('pull caption follows the active reading paper', (tester) async {
    for (final surface in [
      VellumTheme.readerWhite,
      VellumTheme.readerSepia,
      VellumTheme.readerNight,
      VellumTheme.readerCharcoal,
    ]) {
      await tester.pumpWidget(
        CupertinoApp(
          home: SizedBox.expand(
            child: BookmarkRibbon(
              surface: surface,
              progress: 1,
              armed: false,
              alreadyBookmarked: false,
              label: '下拉添加书签',
            ),
          ),
        ),
      );

      final ink = VellumTheme.readerChromeInk(surface);
      final pill = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(BookmarkRibbon),
              matching: find.byType(Container),
            )
            .last,
      );
      final decoration = pill.decoration! as BoxDecoration;
      expect(
        decoration.color,
        surface.withValues(alpha: .94),
        reason: 'caption pill must sit on the active paper $surface',
      );
      expect(
        (decoration.border! as Border).top.color,
        ink.withValues(alpha: .18),
      );
      expect(tester.widget<Text>(find.text('下拉添加书签')).style!.color, ink);
    }
  });
}
