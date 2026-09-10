import 'dart:typed_data';

import 'book_models.dart';
import 'epub_decoder.dart';
import 'html_text_pipeline.dart';
import 'mobi_decoder.dart';

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

  BookFormat formatForFilename(String filename) {
    final normalized = filename.toLowerCase();
    if (normalized.endsWith('.epub')) return BookFormat.epub;
    if (normalized.endsWith('.mobi')) return BookFormat.mobi;
    if (normalized.endsWith('.txt')) return BookFormat.txt;
    throw const BookImportException('仅支持 EPUB、MOBI 与 TXT 文件。');
  }

  ImportedBook decode({required String filename, required Uint8List bytes}) {
    switch (formatForFilename(filename)) {
      case BookFormat.txt:
        return _decodeTxt(filename, bytes);
      case BookFormat.epub:
        return epub.decode(filename, bytes);
      case BookFormat.mobi:
        return mobi.decode(filename, bytes);
    }
  }

  ImportedBook _decodeTxt(String filename, Uint8List bytes) {
    final paragraphs = pipeline.splitParagraphs(
      pipeline.decodePlainText(bytes),
    );
    if (paragraphs.isEmpty) {
      throw const BookImportException('文件中没有可阅读的文字。');
    }
    return ImportedBook(
      title: pipeline.titleFromFilename(filename),
      format: BookFormat.txt,
      paragraphs: paragraphs,
    );
  }
}
