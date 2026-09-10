
class FontPreferences {
  const FontPreferences({
    this.useForUi = false,
    this.useForContent = false,
    this.activeFont = '',
  });

  final bool useForUi;
  final bool useForContent;
  final String activeFont;
}

class InstalledFont {
  const InstalledFont({required this.name, required this.family});

  final String name;
  final String family;
}

class ReadingState {
  const ReadingState({
    this.fontSize = 19,
    this.readerFontFamily = 'Georgia',
    this.readerFontWeight = 'regular',
    this.lineSpacing = 'comfortable',
    this.backgroundValue,
    this.mode = 'scroll',
    this.position = 0,
    this.page = 0,
    this.paragraphIndex = 0,
    this.bookmarks = const [],
  });

  final double fontSize;
  final String readerFontFamily;
  final String readerFontWeight;
  final String lineSpacing;
  final int? backgroundValue;
  final String mode;
  final double position;
  final int page;
  final int paragraphIndex;
  final List<int> bookmarks;

  Map<String, dynamic> toJson() => {
    'fontSize': fontSize,
    'readerFontFamily': readerFontFamily,
    'readerFontWeight': readerFontWeight,
    'lineSpacing': lineSpacing,
    'backgroundValue': backgroundValue,
    'mode': mode,
    'position': position,
    'page': page,
    'paragraphIndex': paragraphIndex,
    'bookmarks': bookmarks,
  };

  factory ReadingState.fromJson(Map<String, dynamic> json) => ReadingState(
    fontSize: (json['fontSize'] as num?)?.toDouble() ?? 19,
    readerFontFamily: json['readerFontFamily'] as String? ?? 'Georgia',
    readerFontWeight: json['readerFontWeight'] as String? ?? 'regular',
    lineSpacing: json['lineSpacing'] as String? ?? 'comfortable',
    backgroundValue: (json['backgroundValue'] as num?)?.toInt(),
    mode: json['mode'] as String? ?? 'scroll',
    position: (json['position'] as num?)?.toDouble() ?? 0,
    page: (json['page'] as num?)?.toInt() ?? 0,
    paragraphIndex: (json['paragraphIndex'] as num?)?.toInt() ?? 0,
    bookmarks: (json['bookmarks'] as List<dynamic>? ?? [])
        .whereType<num>()
        .map((value) => value.toInt())
        .toList(),
  );
}

class StorageUsage {
  const StorageUsage({
    required this.libraryBytes,
    required this.readingStateBytes,
    required this.fontBytes,
  });

  final int libraryBytes;
  final int readingStateBytes;
  final int fontBytes;

  int get totalBytes => libraryBytes + readingStateBytes + fontBytes;
}
