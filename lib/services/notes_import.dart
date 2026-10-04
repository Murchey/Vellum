import 'dart:convert';

import 'book_models.dart';
import 'notes_library.dart';

/// One note read out of an imported file, before it is tied to a book.
class ImportedNote {
  ImportedNote({
    required this.selectedText,
    this.note = '',
    this.paragraphIndex = 0,
    this.bookTitle = '',
    this.bookId = '',
    this.createdAt,
    this.style = ReadingNoteStyle.note,
  });

  /// Passage the note is attached to.
  String selectedText;

  /// The reader's own words.
  String note;

  /// Paragraph recorded by an earlier Vellum export; 0 when unknown.
  int paragraphIndex;

  /// Book name carried by the file (a header, or an exported [ReadingNote]).
  String bookTitle;

  /// Storage id carried by an earlier Vellum export, when present.
  String bookId;

  DateTime? createdAt;
  ReadingNoteStyle style;
}

/// Result of reading a notes file.
class NotesImport {
  const NotesImport({
    required this.notes,
    required this.titleHint,
    required this.format,
    this.warning = '',
  });

  final List<ImportedNote> notes;

  /// Book name the file itself claims, used to preselect a match.
  final String titleHint;

  /// `json` or `text`, for the confirmation copy.
  final String format;

  /// Set when the file was readable but something had to be skipped.
  final String warning;

  bool get isEmpty => notes.isEmpty;
}

/// Reads a Vellum notes export (JSON) or free-form text/Markdown into notes.
///
/// Nothing here touches the library or the disk beyond the given text, so the
/// whole import decision path is testable.
NotesImport parseNotesFile({required String content, String fileName = ''}) {
  final trimmed = content.trim();
  if (trimmed.isEmpty) {
    return const NotesImport(notes: [], titleHint: '', format: 'text');
  }
  final structured = _tryParseJson(trimmed, fileName);
  if (structured != null) return structured;
  return _parseText(content, fileName);
}

NotesImport? _tryParseJson(String content, String fileName) {
  if (!content.startsWith('[') && !content.startsWith('{')) return null;
  dynamic raw;
  try {
    raw = jsonDecode(content);
  } catch (_) {
    // Not JSON after all: fall through to the text parser.
    return null;
  }
  final entries = switch (raw) {
    List<dynamic>() => raw,
    Map<String, dynamic>() when raw['notes'] is List<dynamic> =>
      raw['notes'] as List<dynamic>,
    Map<String, dynamic>() when raw['items'] is List<dynamic> =>
      raw['items'] as List<dynamic>,
    _ => null,
  };
  if (entries == null) return null;

  final notes = <ImportedNote>[];
  var skipped = 0;
  for (final entry in entries) {
    if (entry is! Map<String, dynamic>) {
      skipped++;
      continue;
    }
    final note = _fromJsonEntry(entry);
    if (note == null) {
      skipped++;
      continue;
    }
    notes.add(note);
  }
  final hint = _titleHintFromJson(raw) ?? _titleHintFromFileName(fileName);
  return NotesImport(
    notes: notes,
    titleHint: hint,
    format: 'json',
    warning: skipped > 0 ? '有 $skipped 条记录无法识别，已跳过。' : '',
  );
}

ImportedNote? _fromJsonEntry(Map<String, dynamic> entry) {
  final selected = _firstString(entry, const [
    'selectedText',
    'text',
    'quote',
    'excerpt',
    'content',
    'highlight',
  ]);
  final note = _firstString(entry, const ['note', 'comment', 'remark', 'body']);
  // A note with neither a passage nor a comment carries nothing to import.
  if ((selected == null || selected.trim().isEmpty) &&
      (note == null || note.trim().isEmpty)) {
    return null;
  }
  return ImportedNote(
    selectedText: selected?.trim() ?? '',
    note: note?.trim() ?? '',
    paragraphIndex: _firstInt(entry, const [
      'paragraphIndex',
      'paragraph',
      'index',
      'para',
    ]),
    bookTitle: _firstString(entry, const ['bookTitle', 'book', 'title']) ?? '',
    bookId: _firstString(entry, const ['bookId', 'book_id']) ?? '',
    createdAt: _firstDate(entry),
    style: ReadingNoteStyle.fromStorage(
      _firstString(entry, const ['style', 'kind', 'type']) ?? 'note',
    ),
  );
}

