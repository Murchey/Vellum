import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Cumulative reading-time statistics for the local reader.
class ReadingStats {
  const ReadingStats({
    this.totalSeconds = 0,
    this.dailySeconds = const {},
    this.bookSeconds = const {},
  });

  final int totalSeconds;
  final Map<String, int> dailySeconds;
  final Map<String, int> bookSeconds;

  int get todaySeconds => dailySeconds[ReadingStatsService.dayKey(DateTime.now())] ?? 0;

  ReadingStats copyWith({
    int? totalSeconds,
    Map<String, int>? dailySeconds,
    Map<String, int>? bookSeconds,
  }) => ReadingStats(
    totalSeconds: totalSeconds ?? this.totalSeconds,
    dailySeconds: dailySeconds ?? this.dailySeconds,
    bookSeconds: bookSeconds ?? this.bookSeconds,
  );

  Map<String, dynamic> toJson() => {
    'totalSeconds': totalSeconds,
    'dailySeconds': dailySeconds,
    'bookSeconds': bookSeconds,
  };

  factory ReadingStats.fromJson(Map<String, dynamic> json) => ReadingStats(
    totalSeconds: (json['totalSeconds'] as num?)?.toInt() ?? 0,
    dailySeconds: (json['dailySeconds'] as Map<String, dynamic>? ?? {}).map(
      (key, value) => MapEntry(key, (value as num).toInt()),
    ),
    bookSeconds: (json['bookSeconds'] as Map<String, dynamic>? ?? {}).map(
      (key, value) => MapEntry(key, (value as num).toInt()),
    ),
  );
}

class ReadingStatsService {
  const ReadingStatsService();

  static String dayKey(DateTime time) {
    final local = time.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }

  static String formatDuration(int seconds) {
    final value = seconds < 0 ? 0 : seconds;
    final hours = value ~/ 3600;
    final minutes = (value % 3600) ~/ 60;
    if (hours > 0) return '$hours 小时 $minutes 分钟';
    if (minutes > 0) return '$minutes 分钟';
    return '$value 秒';
  }

  Future<ReadingStats> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const ReadingStats();
      final raw = jsonDecode(await file.readAsString());
      if (raw is Map<String, dynamic>) {
        return ReadingStats.fromJson(raw);
      }
    } catch (_) {}
    return const ReadingStats();
  }

  Future<void> save(ReadingStats stats) async {
    final file = await _file();
    await file.writeAsString(jsonEncode(stats.toJson()), flush: true);
  }

  /// Adds [seconds] of active reading for [bookId].
  Future<ReadingStats> addSeconds({
    required String bookId,
    required int seconds,
  }) async {
    if (seconds <= 0) return load();
    final current = await load();
    final day = dayKey(DateTime.now());
    final next = current.copyWith(
      totalSeconds: current.totalSeconds + seconds,
      dailySeconds: {
        ...current.dailySeconds,
        day: (current.dailySeconds[day] ?? 0) + seconds,
      },
      bookSeconds: {
        ...current.bookSeconds,
        bookId: (current.bookSeconds[bookId] ?? 0) + seconds,
      },
    );
    await save(next);
    return next;
  }

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(
      '${dir.path}${Platform.pathSeparator}vellum_reading_stats.json',
    );
  }
}
