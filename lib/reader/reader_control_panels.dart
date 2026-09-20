import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Scrollbar;

import '../services/notes_library.dart';
import '../theme/vellum_theme.dart';
import 'reader_models.dart';

class ReaderDirectoryPanel extends StatefulWidget {
  const ReaderDirectoryPanel({
    required this.chapters,
    required this.bookmarks,
    required this.notes,
    required this.chapterPageLabels,
    required this.currentParagraph,
    required this.readingMode,
    required this.onJumpToParagraph,
    required this.onRemoveBookmark,
    required this.onRemoveNote,
    required this.onClose,
    super.key,
  });

  final List<MapEntry<int, String>> chapters;
  final List<MapEntry<int, String>> bookmarks;

  /// This book's highlights and notes, newest first.
  final List<ReadingNote> notes;
  final Map<int, String> chapterPageLabels;
  final int currentParagraph;
  final ReadingMode readingMode;
  final ValueChanged<int> onJumpToParagraph;
  final Future<void> Function(int) onRemoveBookmark;
  final Future<void> Function(String) onRemoveNote;
  final VoidCallback onClose;

  @override
  State<ReaderDirectoryPanel> createState() => _ReaderDirectoryPanelState();
}

class _ReaderDirectoryPanelState extends State<ReaderDirectoryPanel> {
  var _tab = 0;
  final _scrollController = ScrollController();
  var _didAutoScroll = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoScrollToCurrent());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool _isCurrentChapter(
    int paragraphIndex,
    int index,
    List<MapEntry<int, String>> entries,
  ) {
    final current = widget.currentParagraph;
    final next = index + 1 < entries.length
        ? entries[index + 1].key
        : 1 << 30;
    return current >= paragraphIndex && current < next;
  }

  /// Fanqie opens the catalog drawer already centred on the current chapter —
  /// hunting for "where was I" is one of the main reasons a TOC feels clumsy.
  void _autoScrollToCurrent() {
    if (_didAutoScroll || !_scrollController.hasClients) return;
    final entries = _tab == 0 ? widget.chapters : widget.bookmarks;
    if (entries.isEmpty) return;
    var target = 0;
    for (var i = 0; i < entries.length; i++) {
      if (entries[i].key <= widget.currentParagraph) {
        target = i;
      } else {
        break;
      }
    }
    _didAutoScroll = true;
    final itemExtent = 56.0;
    final maxOffset = _scrollController.position.maxScrollExtent;
    final offset = (target * itemExtent - 80).clamp(0.0, maxOffset);
    _scrollController.jumpTo(offset);
  }

  String _secondaryLabel(int paragraphIndex, int index,
      List<MapEntry<int, String>> entries) {
    if (_tab == 1) return '第 ${paragraphIndex + 1} 段';
    // Page mode: Fanqie shows a page number. Scroll mode: show nothing
    // noisy — a raw paragraph index means nothing to a reader.
    if (widget.readingMode == ReadingMode.page) {
      return widget.chapterPageLabels[paragraphIndex] ?? '';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final entries = _tab == 0 ? widget.chapters : widget.bookmarks;
    final emptyMessage = switch (_tab) {
      0 => '这本书暂未识别出章节标题。',
      1 => '下拉阅读页面即可添加书签。',
      _ => '选中正文后可以划线或写笔记。',
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenH = MediaQuery.sizeOf(context).height;
        final maxH = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : screenH * .55;
        // Fanqie's catalog drawer occupies roughly half the screen. The old
        // 180–280px clamp only showed ~4 rows and forced constant scrolling.
        final height = maxH.clamp(280.0, screenH * .55);
        return SizedBox(
          height: height,
          child: Column(
            children: [
              ReaderPanelTitle(
                icon: switch (_tab) {
                  0 => CupertinoIcons.list_bullet,
                  1 => CupertinoIcons.bookmark,
                  _ => CupertinoIcons.pencil_outline,
                },
                title: switch (_tab) {
                  0 => '目录',
                  1 => '书签',
                  _ => '划线笔记',
                },
                onClose: widget.onClose,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: CupertinoSlidingSegmentedControl<int>(
                  groupValue: _tab,
                  children: const {
                    0: Text('目录'),
                    1: Text('书签'),
                    2: Text('笔记'),
                  },
                  onValueChanged: (value) {
                    if (value == null) return;
                    setState(() => _tab = value);
                    _didAutoScroll = false;
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _autoScrollToCurrent(),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _tab == 2
                    ? _buildNotes(context)
                    : entries.isEmpty
                    ? Center(
                        child: Text(
                          emptyMessage,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: VellumTheme.mutedOf(context),
                          ),
                        ),
                      )
                    : Scrollbar(
                        controller: _scrollController,
                        thumbVisibility: true,
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.only(bottom: 8),
                          itemCount: entries.length,
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            final isCurrentChapter =
                                _tab == 0 &&
                                _isCurrentChapter(entry.key, index, entries);
                            final secondary = _secondaryLabel(
                              entry.key,
                              index,
                              entries,
                            );
                            return CupertinoListTile(
                              backgroundColor: isCurrentChapter
                                  ? VellumTheme.softAccentOf(context)
                                  : VellumTheme.cardOf(context),
                              backgroundColorActivated: VellumTheme.lineOf(
                                context,
                              ),
                              title: Text(
                                entry.value,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isCurrentChapter
                                      ? VellumTheme.accentOf(context)
                                      : VellumTheme.inkOf(context),
                                  fontWeight: isCurrentChapter
                                      ? FontWeight.w600
                                      : null,
                                ),
                              ),
                              additionalInfo: secondary.isEmpty
                                  ? null
                                  : Text(
                                      secondary,
                                      style: TextStyle(
                                        color: VellumTheme.mutedOf(context),
                                      ),
                                    ),
                              trailing: _tab == 1
                                  ? CupertinoButton(
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(32, 32),
                                      onPressed: () async {
                                        await widget.onRemoveBookmark(entry.key);
                                        if (mounted) setState(() {});
                                      },
                                      child: const Icon(
                                        CupertinoIcons.delete,
                                        size: 17,
                                      ),
                                    )
                                  : isCurrentChapter
                                  ? Icon(
                                      CupertinoIcons.bookmark_fill,
                                      size: 14,
                                      color: VellumTheme.accentOf(context),
                                    )
                                  : null,
                              onTap: () =>
                                  widget.onJumpToParagraph(entry.key),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNotes(BuildContext context) {
    final notes = widget.notes;
    if (notes.isEmpty) {
      return Center(
        child: Text(
          '选中正文后可以划线或写笔记。',
          textAlign: TextAlign.center,
          style: TextStyle(color: VellumTheme.mutedOf(context)),
        ),
      );
    }
    return Scrollbar(
      thumbVisibility: true,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 8),
        itemCount: notes.length,
        itemBuilder: (context, index) {
          final note = notes[index];
          return CupertinoListTile(
            backgroundColor: VellumTheme.cardOf(context),
            backgroundColorActivated: VellumTheme.lineOf(context),
            title: Text(
              note.selectedText,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: VellumTheme.inkOf(context),
                backgroundColor: VellumTheme.accentOf(
                  context,
                ).withValues(alpha: .18),
              ),
            ),
            subtitle: note.note.trim().isEmpty
                ? Text(
                    '${note.kind.label} · 第 ${note.paragraphIndex + 1} 段',
                    style: TextStyle(color: VellumTheme.mutedOf(context)),
                  )
                : Text(
                    note.note.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: VellumTheme.mutedOf(context)),
                  ),
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(32, 32),
              onPressed: () async {
                await widget.onRemoveNote(note.id);
                if (mounted) setState(() {});
              },
              child: const Icon(CupertinoIcons.delete, size: 17),
            ),
            onTap: () => widget.onJumpToParagraph(note.paragraphIndex),
          );
        },
      ),
    );
  }
}

class ReaderSettingsPanel extends StatefulWidget {
  const ReaderSettingsPanel({
    required this.fontSize,
    required this.readerFontWeight,
    required this.lineSpacing,
    required this.background,
    required this.readingMode,
    required this.pageTurnStyle,
    required this.brightness,
    required this.eyeCare,
    required this.keepScreenOn,
    required this.volumeKeys,
    required this.onFontSize,
    required this.onReaderFontWeight,
    required this.onLineSpacing,
    required this.onBackground,
    required this.onReadingMode,
    required this.onPageTurnStyle,
    required this.onBrightness,
    required this.onEyeCare,
    required this.onKeepScreenOn,
    required this.onVolumeKeys,
    required this.onShowFonts,
    required this.onClose,
    super.key,
  });

  final double fontSize;
  final ReaderFontWeight readerFontWeight;
  final ReaderLineSpacing lineSpacing;
  final Color background;
  final ReadingMode readingMode;
  final PageTurnStyle pageTurnStyle;

  /// `-1` follows the system brightness.
  final double brightness;
  final ReaderEyeCare eyeCare;
  final bool keepScreenOn;
  final bool volumeKeys;
  final ValueChanged<double> onFontSize;
  final ValueChanged<ReaderFontWeight> onReaderFontWeight;
  final ValueChanged<ReaderLineSpacing> onLineSpacing;
  final ValueChanged<Color> onBackground;
  final ValueChanged<ReadingMode> onReadingMode;
  final ValueChanged<PageTurnStyle> onPageTurnStyle;
  final ValueChanged<double> onBrightness;
  final ValueChanged<ReaderEyeCare> onEyeCare;
  final ValueChanged<bool> onKeepScreenOn;
  final ValueChanged<bool> onVolumeKeys;
  final VoidCallback onShowFonts;
  final VoidCallback onClose;

  @override
  State<ReaderSettingsPanel> createState() => _ReaderSettingsPanelState();
}

/// Two levels on purpose: the front page keeps only the controls a reader
/// reaches for mid-book (font size, brightness, paper), everything else lives
/// behind 「更多设置」.
class _ReaderSettingsPanelState extends State<ReaderSettingsPanel> {
  bool _showMore = false;

  static const double _followSystemBrightness = -1;

  bool get _followsSystem => widget.brightness < 0;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .48,
    ),
    child: AnimatedSize(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
        child: Column(
          children: _showMore
              ? _moreSettings(context)
              : _mainSettings(context),
        ),
      ),
    ),
  );

  List<Widget> _mainSettings(BuildContext context) => [
    ReaderPanelTitle(
      icon: CupertinoIcons.gear,
      title: '阅读设置',
      onClose: widget.onClose,
    ),
    _fontSizeRow(context),
    const SizedBox(height: 10),
    _brightnessRow(context),
    const SizedBox(height: 10),
    ReaderSettingRow(
      label: '背景',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children:
            [
                  VellumTheme.readerNight,
                  VellumTheme.readerMint,
                  VellumTheme.readerSepia,
                  VellumTheme.readerCharcoal,
                  VellumTheme.readerBlue,
                  VellumTheme.readerWhite,
                ]
                .map(
                  (color) => GestureDetector(
                    onTap: () => widget.onBackground(color),
                    child: Container(
                      width: 28,
                      height: 28,
                      margin: const EdgeInsets.only(left: 8),
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: widget.background == color
                              ? VellumTheme.accentOf(context)
                              : VellumTheme.lineOf(context),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
      ),
    ),
    const SizedBox(height: 14),
    Row(
      children: [
        Expanded(
          child: _entryButton(
            context,
            icon: CupertinoIcons.textformat,
            label: '字体',
            detail: '系统 / 导入',
            onTap: widget.onShowFonts,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _entryButton(
            context,
            icon: CupertinoIcons.slider_horizontal_3,
            label: '更多设置',
            detail: '排版 / 常亮',
            onTap: () => setState(() => _showMore = true),
          ),
        ),
      ],
    ),
  ];

  List<Widget> _moreSettings(BuildContext context) => [
    ReaderPanelTitle(
      icon: CupertinoIcons.slider_horizontal_3,
      title: '更多设置',
      onClose: widget.onClose,
      onBack: () => setState(() => _showMore = false),
    ),
    ReaderSettingRow(
      label: '阅读方式',
      child: CupertinoSlidingSegmentedControl<ReadingMode>(
        groupValue: widget.readingMode,
        children: const {
          ReadingMode.scroll: Text('上下滚动'),
          ReadingMode.page: Text('左右翻页'),
        },
        onValueChanged: (value) {
          if (value != null) widget.onReadingMode(value);
        },
      ),
    ),
    const SizedBox(height: 10),
    if (widget.readingMode == ReadingMode.page) ...[
      ReaderSettingRow(
        label: '翻页效果',
        child: CupertinoSlidingSegmentedControl<PageTurnStyle>(
          groupValue: widget.pageTurnStyle,
          children: {
            for (final style in PageTurnStyle.values) style: Text(style.label),
          },
          onValueChanged: (value) {
            if (value != null) widget.onPageTurnStyle(value);
          },
        ),
      ),
      const SizedBox(height: 10),
    ],
    ReaderSettingRow(
      label: '行间距',
      child: CupertinoSlidingSegmentedControl<ReaderLineSpacing>(
        groupValue: widget.lineSpacing,
        children: {
          for (final spacing in ReaderLineSpacing.values)
            spacing: Text(spacing.label),
        },
        onValueChanged: (value) {
          if (value != null) widget.onLineSpacing(value);
        },
      ),
    ),
    const SizedBox(height: 10),
    ReaderSettingRow(
      label: '字重',
      child: CupertinoSlidingSegmentedControl<ReaderFontWeight>(
        groupValue: widget.readerFontWeight,
        children: {
          for (final weight in ReaderFontWeight.values)
            weight: Text(weight.label),
        },
        onValueChanged: (value) {
          if (value != null) widget.onReaderFontWeight(value);
        },
      ),
    ),
    const SizedBox(height: 10),
    ReaderSettingRow(
      label: '护眼',
      child: CupertinoSlidingSegmentedControl<ReaderEyeCare>(
        groupValue: widget.eyeCare,
        children: {
          for (final level in ReaderEyeCare.values) level: Text(level.label),
        },
        onValueChanged: (value) {
          if (value != null) widget.onEyeCare(value);
        },
      ),
    ),
    const SizedBox(height: 6),
    _switchRow(
      context,
      label: '常亮',
      detail: '阅读时保持屏幕常亮',
      value: widget.keepScreenOn,
      onChanged: widget.onKeepScreenOn,
    ),
    _switchRow(
      context,
      label: '音量键',
      detail: '用音量键翻页',
      value: widget.volumeKeys,
      onChanged: widget.onVolumeKeys,
    ),
  ];

  Widget _fontSizeRow(BuildContext context) => Row(
    children: [
      Text('字号', style: TextStyle(color: VellumTheme.mutedOf(context))),
      CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: Size.zero,
        onPressed: () =>
            widget.onFontSize((widget.fontSize - 1).clamp(16, 36)),
        child: const Text('A−'),
      ),
      Expanded(
        child: CupertinoSlider(
          value: widget.fontSize,
          min: 16,
          max: 36,
          onChanged: widget.onFontSize,
        ),
      ),
      CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: Size.zero,
        onPressed: () =>
            widget.onFontSize((widget.fontSize + 1).clamp(16, 36)),
        child: const Text('A+'),
      ),
      Text(
        '${widget.fontSize.round()}',
        style: TextStyle(color: VellumTheme.mutedOf(context)),
      ),
    ],
  );

  Widget _brightnessRow(BuildContext context) => ReaderSettingRow(
    label: '亮度',
    child: Row(
      children: [
        Icon(
          CupertinoIcons.sun_min,
          size: 16,
          color: VellumTheme.mutedOf(context),
        ),
        Expanded(
          child: CupertinoSlider(
            value: _followsSystem ? 0.6 : widget.brightness,
            min: 0.05,
            max: 1,
            onChanged: widget.onBrightness,
          ),
        ),
        CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          minimumSize: Size.zero,
          onPressed: () => widget.onBrightness(_followSystemBrightness),
          child: Text(
            _followsSystem ? '跟随系统' : '恢复跟随',
            style: TextStyle(
              fontSize: 12,
              color: _followsSystem
                  ? VellumTheme.mutedOf(context)
                  : VellumTheme.accentOf(context),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _switchRow(
    BuildContext context, {
    required String label,
    required String detail,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => ReaderSettingRow(
    label: label,
    child: Row(
      children: [
        Expanded(
          child: Text(
            detail,
            style: TextStyle(fontSize: 13, color: VellumTheme.mutedOf(context)),
          ),
        ),
        CupertinoSwitch(value: value, onChanged: onChanged),
      ],
    ),
  );

  /// Secondary-entry tile: icon + label + hint, tapping opens its own screen.
  Widget _entryButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String detail,
    required VoidCallback onTap,
  }) => CupertinoButton(
    padding: EdgeInsets.zero,
    onPressed: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: VellumTheme.cardOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VellumTheme.lineOf(context)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: VellumTheme.accentOf(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: VellumTheme.inkOf(context),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: VellumTheme.mutedOf(context),
                  ),
                ),
              ],
            ),
          ),
          Icon(
            CupertinoIcons.chevron_right,
            size: 13,
            color: VellumTheme.mutedOf(context),
          ),
        ],
      ),
    ),
  );
}

class ReaderPanelTitle extends StatelessWidget {
  const ReaderPanelTitle({
    required this.icon,
    required this.title,
    required this.onClose,
    this.onBack,
    super.key,
  });

  final IconData icon;
  final String title;
  final VoidCallback onClose;

  /// Shown on secondary pages to return to the parent panel.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
    child: Row(
      children: [
        if (onBack != null)
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(28, 28),
            onPressed: onBack,
            child: Icon(
              CupertinoIcons.chevron_back,
              size: 18,
              color: VellumTheme.mutedOf(context),
            ),
          )
        else
          Icon(icon, size: 18, color: VellumTheme.accentOf(context)),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: VellumTheme.inkOf(context),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(32, 28),
          onPressed: onClose,
          child: const Icon(CupertinoIcons.chevron_down, size: 18),
        ),
      ],
    ),
  );
}

class ReaderSettingRow extends StatelessWidget {
  const ReaderSettingRow({
    required this.label,
    required this.child,
    super.key,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 58,
        child: Text(
          label,
          style: TextStyle(color: VellumTheme.mutedOf(context)),
        ),
      ),
      Expanded(child: child),
    ],
  );
}