/// Plain text / Markdown import.
///
/// Accepts what a reader would actually paste or export from another app:
///
/// ```text
/// # 书名
/// > 被划线的句子
/// 自己的批注
///
/// 第二段划线
/// ```
///
/// A `#` heading names the book (the first one wins), a line starting with `>`
/// or `「` starts a new entry, and the lines after it become the note.
NotesImport _parseText(String content, String fileName) {
  final lines = const LineSplitter().convert(content);
  final notes = <ImportedNote>[];
  String? titleHint;

  String? selected;
  final pending = <String>[];

  void flush() {
    final quote = selected?.trim() ?? '';
    final note = pending.join('\n').trim();
    if (quote.isEmpty && note.isEmpty) {
      selected = null;
      pending.clear();
      return;
    }
    notes.add(
      ImportedNote(
        selectedText: quote,
        note: note,
        style: quote.isEmpty
            ? ReadingNoteStyle.note
            : ReadingNoteStyle.highlight,
      ),
    );
    selected = null;
    pending.clear();
  }

  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      // A blank line ends a note only when it already has a passage.
      if (selected != null) flush();
      continue;
    }
    if (_isHeading(line)) {
      flush();
      final title = line.replaceFirst(RegExp(r'^#+\s*'), '').trim();
      if (title.isNotEmpty && titleHint == null) titleHint = title;
      continue;
    }
    if (_isQuote(line)) {
      flush();
      selected = _stripQuote(line);
      continue;
    }
    if (selected == null) {
      // Text before any quote: the first line is a plausible book name.
      if (titleHint == null && _looksLikeBookTitle(line)) {
        titleHint = line;
        continue;
      }
      // Otherwise treat it as a standalone comment.
      selected = '';
    }
    pending.add(line);
  }
  flush();

  return NotesImport(
    notes: notes,
    titleHint: titleHint ?? _titleHintFromFileName(fileName),
    format: 'text',
    warning: notes.isEmpty ? '没有识别到可导入的笔记内容。' : '',
  );
}

bool _isHeading(String line) =>
    line.startsWith('#') || line.startsWith('==') || line.startsWith('【书名');

bool _isQuote(String line) {
  const markers = ['>', '「', '“', '"', '- ', '* ', '· '];
  return markers.any((marker) => line.startsWith(marker));
}

String _stripQuote(String line) {
  var value = line;
  for (final marker in ['>', '「', '“', '"', '- ', '* ', '· ']) {
    if (value.startsWith(marker)) {
      value = value.substring(marker.length);
      break;
    }
  }
  value = value.trim();
  if (value.endsWith('」')) value = value.substring(0, value.length - 1);
  if (value.endsWith('”') || value.endsWith('"')) {
    value = value.substring(0, value.length - 1);
  }
  return value.trim();
}

/// Heuristic: a short line with no sentence punctuation, before any content.
bool _looksLikeBookTitle(String line) {
  if (line.length > 40) return false;
  if (line.endsWith('。') || line.contains('，') || line.contains('：')) {
    return false;
  }
  return !line.startsWith('- ');
}

String? _titleHintFromJson(dynamic raw) {
  if (raw is Map<String, dynamic>) {
    final title = _firstString(raw, const ['bookTitle', 'book', 'title']);
    if (title != null && title.trim().isNotEmpty) return title.trim();
  }
  return null;
}

/// `《书名》的笔记.md` / `书名-notes.json` → `书名`.
String _titleHintFromFileName(String fileName) {
  if (fileName.isEmpty) return '';
  var name = fileName.split(RegExp(r'[\\/]')).last;
  name = name.replaceFirst(RegExp(r'\.[A-Za-z0-9]+$'), '');
  name = name.replaceAll(RegExp(r'[《》]'), '');
  name = name.replaceAll(
    RegExp(r'[-_ ]*(notes?|笔记|划线|摘录|标注|读书笔记)$', caseSensitive: false),
    '',
  );
  return name.trim();
}

String? _firstString(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is String && value.trim().isNotEmpty) return value;
  }
  return null;
}

int _firstInt(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null) return parsed;
    }
  }
  return 0;
}

DateTime? _firstDate(Map<String, dynamic> map) {
  for (final key in const ['createdAt', 'created_at', 'time', 'date']) {
    final value = map[key];
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
  }
  return null;
}

/// A book the imported notes could belong to.
class BookMatchCandidate {
  const BookMatchCandidate({required this.id, required this.title});

  final String id;
  final String title;
}

/// How the imported notes were tied to a book.
enum BookMatchKind {
  /// An exported note carried the book's storage id.
  id,

  /// The file's title hint or the notes' own title matched a shelf book.
  title,

  /// Nothing matched; the notes are kept and can be linked by hand.
  unmatched,
}

class BookMatch {
  const BookMatch({required this.kind, this.book, required this.reason});

  final BookMatchKind kind;
  final BookMatchCandidate? book;

  /// Short, user-facing explanation of the decision.
  final String reason;

