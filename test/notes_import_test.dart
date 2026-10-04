import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/services/notes_library.dart';
import 'package:vellum/services/notes_import.dart';

void main() {
  group('notes file parsing', () {
    test('reads a Vellum JSON export', () {
      const json = '''
[
  {"id":"n_1","bookId":"abc","bookTitle":"史记","paragraphIndex":12,
   "selectedText":"太史公曰","note":"好句","createdAt":"2024-05-01T10:00:00.000",
   "style":"note"}
]''';
      final result = parseNotesFile(content: json, fileName: 'vellum_notes.json');
      expect(result.format, 'json');
      expect(result.notes, hasLength(1));
      final note = result.notes.single;
      expect(note.selectedText, '太史公曰');
      expect(note.note, '好句');
      expect(note.paragraphIndex, 12);
      expect(note.bookId, 'abc');
      expect(note.bookTitle, '史记');
      expect(note.style, ReadingNoteStyle.note);
    });

    test('accepts foreign JSON keys and skips unusable rows', () {
      const json = '''
{"notes":[
  {"text":"划线内容","comment":"批注"},
  {"quote":"只有划线"},
  {"id":"nothing-useful"},
  "not an object"
]}''';
      final result = parseNotesFile(content: json, fileName: 'x.json');
      expect(result.notes, hasLength(2));
      expect(result.notes[0].selectedText, '划线内容');
      expect(result.notes[0].note, '批注');
      expect(result.notes[1].selectedText, '只有划线');
      expect(result.warning, contains('2 条'));
    });

    test('reads a Markdown file with a book heading', () {
      const text = '''
# 史记

> 太史公曰：余读谍记
很不错的一句

> 天下熙熙
皆为利来
''';
      final result = parseNotesFile(content: text, fileName: '史记-笔记.md');
      expect(result.format, 'text');
      expect(result.titleHint, '史记');
      expect(result.notes, hasLength(2));
      expect(result.notes[0].selectedText, '太史公曰：余读谍记');
      expect(result.notes[0].note, '很不错的一句');
      expect(result.notes[1].note, '皆为利来');
    });

    test('takes a quote line as a highlight even without a comment', () {
      final result = parseNotesFile(content: '> 只划一句\n', fileName: 'a.txt');
      expect(result.notes.single.selectedText, '只划一句');
      expect(result.notes.single.note, '');
      expect(result.notes.single.style, ReadingNoteStyle.highlight);
    });

    test('uses the file name as a title hint when the text has none', () {
      final result = parseNotesFile(
        content: '> 一句\n',
        fileName: '《资治通鉴》读书笔记.txt',
      );
      expect(result.titleHint, '资治通鉴');
    });

    test('an empty file yields a readable warning, not a crash', () {
      final result = parseNotesFile(content: '   \n  ', fileName: 'x.txt');
      expect(result.isEmpty, isTrue);
    });

    test('content that is not JSON falls back to the text parser', () {
      final result = parseNotesFile(
        content: '[这本不是 JSON 而是一行文字]\n> 划线',
        fileName: 'x.txt',
      );
      expect(result.format, 'text');
      expect(result.notes.single.selectedText, '划线');
    });
  });

  group('book matching', () {
    const library = [
      BookMatchCandidate(id: 'id-shiji', title: '史记'),
      BookMatchCandidate(id: 'id-24shi', title: '二十四史'),
      BookMatchCandidate(id: 'id-sanguo', title: '三国志'),
    ];

    test('matches by the storage id an export carried', () {
      final import = NotesImport(
        notes: [
          ImportedNote(selectedText: 'x', bookId: 'id-24shi', bookTitle: '别的名字'),
        ],
        titleHint: '别的名字',
        format: 'json',
      );
      final match = matchBooksForImport(books: library, import: import);
      expect(match.kind, BookMatchKind.id);
      expect(match.book!.title, '二十四史');
    });

    test('matches by an exact title after punctuation folding', () {
      final import = NotesImport(
        notes: [ImportedNote(selectedText: 'x')],
        titleHint: '《史记》',
        format: 'text',
      );
      final match = matchBooksForImport(books: library, import: import);
      expect(match.kind, BookMatchKind.title);
      expect(match.book!.id, 'id-shiji');
    });

    test('accepts a unique partial title', () {
      final import = NotesImport(
        notes: [ImportedNote(selectedText: 'x')],
        titleHint: '三国',
        format: 'text',
      );
      final match = matchBooksForImport(books: library, import: import);
      expect(match.book!.id, 'id-sanguo');
    });

    test('falls back to manual linking when nothing matches', () {
      final import = NotesImport(
        notes: [ImportedNote(selectedText: 'x')],
        titleHint: '不存在的书',
        format: 'text',
      );
      final match = matchBooksForImport(books: library, import: import);
      expect(match.isFallback, isTrue);
      expect(match.book, isNull);
      expect(match.reason, contains('不存在的书'));
    });

    test('ambiguous partial titles do not guess', () {
      const ambiguous = [
        BookMatchCandidate(id: 'a', title: '史记'),
        BookMatchCandidate(id: 'b', title: '史记集解'),
      ];
      final import = NotesImport(
        notes: [ImportedNote(selectedText: 'x')],
        titleHint: '史记',
        format: 'text',
      );
      // The exact title still wins over the ambiguous contains-match.
      final match = matchBooksForImport(books: ambiguous, import: import);
      expect(match.book!.id, 'a');

      final fuzzy = NotesImport(
        notes: [ImportedNote(selectedText: 'x')],
        titleHint: '史',
        format: 'text',
      );
      expect(
        matchBooksForImport(books: ambiguous, import: fuzzy).isFallback,
        isTrue,
      );
    });

    test('an empty library always asks the reader to choose', () {
      final import = NotesImport(
        notes: [ImportedNote(selectedText: 'x')],
        titleHint: '史记',
        format: 'text',
      );
      final match = matchBooksForImport(books: const [], import: import);
      expect(match.isFallback, isTrue);
    });
  });
}
