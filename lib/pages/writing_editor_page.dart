import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:path_provider/path_provider.dart';

import '../services/font_registry.dart';
import '../services/font_storage.dart';
import '../services/library_models.dart';
import '../services/writing_library.dart';
import '../theme/vellum_theme.dart';
import '../widgets/markdown_preview.dart';
import 'writing_typography_sheet.dart';

/// Writing tab: list of local drafts, open editor to write .md / .txt.
class WritingEditorPage extends StatefulWidget {
  const WritingEditorPage({
    required this.document,
    this.onChanged,
    this.library,
    super.key,
  });

  final WritingDocument document;
  final VoidCallback? onChanged;

  /// Test hook: defaults to the on-disk [WritingLibrary].
  final WritingLibrary? library;

  @override
  State<WritingEditorPage> createState() => _WritingEditorPageState();
}

class _WritingEditorPageState extends State<WritingEditorPage> {
  late final WritingLibrary _library = widget.library ?? const WritingLibrary();
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  late WritingFormat _format;
  late WritingDocument _document;
  bool _saving = false;
  bool _dirty = false;

  /// Typing pauses briefly before the disk write, so a burst of keystrokes is
  /// one save rather than one per character.
  static const Duration _autoSaveDelay = Duration(milliseconds: 600);
  Timer? _autoSaveTimer;
  Timer? _novelFormatTimer;
  final _typoStore = const WritingTypographyStore();
  final _fontStorage = const FontStorage();
  WritingTypography _typo = const WritingTypography();
  List<InstalledFont> _installedFonts = const [];

  /// Markdown drafts can be flipped to a rendered preview.
  bool _previewing = false;

  bool get _canPreview => _format == WritingFormat.md;

  String get _saveStatusText {
    if (_saving) return '保存中…';
    if (_dirty) return '即将自动保存';
    return '已自动保存';
  }

  @override
  void initState() {
    super.initState();
    _document = widget.document;
    _format = _document.format;
    _titleController = TextEditingController(text: _document.title);
    _bodyController = TextEditingController(text: _document.body);
    _lastBodyText = _document.body;
    _titleController.addListener(_markDirty);
    _bodyController.addListener(_onBodyChanged);
    _loadTypo();
    _loadFonts();
  }

  Future<void> _loadTypo() async {
    // Skip in widget tests: path_provider + timeout leaves a pending timer.
    if (Platform.environment['FLUTTER_TEST'] == 'true') return;
    try {
      final typo = await _typoStore.load().timeout(const Duration(seconds: 2));
      if (mounted) setState(() => _typo = typo);
    } catch (_) {}
  }

  Future<void> _loadFonts() async {
    if (Platform.environment['FLUTTER_TEST'] == 'true') return;
    try {
      final fonts = await _fontStorage
          .listFonts()
          .timeout(const Duration(seconds: 2));
      if (mounted) setState(() => _installedFonts = fonts);
    } catch (_) {}
  }

  /// 小说排版 only applies to 纯文本 drafts. Markdown owns its own rules
  /// (headings, lists, fences), so the novel switch is inert in MD mode.
  bool get _novelModeActive =>
      _typo.novelMode && _format == WritingFormat.txt;

  void _applyTypo(WritingTypography next) {
    final novelTurnedOn = next.novelMode && !_typo.novelMode;
    setState(() => _typo = next);
    // Persist in the background — the sheet must not wait on disk.
    unawaited(() async {
      try {
        await _typoStore.save(next);
      } catch (_) {}
    }());
    if (novelTurnedOn && _novelModeActive) {
      _applyNovelFormat();
    }
  }

  String _lastBodyText = '';

  void _onBodyChanged() {
    _markDirty();
    if (!_novelModeActive) return;
    _maybeOpenNovelParagraph();
    _lastBodyText = _bodyController.text;
  }

