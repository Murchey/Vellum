import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:path_provider/path_provider.dart';

import 'book_importer.dart';

Map<String, dynamic> _bookContentJson(ImportedBook book) => {
  'id': book.storageId,
  'title': book.title,
  'format': book.format.name,
  'paragraphs': book.paragraphs,
  'linkTargets': book.linkTargets.map(
    (source, target) => MapEntry(source.toString(), target),
  ),
  'tocEntries': book.tocEntries
      .map(
        (entry) => {
          'title': entry.title,
          'paragraphIndex': entry.paragraphIndex,
        },
      )
      .toList(),
  'imageBytes': book.imageBytes.map(
    (index, bytes) => MapEntry(index.toString(), base64Encode(bytes)),
  ),
};

Map<String, dynamic> _bookIndexJson(ImportedBook book) => {
  'id': book.storageId,
  'title': book.title,
  'format': book.format.name,
  'paragraphCount': book.paragraphCount,
  'cover': book.coverBytes == null ? null : base64Encode(book.coverBytes!),
};

String _encodeLibraryIndex(List<ImportedBook> books) =>
    jsonEncode([for (final book in books) _bookIndexJson(book)]);

String _encodeBookContent(ImportedBook book) =>
    jsonEncode(_bookContentJson(book));

ImportedBook _decodeIndexEntry(Map<String, dynamic> data) => ImportedBook(
  id: data['id'] as String?,
  title: data['title'] as String,
  format: BookFormat.values.byName(data['format'] as String),
  paragraphs: const [],
  metaParagraphCount: (data['paragraphCount'] as num?)?.toInt() ?? 0,
  coverBytes: data['cover'] == null
      ? null
      : Uint8List.fromList(base64Decode(data['cover'] as String)),
);

ImportedBook _decodeBookContent(Map<String, dynamic> data) {
  final paragraphs = (data['paragraphs'] as List<dynamic>? ?? [])
      .cast<String>();
  return ImportedBook(
    id: data['id'] as String?,
    title: data['title'] as String,
    format: BookFormat.values.byName(data['format'] as String),
    paragraphs: paragraphs,
    coverBytes: data['cover'] == null
        ? null
        : Uint8List.fromList(base64Decode(data['cover'] as String)),
    linkTargets: (data['linkTargets'] as Map<String, dynamic>? ?? {}).map(
      (key, value) => MapEntry(int.parse(key), value as int),
    ),
    tocEntries: (data['tocEntries'] as List<dynamic>? ?? [])
        .map(
          (entry) => BookTocEntry(
            title: (entry as Map<String, dynamic>)['title'] as String,
            paragraphIndex: entry['paragraphIndex'] as int,
          ),
        )
        .toList(),
    imageBytes: (data['imageBytes'] as Map<String, dynamic>? ?? {}).map(
      (key, value) => MapEntry(
        int.parse(key),
        Uint8List.fromList(base64Decode(value as String)),
      ),
    ),
  );
}

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

class BookLibrary {
  const BookLibrary();

  /// Loads lightweight index shells. Full text is loaded via [loadBookContent].
  Future<List<ImportedBook>> load() async {
    final file = await _file();
    if (!await file.exists()) return [];
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List<dynamic>) return [];

      // Legacy format: one array containing full books. Migrate once.
      if (raw.isNotEmpty && raw.first is Map<String, dynamic>) {
        final first = raw.first as Map<String, dynamic>;
        if (first.containsKey('paragraphs')) {
          final books = [
            for (final entry in raw)
              _decodeBookContent(entry as Map<String, dynamic>),
          ];
          await save(books);
          return [for (final book in books) book.asIndexShell()];
        }
      }

