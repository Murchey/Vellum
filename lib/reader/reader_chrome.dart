import 'package:flutter/cupertino.dart';

import '../theme/vellum_theme.dart';

/// Fanqie top bar (alg.xml): **44dp**, back icon at left **16dp**,
/// centre slot shows chapter/book context (usability: Fanqie omits title
/// but offline readers need to know where they are).
class ReaderTopBar extends StatelessWidget {
  const ReaderTopBar({
    required this.bookmarked,
    this.onBack,
    this.onToggleBookmark,
    this.title = '',
    this.surface,
    super.key,
  });

  final bool bookmarked;
  final VoidCallback? onBack;
  final VoidCallback? onToggleBookmark;

  /// Chapter or book label; ellipsized in the centre.
  final String title;

  /// Chrome background — defaults to theme card/paper.
  final Color? surface;

  static const double height = 44;

  @override
  Widget build(BuildContext context) {
    final bg =
        surface ??
        VellumTheme.readerChromeOf(context);
    final ink = VellumTheme.readerChromeInk(bg);
    return ColoredBox(
      color: bg,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: height,
          child: Row(
            children: [
              // alg.xml: ImageView marginLeft 16dp; 44dp hit target.
              CupertinoButton(
                padding: const EdgeInsets.only(left: 16, right: 4),
                minimumSize: const Size(48, 44),
                onPressed: onBack,
                child: Icon(
                  CupertinoIcons.chevron_back,
                  size: 26,
                  color: ink,
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: ink.withValues(alpha: .78),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(48, 44),
                onPressed: onToggleBookmark,
                child: Icon(
                  bookmarked
                      ? CupertinoIcons.bookmark_fill
                      : CupertinoIcons.bookmark,
                  size: 22,
                  color: bookmarked
                      ? VellumTheme.accentOf(context)
                      : ink.withValues(alpha: .85),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom status pill (Fanqie BottomIndicatorContainer): marginBottom 18dp.
class ReaderStatusBar extends StatelessWidget {
  const ReaderStatusBar({
    required this.progressLabel,
    required this.batteryLabel,
    required this.chapterLabel,
    required this.remainingLabel,
    this.surface,
    super.key,
  });

  final String progressLabel;
  final String batteryLabel;
  final String chapterLabel;
  final String remainingLabel;
  final Color? surface;

  @override
  Widget build(BuildContext context) {
    final bg = surface ?? VellumTheme.readerChromeOf(context);
    final ink = VellumTheme.readerChromeInk(bg);
    final lines = <String>[
      if (progressLabel.isNotEmpty) progressLabel,
      if (chapterLabel.isNotEmpty) chapterLabel,
      if (remainingLabel.isNotEmpty) remainingLabel,
      if (batteryLabel.isNotEmpty) batteryLabel,
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: bg.withValues(alpha: .92),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: ink.withValues(alpha: .12),
              ),
            ),
            child: Text(
              lines.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: ink.withValues(alpha: .72), fontSize: 12, height: 1.25),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bookmark pull ribbon (Fanqie BookMarkView notch ~4dp).
class BookmarkRibbon extends StatelessWidget {
  const BookmarkRibbon({
    required this.progress,
    required this.armed,
    required this.alreadyBookmarked,
    required this.label,
    super.key,
  });

  final double progress;
  final bool armed;
  final bool alreadyBookmarked;
  final String label;

  @override
  Widget build(BuildContext context) {
    final accent = VellumTheme.accentOf(context);
    final ribbonLength = (28 + progress * 52).clamp(28.0, 90.0);
    final ribbonColor = armed
        ? accent
        : (alreadyBookmarked
              ? accent.withValues(alpha: .55)
              : VellumTheme.mutedOf(context).withValues(alpha: .7));
    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 22,
                height: ribbonLength,
                decoration: BoxDecoration(
                  color: ribbonColor,
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(4),
                  ),
                ),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Icon(
                      armed || alreadyBookmarked
                          ? CupertinoIcons.bookmark_fill
                          : CupertinoIcons.bookmark,
                      size: 14,
                      color: CupertinoColors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Opacity(
                opacity: progress.clamp(0.25, 1.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: VellumTheme.readerChromeOf(context).withValues(
                      alpha: .94,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: armed
                          ? accent.withValues(alpha: .55)
                          : VellumTheme.lineOf(context),
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: armed ? accent : VellumTheme.inkOf(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
