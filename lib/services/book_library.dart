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
  'coverText': book.coverText,
  'folderId': book.folderId,
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
  coverText: data['coverText'] as String?,
  folderId: data['folderId'] as String?,
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
      List<ImportedBook> books;
      if (raw.isNotEmpty && raw.first is Map<String, dynamic>) {
        final first = raw.first as Map<String, dynamic>;
        if (first.containsKey('paragraphs')) {
          books = [
            for (final entry in raw)
              _decodeBookContent(entry as Map<String, dynamic>),
          ];
          books = _ensureUniqueBookIds(books);
          await save(books);
          return [for (final book in books) book.asIndexShell()];
        }
      }
      books = [
        for (final entry in raw)
          _decodeIndexEntry(entry as Map<String, dynamic>),
      ];
      final repaired = _ensureUniqueBookIds(books);
      if (!_sameBookIds(books, repaired)) {
        await (await _file()).writeAsString(
          await compute(_encodeLibraryIndex, repaired),
          flush: true,
        );
      }
      return repaired;
    } catch (_) {
      return [];
    }
  }

  bool _sameBookIds(List<ImportedBook> a, List<ImportedBook> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].storageId != b[i].storageId) return false;
    }
    return true;
  }

  /// Repairs ids from the broken interpolation era and any accidental
  /// collisions so each shelf item maps to its own content file.
  List<ImportedBook> _ensureUniqueBookIds(List<ImportedBook> books) {
    final seen = <String>{};
    final result = <ImportedBook>[];
    for (final book in books) {
      final id = book.id;
      final usable =
          id != null && id.isNotEmpty && !BookLibraryIds.isLegacyBrokenId(id);
      if (usable && seen.add(id)) {
        result.add(book);
        continue;
      }
      final base = BookLibraryIds.forBook(book);
      var candidate = base;
      var suffix = 1;
      while (!seen.add(candidate)) {
        candidate = '${base}_$suffix';
        suffix++;
      }
      result.add(book.copyWith(id: candidate));
    }
    return result;
  }

  Future<ImportedBook> loadBookContent(ImportedBook book) async {
    if (book.hasContentLoaded) return book;
    final file = await _bookContentFile(book.storageId);
    if (await file.exists()) {
      try {
        final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final full = _decodeBookContent(data);
        // Content files do not carry shelf cover; keep the index shell's cover.
        return full.copyWith(
          coverBytes: book.coverBytes,
          coverText: book.coverText,
          folderId: book.folderId,
        );
      } catch (_) {}
    }
    return book;
  }

  /// Updates only the shelf cover (image and/or text) and rewrites the index.
  Future<void> updateBookCover(
    ImportedBook book, {
    Uint8List? coverBytes,
    String? coverText,
    bool clearCoverImage = false,
    bool clearCoverText = false,
  }) async {
    final updated = book.copyWith(
      coverBytes: coverBytes,
      coverText: coverText,
      clearCoverImage: clearCoverImage,
      clearCoverText: clearCoverText,
    );
    final books = await load();
    final next = <ImportedBook>[
      for (final item in books)
        item.storageId == updated.storageId ? updated : item,
    ];
    if (!next.any((item) => item.storageId == updated.storageId)) {
      next.insert(0, updated);
    }
    // Rewrite index without loading every book body.
    await (await _file()).writeAsString(
      await compute(_encodeLibraryIndex, next),
      flush: true,
    );
  }

  Future<List<LibraryFolder>> loadFolders() async {
    final file = await _foldersFile();
    if (!await file.exists()) return const [];
    try {
      final raw = jsonDecode(await file.readAsString()) as List<dynamic>;
      return [
        for (final entry in raw)
          LibraryFolder(
            id: entry['id'] as String,
            name: entry['name'] as String,
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<LibraryFolder> createFolder(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const BookImportException('文件夹名称不能为空。');
    }
    final folders = await loadFolders();
    final folder = LibraryFolder(
      id: 'f_${DateTime.now().microsecondsSinceEpoch}',
      name: trimmed,
    );
    await _writeFolders([...folders, folder]);
    return folder;
  }

  Future<void> renameFolder(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final folders = await loadFolders();
    await _writeFolders([
      for (final folder in folders)
        if (folder.id == id)
          LibraryFolder(id: folder.id, name: trimmed)
        else
          folder,
    ]);
  }

  Future<void> deleteFolder(String id) async {
    final folders = await loadFolders();
    await _writeFolders([
      for (final folder in folders)
        if (folder.id != id) folder,
    ]);
    final books = await load();
    final next = <ImportedBook>[
      for (final book in books)
        if (book.folderId == id) book.copyWith(clearFolder: true) else book,
    ];
    await (await _file()).writeAsString(
      await compute(_encodeLibraryIndex, next),
      flush: true,
    );
  }

  Future<void> setBookFolder(
    ImportedBook book,
    String? folderId,
  ) async {
    final updated = folderId == null
        ? book.copyWith(clearFolder: true)
        : book.copyWith(folderId: folderId);
    final books = await load();
    final next = <ImportedBook>[
      for (final item in books)
        item.storageId == updated.storageId ? updated : item,
    ];
    if (!next.any((item) => item.storageId == updated.storageId)) {
      next.insert(0, updated);
    }
    await (await _file()).writeAsString(
      await compute(_encodeLibraryIndex, next),
      flush: true,
    );
  }

  Future<void> _writeFolders(List<LibraryFolder> folders) async {
    await (await _foldersFile()).writeAsString(
      jsonEncode([
        for (final folder in folders)
          {'id': folder.id, 'name': folder.name},
      ]),
      flush: true,
    );
  }

  /// Empty string means the built-in default update repository.
  Future<String> loadUpdateRepository() async {
    final file = await _updateRepoFile();
    if (!await file.exists()) return '';
    try {
      final raw = (await file.readAsString()).trim();
      return raw;
    } catch (_) {
      return '';
    }
  }

  Future<void> saveUpdateRepository(String repository) async {
    await (await _updateRepoFile()).writeAsString(repository.trim(), flush: true);
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
    final prefs = await loadReaderPreferences();
    final file = await _stateFile();
    if (!await file.exists()) {
      return ReadingState(
        fontSize: prefs.fontSize,
        readerFontFamily: prefs.readerFontFamily,
        readerFontWeight: prefs.readerFontWeight,
        lineSpacing: prefs.lineSpacing,
        backgroundValue: prefs.backgroundValue,
        mode: prefs.mode,
        pageTurn: prefs.pageTurn,
      ).copyWith(bookId: book.storageId);
    }
    try {
      final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final value = raw[_key(book)];
      // Display settings are global; only progress/bookmarks stay per book.
      if (value is! Map<String, dynamic>) {
        return ReadingState(
          fontSize: prefs.fontSize,
          readerFontFamily: prefs.readerFontFamily,
          readerFontWeight: prefs.readerFontWeight,
          lineSpacing: prefs.lineSpacing,
          backgroundValue: prefs.backgroundValue,
          mode: prefs.mode,
          pageTurn: prefs.pageTurn,
        ).copyWith(bookId: book.storageId);
      }
      final saved = ReadingState.fromJson(value);
      return ReadingState(
        fontSize: prefs.fontSize,
        readerFontFamily: prefs.readerFontFamily,
        readerFontWeight: prefs.readerFontWeight,
        lineSpacing: prefs.lineSpacing,
        backgroundValue: prefs.backgroundValue,
        mode: prefs.mode,
        pageTurn: prefs.pageTurn,
        position: saved.position,
        page: saved.page,
        paragraphIndex: saved.paragraphIndex,
        bookmarks: saved.bookmarks,
        bookId: book.storageId,
      );
    } catch (_) {
      return ReadingState(
        fontSize: prefs.fontSize,
        readerFontFamily: prefs.readerFontFamily,
        readerFontWeight: prefs.readerFontWeight,
        lineSpacing: prefs.lineSpacing,
        backgroundValue: prefs.backgroundValue,
        mode: prefs.mode,
        pageTurn: prefs.pageTurn,
      ).copyWith(bookId: book.storageId);
    }
  }

  Future<void> saveReadingState(ImportedBook book, ReadingState state) async {
    await saveReaderPreferences(
      ReaderPreferences(
        fontSize: state.fontSize,
        readerFontFamily: state.readerFontFamily,
        readerFontWeight: state.readerFontWeight,
        lineSpacing: state.lineSpacing,
        backgroundValue: state.backgroundValue,
        mode: state.mode,
        pageTurn: state.pageTurn,
      ),
    );
    final file = await _stateFile();
    Map<String, dynamic> states = {};
    if (await file.exists()) {
      try {
        states = (jsonDecode(await file.readAsString()) as Map<String, dynamic>);
      } catch (_) {
        states = {};
      }
    }
    // Progress only — display prefs live in the shared preferences file.
    states[_key(book)] = {
      'position': state.position,
      'page': state.page,
      'paragraphIndex': state.paragraphIndex,
      'bookmarks': state.bookmarks,
      'bookId': book.storageId,
    };
    await file.writeAsString(jsonEncode(states));
  }

  Future<ReaderPreferences> loadReaderPreferences() async {
    try {
      final file = await _prefsFile();
      if (!await file.exists()) return const ReaderPreferences();
      final raw = jsonDecode(await file.readAsString());
      if (raw is Map<String, dynamic>) return ReaderPreferences.fromJson(raw);
    } catch (_) {}
    return const ReaderPreferences();
  }

  Future<void> saveReaderPreferences(ReaderPreferences prefs) async {
    final file = await _prefsFile();
    await file.writeAsString(jsonEncode(prefs.toJson()), flush: true);
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

  Future<File> _prefsFile() async => File(
    '${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}vellum_reader_prefs.json',
  );

  Future<File> _foldersFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(
      '${dir.path}${Platform.pathSeparator}vellum_folders.json',
    );
  }

  Future<File> _updateRepoFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(
      '${dir.path}${Platform.pathSeparator}vellum_update_repo.txt',
    );
  }
}
