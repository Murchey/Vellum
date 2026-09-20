
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

/// Global reader display preferences — shared across all books.
class ReaderPreferences {
  const ReaderPreferences({
    this.fontSize = 19,
    this.readerFontFamily = 'Georgia',
    this.readerFontWeight = 'regular',
    this.lineSpacing = 'comfortable',
    this.backgroundValue,
    this.mode = 'scroll',
    this.pageTurn = 'cover',
    this.brightness = -1,
    this.eyeCare = 'off',
    this.keepScreenOn = true,
    this.volumeKeys = false,
  });

  final double fontSize;
  final String readerFontFamily;
  final String readerFontWeight;
  final String lineSpacing;
  final int? backgroundValue;
  final String mode;
  final String pageTurn;

  /// Screen brightness override, `-1` follows the system.
  final double brightness;

  /// `off` / `soft` / `warm` warm-tint overlay strength.
  final String eyeCare;

  /// Keep the screen awake while the reader is open.
  final bool keepScreenOn;

  /// Volume buttons turn pages while the reader is open.
  final bool volumeKeys;

  Map<String, dynamic> toJson() => {
    'fontSize': fontSize,
    'readerFontFamily': readerFontFamily,
    'readerFontWeight': readerFontWeight,
    'lineSpacing': lineSpacing,
    'backgroundValue': backgroundValue,
    'mode': mode,
    'pageTurn': pageTurn,
    'brightness': brightness,
    'eyeCare': eyeCare,
    'keepScreenOn': keepScreenOn,
    'volumeKeys': volumeKeys,
  };

  factory ReaderPreferences.fromJson(Map<String, dynamic> json) =>
      ReaderPreferences(
        fontSize: (json['fontSize'] as num?)?.toDouble() ?? 19,
        readerFontFamily: json['readerFontFamily'] as String? ?? 'Georgia',
        readerFontWeight: json['readerFontWeight'] as String? ?? 'regular',
        lineSpacing: json['lineSpacing'] as String? ?? 'comfortable',
        backgroundValue: (json['backgroundValue'] as num?)?.toInt(),
        mode: json['mode'] as String? ?? 'scroll',
        pageTurn: json['pageTurn'] as String? ?? 'cover',
        brightness: (json['brightness'] as num?)?.toDouble() ?? -1,
        eyeCare: json['eyeCare'] as String? ?? 'off',
        keepScreenOn: json['keepScreenOn'] as bool? ?? true,
        volumeKeys: json['volumeKeys'] as bool? ?? false,
      );
}

class InstalledFont {
  const InstalledFont({
    required this.name,
    required this.family,
    this.displayName,
  });

  /// File key (without `.ttf`) used to load/delete the font file.
  final String name;
  final String family;

  /// Human-readable name from the font's internal `name` table.
  /// Falls back to [name] (filename) when unavailable.
  final String? displayName;

  String get label => (displayName?.isNotEmpty ?? false) ? displayName! : name;
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
    this.pageTurn = 'cover',
    this.bookId = '',
    this.brightness = -1,
    this.eyeCare = 'off',
    this.keepScreenOn = true,
    this.volumeKeys = false,
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

  /// `cover` or `none` — page turn animation style.
  final String pageTurn;

  /// Storage id of the book this state belongs to.
  final String bookId;

  /// Screen brightness override, `-1` follows the system.
  final double brightness;
  final String eyeCare;
  final bool keepScreenOn;
  final bool volumeKeys;

  ReadingState copyWith({String? bookId}) => ReadingState(
    fontSize: fontSize,
    readerFontFamily: readerFontFamily,
    readerFontWeight: readerFontWeight,
    lineSpacing: lineSpacing,
    backgroundValue: backgroundValue,
    mode: mode,
    position: position,
    page: page,
    paragraphIndex: paragraphIndex,
    bookmarks: bookmarks,
    pageTurn: pageTurn,
    bookId: bookId ?? this.bookId,
    brightness: brightness,
    eyeCare: eyeCare,
    keepScreenOn: keepScreenOn,
    volumeKeys: volumeKeys,
  );

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
    'pageTurn': pageTurn,
    'bookId': bookId,
    'brightness': brightness,
    'eyeCare': eyeCare,
    'keepScreenOn': keepScreenOn,
    'volumeKeys': volumeKeys,
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
    pageTurn: json['pageTurn'] as String? ?? 'cover',
    bookId: json['bookId'] as String? ?? '',
    brightness: (json['brightness'] as num?)?.toDouble() ?? -1,
    eyeCare: json['eyeCare'] as String? ?? 'off',
    keepScreenOn: json['keepScreenOn'] as bool? ?? true,
    volumeKeys: json['volumeKeys'] as bool? ?? false,
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


class LibraryFolder {
  const LibraryFolder({required this.id, required this.name});
  final String id;
  final String name;
}
