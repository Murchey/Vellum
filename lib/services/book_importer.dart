import 'dart:typed_data';

import 'book_models.dart';
import 'epub_decoder.dart';
import 'html_text_pipeline.dart';
import 'mobi_decoder.dart';
import 'txt_catalog.dart';
import 'txt_seek_source.dart';

export 'book_models.dart';

class BookImporter {
  const BookImporter({
    this.pipeline = const HtmlTextPipeline(),
    this.mobi = const MobiDecoder(),
    this.epub = const EpubDecoder(),
  });

  final HtmlTextPipeline pipeline;
  final MobiDecoder mobi;
  final EpubDecoder epub;

  /// Fanqie caps TXT imports at 100 MB (`n1.r`); beyond that the book is
  /// unusable on a phone and risks OOM during decode.
  static const int maxTxtBytes = 100 * 1024 * 1024;

  /// Fanqie's bookshelf cap (`ILocalBookSizeConfig.size`, default 200).
  static const int maxBookCount = 200;

  BookFormat formatForFilename(String filename) {
    final normalized = filename.toLowerCase();
    if (normalized.endsWith('.epub')) return BookFormat.epub;
    if (normalized.endsWith('.mobi')) return BookFormat.mobi;
    if (normalized.endsWith('.txt')) return BookFormat.txt;
    throw const BookImportException('仅支持 EPUB、MOBI 与 TXT 文件。');
  }

  ImportedBook decode({required String filename, required Uint8List bytes}) {
    final format = formatForFilename(filename);
    if (format == BookFormat.txt && bytes.length > maxTxtBytes) {
      throw const BookImportException('TXT 文件超过 100 MB，请先拆分后再导入。');
    }
    final book = switch (format) {
      BookFormat.txt => _decodeTxt(filename, bytes),
      BookFormat.epub => epub.decode(filename, bytes),
      BookFormat.mobi => mobi.decode(filename, bytes),
    };
    // Content-addressed id (Fanqie: bookId = 文件 MD5). Existing shelf entries
    // keep their persisted id; new imports get a stable content id so renames
    // and duplicate picks resolve to the same book.
    final contentId = BookLibraryIds.forBytes(bytes, format);
    return book.copyWith(id: contentId);
  }

  ImportedBook _decodeTxt(String filename, Uint8List bytes) {
    // Fanqie-style byte-offset catalog: 前言 naming, empty-chapter merge,
    // synthetic 第N章 when no titles exist, paragraph counts per chapter.
    final catalog = scanTxtCatalog(
      bytes,
      pipeline: pipeline,
      syntheticChapterBytes: 5000,
    );
    if (catalog.totalParagraphs <= 0) {
      throw const BookImportException('文件中没有可阅读的文字。');
    }
    return ImportedBook(
      title: pipeline.titleFromFilename(filename),
      format: BookFormat.txt,
      // Chapter-at-a-time lazy list; the reader sees a normal List<String>.
      paragraphs: InMemoryTxtParagraphList(bytes, catalog, pipeline: pipeline),
      tocEntries: [
        for (final entry in catalog.tocEntries)
          BookTocEntry(title: entry.value, paragraphIndex: entry.key),
      ],
      catalog: catalog,
      contentMode: 'seek',
    );
  }

  /// Re-runs catalog scan for a book whose TOC was synthesised (no titles
  /// recognised on first pass). Returns null when nothing better was found —
  /// the caller keeps the existing synthetic catalog.
  ImportedBook? refineTxtCatalog(ImportedBook book, Uint8List bytes) {
    if (book.format != BookFormat.txt) return null;
    final catalog = scanTxtCatalog(bytes, pipeline: pipeline);
    if (catalog.status != TxtCatalogStatus.ready) return null;
    if (catalog.totalParagraphs <= 0) return null;
    return book.copyWith(
      catalog: catalog,
      tocEntries: [
        for (final entry in catalog.tocEntries)
          BookTocEntry(title: entry.value, paragraphIndex: entry.key),
      ],
      paragraphs: InMemoryTxtParagraphList(bytes, catalog, pipeline: pipeline),
    );
  }
}
