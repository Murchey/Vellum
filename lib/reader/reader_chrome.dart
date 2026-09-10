import 'package:flutter/cupertino.dart';

import '../theme/vellum_theme.dart';

/// Top chrome: back + title only. Progress lives on the bottom seek bar.
class ReaderHeaderPanel extends StatelessWidget {
  const ReaderHeaderPanel({
    required this.title,
    this.onBack,
    super.key,
  });

  final String title;
  final VoidCallback? onBack;

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
    super.key,
  });

  final String progressLabel;
  final String batteryLabel;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    // Parent SafeArea already handles system insets.
    child: Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
        child: MediaQuery.withClampedTextScaling(
          minScaleFactor: 1,
          maxScaleFactor: 1.1,
          child: Row(
            children: [
              Text(
                progressLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: VellumTheme.mutedOf(context).withValues(alpha: .82),
                  fontSize: 11,
                ),
              ),
              const Spacer(),
              Text(
                batteryLabel,
                maxLines: 1,
                style: TextStyle(
                  color: VellumTheme.mutedOf(context).withValues(alpha: .82),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
