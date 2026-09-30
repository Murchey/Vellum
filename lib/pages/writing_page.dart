import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:path_provider/path_provider.dart';

import '../services/writing_library.dart';
import '../theme/vellum_theme.dart';
import '../widgets/markdown_preview.dart';

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

/// Editor for one writing document. Auto-saves drafts; can export .md/.txt.
class WritingEditorPage extends StatefulWidget {
  const WritingEditorPage({required this.document, this.onChanged, super.key});

  final WritingDocument document;
  final VoidCallback? onChanged;

  @override
  State<WritingEditorPage> createState() => _WritingEditorPageState();
}

class _WritingEditorPageState extends State<WritingEditorPage> {
  final _library = const WritingLibrary();
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  late WritingFormat _format;
  late WritingDocument _document;
  bool _saving = false;
  bool _dirty = false;
  final _typoStore = const WritingTypographyStore();
  WritingTypography _typo = const WritingTypography();

  /// Markdown drafts can be flipped to a rendered preview.
  bool _previewing = false;

  bool get _canPreview => _format == WritingFormat.md;

  @override
  void initState() {
    super.initState();
    _document = widget.document;
    _format = _document.format;
    _titleController = TextEditingController(text: _document.title);
    _bodyController = TextEditingController(text: _document.body);
    _titleController.addListener(_markDirty);
    _bodyController.addListener(_markDirty);
    _loadTypo();
  }

  Future<void> _loadTypo() async {
    // Skip in widget tests: path_provider + timeout leaves a pending timer.
    if (Platform.environment['FLUTTER_TEST'] == 'true') return;
    try {
      final typo = await _typoStore.load().timeout(const Duration(seconds: 2));
      if (mounted) setState(() => _typo = typo);
    } catch (_) {}
  }

  Future<void> _applyTypo(WritingTypography next) async {
    setState(() => _typo = next);
    try {
      await _typoStore.save(next);
    } catch (_) {}
  }

