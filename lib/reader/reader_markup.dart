/// Shared reader markup markers and display-text helpers.
abstract final class ReaderMarkup {
  static final RegExp inlineImage = RegExp(r'\[\[image:\d+\]\]');
  static final RegExp heading = RegExp(r'^\[\[vellum-heading:([1-6])\]\]');
  static final RegExp quote = RegExp(r'^(?:\[\[vellum-quote\]\])+');
  static final RegExp list = RegExp(r'^(?:\[\[vellum-list\]\])+');
  static final RegExp center = RegExp(r'^(?:\[\[vellum-center\]\])+');
  static final RegExp inlineTag = RegExp(r'\[\[/?[biu]\]\]');

  static String readerText(String source) => source
      .replaceFirst(heading, '')
      .replaceFirst(quote, '')
      .replaceFirst(center, '')
      .replaceFirst(list, '• ')
      .replaceAll(inlineTag, '');

  static String layoutText(String source) =>
      readerText(source).replaceAll(inlineImage, '￼');

  static bool isStandaloneImageParagraph(String source) =>
      stripAllMarkers(source).trim().isEmpty;

  static String stripAllMarkers(String source) => source
      .replaceAll(heading, '')
      .replaceAll(quote, '')
      .replaceAll(center, '')
      .replaceAll(list, '')
      .replaceAll(inlineTag, '')
      .replaceAll(inlineImage, '');

  static double headingFontScale(int level) {
    switch (level) {
      case 1:
        return 1.5;
      case 2:
        return 1.3;
      case 3:
        return 1.16;
      case 4:
        return 1.08;
      default:
        return 1.04;
    }
  }

  static double headingLineHeight(int level) => switch (level) {
    1 => 1.22,
    2 => 1.28,
    _ => 1.35,
  };
}
