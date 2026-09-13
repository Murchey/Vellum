import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/vellum.dart';

void main() {
  testWidgets('settings opens convert page without render errors', (
    tester,
  ) async {
    // Logical 390x844
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final errors = <Object>[];
    final old = FlutterError.onError;
    FlutterError.onError = (details) {
      errors.add(details.exceptionAsString());
      old?.call(details);
    };
    addTearDown(() => FlutterError.onError = old);

    await tester.pumpWidget(const VellumApp());
    await tester.pumpAndSettle();
    expect(errors, isEmpty, reason: 'open app: ');

    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    expect(errors, isEmpty, reason: 'open settings: ');

    await tester.tap(find.text('MOBI / EPUB 转 TXT'));
    await tester.pumpAndSettle();

    expect(find.text('转为 TXT'), findsOneWidget);
    expect(errors, isEmpty, reason: 'after convert page: ');
    expect(tester.takeException(), isNull);
  });
}
