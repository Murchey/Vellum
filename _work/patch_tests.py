from pathlib import Path

# reader_highlights_test.dart
p = Path(r'D:\Projects\vibecoding\Vellum\test\reader_highlights_test.dart')
text = p.read_text(encoding='utf-8')
old = """    expect(find.text('第一章 夜雨 · 本章 50%'), findsOneWidget);
    expect(find.text('50% · 剩余约 12 分钟 · 电量 80%'), findsOneWidget);"""
new = """    expect(
      find.text(
        '50% · 第一章 夜雨 · 本章 50% · 剩余约 12 分钟 · 电量 80%',
      ),
      findsOneWidget,
    );"""
if old not in text:
    raise SystemExit('highlights block1 not found')
text = text.replace(old, new, 1)
old2 = """    expect(find.text('第一章 夜雨 · 本章 50%'), findsOneWidget);
    expect(find.textContaining('剩余约 1 分钟'), findsOneWidget);"""
new2 = """    expect(find.textContaining('第一章 夜雨'), findsOneWidget);
    expect(find.textContaining('剩余约 1 分钟'), findsOneWidget);"""
if old2 not in text:
    raise SystemExit('highlights block2 not found')
text = text.replace(old2, new2, 1)
p.write_text(text, encoding='utf-8')
print('highlights ok')

# widget_test font button
p2 = Path(r'D:\Projects\vibecoding\Vellum\test\widget_test.dart')
text2 = p2.read_text(encoding='utf-8')
old3 = """    await tester.tapAt(const Offset(400, 300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('字体').last);
    await tester.pumpAndSettle();"""
new3 = """    await tester.tapAt(const Offset(400, 300));
    await tester.pumpAndSettle();
    // Fanqie structure: 字体 lives inside the settings panel.
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('字体'));
    await tester.pumpAndSettle();"""
if old3 not in text2:
    raise SystemExit('font button block not found')
text2 = text2.replace(old3, new3, 1)
p2.write_text(text2, encoding='utf-8')
print('font button ok')
