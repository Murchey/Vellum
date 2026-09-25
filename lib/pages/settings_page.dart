import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';

import '../services/book_library.dart';

import '../services/notes_library.dart';
import '../services/reading_stats.dart';
import '../services/vellum_update_service.dart';

import '../theme/vellum_theme.dart';

import 'font_manager_sheet.dart';

import 'ebook_to_txt_page.dart';
import 'reading_stats_page.dart';
import 'tts_settings_page.dart';
import 'update_sheet.dart';

class SettingsPage extends StatefulWidget {
  final VoidCallback onCycleTheme;

  final String themeModeLabel;

  final bool isDark;

  final List<InstalledFont> installedFonts;

  final String activeFontName;

  final bool useFontForUi;

  final bool useFontForContent;

  final Future<void> Function() onImportFonts;

  final Future<void> Function(String) onActivateFont;

  final Future<void> Function(String) onDeleteFont;

  final Future<void> Function({
    required bool useForUi,

    required bool useForContent,
  })
  onFontUsageChanged;

  final Future<StorageUsage> Function() storageUsage;

  final Future<void> Function() onClearBooks;

  final Future<void> Function() onClearReadingStates;

  const SettingsPage({
    required this.onCycleTheme,
    required this.themeModeLabel,

    required this.isDark,

    required this.installedFonts,

    required this.activeFontName,

    required this.useFontForUi,

    required this.useFontForContent,

    required this.onImportFonts,

    required this.onActivateFont,

    required this.onDeleteFont,

    required this.onFontUsageChanged,

    required this.storageUsage,

    required this.onClearBooks,

    required this.onClearReadingStates,

    super.key,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late Future<StorageUsage> _usage;
  bool _checkingUpdate = false;
  bool _autoCheckUpdate = true;
  String _updateRepo = '';
  final _library = const BookLibrary();
  final _statsService = const ReadingStatsService();
  ReadingStats _readingStats = const ReadingStats();

  @override
  void initState() {
    super.initState();
    _usage = widget.storageUsage();
    _loadUpdateRepo();
    _loadUpdatePreferences();
    _loadReadingStats();
  }

  Future<void> _loadUpdatePreferences() async {
    final enabled = await _library.loadAutoUpdateCheck();
    if (mounted) setState(() => _autoCheckUpdate = enabled);
  }

  Future<void> _setAutoCheckUpdate(bool enabled) async {
    setState(() => _autoCheckUpdate = enabled);
    await _library.saveAutoUpdateCheck(enabled);
  }

  Future<void> _loadReadingStats() async {
    final stats = await _statsService.load();
    if (mounted) setState(() => _readingStats = stats);
  }

  Future<void> _exportNotes() async {
    try {
      const notesLibrary = NotesLibrary();
      final notes = await notesLibrary.load();
      if (!mounted) return;
      if (notes.isEmpty) {
        await _showUpdateDialog('暂无阅读笔记。长按正文选中文字后即可添加。');
        return;
      }
      final bytes = Uint8List.fromList(
        utf8.encode(
          const JsonEncoder.withIndent(
            '  ',
          ).convert([for (final n in notes) n.toJson()]),
        ),
      );
      final suggested =
          'vellum_notes_${DateTime.now().millisecondsSinceEpoch}.json';
      final useSaf = Platform.isAndroid || Platform.isIOS;
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '导出阅读笔记',
        fileName: suggested,
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: useSaf ? bytes : null,
      );
      if (path == null || path.isEmpty || !mounted) return;
      if (!useSaf) {
        final file = File(path.endsWith('.json') ? path : '$path.json');
        await notesLibrary.exportTo(file.path);
        if (!mounted) return;
        await _showUpdateDialog('已导出 ${notes.length} 条笔记到\n${file.path}');
      } else {
        await _showUpdateDialog('已导出 ${notes.length} 条笔记');
      }
    } catch (error) {
      if (mounted) await _showUpdateDialog('导出笔记失败：$error');
    }
  }

  Future<void> _loadUpdateRepo() async {
    final repo = await _library.loadUpdateRepository();
    if (mounted) setState(() => _updateRepo = repo);
  }

  String get _updateRepoLabel {
    final normalized = normalizeUpdateRepository(_updateRepo);
    return normalized ?? vellumDefaultRepository;
  }

  /// Compact form for list tiles: `Murchey/vellum` instead of `gitee.com/...`.
  String get _shortUpdateRepoLabel {
    final full = _updateRepoLabel;
    final hostEnd = full.indexOf('/');
    if (hostEnd < 0 || hostEnd + 1 >= full.length) return full;
    return full.substring(hostEnd + 1);
  }

  Future<void> _editUpdateRepo() async {
    final controller = TextEditingController(text: _updateRepo);
    final next = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('更新仓库'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '支持 owner/repo、gitee.com/owner/repo 或 github.com/owner/repo；留空则使用默认仓库。',
            ),
            const SizedBox(height: 12),
            CupertinoTextField(
              controller: controller,
              placeholder: vellumDefaultRepository,
              autofocus: true,
              maxLines: 2,
              minLines: 1,
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, ''),
            child: const Text('恢复默认'),
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
    if (next == null || !mounted) return;
    if (next.isNotEmpty && normalizeUpdateRepository(next) == null) {
      await _showUpdateDialog('格式无效，请填写 owner/repo 或完整 GitHub 地址。');
      return;
    }
    await _library.saveUpdateRepository(next);
    if (!mounted) return;
    setState(() => _updateRepo = next);
  }

  void _refresh() => setState(() => _usage = widget.storageUsage());

  Future<void> _checkForUpdate() async {
    setState(() => _checkingUpdate = true);
    try {
      await checkForUpdates(context, repository: _updateRepo, quiet: false);
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  Future<void> _showUpdateDialog(String message) => showCupertinoDialog<void>(
    context: context,

    builder: (context) => CupertinoAlertDialog(
      title: const Text('检查更新'),

      content: Text(message),

      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(context),

          child: const Text('好'),
        ),
      ],
    ),
  );

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';

    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';

    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _confirm(
    String title,

    String message,

    Future<void> Function() action,
  ) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,

      builder: (context) => CupertinoAlertDialog(
        title: Text(title),

        content: Text(message),

        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),

            child: const Text('取消'),
          ),

