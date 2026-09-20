import 'package:flutter/cupertino.dart';

import '../services/notes_library.dart';
import '../theme/vellum_theme.dart';
import 'reader_chrome.dart';
import 'reader_control_panels.dart';
import 'reader_models.dart';

/// Reader chrome overlay.
///
/// Visual language follows Fanqie (44dp top bar, 65dp progress row,
/// 目录|日夜|设置), but usability comes first:
/// - chrome sits on the **reading paper** colour
/// - top bar shows chapter context and **exits the reader**
/// - panels fill the band top-bar → bottom-chrome (no floating sheet gap)
/// - tap-outside only dismisses chrome; it never pops the route
/// - action throttle is short (200ms) so buttons do not feel dead
class ReaderMenu extends StatefulWidget {
  const ReaderMenu({
    required this.visible,
    required this.bookmarked,
    required this.onBack,
    required this.onToggleBookmark,
    required this.progress,
    required this.chapterCount,
    required this.currentChapterIndex,
    required this.chapterTitle,
    required this.canSeek,
    required this.onSeekProgress,
    required this.onSeekChapter,
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
    required this.chapters,
    required this.chapterPageLabels,
    required this.bookmarks,
    required this.notes,
    required this.currentParagraph,
    required this.bookTitle,
    required this.onJumpToParagraph,
    required this.onRemoveBookmark,
    required this.onRemoveNote,
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
    this.onDismiss,
    this.onToggleUiTheme,
    super.key,
  });

  final bool visible;
  final bool bookmarked;

  /// Leave the reader (Navigator.pop). Top-bar back / system back.
  final VoidCallback onBack;

  /// Collapse chrome only (tap-outside, toggle). Never exits.
  final VoidCallback? onDismiss;
  final VoidCallback onToggleBookmark;

  final double progress;
  final int chapterCount;
  final int currentChapterIndex;
  final String chapterTitle;
  final bool canSeek;
  final ValueChanged<double> onSeekProgress;
  final ValueChanged<int> onSeekChapter;

  final double fontSize;
  final ReaderFontWeight readerFontWeight;
  final ReaderLineSpacing lineSpacing;
  final Color background;
  final ReadingMode readingMode;
  final PageTurnStyle pageTurnStyle;
  final double brightness;
  final ReaderEyeCare eyeCare;
  final bool keepScreenOn;
  final bool volumeKeys;

  final List<MapEntry<int, String>> chapters;
  final Map<int, String> chapterPageLabels;
  final List<MapEntry<int, String>> bookmarks;
  final List<ReadingNote> notes;
  final int currentParagraph;
  final String bookTitle;
  final ValueChanged<int> onJumpToParagraph;
  final Future<void> Function(int) onRemoveBookmark;
  final Future<void> Function(String) onRemoveNote;

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

  /// Preserved font functionality.
  final VoidCallback onShowFonts;
  final VoidCallback? onToggleUiTheme;

  @override
  State<ReaderMenu> createState() => _ReaderMenuState();
}

const Duration kReaderMenuAnimDuration = Duration(milliseconds: 300);

/// Short debounce so double-taps do not queue, but buttons still feel live.
const Duration kReaderActionThrottle = Duration(milliseconds: 200);

enum _AbovePanel { none, catalog, settings }