  /// Enter at the end in 小说模式 opens a proper new paragraph (段首两格).
  ///
  /// Deliberately a tiny rewrite of the tail only. The old live formatter
  /// rewrote the whole document on a timer, which ate the caret's newline and
  /// broke IME composition — that is what made 换行 feel broken.
  ///
  /// Backspace is explicitly excluded ([shouldOpenNovelParagraph]): deleting
  /// the indent of an open paragraph used to fall through here and get the
  /// `　　` put right back, so the caret could never return to the previous line.
  void _maybeOpenNovelParagraph() {
    final text = _bodyController.text;
    final sel = _bodyController.selection;
    if (!sel.isValid || !sel.isCollapsed) return;
    // Never rewrite under an active IME composition.
    if (_bodyController.value.composing.isValid) return;
    if (sel.extentOffset != text.length) return;
    if (!shouldOpenNovelParagraph(_lastBodyText, text)) return;
    if (text.endsWith('\n\n　　')) return;

    final edit = novelParagraphBreakWithCaret(text);
    if (edit.text == text) return;
    _bodyController.value = TextEditingValue(
      text: edit.text,
      selection: TextSelection.collapsed(offset: edit.caretOffset),
    );
    _lastBodyText = edit.text;
    _markDirty();
  }

  /// One-shot rewrite used when 小说模式 is switched on. Keeps any open line
  /// at the end so the caret does not lose the writer's current Enter.
  void _applyNovelFormat() {
    final text = _bodyController.text;
    final formatted = applyNovelFormatting(text, keepTrailingNewlines: true);
    if (formatted == text) {
      _lastBodyText = text;
      return;
    }
    final sel = _bodyController.selection;
    final wasAtEnd =
        !sel.isValid || sel.extentOffset >= text.length || text.isEmpty;
    _bodyController.value = TextEditingValue(
      text: formatted,
      selection: wasAtEnd
          ? TextSelection.collapsed(offset: formatted.length)
          : TextSelection.collapsed(
              offset: sel.extentOffset.clamp(0, formatted.length),
            ),
    );
    _lastBodyText = formatted;
    _markDirty();
  }

  void _showTypoSheet() {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => WritingTypographySheet(
        initial: _typo,
        installedFonts: _installedFonts,
        novelAvailable: _format == WritingFormat.txt,
        onChanged: _applyTypo,
        onActivateImportedFont: _activateImportedFont,
        onRefreshFonts: () async {
          await _loadFonts();
          return _installedFonts;
        },
      ),
    );
  }

  /// Registers an imported TTF for the editor (same path as the reader).
  Future<void> _activateImportedFont(InstalledFont font) async {
    try {
      final bytes = await _fontStorage.loadFontByName(font.name);
      if (bytes != null) {
        await FontRegistry.load(font.family, bytes);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _novelFormatTimer?.cancel();
    // Swipe-back / system pop skips 完成; flush whatever is still dirty so the
    // last keystrokes are not lost. Fire-and-forget: dispose cannot await.
    if (_dirty) {
      final snapshot = _document.copyWith(
        title: _titleController.text,
        body: _bodyController.text,
        format: _format,
      );
      unawaited(_library.upsert(snapshot));
    }
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _markDirty() {
    // Rebuild every keystroke so the footer 字/词 count stays live.
    setState(() => _dirty = true);
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(_autoSaveDelay, () {
      if (mounted) unawaited(_persist());
    });
  }

  /// Writes the draft to the local library. Silent — the editor no longer has
  /// a save button; a typing pause (or leaving the page) is the commit point.
  Future<void> _persist() async {
    if (_saving) {
      // A write is already in flight; retry with whatever is on screen now.
      _autoSaveTimer?.cancel();
      _autoSaveTimer = Timer(const Duration(milliseconds: 120), () {
        if (mounted) unawaited(_persist());
      });
      return;
    }
    final next = _document.copyWith(
      title: _titleController.text,
      body: _bodyController.text,
      format: _format,
    );
    setState(() => _saving = true);
    try {
      final saved = await _library.upsert(next);
      if (!mounted) return;
      setState(() {
        _document = saved;
        _dirty = false;
        _saving = false;
      });
      widget.onChanged?.call();
    } catch (_) {
      // Keep the text dirty so the next pause (or export/leave) retries.
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _exportFile() async {
    _autoSaveTimer?.cancel();
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
    // Entering 纯文本 with the global novel switch on applies it once;
    // leaving into Markdown just lets the switch go inert (no rewrite).
    if (_novelModeActive) {
      _lastBodyText = _bodyController.text;
      _applyNovelFormat();
    }
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
            _autoSaveTimer?.cancel();
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
                        height: 1.75,
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
                ' · $_saveStatusText',
                style: TextStyle(color: muted, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet: font, size, weight, and the novel-mode switch.
///
/// State is local so every tap paints immediately — the parent only receives
/// the new value and persists it in the background. Font picking reuses the
/// reader's [ReaderFontPickerSheet] so imported TTFs look and behave the same.
