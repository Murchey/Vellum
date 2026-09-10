import 'package:flutter/cupertino.dart';

import '../theme/vellum_theme.dart';
import 'reader_control_panels.dart';
import 'reader_models.dart';

enum ReaderControlPanel { directory, settings }

/// Bottom chrome: optional panel + single seek bar + function bar.
///
/// Layout:
///   [panel]
///   [ %  slider  ]
///   [ 目录 | 字体 | 深浅色 | 设置 ]
class ReaderBottomControls extends StatefulWidget {
  const ReaderBottomControls({
    required this.fontSize,
    required this.readerFontWeight,
    required this.lineSpacing,
    required this.background,
    required this.readingMode,
    required this.progress,
    required this.canSeek,
    required this.currentParagraph,
    required this.chapters,
    required this.chapterStartPages,
    required this.bookmarks,
    required this.onProgress,
    required this.onJumpToParagraph,
    required this.onRemoveBookmark,
    this.onToggleUiTheme,
    required this.onShowFonts,
    required this.onFontSize,
    required this.onReaderFontWeight,
    required this.onLineSpacing,
    required this.onBackground,
    required this.onReadingMode,
    super.key,
  });

  final double fontSize;
  final ReaderFontWeight readerFontWeight;
  final ReaderLineSpacing lineSpacing;
  final Color background;
  final ReadingMode readingMode;
  final double progress;
  final bool canSeek;
  final int currentParagraph;
  final List<MapEntry<int, String>> chapters;
  final Map<int, int> chapterStartPages;
  final List<MapEntry<int, String>> bookmarks;
  final ValueChanged<double> onProgress;
  final ValueChanged<int> onJumpToParagraph;
  final Future<void> Function(int) onRemoveBookmark;
  final VoidCallback? onToggleUiTheme;
  final VoidCallback onShowFonts;
  final ValueChanged<double> onFontSize;
  final ValueChanged<ReaderFontWeight> onReaderFontWeight;
  final ValueChanged<ReaderLineSpacing> onLineSpacing;
  final ValueChanged<Color> onBackground;
  final ValueChanged<ReadingMode> onReadingMode;

  @override
  State<ReaderBottomControls> createState() => _ReaderBottomControlsState();
}

class _ReaderBottomControlsState extends State<ReaderBottomControls> {
  ReaderControlPanel? _openPanel;
  double? _dragProgress;
  var _seeking = false;

  @override
  void didUpdateWidget(covariant ReaderBottomControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_seeking) return;
    final drag = _dragProgress;
    if (drag == null) return;
    final progress = widget.progress;
    final close = (progress - drag).abs() < 0.02;
    final bothStart = drag <= 0.03 && progress <= 0.03;
    final bothEnd = drag >= 0.97 && progress >= 0.97;
    if (close || bothStart || bothEnd || !widget.canSeek) {
      _seeking = false;
      _dragProgress = null;
    }
  }

  void _togglePanel(ReaderControlPanel panel) {
    setState(() => _openPanel = _openPanel == panel ? null : panel);
  }

  bool get _isDark => CupertinoTheme.of(context).brightness == Brightness.dark;

  double get _displayProgress {
    final value = _seeking ? _dragProgress ?? widget.progress : widget.progress;
    return value.clamp(0.0, 1.0);
  }

  void _onSeekChanged(double value) {
    if (!widget.canSeek) return;
    setState(() {
      _seeking = true;
      _dragProgress = value;
    });
    widget.onProgress(value);
  }

  void _onSeekEnd(double value) {
    if (!widget.canSeek) return;
    setState(() {
      _seeking = true;
      _dragProgress = value;
    });
    widget.onProgress(value);
  }

  @override
  Widget build(BuildContext context) {
    final percent = (_displayProgress * 100).round();
    return Container(
      decoration: BoxDecoration(
        color: VellumTheme.readerChromeOf(context),
        border: Border(top: BorderSide(color: VellumTheme.lineOf(context))),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.black.withValues(alpha: .08),
            blurRadius: 18,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: switch (_openPanel) {
              null => const SizedBox.shrink(),
              ReaderControlPanel.directory => ReaderDirectoryPanel(
                chapters: widget.chapters,
                bookmarks: widget.bookmarks,
                chapterStartPages: widget.chapterStartPages,
                currentParagraph: widget.currentParagraph,
                readingMode: widget.readingMode,
                onJumpToParagraph: widget.onJumpToParagraph,
                onRemoveBookmark: widget.onRemoveBookmark,
                onClose: () => setState(() => _openPanel = null),
              ),
              ReaderControlPanel.settings => ReaderSettingsPanel(
                fontSize: widget.fontSize,
                readerFontWeight: widget.readerFontWeight,
                lineSpacing: widget.lineSpacing,
                background: widget.background,
                readingMode: widget.readingMode,
                onFontSize: widget.onFontSize,
                onReaderFontWeight: widget.onReaderFontWeight,
                onLineSpacing: widget.onLineSpacing,
                onBackground: widget.onBackground,
                onReadingMode: widget.onReadingMode,
                onShowFonts: widget.onShowFonts,
                onClose: () => setState(() => _openPanel = null),
              ),
            },
          ),
          // Single seek bar — the only percentage display in the reader chrome.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Text(
                    '$percent%',
                    textAlign: TextAlign.left,
                    style: TextStyle(
                      color: VellumTheme.accentOf(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: CupertinoSlider(
                    value: _displayProgress,
                    min: 0,
                    max: 1,
                    onChanged: widget.canSeek ? _onSeekChanged : null,
                    onChangeEnd: widget.canSeek ? _onSeekEnd : null,
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: VellumTheme.lineOf(context)),
          SizedBox(
            height: 54,
            child: Row(
              children: [
                _barButton(
                  context,
                  icon: CupertinoIcons.list_bullet,
                  label: '目录',
                  selected: _openPanel == ReaderControlPanel.directory,
                  onPressed: () => _togglePanel(ReaderControlPanel.directory),
                ),
                _barButton(
                  context,
                  icon: CupertinoIcons.textformat,
                  label: '字体',
                  selected: false,
                  onPressed: widget.onShowFonts,
                ),
                _barButton(
                  context,
                  icon: _isDark
                      ? CupertinoIcons.sun_max
                      : CupertinoIcons.moon,
                  label: _isDark ? '浅色' : '深色',
                  selected: false,
                  onPressed: widget.onToggleUiTheme ?? () {},
                ),
                _barButton(
                  context,
                  icon: CupertinoIcons.gear,
                  label: '设置',
                  selected: _openPanel == ReaderControlPanel.settings,
                  onPressed: () => _togglePanel(ReaderControlPanel.settings),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _barButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onPressed,
  }) => Expanded(
    child: CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 20,
            color: selected
                ? VellumTheme.accentOf(context)
                : VellumTheme.mutedOf(context),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: selected
                  ? VellumTheme.accentOf(context)
                  : VellumTheme.inkOf(context),
              fontSize: 11,
            ),
          ),
        ],
      ),
    ),
  );
}
