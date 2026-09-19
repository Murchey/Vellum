import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/reader_gestures.dart';
import 'package:vellum/reader/reader_models.dart';
import 'package:vellum/reader/reader_selection.dart';

void main() {
  test('long-press selection drag does not arm bookmark', () {
    final down = DateTime.now().subtract(const Duration(milliseconds: 600));
    final action = ReaderGestures.resolvePointerUp(
      downAt: down,
      downPosition: const Offset(200, 80),
      upPosition: const Offset(210, 200),
      mode: ReadingMode.scroll,
      beginsAtScrollTop: true,
      isIdle: true,
      screenWidth: 400,
      screenHeight: 800,
      selectionGesture: true,
    );
    expect(action, ReaderTapAction.none);
  });

  test('quick vertical flick at top can bookmark', () {
    final down = DateTime.now().subtract(const Duration(milliseconds: 80));
    final action = ReaderGestures.resolvePointerUp(
      downAt: down,
      downPosition: const Offset(200, 80),
      upPosition: const Offset(204, 220),
      mode: ReadingMode.scroll,
      beginsAtScrollTop: true,
      isIdle: true,
      screenWidth: 400,
      screenHeight: 800,
    );
    expect(action, ReaderTapAction.toggleBookmark);
  });

  test('deepl uri embeds selected text in the hash fragment', () {
    final uri = deeplTranslateUri('你好 world');
    expect(uri.host, 'www.deepl.com');
    expect(uri.fragment, contains('auto/zh/'));
    expect(uri.fragment, contains(Uri.encodeComponent('你好 world')));
  });

  test('page turn style includes slide', () {
    expect(PageTurnStyle.values.map((e) => e.name), contains('slide'));
    expect(PageTurnStyle.slide.label, '平移');
  });
}