class _ReaderMenuState extends State<ReaderMenu>
    with SingleTickerProviderStateMixin {
  _AbovePanel _panel = _AbovePanel.none;
  DateTime? _lastActionAt;
  late final AnimationController _chromeAnim = AnimationController(
    vsync: this,
    duration: kReaderMenuAnimDuration,
  );

  @override
  void initState() {
    super.initState();
    if (widget.visible) _chromeAnim.value = 1;
  }

  @override
  void dispose() {
    _chromeAnim.dispose();
    super.dispose();
  }

  bool get _throttled {
    final now = DateTime.now();
    final last = _lastActionAt;
    if (last != null && now.difference(last) < kReaderActionThrottle) {
      return true;
    }
    _lastActionAt = now;
    return false;
  }

  @override
  void didUpdateWidget(covariant ReaderMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) {
      _panel = _AbovePanel.none;
      _chromeAnim.forward();
    } else if (!widget.visible && oldWidget.visible) {
      _panel = _AbovePanel.none;
      _chromeAnim.reverse();
    }
  }

  void _togglePanel(_AbovePanel panel) {
    if (_throttled) return;
    setState(() => _panel = _panel == panel ? _AbovePanel.none : panel);
  }

  void _closePanel() {
    if (_panel != _AbovePanel.none) {
      setState(() => _panel = _AbovePanel.none);
    }
  }

  /// Tap-outside: close panel, then chrome. Never pops the route.
  void _handleDismiss() {
    if (_panel != _AbovePanel.none) {
      _closePanel();
      return;
    }
    (widget.onDismiss ?? widget.onBack)();
  }

  /// Top-bar back: panel first, then leave the reader. No throttle — exit
  /// must always respond.
  void _handleTopBarBack() {
    if (_panel != _AbovePanel.none) {
      _closePanel();
      return;
    }
    widget.onBack();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible && _chromeAnim.isDismissed) {
      return const SizedBox.shrink();
    }
    // Chrome sits on the reading paper so menu and page feel like one surface.
    final themeBg = widget.background;
    final chromeInk = VellumTheme.readerChromeInk(themeBg);
    final media = MediaQuery.of(context);
    final topSafe = media.padding.top;
    final bottomSafe = media.padding.bottom;
    final topSlide = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _chromeAnim, curve: Curves.easeOutCubic));
    final bottomSlide = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _chromeAnim, curve: Curves.easeOutCubic));
    final chromeVisible = widget.visible || _chromeAnim.isAnimating;

    // Exact bottom chrome height (Progress 65 + line 1 + pad 2+56+2 + safe).
    final bottomChrome = 65.0 + 1 + 2 + 56 + 2 + bottomSafe;
    final bandTop = ReaderTopBar.height + topSafe;

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !widget.visible,
        child: Stack(
          children: [
            // Middle-band dismiss target (page stays visible around chrome).
            if (widget.visible)
              Positioned(
                left: 0,
                right: 0,
                top: bandTop,
                bottom: bottomChrome,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _handleDismiss,
                  child: const ColoredBox(color: Color(0x00000000)),
                ),
              ),

            // Catalog / settings fill the band — sealed to bottom chrome.
            if (_panel != _AbovePanel.none)
              Positioned(
                left: 0,
                right: 0,
                top: bandTop,
                bottom: bottomChrome,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: themeBg,
                    border: Border(
                      top: BorderSide(
                        color: chromeInk.withValues(alpha: .08),
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: _panel == _AbovePanel.catalog
                      ? _catalogPanel(context, themeBg)
                      : _settingsPanel(context, themeBg),
                ),
              ),

            if (chromeVisible)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SlideTransition(
                  position: topSlide,
                  child: ReaderTopBar(
                    bookmarked: widget.bookmarked,
                    title: widget.chapterTitle.isNotEmpty
                        ? widget.chapterTitle
                        : widget.bookTitle,
                    surface: themeBg,
                    onBack: _handleTopBarBack,
                    onToggleBookmark: widget.onToggleBookmark,
                  ),
                ),
              ),

            if (chromeVisible)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SlideTransition(
                  position: bottomSlide,
                  child: ColoredBox(
                    color: themeBg,
                    child: SafeArea(
                      top: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _progressRow(context, themeBg),
                          Container(
                            height: 1,
                            color: chromeInk.withValues(alpha: .08),
                          ),
                          _actionRow(context, themeBg),
                        ],
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

  /// Progress row: labels are tappable chapter steps + seek bar.
  Widget _progressRow(BuildContext context, Color themeBg) {
    final ink = VellumTheme.readerChromeInk(themeBg);
    final accent = VellumTheme.accentOf(context);
    final hasChapters = widget.chapterCount > 1;
    final chapterMax = (widget.chapterCount - 1).clamp(0, 1 << 30);
    final chapterValue = widget.currentChapterIndex.clamp(0, chapterMax);
    final atStart = hasChapters
        ? chapterValue <= 0
        : widget.progress <= 0.001;
    final atEnd = hasChapters
        ? chapterValue >= chapterMax
        : widget.progress >= 0.999;
    final sliderValue = hasChapters
        ? (chapterMax == 0 ? 0.0 : chapterValue / chapterMax)
        : widget.progress.clamp(0.0, 1.0);

    void seek(double value) {
      if (!widget.canSeek) return;
      if (hasChapters) {
        widget.onSeekChapter((value * chapterMax).round());
      } else {
        widget.onSeekProgress(value);
      }
    }

    Widget stepLabel(String text, {required bool enabled, VoidCallback? onTap}) {
      final color = ink.withValues(alpha: enabled ? .9 : .32);
      return CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        minimumSize: const Size(52, 44),
        onPressed: enabled ? onTap : null,
        child: Text(text, style: TextStyle(color: color, fontSize: 14)),
      );
    }

    return SizedBox(
      height: 65,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            stepLabel(
              '上一章',
              enabled: !atStart,
              onTap: () {
                if (!widget.canSeek) return;
                if (hasChapters) {
                  widget.onSeekChapter((chapterValue - 1).clamp(0, chapterMax));
                } else {
                  widget.onSeekProgress((widget.progress - 0.05).clamp(0, 1));
                }
              },
            ),
            Expanded(
              child: CupertinoSlider(
                value: sliderValue.clamp(0.0, 1.0),
                activeColor: accent,
                thumbColor: accent,
                onChanged: widget.canSeek ? seek : null,
                onChangeEnd: widget.canSeek ? seek : null,
              ),
            ),
            stepLabel(
              '下一章',
              enabled: !atEnd,
              onTap: () {
                if (!widget.canSeek) return;
                if (hasChapters) {
                  widget.onSeekChapter((chapterValue + 1).clamp(0, chapterMax));
                } else {
                  widget.onSeekProgress((widget.progress + 0.05).clamp(0, 1));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionRow(BuildContext context, Color themeBg) {
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            _actionItem(
              context,
              themeBg,
              icon: CupertinoIcons.list_bullet,
              label: '目录',
              selected: _panel == _AbovePanel.catalog,
              onTap: () => _togglePanel(_AbovePanel.catalog),
            ),
            _actionItem(
              context,
              themeBg,
              icon: isDark ? CupertinoIcons.sun_max : CupertinoIcons.moon,
              label: isDark ? '日间' : '夜间',
              selected: false,
              onTap: () {
                if (_throttled) return;
                widget.onToggleUiTheme?.call();
              },
            ),
            _actionItem(
              context,
              themeBg,
              icon: CupertinoIcons.gear,
              label: '设置',
              selected: _panel == _AbovePanel.settings,
              onTap: () => _togglePanel(_AbovePanel.settings),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionItem(
    BuildContext context,
    Color themeBg, {
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final accent = VellumTheme.accentOf(context);
    final ink = VellumTheme.readerChromeInk(themeBg);
    return Expanded(
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 24,
              color: selected ? accent : ink.withValues(alpha: .92),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: selected ? accent : ink.withValues(alpha: .92),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _catalogPanel(BuildContext context, Color themeBg) {
    return ColoredBox(
      color: themeBg,
      child: ReaderDirectoryPanel(
        bookTitle: widget.bookTitle,
        surface: themeBg,
        chapters: widget.chapters,
        bookmarks: widget.bookmarks,
        notes: widget.notes,
        chapterPageLabels: widget.chapterPageLabels,
        currentParagraph: widget.currentParagraph,
        readingMode: widget.readingMode,
        onJumpToParagraph: (paragraph) {
          _closePanel();
          widget.onJumpToParagraph(paragraph);
        },
        onRemoveBookmark: widget.onRemoveBookmark,
        onRemoveNote: widget.onRemoveNote,
        onClose: _closePanel,
      ),
    );
  }

  Widget _settingsPanel(BuildContext context, Color themeBg) {
    return ColoredBox(
      color: themeBg,
      child: ReaderSettingsPanel(
        surface: themeBg,
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
        onClose: _closePanel,
      ),
    );
  }
}
