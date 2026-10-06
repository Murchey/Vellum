import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/services/book_models.dart';
import 'package:vellum/services/widget_shelf.dart';

ImportedBook book(String id, String title) => ImportedBook(
  id: id,
  title: title,
  format: BookFormat.txt,
  paragraphs: const ['正文'],
);

void main() {
  test('current book is first and remaining shelf order is preserved', () {
    final snapshot = WidgetShelfSnapshot.fromBooks(
      books: [book('a', '甲'), book('b', '乙'), book('c', '丙')],
      progressById: const {'a': .1, 'b': .8, 'c': .3},
      currentBookId: 'b',
    );

    expect(snapshot.currentBookId, 'b');
    expect(snapshot.books.map((entry) => entry.id), ['b', 'a', 'c']);
    expect(snapshot.books.first.current, isTrue);
    expect(snapshot.books.first.progress, .8);
  });

  test('snapshot is capped at five books and clamps progress', () {
    final books = [for (var i = 0; i < 7; i++) book('$i', '书$i')];
    final snapshot = WidgetShelfSnapshot.fromBooks(
      books: books,
      progressById: const {'0': -1, '1': 2},
      currentBookId: 'missing',
    );

    expect(snapshot.books, hasLength(5));
    expect(snapshot.currentBookId, '0');
    expect(snapshot.books.first.progress, 0);
    expect(snapshot.books[1].progress, 1);
    expect(snapshot.books.first.current, isTrue);
  });

  test('empty shelf and JSON round trip are stable', () {
    const empty = WidgetShelfSnapshot();
    final decoded = WidgetShelfSnapshot.fromJson(
      jsonDecode(empty.encode()) as Map<String, dynamic>,
    );

    expect(decoded.version, 1);
    expect(decoded.currentBookId, isEmpty);
    expect(decoded.books, isEmpty);
  });

  test('fromJson clamps progress and limits entries', () {
    final decoded = WidgetShelfSnapshot.fromJson({
      'version': 1,
      'currentBookId': 'book',
      'books': [
        {'id': 'book', 'title': '书', 'progress': 1.5, 'current': true},
        {'id': 'other', 'title': '另一本', 'progress': -.2},
        for (var i = 0; i < 8; i++)
          {'id': 'extra$i', 'title': '额外$i', 'progress': .5},
      ],
    });

    expect(decoded.books, hasLength(5));
    expect(decoded.books.first.progress, 1);
    expect(decoded.books[1].progress, 0);
  });
}
