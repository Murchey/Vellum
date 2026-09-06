import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:path_provider/path_provider.dart';

import 'book_importer.dart';

String _encodeBooksForStorage(List<ImportedBook> books) => jsonEncode(
  books
      .map(
        (book) => {
          'title': book.title,
          'format': book.format.name,
          'paragraphs': book.paragraphs,
          'cover': book.coverBytes == null
              ? null
              : base64Encode(book.coverBytes!),
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
        },
      )
      .toList(),
);

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

  Future<List<ImportedBook>> load() async {
    final file = await _file();
    if (!await file.exists()) return [];
    try {
      final raw = jsonDecode(await file.readAsString()) as List<dynamic>;
      return raw.map((entry) {
        final data = entry as Map<String, dynamic>;
        return ImportedBook(
          title: data['title'] as String,
          format: BookFormat.values.byName(data['format'] as String),
          paragraphs: (data['paragraphs'] as List<dynamic>).cast<String>(),
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
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<ImportedBook> books) async {
    final file = await _file();
    final encoded = await compute(_encodeBooksForStorage, books);
    await file.writeAsString(encoded, flush: true);
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
    final files = await Future.wait([_file(), _stateFile(), _fontFile()]);
    final sizes = await Future.wait<int>(
      files.map((file) async => await file.exists() ? await file.length() : 0),
    );
    return StorageUsage(
      libraryBytes: sizes[0],
      readingStateBytes: sizes[1],
      fontBytes: sizes[2],
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
