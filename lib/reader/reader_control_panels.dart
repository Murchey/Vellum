import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Scrollbar;

import '../theme/vellum_theme.dart';
import 'reader_models.dart';

class ReaderDirectoryPanel extends StatefulWidget {
  const ReaderDirectoryPanel({
    required this.chapters,
    required this.bookmarks,
    required this.chapterPageLabels,
    required this.currentParagraph,
    required this.readingMode,
    required this.onJumpToParagraph,
    required this.onRemoveBookmark,
    required this.onClose,
    super.key,
  });

  final List<MapEntry<int, String>> chapters;
  final List<MapEntry<int, String>> bookmarks;
  final Map<int, String> chapterPageLabels;
  final int currentParagraph;
  final ReadingMode readingMode;
  final ValueChanged<int> onJumpToParagraph;
  final Future<void> Function(int) onRemoveBookmark;
  final VoidCallback onClose;

  @override
  State<ReaderDirectoryPanel> createState() => _ReaderDirectoryPanelState();
}

class _ReaderDirectoryPanelState extends State<ReaderDirectoryPanel> {
  var _tab = 0;

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

  @override
  Widget build(BuildContext context) {
    final entries = _tab == 0 ? widget.chapters : widget.bookmarks;
    final emptyMessage = _tab == 0
        ? '这本书暂未识别出章节标题。'
        : '下拉阅读页面即可添加书签。';
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxH = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : MediaQuery.sizeOf(context).height * .42;
        final height = maxH.clamp(180.0, 280.0);
        return SizedBox(
          height: height,
          child: Column(
            children: [
              ReaderPanelTitle(
                icon: _tab == 0
                    ? CupertinoIcons.list_bullet
                    : CupertinoIcons.bookmark,
                title: _tab == 0 ? '目录' : '书签',
                onClose: widget.onClose,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: CupertinoSlidingSegmentedControl<int>(
                  groupValue: _tab,
                  children: const {0: Text('目录'), 1: Text('书签')},
                  onValueChanged: (value) {
                    if (value != null) setState(() => _tab = value);
                  },
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: entries.isEmpty
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
                        thumbVisibility: true,
                        child: ListView.builder(
                          padding: const EdgeInsets.only(bottom: 8),
                          itemCount: entries.length,
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            final isCurrentChapter =
                                _tab == 0 &&
                                _isCurrentChapter(entry.key, index, entries);
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
                              additionalInfo: _tab == 1
                                  ? Text('第 ${entry.key + 1} 段')
                                  : Text(
                                      widget.readingMode == ReadingMode.page
                                          ? (widget.chapterPageLabels[entry.key] ??
                                                '约第 ${entry.key + 1} 页')
                                          : '第 ${entry.key + 1} 段',
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
}

class ReaderSettingsPanel extends StatelessWidget {
  const ReaderSettingsPanel({
    required this.fontSize,
    required this.readerFontWeight,
    required this.lineSpacing,
    required this.background,
    required this.readingMode,
    required this.pageTurnStyle,
    required this.onFontSize,
    required this.onReaderFontWeight,
    required this.onLineSpacing,
    required this.onBackground,
    required this.onReadingMode,
    required this.onPageTurnStyle,
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
  final ValueChanged<double> onFontSize;
  final ValueChanged<ReaderFontWeight> onReaderFontWeight;
  final ValueChanged<ReaderLineSpacing> onLineSpacing;
  final ValueChanged<Color> onBackground;
  final ValueChanged<ReadingMode> onReadingMode;
  final ValueChanged<PageTurnStyle> onPageTurnStyle;
  final VoidCallback onShowFonts;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .48,
    ),
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: Column(
        children: [
          ReaderPanelTitle(
            icon: CupertinoIcons.gear,
            title: '阅读设置',
            onClose: onClose,
          ),
          ReaderSettingRow(
            label: '阅读方式',
            child: CupertinoSlidingSegmentedControl<ReadingMode>(
              groupValue: readingMode,
              children: const {
                ReadingMode.scroll: Text('上下滚动'),
                ReadingMode.page: Text('左右翻页'),
              },
              onValueChanged: (value) {
                if (value != null) onReadingMode(value);
              },
            ),
          ),
          const SizedBox(height: 10),
          if (readingMode == ReadingMode.page) ...[
            ReaderSettingRow(
              label: '翻页效果',
              child: CupertinoSlidingSegmentedControl<PageTurnStyle>(
                groupValue: pageTurnStyle,
                children: {
                  for (final style in PageTurnStyle.values)
                    style: Text(style.label),
                },
                onValueChanged: (value) {
                  if (value != null) onPageTurnStyle(value);
                },
              ),
            ),
            const SizedBox(height: 10),
          ],
          ReaderSettingRow(
            label: '行间距',
            child: CupertinoSlidingSegmentedControl<ReaderLineSpacing>(
              groupValue: lineSpacing,
              children: {
                for (final spacing in ReaderLineSpacing.values)
                  spacing: Text(spacing.label),
              },
              onValueChanged: (value) {
                if (value != null) onLineSpacing(value);
              },
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text('字号', style: TextStyle(color: VellumTheme.mutedOf(context))),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                onPressed: () => onFontSize((fontSize - 1).clamp(16, 36)),
                child: const Text('A−'),
              ),
              Expanded(
                child: CupertinoSlider(
                  value: fontSize,
                  min: 16,
                  max: 36,
                  onChanged: onFontSize,
                ),
              ),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                onPressed: () => onFontSize((fontSize + 1).clamp(16, 36)),
                child: const Text('A+'),
              ),
              Text(
                '${fontSize.round()}',
                style: TextStyle(color: VellumTheme.mutedOf(context)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ReaderSettingRow(
            label: '字重',
            child: CupertinoSlidingSegmentedControl<ReaderFontWeight>(
              groupValue: readerFontWeight,
              children: {
                for (final weight in ReaderFontWeight.values)
                  weight: Text(weight.label),
              },
              onValueChanged: (value) {
                if (value != null) onReaderFontWeight(value);
              },
            ),
          ),
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
                          onTap: () => onBackground(color),
                          child: Container(
                            width: 28,
                            height: 28,
                            margin: const EdgeInsets.only(left: 8),
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: background == color
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
          Row(
            children: [
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: onShowFonts,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.textformat, size: 17),
                    SizedBox(width: 6),
                    Text('字体'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
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
    super.key,
  });

  final IconData icon;
  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
    child: Row(
      children: [
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
