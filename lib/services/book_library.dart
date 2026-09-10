import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:path_provider/path_provider.dart';

import 'book_importer.dart';
import 'font_storage.dart';
import 'library_models.dart';

export 'font_storage.dart';
export 'library_models.dart';

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
  final paragraphs = (data['paragraphs'] as List<dynamic>? ?? []).cast<String>();
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

class BookLibrary {
  const BookLibrary({this.fonts = const FontStorage()});

  final FontStorage fonts;

  Future<List<ImportedBook>> load() async {
    final file = await _file();
    if (!await file.exists()) return [];
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List<dynamic>) return [];
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

  Future<ImportedBook> loadBookContent(ImportedBook book) async {
    if (book.hasContentLoaded) return book;
    final file = await _bookContentFile(book.storageId);
    if (await file.exists()) {
      try {
        final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        return _decodeBookContent(data);
      } catch (_) {}
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
        states = (jsonDecode(await file.readAsString()) as Map<String, dynamic>);
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
      final states = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      states.remove(_key(book));
      await file.writeAsString(jsonEncode(states));
    } catch (_) {}
  }

  Future<Uint8List?> loadFont() => fonts.loadFont();
  Future<void> saveFont(Uint8List bytes) => fonts.saveFont(bytes);

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
    final fontFile = await fonts.fontFile();
    return StorageUsage(
      libraryBytes: libraryBytes,
      readingStateBytes: await stateFile.exists() ? await stateFile.length() : 0,
      fontBytes: await fontFile.exists() ? await fontFile.length() : 0,
    );
  }

  String bookAsPlainText(ImportedBook book) {
    final marker = RegExp(
      r'^\[\[vellum-(?:heading:[1-6]|quote|list|center)\]\]+',
    );
    final image = RegExp(r'\[\[image:\d+\]\]');
    final inline = RegExp(r'\[\[/?[biu]\]\]');
    return book.paragraphs
        .map(
          (paragraph) => paragraph
              .replaceFirst(marker, '')
              .replaceAll(image, '')
              .replaceAll(inline, '')
              .trim(),
        )
        .where((paragraph) => paragraph.isNotEmpty)
        .join('\n\n');
  }

  String suggestedTxtFilename(ImportedBook book) {
    final safeTitle = book.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return safeTitle.isEmpty ? 'book.txt' : '$safeTitle.txt';
  }

  Future<File> exportAsTxt(ImportedBook book, {String? outputPath}) async {
    final text = bookAsPlainText(book);
    if (outputPath != null && outputPath.isNotEmpty) {
      final file = File(outputPath);
      final parent = file.parent;
      if (!await parent.exists()) await parent.create(recursive: true);
      await file.writeAsString(text, encoding: utf8, flush: true);
      return file;
    }
    final directory = Directory(
      '${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}vellum_exports',
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    final file = File(
      '${directory.path}${Platform.pathSeparator}${suggestedTxtFilename(book)}',
    );
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

  Future<FontPreferences> loadFontPreferences() =>
      fonts.loadFontPreferences();
  Future<void> saveFontPreferences(FontPreferences preferences) =>
      fonts.saveFontPreferences(preferences);
  Future<List<InstalledFont>> listFonts() => fonts.listFonts();
  Future<void> saveFontWithName(String name, Uint8List bytes) =>
      fonts.saveFontWithName(name, bytes);
  Future<Uint8List?> loadFontByName(String name) =>
      fonts.loadFontByName(name);
  Future<void> deleteFontByName(String name) =>
      fonts.deleteFontByName(name);
  Future<void> clearFont() => fonts.clearFont();

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
}
