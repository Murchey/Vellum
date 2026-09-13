import 'package:flutter/cupertino.dart';

enum ReadingMode { scroll, page }

enum PageTurnStyle {
  cover('覆盖'),
  none('无动画');

  const PageTurnStyle(this.label);
  final String label;

  static PageTurnStyle fromStorage(String value) =>
      PageTurnStyle.values.firstWhere(
        (style) => style.name == value,
        orElse: () => PageTurnStyle.cover,
      );
}

enum ReaderLineSpacing {
  compact('紧凑', 1.55),
  comfortable('舒适', 1.9),
  relaxed('宽松', 2.2);

  const ReaderLineSpacing(this.label, this.height);

  final String label;
  final double height;

  static ReaderLineSpacing fromStorage(String value) =>
      ReaderLineSpacing.values.firstWhere(
        (spacing) => spacing.name == value,
        orElse: () => ReaderLineSpacing.comfortable,
      );
}

enum ReaderFontWeight {
  light('细', FontWeight.w300),
  regular('常规', FontWeight.w400),
  bold('粗', FontWeight.w600);

  const ReaderFontWeight(this.label, this.value);

  final String label;
  final FontWeight value;

  static ReaderFontWeight fromStorage(String value) =>
      ReaderFontWeight.values.firstWhere(
        (weight) => weight.name == value,
        orElse: () => ReaderFontWeight.regular,
      );
}

class PageFragment {
  const PageFragment({
    required this.paragraphIndex,
    required this.text,
    this.showImage = false,
    this.showLinkAction = false,
    this.compactPadding = false,
    this.indentFirstLine = true,
  });

  final int paragraphIndex;
  final String text;
  final bool showImage;
  final bool showLinkAction;
  final bool compactPadding;
  final bool indentFirstLine;
}
