import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'book_models.dart';

/// The small, rebuildable payload shared with the Android home-screen widget.
///
/// It intentionally contains book metadata and progress only. Book bodies,
/// notes, credentials, and backup data never cross the widget boundary.
class WidgetShelfBook {
  const WidgetShelfBook({
    required this.id,
    required this.title,
    required this.progress,
    required this.current,
  });

  final String id;
  final String title;
  final double progress;
  final bool current;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'progress': progress,
    'current': current,
  };

  factory WidgetShelfBook.fromJson(Map<String, dynamic> json) {
    final progress = (json['progress'] as num?)?.toDouble() ?? 0;
    return WidgetShelfBook(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      progress: progress.clamp(0.0, 1.0),
      current: json['current'] as bool? ?? false,
    );
  }
}

class WidgetShelfSnapshot {
  const WidgetShelfSnapshot({
    this.version = 1,
    this.currentBookId = '',
    this.books = const [],
  });

  static const maxBooks = 5;

  final int version;
  final String currentBookId;
  final List<WidgetShelfBook> books;

  /// Builds the display order without adding a timestamp to reading state.
  /// The current book is first; all remaining books retain shelf order.
  factory WidgetShelfSnapshot.fromBooks({
    required List<ImportedBook> books,
    required Map<String, double> progressById,
    String? currentBookId,
  }) {
    final requestedCurrent = currentBookId?.trim() ?? '';
    final current = books.where((book) => book.storageId == requestedCurrent);
    final ordered = <ImportedBook>[
      ...current,
      for (final book in books)
        if (book.storageId != requestedCurrent) book,
    ];
    final visible = ordered.take(maxBooks).toList(growable: false);
    final resolvedCurrent = visible.isEmpty
        ? ''
        : (visible.any((book) => book.storageId == requestedCurrent)
              ? requestedCurrent
              : visible.first.storageId);
    return WidgetShelfSnapshot(
      currentBookId: resolvedCurrent,
      books: [
        for (final book in visible)
          WidgetShelfBook(
            id: book.storageId,
            title: book.title.trim(),
            progress: (progressById[book.storageId] ?? 0).clamp(0.0, 1.0),
            current: book.storageId == resolvedCurrent,
          ),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'currentBookId': currentBookId,
    'books': [for (final book in books.take(maxBooks)) book.toJson()],
  };

  String encode() => jsonEncode(toJson());

  factory WidgetShelfSnapshot.fromJson(Map<String, dynamic> json) {
    final rawBooks = json['books'];
    final books = rawBooks is List
        ? [
            for (final value in rawBooks.take(maxBooks))
              if (value is Map<String, dynamic>)
                WidgetShelfBook.fromJson(value),
          ]
        : const <WidgetShelfBook>[];
    final requestedCurrent = json['currentBookId'] as String? ?? '';
    final resolvedCurrent = books.any((book) => book.id == requestedCurrent)
        ? requestedCurrent
        : (books.isEmpty ? '' : books.first.id);
    return WidgetShelfSnapshot(
      version: (json['version'] as num?)?.toInt() ?? 1,
      currentBookId: resolvedCurrent,
      books: [
        for (final book in books)
          WidgetShelfBook(
            id: book.id,
            title: book.title,
            progress: book.progress,
            current: book.id == resolvedCurrent,
          ),
      ],
    );
  }
}

/// Publishes a snapshot to Android. On other platforms this is a no-op so the
/// shelf model remains testable and the rest of the app stays platform-neutral.
class WidgetShelfSync {
  const WidgetShelfSync();

  static const channel = MethodChannel('vellum/device');

  Future<void> publish(WidgetShelfSnapshot snapshot) async {
    if (!Platform.isAndroid) return;
    try {
      await channel.invokeMethod<bool>('updateWidgetShelf', {
        'snapshot': snapshot.encode(),
      });
    } on MissingPluginException {
      // Desktop and older installs can run without the optional widget hook.
    } on PlatformException {
      // A stale or unavailable widget must never block reading or importing.
    }
  }
}
