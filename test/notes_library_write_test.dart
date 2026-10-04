import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/reader_selection.dart';
import 'package:vellum/services/notes_library.dart';

/// A store that always fails to write, to prove the failure is not silent.
class _FailingStore extends NotesLibrary {
  const _FailingStore();

  @override
  Future<List<ReadingNote>> load() async => const [];

  @override
  Future<void> saveAll(List<ReadingNote> notes) async {
    throw const FileSystemException('磁盘写入失败');
  }
}

/// Writing notes into a store that has no notes yet.
///
/// The real store read `const []` before the first note existed, and `add`
/// inserted into that list: every reader's first note threw
/// `Cannot add to an unmodifiable list`, the composer swallowed the error and
/// closed, and the note was never written.
class _EmptyReadOnlyStore extends NotesLibrary {
  final List<ReadingNote> written = [];

  @override
  Future<List<ReadingNote>> load() async => const [];

  @override
  Future<void> saveAll(List<ReadingNote> notes) async {
    written
      ..clear()
      ..addAll(notes);
  }
}

/// A store that echoes a read-only view of what it holds, like the real one.
class _ReadOnlyViewStore extends NotesLibrary {
  final List<ReadingNote> written = [];

  @override
  Future<List<ReadingNote>> load() async => List.unmodifiable(written);

  @override
  Future<void> saveAll(List<ReadingNote> notes) async {
    written
      ..clear()
      ..addAll(notes);
  }
}

void main() {
  test('the first note can be written into an empty store', () async {
    final store = _EmptyReadOnlyStore();
    final note = await store.add(
      bookId: 'book-1',
      bookTitle: '测试书',
      paragraphIndex: 4,
      selectedText: '太祖本纪',
      note: '批注',
    );

    expect(note.paragraphIndex, 4);
    expect(store.written, hasLength(1));
    expect(store.written.single.selectedText, '太祖本纪');
    expect(store.written.single.note, '批注');
  });

  test('a second note appends to the existing ones', () async {
    final store = _ReadOnlyViewStore();
    await store.add(
      bookId: 'book-1',
      bookTitle: '测试书',
      paragraphIndex: 1,
      selectedText: 'a',
    );
    await store.add(
      bookId: 'book-1',
      bookTitle: '测试书',
      paragraphIndex: 2,
      selectedText: 'b',
    );

    expect(store.written, hasLength(2));
    // Newest first, like the note lists expect.
    expect(store.written.first.selectedText, 'b');
    expect(store.written.last.selectedText, 'a');
  });

  test('a highlight can be written into an empty store', () async {
    final store = _EmptyReadOnlyStore();
    await store.add(
      bookId: 'book-1',
      bookTitle: '测试书',
      paragraphIndex: 2,
      selectedText: '划线内容',
      style: ReadingNoteStyle.highlight,
    );

    expect(store.written.single.style, ReadingNoteStyle.highlight.name);
  });

  test('deleting from a read-only view does not throw', () async {
    final store = _ReadOnlyViewStore();
    await store.add(
      bookId: 'book-1',
      bookTitle: '测试书',
      paragraphIndex: 1,
      selectedText: 'a',
    );
    final id = store.written.single.id;

    await store.delete(id);
    expect(store.written, isEmpty);
  });

  test('the real library reports note kinds', () {
    final note = ReadingNote(
      id: 'n1',
      bookId: 'b',
      bookTitle: '书',
      paragraphIndex: 0,
      selectedText: 'x',
      createdAt: DateTime(2024),
    );
    expect(note.kind, ReadingNoteStyle.note);
  });

  testWidgets('a failed save says so instead of closing silently', (
    tester,
  ) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: Builder(
            builder: (context) => Center(
              child: CupertinoButton(
                onPressed: () => showAddNoteSheet(
                  context,
                  bookId: 'book-1',
                  bookTitle: '测试书',
                  paragraphIndex: 1,
                  selectedText: '太祖本纪',
                  notesLibrary: const _FailingStore(),
                ),
                child: const Text('添加笔记'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('添加笔记'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField), '写点什么');
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('保存失败'),
      findsOneWidget,
      reason: 'the reader must see that the note was not written',
    );
    // And their text is still there to retry.
    expect(find.text('写点什么'), findsOneWidget);
  });
}