          CupertinoDialogAction(
            isDestructiveAction: true,

            onPressed: () => Navigator.pop(context, true),

            child: const Text('清理'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await action();

      if (mounted) _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pageBackground = CupertinoTheme.of(context).scaffoldBackgroundColor;

    final pressedBackground = VellumTheme.cardOf(context);

    final hasActiveFont = widget.activeFontName.isNotEmpty;

    return CupertinoPageScaffold(
      backgroundColor: pageBackground,

      navigationBar: CupertinoNavigationBar(
        backgroundColor: VellumTheme.shellOf(context),
        border: null,
        middle: const Text('设置'),
      ),

      child: MediaQuery.withClampedTextScaling(
        minScaleFactor: 1,

        maxScaleFactor: 1.2,

        child: SafeArea(
          child: ListView(
            children: [
              CupertinoListSection.insetGrouped(
                backgroundColor: pageBackground,

                header: const Text('外观'),

                children: [
                  CupertinoListTile(
                    backgroundColor: pageBackground,

                    backgroundColorActivated: pressedBackground,

                    leading: Icon(
                      widget.isDark
                          ? CupertinoIcons.sun_max
                          : CupertinoIcons.moon,
                    ),

                    title: const Text('界面主题'),

                    additionalInfo: Text(widget.themeModeLabel),

                    onTap: widget.onCycleTheme,
                  ),
                ],
              ),

              CupertinoListSection.insetGrouped(
                backgroundColor: pageBackground,

                header: const Text('字体管理'),

                children: [
                  CupertinoListTile(
                    backgroundColor: pageBackground,

                    backgroundColorActivated: pressedBackground,

                    leading: const Icon(CupertinoIcons.plus_circle),

                    title: const Text('导入字体'),

                    additionalInfo: Text('${widget.installedFonts.length}'),

                    onTap: widget.onImportFonts,
                  ),

                  CupertinoListTile(
                    backgroundColor: pageBackground,

                    backgroundColorActivated: pressedBackground,

                    leading: const Icon(CupertinoIcons.textformat),

                    title: const Text('字体列表'),

                    onTap: () => _showFontManager(context),
                  ),

                  if (hasActiveFont) ...[
                    CupertinoListTile(
                      backgroundColor: pageBackground,

                      backgroundColorActivated: pressedBackground,

                      title: const Text('用于界面字体'),

                      trailing: CupertinoSwitch(
                        value: widget.useFontForUi,

                        onChanged: (value) => widget.onFontUsageChanged(
                          useForUi: value,

                          useForContent: widget.useFontForContent,
                        ),
                      ),
                    ),
                  ],
                ],
              ),

              CupertinoListSection.insetGrouped(
                backgroundColor: pageBackground,

                header: const Text('工具'),

                children: [
                  CupertinoListTile(
                    backgroundColor: pageBackground,

                    backgroundColorActivated: pressedBackground,

                    leading: const Icon(CupertinoIcons.doc_text),

                    title: const Text('MOBI / EPUB 转 TXT'),

                    additionalInfo: const Text('独立页面'),

                    onTap: () => Navigator.of(context).push(
                      CupertinoPageRoute(
                        builder: (_) => const EbookToTxtPage(),
                      ),
                    ),
                  ),
                  CupertinoListTile(
                    backgroundColor: pageBackground,

                    backgroundColorActivated: pressedBackground,

                    leading: const Icon(CupertinoIcons.speaker_1),

                    title: const Text('朗读服务（听书）'),

                    additionalInfo: const Text('TTS 接口'),

                    onTap: () => Navigator.of(context).push(
                      CupertinoPageRoute(
                        builder: (_) => const TtsSettingsPage(),
                      ),
                    ),
                  ),
                ],
              ),

              CupertinoListSection.insetGrouped(
                backgroundColor: pageBackground,
                header: const Text('阅读数据'),
                children: [
                  CupertinoListTile(
                    backgroundColor: pageBackground,
                    backgroundColorActivated: pressedBackground,
                    leading: const Icon(CupertinoIcons.chart_bar),
                    title: const Text('阅读统计'),
                    additionalInfo: Text(
                      '今日 ${ReadingStatsService.formatDuration(_readingStats.todaySeconds)}'
                      ' · 累计 ${ReadingStatsService.formatDuration(_readingStats.totalSeconds)}',
                    ),
                    onTap: () async {
                      await Navigator.of(context).push(
                        CupertinoPageRoute(
                          builder: (_) => const ReadingStatsPage(),
                        ),
                      );
                      await _loadReadingStats();
                    },
                  ),
                  CupertinoListTile(
                    backgroundColor: pageBackground,
                    backgroundColorActivated: pressedBackground,
                    leading: const Icon(CupertinoIcons.doc_text),
                    title: const Text('导出阅读笔记'),
                    additionalInfo: const Text('JSON'),
                    onTap: _exportNotes,
                  ),
                ],
              ),

              CupertinoListSection.insetGrouped(
                backgroundColor: pageBackground,

                header: const Text('软件更新'),

                children: [
                  CupertinoListTile(
                    backgroundColor: pageBackground,

                    backgroundColorActivated: pressedBackground,

                    leading: const Icon(CupertinoIcons.arrow_down_circle),

                    title: const Text('检查更新'),

                    additionalInfo: Text(
                      _checkingUpdate ? '检查中…' : _shortUpdateRepoLabel,
                    ),

                    onTap: _checkingUpdate ? null : _checkForUpdate,
                  ),
                  CupertinoListTile(
                    backgroundColor: pageBackground,
                    backgroundColorActivated: pressedBackground,
                    leading: const Icon(CupertinoIcons.gear_alt),
                    title: const Text('更新仓库'),
                    additionalInfo: const Text('自定义'),
                    onTap: _editUpdateRepo,
                  ),
                  CupertinoListTile(
                    backgroundColor: pageBackground,
                    backgroundColorActivated: pressedBackground,
                    leading: const Icon(CupertinoIcons.arrow_2_circlepath),
                    title: const Text('启动时自动检查更新'),
                    additionalInfo: Text(_autoCheckUpdate ? '开' : '关'),
                    trailing: CupertinoSwitch(
                      value: _autoCheckUpdate,
                      onChanged: _setAutoCheckUpdate,
                    ),
                    onTap: () => _setAutoCheckUpdate(!_autoCheckUpdate),
                  ),
                ],
              ),

              CupertinoListSection.insetGrouped(
                backgroundColor: pageBackground,

                header: const Text('存储管理'),

                children: [
                  FutureBuilder<StorageUsage>(
                    future: _usage,

                    builder: (context, snapshot) => CupertinoListTile(
                      backgroundColor: pageBackground,

                      backgroundColorActivated: pressedBackground,

                      leading: const Icon(CupertinoIcons.chart_bar),

                      title: const Text('占用空间'),

                      additionalInfo: Text(
                        snapshot.data == null
                            ? '计算中…'
                            : _formatBytes(snapshot.data!.totalBytes),
                      ),
                    ),
                  ),

                  CupertinoListTile(
                    backgroundColor: pageBackground,

                    backgroundColorActivated: pressedBackground,

                    leading: const Icon(CupertinoIcons.book),

                    title: const Text('清空书库'),

                    onTap: () => _confirm(
                      '清空书库？',

                      '将删除已导入的电子书和对应阅读位置，此操作不可恢复。',

                      widget.onClearBooks,
                    ),
                  ),

                  CupertinoListTile(
                    backgroundColor: pageBackground,

                    backgroundColorActivated: pressedBackground,

                    leading: const Icon(CupertinoIcons.clock),

                    title: const Text('清除阅读记录'),

                    onTap: () => _confirm(
                      '清除阅读记录？',

                      '将重置所有书籍的字号、背景、阅读方式和阅读位置。',

                      widget.onClearReadingStates,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFontManager(BuildContext context) {
    showCupertinoModalPopup(
      context: context,

      builder: (ctx) => FontManagerSheet(
        installedFonts: widget.installedFonts,

        activeFontName: widget.activeFontName,

        onActivateFont: widget.onActivateFont,

        onDeleteFont: widget.onDeleteFont,

        onImportFonts: widget.onImportFonts,
      ),
    );
  }
}

