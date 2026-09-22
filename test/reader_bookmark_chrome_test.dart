import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/reader_chrome.dart';

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
}
