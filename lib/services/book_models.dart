import 'dart:typed_data';

enum BookFormat { epub, mobi, txt }

class BookTocEntry {
  const BookTocEntry({required this.title, required this.paragraphIndex});
  final String title;
  final int paragraphIndex;
}

class BookImportException implements Exception {
  const BookImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ImportedBook {
  const ImportedBook({
    required this.title,
    required this.format,
    required this.paragraphs,
    this.coverBytes,
    this.coverText,
    this.folderId,
    this.linkTargets = const {},
    this.tocEntries = const [],
    this.imageBytes = const {},
    this.metaParagraphCount,
    this.id,
  });
  final String title;
  final BookFormat format;
  final List<String> paragraphs;
  final Uint8List? coverBytes;
  final String? coverText;
  final String? folderId;
  final Map<int, int> linkTargets;
  final List<BookTocEntry> tocEntries;
  final Map<int, Uint8List> imageBytes;
  final int? metaParagraphCount;
  final String? id;
  bool get hasContentLoaded =>
      paragraphs.isNotEmpty || (metaParagraphCount ?? 0) == 0;
  int get paragraphCount =>
      paragraphs.isNotEmpty ? paragraphs.length : (metaParagraphCount ?? 0);
  String get storageId => id ?? BookLibraryIds.forBook(this);

  ImportedBook copyWith({
    Uint8List? coverBytes,
    String? coverText,
    String? folderId,
    bool clearCoverImage = false,
    bool clearCoverText = false,
    bool clearFolder = false,
  }) => ImportedBook(
    id: id,
    title: title,
    format: format,
    paragraphs: paragraphs,
    coverBytes: clearCoverImage ? null : (coverBytes ?? this.coverBytes),
    coverText: clearCoverText ? null : (coverText ?? this.coverText),
    folderId: clearFolder ? null : (folderId ?? this.folderId),
    linkTargets: linkTargets,
    tocEntries: tocEntries,
    imageBytes: imageBytes,
    metaParagraphCount: metaParagraphCount,
  );

  ImportedBook asIndexShell() => ImportedBook(
    id: storageId,
    title: title,
    format: format,
    paragraphs: const [],
    coverBytes: coverBytes,
    coverText: coverText,
    folderId: folderId,
    metaParagraphCount: paragraphCount,
    tocEntries: tocEntries.take(32).toList(),
  );
}

abstract final class BookLibraryIds {
  static String forBook(ImportedBook book) {
    final parts = [book.format.name, book.title, '\${book.paragraphCount}'];
    final source = parts.join(String.fromCharCode(0));
    var hash = 0x811c9dc5;
    for (final unit in source.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return '\${book.format.name}_\${hash.toRadixString(16)}';
  }
}

class HtmlContent {
  const HtmlContent({
    required this.paragraphs,
    required this.anchors,
    required this.links,
    required this.images,
  });
  final List<String> paragraphs;
  final Map<String, int> anchors;
  final Map<int, String> links;
  final Map<int, int> images;
}
