import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/main.dart';

void main() {
  testWidgets('renders the reading-first shell', (tester) async {
    await tester.pumpWidget(const VellumApp());

    expect(find.text('继续阅读'), findsOneWidget);
    expect(find.text('夜航西飞'), findsNWidgets(2));
    expect(find.text('书库'), findsOneWidget);
    expect(find.text('写作'), findsOneWidget);
  });

  testWidgets('opens the reader from the current book', (tester) async {
    await tester.pumpWidget(const VellumApp());
    await tester.tap(find.text('夜航西飞').first);
    await tester.pumpAndSettle();

    expect(find.text('夜航西飞 · 第七章'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Text && widget.data?.contains('云上的世界') == true,
      ),
      findsOneWidget,
    );
  });
}
