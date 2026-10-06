import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';

import '../services/writing_library.dart';
import '../theme/vellum_theme.dart';
import 'writing_editor_page.dart';

/// Writing tab: list of local drafts, open editor to write .md / .txt.
class WritingPage extends StatefulWidget {
  const WritingPage({this.initialDocuments, super.key});

  /// Optional seed for tests; when null, drafts load from local storage.
  final List<WritingDocument>? initialDocuments;

  @override
  State<WritingPage> createState() => _WritingPageState();
}

class _WritingPageState extends State<WritingPage> {
  final _library = const WritingLibrary();
  List<WritingDocument> _documents = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final seed = widget.initialDocuments;
    if (seed != null) {
      _documents = List.of(seed);
      _loading = false;
      return;
    }
    _reload();
  }

  Future<void> _reload() async {
    List<WritingDocument> docs;
    try {
      docs = await _library.load().timeout(const Duration(seconds: 2));
    } catch (_) {
      docs = [];
    }
    if (!mounted) return;
    setState(() {
      _documents = docs;
      _loading = false;
    });
  }

  Future<void> _createDocument() async {
    final doc = await _library.create();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      CupertinoPageRoute(
        builder: (_) => WritingEditorPage(document: doc, onChanged: _reload),
      ),
    );
    await _reload();
  }

  Future<void> _openDocument(WritingDocument doc) async {
    await Navigator.of(context).push<void>(
      CupertinoPageRoute(
        builder: (_) => WritingEditorPage(document: doc, onChanged: _reload),
      ),
    );
    await _reload();
  }

  Future<void> _importDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['md', 'txt', 'markdown'],
        withData: !Platform.isAndroid,
      );
      if (result == null || !mounted) return;
      final selected = result.files.single;
      final bytes = selected.bytes ?? await File(selected.path!).readAsBytes();
      final text = utf8.decode(bytes, allowMalformed: true);
      final isMd =
          selected.name.toLowerCase().endsWith('.md') ||
          selected.name.toLowerCase().endsWith('.markdown');
      final title = selected.name.contains('.')
          ? selected.name.substring(0, selected.name.lastIndexOf('.'))
          : selected.name;
      await _library.create(
        title: title,
        body: text,
        format: isMd ? WritingFormat.md : WritingFormat.txt,
      );
      await _reload();
    } catch (error) {
      if (!mounted) return;
      await showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('导入失败'),
          content: Text('$error'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('好'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _confirmDelete(WritingDocument doc) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text('删除《${doc.displayTitle}》？'),
        content: const Text('文稿将从本机删除，此操作不可恢复。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _library.delete(doc.id);
    await _reload();
  }

  String _formatTime(DateTime time) {
    final local = time.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    if (day == today) return '今天 $hh:$mm';
    if (day == today.subtract(const Duration(days: 1))) return '昨天 $hh:$mm';
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final muted = VellumTheme.mutedOf(context);
    final accent = VellumTheme.accentOf(context);

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        backgroundColor: VellumTheme.shellOf(context),
        border: null,
        middle: const Text('写作'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(40, 40),
              onPressed: _importDocument,
              child: Icon(CupertinoIcons.folder_open, size: 22, color: accent),
            ),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(40, 40),
              onPressed: _createDocument,
              child: Icon(
                CupertinoIcons.square_pencil,
                size: 22,
                color: accent,
              ),
            ),
          ],
        ),
      ),
      child: SafeArea(
        child: _loading
            ? const Center(child: CupertinoActivityIndicator())
            : _documents.isEmpty
            ? _EmptyWritingState(onCreate: _createDocument)
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: _documents.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final doc = _documents[index];
                  return CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => _openDocument(doc),
                    onLongPress: () => _confirmDelete(doc),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: VellumTheme.cardOf(context),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: VellumTheme.lineOf(context)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  doc.displayTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: VellumTheme.inkOf(context),
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: .12),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  doc.format.extension.toUpperCase(),
                                  style: TextStyle(
                                    color: accent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            doc.preview,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: muted,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${_formatTime(doc.updatedAt)} · ${doc.characterCount} 字',
                            style: TextStyle(color: muted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _EmptyWritingState extends StatelessWidget {
  const _EmptyWritingState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final muted = VellumTheme.mutedOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.doc_text,
              size: 42,
              color: muted.withValues(alpha: .7),
            ),
            const SizedBox(height: 14),
            Text(
              '开始写作',
              style: TextStyle(
                color: VellumTheme.inkOf(context),
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '文稿保存在本机，可导出为 Markdown 或纯文本。',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 14, height: 1.45),
            ),
            const SizedBox(height: 20),
            CupertinoButton.filled(
              onPressed: onCreate,
              child: const Text('新建文稿'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Editor for one writing document. Auto-saves on every edit; can export .md/.txt.