  void _showTypoSheet() {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => _WritingTypoSheet(
        initial: _typo,
        onChanged: _applyTypo,
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (_dirty) return;
    setState(() => _dirty = true);
  }

  Future<void> _persist({bool silent = true}) async {
    final next = _document.copyWith(
      title: _titleController.text,
      body: _bodyController.text,
      format: _format,
    );
    setState(() => _saving = true);
    final saved = await _library.upsert(next);
    if (!mounted) return;
    setState(() {
      _document = saved;
      _dirty = false;
      _saving = false;
    });
    widget.onChanged?.call();
    if (!silent) {
      await showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('已保存'),
          content: Text('《${saved.displayTitle}》已保存到本机文稿。'),
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

  Future<void> _exportFile() async {
    if (_dirty) await _persist();
    final text = _bodyController.text;
    final bytes = Uint8List.fromList(utf8.encode(text));
    final name = _document.suggestedFileName;
    final useSaf = Platform.isAndroid || Platform.isIOS;
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '导出文稿',
        fileName: name,
        type: FileType.custom,
        allowedExtensions: [_format.extension],
        bytes: useSaf ? bytes : null,
      );
      if (path == null || path.isEmpty || !mounted) return;
      if (!useSaf) {
        final file = File(
          path.endsWith('.${_format.extension}')
              ? path
              : '$path.${_format.extension}',
        );
        await file.writeAsString(text, encoding: utf8, flush: true);
        if (!mounted) return;
        _showToast('已导出到 ${file.path}');
      } else {
        _showToast('已导出');
      }
    } catch (error) {
      if (!mounted) return;
      try {
        final directory = Directory(
          '${(await getApplicationDocumentsDirectory()).path}'
          '${Platform.pathSeparator}vellum_exports',
        );
        if (!await directory.exists()) {
          await directory.create(recursive: true);
        }
        final file = File('${directory.path}${Platform.pathSeparator}$name');
        await file.writeAsString(text, encoding: utf8, flush: true);
        if (!mounted) return;
        _showToast('已导出到 ${file.path}');
      } catch (_) {
        _showToast('导出失败：$error');
      }
    }
  }

  void _showToast(String message) {
    showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('导出'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('好'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text('删除《${_document.displayTitle}》？'),
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
    if (confirmed != true || !mounted) return;
    await _library.delete(_document.id);
    widget.onChanged?.call();
    if (mounted) Navigator.pop(context);
  }

  void _togglePreview() {
    if (!_canPreview) return;
    if (!_previewing) FocusScope.of(context).unfocus();
    setState(() => _previewing = !_previewing);
  }

  void _setFormat(WritingFormat value) {
    if (value == _format) return;
    setState(() {
      _format = value;
      // Plain text has nothing to render.
      if (value != WritingFormat.md) _previewing = false;
    });
    _markDirty();
  }

  @override
  Widget build(BuildContext context) {
    final muted = VellumTheme.mutedOf(context);
    final ink = VellumTheme.inkOf(context);
    final accent = VellumTheme.accentOf(context);
    final previewDoc = _document.copyWith(
      title: _titleController.text,
      body: _bodyController.text,
      format: _format,
    );

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () async {
            if (_dirty) await _persist();
            if (!context.mounted) return;
            Navigator.pop(context);
          },
          child: const Text('完成'),
        ),
        backgroundColor: VellumTheme.shellOf(context),
        border: null,
        middle: Text(_format.label),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: const Size(40, 40),
              onPressed: _showTypoSheet,
              child: const Icon(CupertinoIcons.textformat_size, size: 20),
            ),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: const Size(40, 40),
              onPressed: _confirmDelete,
              child: Icon(
                CupertinoIcons.delete,
                size: 20,
                color: VellumTheme.mutedOf(context),
              ),
            ),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: const Size(40, 40),
              onPressed: _exportFile,
              child: Icon(CupertinoIcons.share_up, size: 20, color: accent),
            ),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: const Size(40, 40),
              onPressed: _saving ? null : () => _persist(silent: false),
              child: _saving
                  ? const CupertinoActivityIndicator(radius: 9)
                  : Text(
                      '保存',
                      style: TextStyle(
                        color: _dirty ? accent : muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoSlidingSegmentedControl<WritingFormat>(
                      groupValue: _format,
                      children: {
                        for (final format in WritingFormat.values)
                          format: Text(format.label),
                      },
                      onValueChanged: (value) {
                        if (value != null) _setFormat(value);
                      },
                    ),
                  ),
                  if (_canPreview) ...[
                    const SizedBox(width: 10),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: _togglePreview,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _previewing
                              ? VellumTheme.softAccentOf(context)
                              : VellumTheme.cardOf(context),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _previewing
                                ? accent
                                : VellumTheme.lineOf(context),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _previewing
                                  ? CupertinoIcons.pencil
                                  : CupertinoIcons.eye,
                              size: 16,
                              color: _previewing ? accent : muted,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _previewing ? '编辑' : '预览',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _previewing ? accent : ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: CupertinoTextField(
                controller: _titleController,
                placeholder: '标题',
                maxLines: 1,
                style: TextStyle(
                  color: ink,
                  fontSize: (_typo.fontSize + 4).clamp(16.0, 32.0),
                  fontFamily: _typo.fontFamily,
                  fontWeight: FontWeight.w600,
                ),
                placeholderStyle: TextStyle(
                  color: muted,
                  fontWeight: FontWeight.w400,
                ),
                decoration: const BoxDecoration(),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
            Container(height: 1, color: VellumTheme.lineOf(context)),
            Expanded(
              child: _previewing
                  ? MarkdownPreview(source: _bodyController.text)
                  : CupertinoTextField(
                      controller: _bodyController,
                      placeholder: '开始写下……\n支持 Markdown，导出时按所选格式保存。',
                      placeholderStyle: TextStyle(color: muted, height: 1.5),
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      keyboardType: TextInputType.multiline,
                      style: TextStyle(
                        color: ink,
                        fontSize: _typo.fontSize,
                        fontFamily: _typo.fontFamily,
                        fontWeight: _typo.fontWeight,
                        height: 1.65,
                      ),
                      decoration: const BoxDecoration(),
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: VellumTheme.lineOf(context)),
                ),
              ),
              child: Text(
                '${previewDoc.characterCount} 字 · ${previewDoc.wordCount} 词'
                '${_dirty ? ' · 未保存' : ''}',
                style: TextStyle(color: muted, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet: font family, size, and weight for the writing editor.
class _WritingTypoSheet extends StatelessWidget {
  const _WritingTypoSheet({required this.initial, required this.onChanged});

  final WritingTypography initial;
  final ValueChanged<WritingTypography> onChanged;

  static const _families = <String?>[
    null,
    'serif',
    'monospace',
    'sans-serif',
    'Cursive',
  ];

  static const _familyLabels = <String>[
    '默认',
    '衬线',
    '等宽',
    '无衬线',
    '手写',
  ];

  @override
  Widget build(BuildContext context) {
    final ink = VellumTheme.inkOf(context);
    final muted = VellumTheme.mutedOf(context);
    final accent = VellumTheme.accentOf(context);
    final card = VellumTheme.cardOf(context);
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '排版',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
            const SizedBox(height: 14),
            Text('字体', style: TextStyle(fontSize: 12, color: muted)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _families.length; i++)
                  _chip(
                    context,
                    label: _familyLabels[i],
                    selected: initial.fontFamily == _families[i],
                    onTap: () => onChanged(
                      initial.copyWith(
                        fontFamily: _families[i],
                        clearFont: _families[i] == null,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('字号', style: TextStyle(fontSize: 12, color: muted)),
            Row(
              children: [
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(36, 36),
                  onPressed: () => onChanged(
                    initial.copyWith(
                      fontSize: (initial.fontSize - 1).clamp(
                        WritingTypography.minSize,
                        WritingTypography.maxSize,
                      ),
                    ),
                  ),
                  child: Text('A−', style: TextStyle(color: ink)),
                ),
                Expanded(
                  child: CupertinoSlider(
                    value: initial.fontSize.clamp(
                      WritingTypography.minSize,
                      WritingTypography.maxSize,
                    ),
                    min: WritingTypography.minSize,
                    max: WritingTypography.maxSize,
                    onChanged: (v) =>
                        onChanged(initial.copyWith(fontSize: v)),
                  ),
                ),
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(36, 36),
                  onPressed: () => onChanged(
                    initial.copyWith(
                      fontSize: (initial.fontSize + 1).clamp(
                        WritingTypography.minSize,
                        WritingTypography.maxSize,
                      ),
                    ),
                  ),
                  child: Text('A+', style: TextStyle(color: ink)),
                ),
                SizedBox(
                  width: 36,
                  child: Text(
                    '${initial.fontSize.round()}',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('字重', style: TextStyle(fontSize: 12, color: muted)),
            const SizedBox(height: 8),
            CupertinoSlidingSegmentedControl<int>(
              groupValue: initial.weightIndex,
              children: {
                for (var i = 0; i < WritingTypography.weightLabels.length; i++)
                  i: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(WritingTypography.weightLabels[i]),
                  ),
              },
              onValueChanged: (v) {
                if (v == null) return;
                onChanged(initial.copyWith(weightIndex: v));
              },
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '示例文字 The quick brown fox',
                style: TextStyle(
                  color: ink,
                  fontSize: initial.fontSize,
                  fontFamily: initial.fontFamily,
                  fontWeight: initial.fontWeight,
                ),
              ),
            ),
            const SizedBox(height: 12),
            CupertinoButton(
              onPressed: () => Navigator.pop(context),
              child: Text('完成', style: TextStyle(color: accent)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final accent = VellumTheme.accentOf(context);
    final ink = VellumTheme.inkOf(context);
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      minimumSize: const Size(0, 32),
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: .15)
              : VellumTheme.cardOf(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? accent : VellumTheme.lineOf(context),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: selected ? accent : ink,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
