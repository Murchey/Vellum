import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

enum WritingFormat {
  md('Markdown', 'md'),
  txt('纯文本', 'txt');

  const WritingFormat(this.label, this.extension);
  final String label;
  final String extension;

  static WritingFormat fromName(String value) =>
      WritingFormat.values.firstWhere(
        (format) => format.name == value,
        orElse: () => WritingFormat.md,
      );
}

class WritingDocument {
  const WritingDocument({
    required this.id,
    required this.title,
    required this.body,
    this.format = WritingFormat.md,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String body;
  final WritingFormat format;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get displayTitle => title.trim().isEmpty ? '未命名' : title.trim();

  String get preview {
    final text = body.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty) return '（空白文稿）';
    return text.length <= 80 ? text : '${text.substring(0, 80)}…';
  }

  int get characterCount => body.replaceAll('\r\n', '\n').length;

  int get wordCount {
    final text = body.trim();
    if (text.isEmpty) return 0;
    final cjkPattern = RegExp(r'[一-鿿㐀-䶿]');
    final cjk = cjkPattern.allMatches(text).length;
    final latin = text
        .replaceAll(cjkPattern, ' ')
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .length;
    return cjk + latin;
  }

  String get suggestedFileName {
    final trimmed = title.trim();
    final raw = trimmed.isEmpty ? '未命名文稿' : trimmed;
    final name = raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    final base = name.isEmpty ? '未命名文稿' : name;
    return '$base.${format.extension}';
  }

  WritingDocument copyWith({
    String? title,
    String? body,
    WritingFormat? format,
  }) => WritingDocument(
    id: id,
    title: title ?? this.title,
    body: body ?? this.body,
    format: format ?? this.format,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'format': format.name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory WritingDocument.fromJson(Map<String, dynamic> json) {
    final created =
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now();
    final updated =
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? created;
    return WritingDocument(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      format: WritingFormat.fromName(json['format'] as String? ?? 'md'),
      createdAt: created,
      updatedAt: updated,
    );
  }
}

/// Local draft library for the writing tab.
class WritingLibrary {
  const WritingLibrary();

  Future<List<WritingDocument>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return [];
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List<dynamic>) return [];
      final docs = <WritingDocument>[];
      for (final entry in raw) {
        if (entry is Map<String, dynamic>) {
          final doc = WritingDocument.fromJson(entry);
          if (doc.id.isNotEmpty) docs.add(doc);
        }
      }
      docs.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return docs;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveAll(List<WritingDocument> documents) async {
    final file = await _file();
    await file.writeAsString(
      jsonEncode([for (final doc in documents) doc.toJson()]),
      flush: true,
    );
  }

  Future<WritingDocument> create({
    String title = '',
    String body = '',
    WritingFormat format = WritingFormat.md,
  }) async {
    final now = DateTime.now();
    final doc = WritingDocument(
      id: 'w_${now.microsecondsSinceEpoch}',
      title: title,
      body: body,
      format: format,
      createdAt: now,
      updatedAt: now,
    );
    final docs = await load();
    docs.insert(0, doc);
    await saveAll(docs);
    return doc;
  }

  Future<WritingDocument> upsert(WritingDocument document) async {
    final docs = await load();
    final index = docs.indexWhere((item) => item.id == document.id);
    final next = document.copyWith();
    if (index >= 0) {
      docs[index] = next;
    } else {
      docs.insert(0, next);
    }
    docs.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await saveAll(docs);
    return next;
  }

  Future<void> delete(String id) async {
    final docs = await load();
    docs.removeWhere((item) => item.id == id);
    await saveAll(docs);
  }

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}${Platform.pathSeparator}vellum_writings.json');
  }
}