      return [
        for (final entry in raw)
          _decodeIndexEntry(entry as Map<String, dynamic>),
      ];
    } catch (_) {
      return [];
    }
  }

  /// Loads full reading content for one book. Falls back to index shell data.
  Future<ImportedBook> loadBookContent(ImportedBook book) async {
    if (book.hasContentLoaded) return book;
    final file = await _bookContentFile(book.storageId);
    if (await file.exists()) {
      try {
        final data =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        return _decodeBookContent(data);
      } catch (_) {
        // Fall through to empty shell below.
      }
    }
    return book;
  }

  Future<void> save(List<ImportedBook> books) async {
    final directory = await _booksDir();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final fullBooks = <ImportedBook>[];
    for (final book in books) {
      fullBooks.add(book.hasContentLoaded ? book : await loadBookContent(book));
    }

    // Persist each book body separately so app start only parses the index.
    await Future.wait([
      for (final book in fullBooks)
        () async {
          final file = await _bookContentFile(book.storageId);
          final encoded = await compute(_encodeBookContent, book);
          await file.writeAsString(encoded, flush: true);
        }(),
    ]);

    final index = await compute(_encodeLibraryIndex, fullBooks);
    await (await _file()).writeAsString(index, flush: true);
  }

  Future<void> deleteBook(ImportedBook book) async {
    final content = await _bookContentFile(book.storageId);
    if (await content.exists()) await content.delete();
  }

  Future<ReadingState> loadReadingState(ImportedBook book) async {
    final file = await _stateFile();
    if (!await file.exists()) return const ReadingState();
    try {
      final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final value = raw[_key(book)];
      return value is Map<String, dynamic>
          ? ReadingState.fromJson(value)
          : const ReadingState();
    } catch (_) {
      return const ReadingState();
    }
  }

  Future<void> saveReadingState(ImportedBook book, ReadingState state) async {
    final file = await _stateFile();
    Map<String, dynamic> states = {};
    if (await file.exists()) {
      try {
        states =
            (jsonDecode(await file.readAsString()) as Map<String, dynamic>);
      } catch (_) {
        states = {};
      }
    }
    states[_key(book)] = state.toJson();
    await file.writeAsString(jsonEncode(states));
  }

  Future<void> deleteReadingState(ImportedBook book) async {
    final file = await _stateFile();
    if (!await file.exists()) return;
    try {
      final states =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      states.remove(_key(book));
      await file.writeAsString(jsonEncode(states));
    } catch (_) {
      // A corrupted state file will be overwritten by the next save.
    }
  }

  Future<Uint8List?> loadFont() async {
    final file = await _fontFile();
    if (!await file.exists()) return null;
    return Uint8List.fromList(await file.readAsBytes());
  }

  Future<void> saveFont(Uint8List bytes) async {
    final file = await _fontFile();
    await file.writeAsBytes(bytes, flush: true);
  }

  Future<StorageUsage> storageUsage() async {
    final directory = await _booksDir();
    var libraryBytes = 0;
    if (await directory.exists()) {
      await for (final entity in directory.list()) {
        if (entity is File) libraryBytes += await entity.length();
      }
    }
    final index = await _file();
    if (await index.exists()) libraryBytes += await index.length();
    final stateFile = await _stateFile();
    final fontFile = await _fontFile();
    return StorageUsage(
      libraryBytes: libraryBytes,
      readingStateBytes: await stateFile.exists() ? await stateFile.length() : 0,
      fontBytes: await fontFile.exists() ? await fontFile.length() : 0,
    );
  }

  Future<File> exportAsTxt(ImportedBook book) async {
    final directory = Directory(
      '${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}vellum_exports',
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    final safeTitle = book.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final file = File(
      '${directory.path}${Platform.pathSeparator}$safeTitle.txt',
    );
    final marker = RegExp(r'^\[\[vellum-(?:heading:[1-6]|quote|list)\]\]+');
    final image = RegExp(r'\[\[image:\d+\]\]');
    final text = book.paragraphs
        .map(
          (paragraph) =>
              paragraph.replaceFirst(marker, '').replaceAll(image, '').trim(),
        )
        .where((paragraph) => paragraph.isNotEmpty)
        .join('\n\n');
    await file.writeAsString(text, encoding: utf8, flush: true);
    return file;
  }

  Future<void> clearBooks() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
    final directory = await _booksDir();
    if (await directory.exists()) {
      await for (final entity in directory.list()) {
        if (entity is File) await entity.delete();
      }
    }
  }

  Future<void> clearReadingStates() async {
    final file = await _stateFile();
    if (await file.exists()) await file.delete();
  }

  Future<FontPreferences> loadFontPreferences() async {
    final file = await _fontPreferencesFile();
    if (!await file.exists()) return const FontPreferences();
    try {
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return FontPreferences(
        useForUi: data['useForUi'] as bool? ?? false,
        useForContent: data['useForContent'] as bool? ?? false,
        activeFont: data['activeFont'] as String? ?? '',
      );
    } catch (_) {
      return const FontPreferences();
    }
  }

  Future<void> saveFontPreferences(FontPreferences preferences) async {
    final file = await _fontPreferencesFile();
    await file.writeAsString(
      jsonEncode({
        'useForUi': preferences.useForUi,
        'useForContent': preferences.useForContent,
        'activeFont': preferences.activeFont,
      }),
    );
  }

  Future<List<InstalledFont>> listFonts() async {
    final dir = await _fontsDir();
    if (!await dir.exists()) return [];

    final fonts = <InstalledFont>[];
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.ttf')) {
        final name = entity.uri.pathSegments.last.replaceAll('.ttf', '');
        final family = 'Font_${name.hashCode.abs()}';
        fonts.add(InstalledFont(name: name, family: family));
      }
    }
    return fonts;
  }

  Future<void> saveFontWithName(String name, Uint8List bytes) async {
    final dir = await _fontsDir();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File('${dir.path}${Platform.pathSeparator}$name.ttf');
    await file.writeAsBytes(bytes, flush: true);
  }

  Future<Uint8List?> loadFontByName(String name) async {
    final dir = await _fontsDir();
    final file = File('${dir.path}${Platform.pathSeparator}$name.ttf');
    if (!await file.exists()) return null;
    return Uint8List.fromList(await file.readAsBytes());
  }

  Future<void> deleteFontByName(String name) async {
    final dir = await _fontsDir();
    final file = File('${dir.path}${Platform.pathSeparator}$name.ttf');
    if (await file.exists()) await file.delete();
  }

  Future<void> clearFont() async {
    final file = await _fontFile();
    if (await file.exists()) await file.delete();
  }

  String _key(ImportedBook book) => '${book.format.name}:${book.title}';

  Future<Directory> _booksDir() async => Directory(
    '${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}vellum_books',
  );

  Future<File> _bookContentFile(String id) async {
    final dir = await _booksDir();
    final safe = id.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    return File('${dir.path}${Platform.pathSeparator}$safe.json');
  }

  Future<File> _file() async => File(
    '${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}vellum_library.json',
  );

  Future<File> _stateFile() async => File(
    '${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}vellum_reading_state.json',
  );

  Future<File> _fontPreferencesFile() async => File(
    '${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}vellum_font_preferences.json',
  );

  Future<File> _fontFile() async => File(
    '${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}vellum_font.ttf',
  );

  Future<Directory> _fontsDir() async => Directory(
    '${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}vellum_fonts',
  );
}
