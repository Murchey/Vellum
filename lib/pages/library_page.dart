import 'package:flutter/cupertino.dart';

import '../services/book_importer.dart';
import 'book_widgets.dart';

class LibraryPage extends StatelessWidget {
  final List<ImportedBook> books;
  final ValueChanged<ImportedBook> onOpen;
  final VoidCallback onImport;
  final ValueChanged<ImportedBook> onDelete;
  const LibraryPage({
    required this.books,
    required this.onOpen,
    required this.onImport,
    required this.onDelete,
    super.key,
  });
  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: CupertinoNavigationBar(
      middle: const Text('书库'),
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: onImport,
        child: const Icon(CupertinoIcons.add),
      ),
    ),
    child: SafeArea(
      child: books.isEmpty
          ? EmptyLibrary(onImport: onImport)
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 20,
                childAspectRatio: .62,
              ),
              itemCount: books.length,
              itemBuilder: (context, index) => BookGridCard(
                book: books[index],
                onTap: () => onOpen(books[index]),
                onDelete: () => onDelete(books[index]),
              ),
            ),
    ),
  );
}
