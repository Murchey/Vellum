import 'dart:io';
import 'dart:isolate' show TransferableTypedData;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;

import 'book_importer.dart';
import 'book_library.dart';

ImportedBook decodeBookInBackground(Map<String, dynamic> message) {
  final path = message['path'] as String?;
  final source = message['bytes'];
  final bytes = path != null
      ? File(path).readAsBytesSync()
      : (source as TransferableTypedData).materialize().asUint8List();
  return const BookImporter().decode(
    filename: message['filename'] as String,
    bytes: bytes,
  );
}

/// Picks an ebook file and decodes it off the UI isolate.
class BookImportService {
  const BookImportService();

  Future<ImportedBook?> pickAndDecode({
    void Function(String stage)? onStage,
  }) async {
    onStage?.call('正在打开文件选择器…');
    await Future<void>.delayed(Duration.zero);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub', 'mobi', 'txt'],
      withData: !Platform.isAndroid,
    );
    if (result == null) return null;
    final file = result.files.single;
    final path = file.path;
    final bytes = file.bytes;
    if (path == null && bytes == null) {
      throw const BookImportException(
        '文件提供方没有返回可读数据。请将 MOBI 复制到设备 Download 后重试。',
      );
    }
    onStage?.call('正在解析《${file.name}》…');
    await Future<void>.delayed(Duration.zero);
    return compute(decodeBookInBackground, <String, dynamic>{
      'filename': file.name,
      if (Platform.isAndroid && bytes != null)
        'bytes': TransferableTypedData.fromList([bytes])
      else if (path != null)
        'path': path
      else
        'bytes': TransferableTypedData.fromList([bytes!]),
    });
  }

  /// Replaces any same title+format entry and persists the library.
  Future<List<ImportedBook>> persistImported(
    BookLibrary library,
    List<ImportedBook> existing,
    ImportedBook book,
  ) async {
    final updatedBooks = <ImportedBook>[
      book,
      for (final item in existing)
        if (item.title != book.title || item.format != book.format) item,
    ];
    await library.save(updatedBooks);
    return updatedBooks;
  }
}
