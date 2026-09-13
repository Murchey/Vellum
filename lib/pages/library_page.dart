import 'package:flutter/cupertino.dart';

import '../services/book_importer.dart';
import '../services/library_models.dart';
import '../theme/vellum_theme.dart';
import 'book_widgets.dart';

class LibraryPage extends StatefulWidget {
  final List<ImportedBook> books;
  final List<LibraryFolder> folders;
  final ValueChanged<ImportedBook> onOpen;
  final VoidCallback onImport;
  final ValueChanged<ImportedBook> onDelete;
  final ValueChanged<ImportedBook>? onEditCover;
  final Future<void> Function(ImportedBook, String? folderId)?
  onMoveToFolder;
  final Future<void> Function(String name)? onCreateFolder;
  final Future<void> Function(String folderId)? onDeleteFolder;
  final Future<void> Function(String folderId, String name)? onRenameFolder;

  const LibraryPage({
    required this.books,
    required this.onOpen,
    required this.onImport,
    required this.onDelete,
    this.folders = const [],
    this.onEditCover,
    this.onMoveToFolder,
    this.onCreateFolder,
    this.onDeleteFolder,
    this.onRenameFolder,
    super.key,
  });

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  String _query = '';
  String? _folderFilter; // null = all

  List<ImportedBook> get _filtered {
    final q = _query.trim().toLowerCase();
    return [
      for (final book in widget.books)
        if ((_folderFilter == null || book.folderId == _folderFilter) &&
            (q.isEmpty ||
                book.title.toLowerCase().contains(q) ||
                (book.coverText?.toLowerCase().contains(q) ?? false) ||
                book.format.name.toLowerCase().contains(q)))
          book,
    ];
  }

  Future<void> _showBookActions(ImportedBook book) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(book.title),
        actions: [
          if (widget.onEditCover != null)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                widget.onEditCover!(book);
              },
              child: const Text('编辑封面'),
            ),
          if (widget.onMoveToFolder != null)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                _showFolderPicker(book);
              },
              child: const Text('移动到文件夹'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
      ),
    );
  }

  Future<void> _showFolderPicker(ImportedBook book) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => _FolderPickerSheet(
        title: '移动到文件夹',
        folders: widget.folders,
        extraActionLabel: widget.onCreateFolder == null
            ? null
            : '新建文件夹…',
        onExtraAction: () {
          Navigator.pop(ctx);
          _promptCreateFolder(book);
        },
        trailingAllLabel: '全部（移出文件夹）',
        onSelectAll: () {
          Navigator.pop(ctx);
          widget.onMoveToFolder?.call(book, null);
        },
        onSelect: (folder) {
          Navigator.pop(ctx);
          widget.onMoveToFolder?.call(book, folder.id);
        },
      ),
    );
  }

  Future<void> _promptCreateFolder([ImportedBook? book]) async {
    final controller = TextEditingController();
    final name = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('新建文件夹'),
        content: CupertinoTextField(
          controller: controller,
          placeholder: '文件夹名称',
          autofocus: true,
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    await widget.onCreateFolder?.call(name);
    if (!mounted || book == null) return;
    // Move the book into the newest folder by name match on next frame.
    final created = widget.folders.where((f) => f.name == name).toList();
    final folderId = created.isEmpty ? null : created.last.id;
    if (folderId != null) {
      await widget.onMoveToFolder?.call(book, folderId);
    }
  }

  Future<void> _promptManageFolders() async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => _FolderPickerSheet(
        title: '文件夹（${widget.folders.length}）',
        folders: widget.folders,
        extraActionLabel: '新建文件夹…',
        onExtraAction: () {
          Navigator.pop(ctx);
          _promptCreateFolder();
        },
        onSelect: (folder) {
          Navigator.pop(ctx);
          _promptFolderOptions(folder);
        },
      ),
    );
  }

  Future<void> _promptFolderOptions(LibraryFolder folder) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(folder.name),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _promptRenameFolder(folder);
            },
            child: const Text('重命名'),
          ),
          if (widget.onDeleteFolder != null)
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.pop(ctx);
                widget.onDeleteFolder!(folder.id);
              },
              child: const Text('删除文件夹'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
      ),
    );
  }

  Future<void> _promptRenameFolder(LibraryFolder folder) async {
    final controller = TextEditingController(text: folder.name);
    final name = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('重命名文件夹'),
        content: CupertinoTextField(controller: controller, autofocus: true),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    await widget.onRenameFolder?.call(folder.id, name);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final showEmptyLibrary = widget.books.isEmpty;
    final showEmptySearch = !showEmptyLibrary && filtered.isEmpty;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('书库'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.onCreateFolder != null)
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _promptManageFolders,
                child: const Icon(CupertinoIcons.folder),
              ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: widget.onImport,
              child: const Icon(CupertinoIcons.add),
            ),
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            if (!showEmptyLibrary) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
                child: CupertinoSearchTextField(
                  placeholder: '搜索书名',
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  children: [
                    _folderChip(id: null, label: '全部'),
                    for (final folder in widget.folders)
                      _folderChip(id: folder.id, label: folder.name),
                  ],
                ),
              ),
            ],
            Expanded(
              child: showEmptyLibrary
                  ? EmptyLibrary(onImport: widget.onImport)
                  : showEmptySearch
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _query.trim().isEmpty
                              ? '这个文件夹里还没有书。'
                              : '没有找到与「${_query.trim()}」相关的书',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: VellumTheme.mutedOf(context),
                          ),
                        ),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 16,
                            childAspectRatio: .55,
                          ),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final book = filtered[index];
                        return BookGridCard(
                          book: book,
                          onTap: () => widget.onOpen(book),
                          onDelete: () => widget.onDelete(book),
                          onLongPress: () => _showBookActions(book),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _folderChip({required String? id, required String label}) {
    final selected = _folderFilter == id;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        minimumSize: const Size(0, 32),
        borderRadius: BorderRadius.circular(16),
        color: selected
            ? VellumTheme.accentOf(context)
            : VellumTheme.cardOf(context),
        onPressed: () => setState(() => _folderFilter = id),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? CupertinoColors.white : VellumTheme.inkOf(context),
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

/// Scrollable bottom sheet for many folders (ActionSheet cannot grow forever).
class _FolderPickerSheet extends StatelessWidget {
  const _FolderPickerSheet({
    required this.title,
    required this.folders,
    required this.onSelect,
    this.onExtraAction,
    this.extraActionLabel,
    this.onSelectAll,
    this.trailingAllLabel,
  });

  final String title;
  final List<LibraryFolder> folders;
  final ValueChanged<LibraryFolder> onSelect;
  final VoidCallback? onExtraAction;
  final String? extraActionLabel;
  final VoidCallback? onSelectAll;
  final String? trailingAllLabel;

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * .56;
    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: BoxDecoration(
        color: VellumTheme.cardOf(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
              child: Text(
                title,
                style: TextStyle(
                  color: VellumTheme.inkOf(context),
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                children: [
                  if (onSelectAll != null)
                    _tile(context, trailingAllLabel ?? '全部', onSelectAll!),
                  if (extraActionLabel != null && onExtraAction != null)
                    _tile(context, extraActionLabel!, onExtraAction!),
                  for (final folder in folders)
                    _tile(context, folder.name, () => onSelect(folder)),
                ],
              ),
            ),
            Container(height: 1, color: VellumTheme.lineOf(context)),
            CupertinoButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, String label, VoidCallback onTap) =>
      CupertinoListTile(
        title: Text(label, style: TextStyle(color: VellumTheme.inkOf(context))),
        onTap: onTap,
      );
}