  bool get isFallback => kind == BookMatchKind.unmatched;
}

/// Picks the shelf book an imported file belongs to.
///
/// Order: exported storage id → exact title (hint, then the notes' own title) →
/// normalised title → unique contains-match. Anything else falls back to
/// [BookMatchKind.unmatched] rather than guessing, and the caller then asks the
/// reader to pick.
BookMatch matchBooksForImport({
  required List<BookMatchCandidate> books,
  required NotesImport import,
  String fileName = '',
}) {
  if (books.isEmpty) {
    return const BookMatch(
      kind: BookMatchKind.unmatched,
      reason: '书库还是空的，先导入这本书再关联笔记。',
    );
  }

  final ids = {for (final note in import.notes) note.bookId};
  ids.removeWhere((id) => id.isEmpty);
  for (final id in ids) {
    for (final book in books) {
      if (book.id == id) {
        return BookMatch(
          kind: BookMatchKind.id,
          book: book,
          reason: '按导出记录中的书籍 ID 匹配到《${book.title}》',
        );
      }
    }
  }

  final titles = <String>[
    import.titleHint,
    for (final note in import.notes)
      if (note.bookTitle.isNotEmpty) note.bookTitle,
  ].where((title) => title.trim().isNotEmpty).toList();

  for (final title in titles) {
    final target = normalizeBookTitle(title);
    if (target.isEmpty) continue;
    for (final book in books) {
      if (normalizeBookTitle(book.title) == target) {
        return BookMatch(
          kind: BookMatchKind.title,
          book: book,
          reason: '书名「$title」匹配到《${book.title}》',
        );
      }
    }
  }

  for (final title in titles) {
    final target = normalizeBookTitle(title);
    if (target.length < 2) continue;
    final contains = [
      for (final book in books)
        if (normalizeBookTitle(book.title).contains(target) ||
            target.contains(normalizeBookTitle(book.title)))
          book,
    ];
    if (contains.length == 1) {
      return BookMatch(
        kind: BookMatchKind.title,
        book: contains.single,
        reason: '书名「$title」只有《${contains.single.title}》相近',
      );
    }
  }

  final hint = import.titleHint.isNotEmpty
      ? '「${import.titleHint}」'
      : (fileName.isEmpty ? '' : '「$fileName」');
  return BookMatch(
    kind: BookMatchKind.unmatched,
    reason: hint.isEmpty
        ? '没能确认这些笔记属于哪本书，请手动选择。'
        : '$hint 没能在书库中找到对应的书，请手动选择或先导入这本书。',
  );
}

/// Book-name form used for matching: punctuation, spaces and case folded away,
/// so 《史记》 and "史记" compare equal.
String normalizeBookTitle(String title) {
  var value = title.toLowerCase();
  // Character-by-character rather than one dense regexp: easier to see exactly
  // which punctuation is ignored.
  const ignorable = ' \t\n\r《》〈〉（）()[]【】「」“”"\'·:：,，.。-_—、';
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    if (ignorable.contains(char)) continue;
    buffer.write(char);
  }
  value = buffer.toString();
  value = value.replaceAll(
    RegExp(r'(全[0-9一二三四五六七八九十]*[册卷本集]|txt|epub|mobi)$', caseSensitive: false),
    '',
  );
  return value;
}

/// Writes imported notes into the library.
///
/// [book] is null only when the reader chose to keep them unassociated; the
/// notes are still saved, so nothing the reader imported is ever dropped.
Future<int> saveImportedNotes({
  required NotesLibrary library,
  required List<ImportedNote> notes,
  BookMatchCandidate? book,
  DateTime? importedAt,
}) async {
  final existing = await library.load();
  final now = importedAt ?? DateTime.now();
  final bookId = book?.id ?? unmatchedBookId;
  final bookTitle = book?.title ?? unmatchedBookTitle;
  var next = 0;
  for (final note in notes) {
    if (note.selectedText.trim().isEmpty && note.note.trim().isEmpty) continue;
    existing.insert(
      0,
      ReadingNote(
        id: 'n_${now.microsecondsSinceEpoch}_$next',
        bookId: bookId,
        bookTitle: bookTitle,
        paragraphIndex: note.paragraphIndex < 0 ? 0 : note.paragraphIndex,
        selectedText: note.selectedText.trim(),
        note: note.note.trim(),
        createdAt: note.createdAt ?? now,
        style: note.style.name,
      ),
    );
    next++;
  }
  await library.saveAll(existing);
  return next;
}

/// Titles of the books currently in the library, for the manual picker.
List<BookMatchCandidate> exportableBooks(List<ImportedBook> books) => [
  for (final book in books)
    BookMatchCandidate(id: book.storageId, title: book.title),
];
