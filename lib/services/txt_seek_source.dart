import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'html_text_pipeline.dart';
import 'txt_catalog.dart';

/// Chapter-at-a-time text cache backed by a seekable TXT source file.
///
/// Fanqie's model: `TxtParser.getContent(idx, startOffset, byteLength)` reads
/// one chapter via seek. [TxtParagraphList] exposes that as a `List<String>`
/// so the existing reader (`book.paragraphs[i]`) keeps working unchanged,
/// while only the chapters actually touched are decoded.
class TxtSeekSource {
  TxtSeekSource({
    required this.file,
    required this.catalog,
    this.pipeline = const HtmlTextPipeline(),
    this.cacheLimit = 4,
  });

  final File file;
  final TxtCatalog catalog;
  final HtmlTextPipeline pipeline;

  /// How many decoded chapters to keep (current ± neighbours is enough).
  final int cacheLimit;

  RandomAccessFile? _raf;
  final Map<int, List<String>> _chapterParagraphs = {};
  final List<int> _lru = [];

  int get chapterCount => catalog.chapters.length;

  /// Decoded paragraphs of one chapter (cached).
  List<String> chapterParagraphs(int chapterIndex) {
    final cached = _chapterParagraphs[chapterIndex];
    if (cached != null) {
      _touch(chapterIndex);
      return cached;
    }
    final chapter = catalog.chapters[chapterIndex];
    final text = readChapterText(chapter);
    final paragraphs = text.isEmpty
        ? const <String>[]
        : pipeline.splitParagraphs(text);
    _store(chapterIndex, paragraphs);
    return paragraphs;
  }

  /// Seeks to [TxtChapterRef.startOffset] and decodes [byteLength] bytes.
  String readChapterText(TxtChapterRef chapter) {
    if (chapter.byteLength <= 0) return '';
    final raf = _raf ??= file.openSync();
    raf.setPositionSync(chapter.startOffset);
    final raw = raf.readSync(chapter.byteLength);
    if (raw.isEmpty) return '';
    return decodeTxtWithEncoding(Uint8List.fromList(raw), catalog.encoding);
  }

  void _store(int chapterIndex, List<String> paragraphs) {
    _chapterParagraphs[chapterIndex] = paragraphs;
    _touch(chapterIndex);
    while (_lru.length > cacheLimit) {
      final evict = _lru.removeAt(0);
      if (evict != chapterIndex) _chapterParagraphs.remove(evict);
    }
  }

  void _touch(int chapterIndex) {
    _lru.remove(chapterIndex);
    _lru.add(chapterIndex);
  }

  void close() {
    _raf?.closeSync();
    _raf = null;
    _chapterParagraphs.clear();
    _lru.clear();
  }
}

/// A `List<String>` view over a [TxtSeekSource].
///
/// Drop-in replacement for `ImportedBook.paragraphs` on seek-mode TXT books:
/// `length` is O(1) from the catalog; `operator []` seeks and decodes only the
/// chapter that owns the paragraph.
class TxtParagraphList extends ListBase<String> {
  TxtParagraphList(this.source);

  final TxtSeekSource source;
  final Map<int, int> _chapterStart = {};

  TxtCatalog get catalog => source.catalog;

  @override
  int get length => catalog.totalParagraphs;

  @override
  set length(int newLength) {
    throw UnsupportedError('TXT seek paragraphs are read-only');
  }

  int paragraphStartOf(int chapterIndex) {
    return _chapterStart.putIfAbsent(chapterIndex, () {
      return catalog.paragraphStartOf(chapterIndex);
    });
  }

  @override
  String operator [](int index) {
    if (index < 0 || index >= length) {
      throw RangeError.index(index, this, 'index');
    }
    final chapter = catalog.chapterForParagraph(index);
    final start = paragraphStartOf(chapter.index);
    final local = index - start;
    final paragraphs = source.chapterParagraphs(chapter.index);
    if (local < 0 || local >= paragraphs.length) {
      // Catalog drift (file edited after import): degrade gracefully.
      return paragraphs.isEmpty
          ? ''
          : paragraphs[local.clamp(0, paragraphs.length - 1)];
    }
    return paragraphs[local];
  }

  @override
  void operator []=(int index, String value) {
    throw UnsupportedError('TXT seek paragraphs are read-only');
  }

  /// Materialise the whole book (only used by export / tests).
  List<String> materialize() {
    final all = <String>[];
    for (var i = 0; i < catalog.chapters.length; i++) {
      all.addAll(source.chapterParagraphs(i));
    }
    return all;
  }
}

/// Wraps raw bytes + catalog into a paragraph list without a file on disk
/// (used right after import, before the source file is persisted).
///
/// Decodes chapter-at-a-time on demand, so a large TXT import never has to
/// hold the fully decoded book in memory at once.
class InMemoryTxtParagraphList extends ListBase<String> {
  InMemoryTxtParagraphList(
    this.bytes,
    this.catalog, {
    this.pipeline = const HtmlTextPipeline(),
  });

  final Uint8List bytes;
  final TxtCatalog catalog;
  final HtmlTextPipeline pipeline;
  final Map<int, List<String>> _cache = {};

  List<String> _decodeChapter(TxtChapterRef chapter) {
    if (chapter.byteLength <= 0) return const [];
    final end = chapter.startOffset + chapter.byteLength;
    if (chapter.startOffset >= bytes.length) return const [];
    final safeEnd = end > bytes.length ? bytes.length : end;
    final text = decodeTxtWithEncoding(
      Uint8List.sublistView(bytes, chapter.startOffset, safeEnd),
      catalog.encoding,
    );
    return text.isEmpty ? const [] : pipeline.splitParagraphs(text);
  }

  List<String> _chapterParagraphs(int chapterIndex) =>
      _cache.putIfAbsent(chapterIndex, () {
        return _decodeChapter(catalog.chapters[chapterIndex]);
      });

  @override
  int get length => catalog.totalParagraphs;

  @override
  set length(int newLength) {
    throw UnsupportedError('TXT paragraphs are read-only');
  }

  @override
  String operator [](int index) {
    if (index < 0 || index >= length) {
      throw RangeError.index(index, this, 'index');
    }
    final chapter = catalog.chapterForParagraph(index);
    final local = index - catalog.paragraphStartOf(chapter.index);
    final paragraphs = _chapterParagraphs(chapter.index);
    if (paragraphs.isEmpty) return '';
    return paragraphs[local.clamp(0, paragraphs.length - 1)];
  }

  @override
  void operator []=(int index, String value) {
    throw UnsupportedError('TXT paragraphs are read-only');
  }

  /// Materialise the whole book (export / tests only).
  List<String> materialize() {
    final all = <String>[];
    for (var i = 0; i < catalog.chapters.length; i++) {
      all.addAll(_chapterParagraphs(i));
    }
    return all;
  }
}
