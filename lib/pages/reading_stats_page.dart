import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show AlwaysStoppedAnimation, LinearProgressIndicator;

import '../services/book_importer.dart';
import '../services/book_library.dart';
import '../services/reading_stats.dart';
import '../theme/vellum_theme.dart';

/// Settings → 阅读统计：今日/累计 + 每本书阅读时长。
class ReadingStatsPage extends StatefulWidget {
  const ReadingStatsPage({super.key});

  @override
  State<ReadingStatsPage> createState() => _ReadingStatsPageState();
}

class _ReadingStatsPageState extends State<ReadingStatsPage> {
  final _library = const BookLibrary();
  final _statsService = const ReadingStatsService();
  ReadingStats _stats = const ReadingStats();
  List<BookReadingRow> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    ReadingStats stats = const ReadingStats();
    List<ImportedBook> books = [];
    try {
      stats = await _statsService.load().timeout(const Duration(seconds: 2));
      books = await _library.load().timeout(const Duration(seconds: 2));
    } catch (_) {}
    // Deleted books are skipped (never 未知书籍).
    final rows = buildBookReadingRows(
      stats: stats,
      titleByBookId: {
        for (final book in books)
          book.storageId: book.title.trim().isEmpty ? '未命名' : book.title.trim(),
      },
    );
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _rows = rows;
      _loading = false;
    });
  }

  Future<void> _confirmReset() async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('重置阅读统计？'),
        content: const Text('今日、累计和按书籍的阅读时长都会清零，此操作不可恢复。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('重置'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _statsService.reset();
    if (!mounted) return;
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final pageBackground = CupertinoTheme.of(context).scaffoldBackgroundColor;
    final muted = VellumTheme.mutedOf(context);
    final accent = VellumTheme.accentOf(context);
    final week = List.generate(7, (index) {
      final day = DateTime.now().subtract(Duration(days: 6 - index));
      return (
        label: _dayLabel(day),
        seconds: _stats.dailySeconds[ReadingStatsService.dayKey(day)] ?? 0,
        today: index == 6,
      );
    });
    final weekMax = week.fold<int>(
      0,
      (max, item) => item.seconds > max ? item.seconds : max,
    );
    final goalSeconds = 30 * 60;

    return CupertinoPageScaffold(
      backgroundColor: pageBackground,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: VellumTheme.shellOf(context),
        border: null,
        middle: const Text('阅读统计'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(44, 44),
          onPressed: _confirmReset,
          child: Text(
            '重置',
            style: TextStyle(
              color: CupertinoColors.destructiveRed.resolveFrom(context),
              fontSize: 16,
            ),
          ),
        ),
      ),
      child: SafeArea(
        child: _loading
            ? const Center(child: CupertinoActivityIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                    decoration: BoxDecoration(
                      color: VellumTheme.cardOf(context),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: VellumTheme.lineOf(context)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(CupertinoIcons.timer, color: accent, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              '今天',
                              style: TextStyle(color: muted, fontSize: 15),
                            ),
                            const Spacer(),
                            Text(
                              '目标 30 分钟',
                              style: TextStyle(color: muted, fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          ReadingStatsService.formatDuration(
                            _stats.todaySeconds,
                          ),
                          style: TextStyle(
                            color: VellumTheme.inkOf(context),
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -.4,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (_stats.todaySeconds / goalSeconds).clamp(
                              0.0,
                              1.0,
                            ),
                            minHeight: 7,
                            backgroundColor: accent.withValues(alpha: .12),
                            valueColor: AlwaysStoppedAnimation<Color>(accent),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _stats.todaySeconds >= goalSeconds
                              ? '今日目标已完成，继续保持。'
                              : '再阅读 ${ReadingStatsService.formatDuration(goalSeconds - _stats.todaySeconds)} 达成今日目标。',
                          style: TextStyle(color: muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text('最近 7 天', style: TextStyle(color: muted, fontSize: 13)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
                    decoration: BoxDecoration(
                      color: VellumTheme.cardOf(context),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: VellumTheme.lineOf(context)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final item in week)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 3,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    height: 76,
                                    child: Align(
                                      alignment: Alignment.bottomCenter,
                                      child: AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 220,
                                        ),
                                        width: 14,
                                        height: weekMax == 0
                                            ? 5
                                            : (item.seconds / weekMax * 64)
                                                  .clamp(5.0, 64.0),
                                        decoration: BoxDecoration(
                                          color: item.today
                                              ? accent
                                              : accent.withValues(alpha: .35),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    item.label,
                                    style: TextStyle(
                                      color: item.today ? accent : muted,
                                      fontSize: 11,
                                      fontWeight: item.today
                                          ? FontWeight.w600
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text('按书籍', style: TextStyle(color: muted, fontSize: 13)),
                  const SizedBox(height: 8),
                  if (_rows.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: VellumTheme.cardOf(context),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: VellumTheme.lineOf(context)),
                      ),
                      child: Row(
                        children: [
                          Icon(CupertinoIcons.book, color: muted),
                          const SizedBox(width: 10),
                          Text('暂无阅读记录', style: TextStyle(color: muted)),
                        ],
                      ),
                    )
                  else
                    for (final row in _rows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 13,
                          ),
                          decoration: BoxDecoration(
                            color: VellumTheme.cardOf(context),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: VellumTheme.lineOf(context),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                CupertinoIcons.book,
                                size: 20,
                                color: accent,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  row.title,
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
                              Text(
                                ReadingStatsService.formatDuration(row.seconds),
                                style: TextStyle(color: muted, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ),
                ],
              ),
      ),
    );
  }

  String _dayLabel(DateTime day) {
    if (day.day == DateTime.now().day && day.month == DateTime.now().month) {
      return '今';
    }
    return '${day.month}/${day.day}';
  }
}
