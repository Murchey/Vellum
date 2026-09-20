import 'package:flutter/cupertino.dart';

import '../theme/vellum_theme.dart';

/// Top chrome: back + title + bookmark toggle. Progress lives on the bottom
/// seek bar.
class ReaderHeaderPanel extends StatelessWidget {
  const ReaderHeaderPanel({
    required this.title,
    this.onBack,
    this.bookmarked = false,
    this.onToggleBookmark,
    super.key,
  });

  final String title;
  final VoidCallback? onBack;

  /// Whether the current page/position already has a bookmark.
  final bool bookmarked;
  final VoidCallback? onToggleBookmark;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: VellumTheme.readerChromeOf(context).withValues(alpha: .96),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: VellumTheme.lineOf(context)),
            boxShadow: [
              BoxShadow(
                color: CupertinoColors.black.withValues(alpha: .08),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              children: [
                if (onBack != null)
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(40, 40),
                    onPressed: onBack,
                    child: Icon(
                      CupertinoIcons.chevron_back,
                      size: 22,
                      color: VellumTheme.inkOf(context),
                    ),
                  ),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: VellumTheme.inkOf(context),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (onToggleBookmark != null)
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(40, 40),
                    onPressed: onToggleBookmark,
                    child: Icon(
                      bookmarked ? CupertinoIcons.bookmark_fill : CupertinoIcons.bookmark,
                      size: 19,
                      color: bookmarked
                          ? VellumTheme.accentOf(context)
                          : VellumTheme.mutedOf(context),
                    ),
                  )
                else
                  const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class ReaderStatusBar extends StatelessWidget {
  const ReaderStatusBar({
    required this.progressLabel,
    required this.batteryLabel,
    this.chapterLabel = '',
    this.remainingLabel = '',
    super.key,
  });

  final String progressLabel;
  final String batteryLabel;

  /// `第 12 章 夜雨 · 本章 38%`, empty when the book has no chapters.
  final String chapterLabel;

  /// `剩余约 12 分钟`, empty when it cannot be estimated yet.
  final String remainingLabel;

  @override
  Widget build(BuildContext context) {
    final muted = VellumTheme.mutedOf(context).withValues(alpha: .82);
    final style = TextStyle(color: muted, fontSize: 11);
    final detail = [
      if (progressLabel.isNotEmpty) progressLabel,
      if (remainingLabel.isNotEmpty) remainingLabel,
      batteryLabel,
    ].join(' · ');

    return IgnorePointer(
      // Parent SafeArea already handles system insets.
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
          child: MediaQuery.withClampedTextScaling(
            minScaleFactor: 1,
            maxScaleFactor: 1.1,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (chapterLabel.isNotEmpty)
                  Text(
                    chapterLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: chapterLabel.isEmpty
                      ? TextAlign.start
                      : TextAlign.right,
                  style: style,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

