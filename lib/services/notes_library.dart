import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// `note` keeps a written thought, `highlight` only marks the passage — both
/// render as a highlight in the body, the difference is the comment.
enum ReadingNoteStyle {
  note('笔记'),
  highlight('划线');

  const ReadingNoteStyle(this.label);
  final String label;

  static ReadingNoteStyle fromStorage(String value) =>
      ReadingNoteStyle.values.firstWhere(
        (style) => style.name == value,
        orElse: () => ReadingNoteStyle.note,
      );
}

/// Storage id carried by imported notes whose book could not be identified.
///
/// They are kept rather than dropped, so nothing the reader imported is lost;
/// opening one offers to link it to a book.
const String unmatchedBookId = 'unassociated';

/// Title shown for those notes, in the reader's note list and in the library.
const String unmatchedBookTitle = '未关联笔记';

class ReadingNote {
  const ReadingNote({
    required this.id,
    required this.bookId,
    required this.bookTitle,
    required this.paragraphIndex,
    required this.selectedText,
    this.note = '',
    required this.createdAt,
    this.style = 'note',
  });

  final String id;
  final String bookId;
  final String bookTitle;
  final int paragraphIndex;
  final String selectedText;
  final String note;
  final DateTime createdAt;
  final String style;

  ReadingNoteStyle get kind => ReadingNoteStyle.fromStorage(style);

  Map<String, dynamic> toJson() => {
    'id': id,
    'bookId': bookId,
    'bookTitle': bookTitle,
    'paragraphIndex': paragraphIndex,
    'selectedText': selectedText,
    'note': note,
    'createdAt': createdAt.toIso8601String(),
    'style': style,
  };

  factory ReadingNote.fromJson(Map<String, dynamic> json) {
    final created =
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now();
    return ReadingNote(
      id: json['id'] as String? ?? '',
      bookId: json['bookId'] as String? ?? '',
      bookTitle: json['bookTitle'] as String? ?? '',
      paragraphIndex: (json['paragraphIndex'] as num?)?.toInt() ?? 0,
      selectedText: json['selectedText'] as String? ?? '',
      note: json['note'] as String? ?? '',
      createdAt: created,
      style: json['style'] as String? ?? 'note',
    );
  }
}

/// Local notes created from reader text selection.
class NotesLibrary {
  const NotesLibrary();

  /// Reads every note. Overridden in tests with an in-memory store.
  Future<List<ReadingNote>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const [];
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List<dynamic>) return const [];
      final notes = <ReadingNote>[
        for (final entry in raw)
          if (entry is Map<String, dynamic>) ReadingNote.fromJson(entry),
      ];
      notes.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return notes;
    } catch (_) {
      return const [];
    }
  }

  /// Writes every note. Overridden in tests with an in-memory store.
  Future<void> saveAll(List<ReadingNote> notes) async {
    final file = await _file();
    await file.writeAsString(
      jsonEncode([for (final note in notes) note.toJson()]),
      flush: true,
    );
  }

  Future<ReadingNote> add({
    required String bookId,
    required String bookTitle,
    required int paragraphIndex,
    required String selectedText,
    String note = '',
    ReadingNoteStyle style = ReadingNoteStyle.note,
  }) async {
    final now = DateTime.now();
    final item = ReadingNote(
      id: 'n_${now.microsecondsSinceEpoch}',
      bookId: bookId,
      bookTitle: bookTitle,
      paragraphIndex: paragraphIndex,
      selectedText: selectedText,
      note: note,
      createdAt: now,
      style: style.name,
    );
    final notes = await load();
    notes.insert(0, item);
    await saveAll(notes);
    return item;
  }

  /// Notes and highlights belonging to one book, newest first.
  Future<List<ReadingNote>> loadForBook(String bookId) async {
    final notes = await load();
    return [
      for (final note in notes)
        if (note.bookId == bookId) note,
    ];
  }

  Future<void> updateNote(String id, String note) async {
    final notes = await load();
    for (var i = 0; i < notes.length; i++) {
      if (notes[i].id == id) {
        notes[i] = _copy(notes[i], noteText: note);
        break;
      }
    }
    await saveAll(notes);
  }

  /// Re-points a note at another book.
  ///
  /// Imported notes whose book could not be identified are stored against
  /// [unmatchedBookId]; this is how the reader links them afterwards.
  Future<void> updateBook(
    String id, {
    required String bookId,
    required String bookTitle,
  }) async {
    final notes = await load();
    for (var i = 0; i < notes.length; i++) {
      if (notes[i].id == id) {
        notes[i] = _copy(notes[i], bookId: bookId, bookTitle: bookTitle);
        break;
      }
    }
    await saveAll(notes);
  }

  static ReadingNote _copy(
    ReadingNote note, {
    String? noteText,
    String? bookId,
    String? bookTitle,
  }) => ReadingNote(
    id: note.id,
    bookId: bookId ?? note.bookId,
    bookTitle: bookTitle ?? note.bookTitle,
    paragraphIndex: note.paragraphIndex,
    selectedText: note.selectedText,
    note: noteText ?? note.note,
    createdAt: note.createdAt,
    style: note.style,
  );

  Future<void> delete(String id) async {
    final notes = await load();
    notes.removeWhere((n) => n.id == id);
    await saveAll(notes);
  }

  /// Writes all notes as pretty JSON to [outputPath].
  Future<File> exportTo(String outputPath) async {
    final notes = await load();
    const encoder = JsonEncoder.withIndent('  ');
    final file = File(outputPath);
    final parent = file.parent;
    if (!await parent.exists()) await parent.create(recursive: true);
    await file.writeAsString(
      encoder.convert([for (final n in notes) n.toJson()]),
      encoding: utf8,
      flush: true,
    );
    return file;
  }

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}${Platform.pathSeparator}vellum_notes.json');
  }
}
