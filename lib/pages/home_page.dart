import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Divider, LinearProgressIndicator;

import '../services/book_importer.dart';
import '../services/book_library.dart';
import '../theme/vellum_theme.dart';
import 'book_widgets.dart';

class HomePage extends StatelessWidget {
  final List<ImportedBook> books;
  final ReadingState? continueState;
  final ValueChanged<ImportedBook> onOpen;
  final VoidCallback onImport;
  const HomePage({
    required this.books,
    required this.onOpen,
    required this.onImport,
    this.continueState,
    super.key,
  });

  double get _continueProgress {
    final state = continueState;
    if (state == null || books.isEmpty) return 0;
    final total = books.first.paragraphCount;
    if (total <= 1) return 0;
    return (state.paragraphIndex / (total - 1)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final ink = VellumTheme.inkOf(context);
    final muted = VellumTheme.mutedOf(context);

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(
          'VELLUM',
          style: TextStyle(
            fontFamily: VellumTheme.fontFamily,
            letterSpacing: 2.2,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: onImport,
          child: const Icon(CupertinoIcons.add),
        ),
      ),
      child: SafeArea(
        child: books.isEmpty
            ? EmptyLibrary(onImport: onImport)
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  Text(
                    '继续阅读',
                    style: TextStyle(
                      fontFamily: VellumTheme.fontFamily,
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      color: ink,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _ContinueCard(
                    book: books.first,
                    progress: _continueProgress,
                    onTap: () => onOpen(books.first),
                  ),
                  if (books.length > 1) ...[
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        Text(
                          '最近加入',
                          style: TextStyle(
                            fontSize: 13,
                            color: muted,
                            fontWeight: FontWeight.w600,
                            letterSpacing: .4,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${books.length - 1} 本',
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: VellumTheme.cardOf(context),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: VellumTheme.lineOf(context)),
                      ),
                      child: Column(
                        children: [
                          for (var i = 1; i < books.length; i++) ...[
                            if (i > 1)
                              Divider(
                                height: 1,
                                indent: 74,
                                color: VellumTheme.lineOf(context),
                              ),
                            BookRow(
                              book: books[i],
                              onTap: () => onOpen(books[i]),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Center(
                    child: Text(
                      '安静地读一本书',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({
    required this.book,
    required this.progress,
    required this.onTap,
  });

  final ImportedBook book;
  final double progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = VellumTheme.inkOf(context);
    final muted = VellumTheme.mutedOf(context);
    final accent = VellumTheme.accentOf(context);
    final percent = (progress * 100).round();

    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: VellumTheme.cardOf(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: VellumTheme.lineOf(context)),
          boxShadow: [
            BoxShadow(
              color: CupertinoColors.black.withValues(
                alpha: CupertinoTheme.of(context).brightness == Brightness.dark
                    ? .25
                    : .05,
              ),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CoverThumb(book: book, width: 78, height: 112),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: VellumTheme.fontFamily,
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                      color: ink,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${book.format.name.toUpperCase()} · ${book.paragraphCount} 段',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                  const SizedBox(height: 18),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      minHeight: 4,
                      backgroundColor: VellumTheme.softAccentOf(context),
                      valueColor: AlwaysStoppedAnimation(accent),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    percent == 0 ? '从这里开始' : '已读 $percent%',
                    style: TextStyle(
                      fontSize: 12,
                      color: accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_right,
              size: 16,
              color: muted.withValues(alpha: .7),
            ),
          ],
        ),
      ),
    );
  }
}
