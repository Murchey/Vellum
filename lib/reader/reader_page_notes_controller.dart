import '../services/notes_library.dart';

/// Owns the note and highlight data used by a reader session.
///
/// The controller deliberately has no Flutter context. The page state decides
/// when to rebuild and remains responsible for presenting note sheets and
/// transient notices.
class ReaderNotesController {
  ReaderNotesController({
    required this.bookId,
    required this.bookTitle,
    this.library = const NotesLibrary(),
  });

  final String bookId;
  final String bookTitle;
  final NotesLibrary library;

  List<ReadingNote> notes = const [];
  Map<int, List<String>> highlights = const {};

  Future<void> load() async {
    final loaded = await library.loadForBook(bookId);
    notes = loaded;
    highlights = _groupHighlights(loaded);
  }

  int noteCountFor(int paragraphIndex) => notes
      .where((note) => note.paragraphIndex == paragraphIndex)
      .length;

  List<ReadingNote> notesForParagraph(int paragraphIndex) => [
    for (final note in notes)
      if (note.paragraphIndex == paragraphIndex) note,
  ];

  Future<bool> toggleHighlight(String selected, int paragraphIndex) async {
    final value = selected.trim();
    if (value.isEmpty) return false;
    final existing = [
      for (final note in notes)
        if (note.paragraphIndex == paragraphIndex &&
            note.selectedText == value)
          note,
    ];
    if (existing.isNotEmpty) {
      await library.delete(existing.first.id);
      await load();
      return false;
    }
    await library.add(
      bookId: bookId,
      bookTitle: bookTitle,
      paragraphIndex: paragraphIndex,
      selectedText: value,
      style: ReadingNoteStyle.highlight,
    );
    await load();
    return true;
  }

  Future<void> removeNote(String id) async {
    await library.delete(id);
    notes = [for (final note in notes) if (note.id != id) note];
    highlights = _groupHighlights(notes);
  }

  static Map<int, List<String>> _groupHighlights(List<ReadingNote> values) {
    final grouped = <int, List<String>>{};
    for (final note in values) {
      if (note.selectedText.isEmpty) continue;
      (grouped[note.paragraphIndex] ??= []).add(note.selectedText);
    }
    return grouped;
  }
}
