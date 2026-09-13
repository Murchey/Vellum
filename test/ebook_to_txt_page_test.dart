import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/vellum.dart';

void main() {
  testWidgets('ebook-to-txt page survives large text scale', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      CupertinoApp(
        builder: (context, child) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(
              textScaler: const TextScaler.linear(1.6),
            ),
            child: child!,
          );
        },
        home: const EbookToTxtPage(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('ebook-to-txt page from settings route', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: Center(
            child: CupertinoButton(
              child: const Text('open'),
              onPressed: () {
                Navigator.of(
                  tester.element(find.text('open')),
                ).push(
                  CupertinoPageRoute(
                    builder: (_) => const EbookToTxtPage(),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('转为 TXT'), findsOneWidget);
  });
}
