import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/services/book_importer.dart';
import 'package:vellum/services/book_models.dart';

void main() {
  test(
    'book storage ids are unique per title and do not embed raw templates',
    () {
      final a = ImportedBook(
        title: '第一本',
        format: BookFormat.txt,
        paragraphs: List.filled(3, '段落'),
      );
      final b = ImportedBook(
        title: '第二本',
        format: BookFormat.txt,
        paragraphs: List.filled(5, '段落'),
      );

      expect(a.storageId, isNot(b.storageId));
      expect(a.storageId.contains(r'${'), isFalse);
      expect(
        BookLibraryIds.isLegacyBrokenId(r'${book.format.name}_abc'),
        isTrue,
      );
      expect(BookLibraryIds.isLegacyBrokenId(a.storageId), isFalse);
    },
  );
}
