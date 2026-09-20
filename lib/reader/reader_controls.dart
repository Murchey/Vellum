import 'package:flutter/cupertino.dart';

import '../services/notes_library.dart';
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
    required this.chapterPageLabels,
    required this.bookmarks,
    required this.notes,
    required this.onProgress,
    required this.onJumpToParagraph,
    required this.onRemoveBookmark,
    required this.onRemoveNote,
    this.onToggleUiTheme,
    required this.onShowFonts,
    required this.onFontSize,
    required this.onReaderFontWeight,
    required this.onLineSpacing,
    required this.onBackground,
    required this.onReadingMode,
    this.pageTurnStyle = PageTurnStyle.cover,
    required this.onPageTurnStyle,
    required this.brightness,
    required this.eyeCare,
    required this.keepScreenOn,
    required this.volumeKeys,
    required this.onBrightness,
    required this.onEyeCare,
    required this.onKeepScreenOn,
    required this.onVolumeKeys,
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
  final Map<int, String> chapterPageLabels;
  final List<MapEntry<int, String>> bookmarks;
  final List<ReadingNote> notes;
  final ValueChanged<double> onProgress;
  final ValueChanged<int> onJumpToParagraph;
  final Future<void> Function(int) onRemoveBookmark;
  final Future<void> Function(String) onRemoveNote;
  final VoidCallback? onToggleUiTheme;
  final VoidCallback onShowFonts;
  final ValueChanged<double> onFontSize;
  final ValueChanged<ReaderFontWeight> onReaderFontWeight;
  final ValueChanged<ReaderLineSpacing> onLineSpacing;
  final ValueChanged<Color> onBackground;
  final ValueChanged<ReadingMode> onReadingMode;
  final PageTurnStyle pageTurnStyle;
  final ValueChanged<PageTurnStyle> onPageTurnStyle;
  final double brightness;
  final ReaderEyeCare eyeCare;
  final bool keepScreenOn;
  final bool volumeKeys;
  final ValueChanged<double> onBrightness;
  final ValueChanged<ReaderEyeCare> onEyeCare;
  final ValueChanged<bool> onKeepScreenOn;
  final ValueChanged<bool> onVolumeKeys;

  @override
  State<ReaderBottomControls> createState() => _ReaderBottomControlsState();
}

/// Seek row + divider + function bar + top border.
const double kReaderBottomChromeHeight = 4 + 56 + 1 + 56 + 1;

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

  /// Seek row + divider + function bar + top border.
  /// Keep in sync with ReaderPage `_readerBottomInset`.
  static const double kReaderBottomChromeHeight = 4 + 56 + 1 + 56 + 1;

  @override
  Widget build(BuildContext context) {
    final percent = (_displayProgress * 100).round();
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : MediaQuery.sizeOf(context).height * .58;
        final panelMax = (available - kReaderBottomChromeHeight).clamp(0.0, available);
        return ClipRect(
          child: MediaQuery.withClampedTextScaling(
            minScaleFactor: 1,
            maxScaleFactor: 1.15,
            child: Container(
              decoration: BoxDecoration(
                color: VellumTheme.readerChromeOf(context),
                border: Border(
                  top: BorderSide(color: VellumTheme.lineOf(context)),
                ),
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
                  if (_openPanel != null)
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: panelMax),
                      child: ClipRect(
                        child: AnimatedSize(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          child: switch (_openPanel) {
                            null => const SizedBox.shrink(),
                            ReaderControlPanel.directory =>
                              ReaderDirectoryPanel(
                                chapters: widget.chapters,
                                bookmarks: widget.bookmarks,
                                notes: widget.notes,
                                chapterPageLabels: widget.chapterPageLabels,
                                currentParagraph: widget.currentParagraph,
                                readingMode: widget.readingMode,
                                onJumpToParagraph: widget.onJumpToParagraph,
                                onRemoveBookmark: widget.onRemoveBookmark,
                                onRemoveNote: widget.onRemoveNote,
                                onClose: () =>
                                    setState(() => _openPanel = null),
                              ),
                            ReaderControlPanel.settings => ReaderSettingsPanel(
                              fontSize: widget.fontSize,
                              readerFontWeight: widget.readerFontWeight,
                              lineSpacing: widget.lineSpacing,
                              background: widget.background,
                              readingMode: widget.readingMode,
                              pageTurnStyle: widget.pageTurnStyle,
                              brightness: widget.brightness,
                              eyeCare: widget.eyeCare,
                              keepScreenOn: widget.keepScreenOn,
                              volumeKeys: widget.volumeKeys,
                              onFontSize: widget.onFontSize,
                              onReaderFontWeight: widget.onReaderFontWeight,
                              onLineSpacing: widget.onLineSpacing,
                              onBackground: widget.onBackground,
                              onReadingMode: widget.onReadingMode,
                              onPageTurnStyle: widget.onPageTurnStyle,
                              onBrightness: widget.onBrightness,
                              onEyeCare: widget.onEyeCare,
                              onKeepScreenOn: widget.onKeepScreenOn,
                              onVolumeKeys: widget.onVolumeKeys,
                              onShowFonts: widget.onShowFonts,
                              onClose: () =>
                                  setState(() => _openPanel = null),
                            ),
                          },
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
                    child: SizedBox(
                      height: 52,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 42,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '$percent%',
                                maxLines: 1,
                                style: TextStyle(
                                  color: VellumTheme.accentOf(context),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: CupertinoSlider(
                              value: _displayProgress,
                              min: 0,
                              max: 1,
                              onChanged: widget.canSeek
                                  ? _onSeekChanged
                                  : null,
                              onChangeEnd: widget.canSeek
                                  ? _onSeekEnd
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(height: 1, color: VellumTheme.lineOf(context)),
                  SizedBox(
                    height: 56,
                    child: Row(
                      children: [
                        _barButton(
                          context,
                          icon: CupertinoIcons.list_bullet,
                          label: '目录',
                          selected: _openPanel ==
                              ReaderControlPanel.directory,
                          onPressed: () =>
                              _togglePanel(ReaderControlPanel.directory),
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
                          selected: _openPanel ==
                              ReaderControlPanel.settings,
                          onPressed: () =>
                              _togglePanel(ReaderControlPanel.settings),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: selected
                        ? VellumTheme.accentOf(context)
                        : VellumTheme.inkOf(context),
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
