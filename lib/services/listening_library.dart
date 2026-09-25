import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Where listening stopped for one book — the local equivalent of the
/// reference reader's `key_is_tts` + position memory, used to offer
/// 「继续上次」 when the user taps 听书 again.
class ListeningPosition {
  const ListeningPosition({
    required this.paragraphIndex,
    this.sentenceIndex = 0,
  });

  final int paragraphIndex;
  final int sentenceIndex;

  Map<String, dynamic> toJson() => {
    'paragraphIndex': paragraphIndex,
    'sentenceIndex': sentenceIndex,
  };

  factory ListeningPosition.fromJson(Map<String, dynamic> json) =>
      ListeningPosition(
        paragraphIndex: (json['paragraphIndex'] as num?)?.toInt() ?? 0,
        sentenceIndex: (json['sentenceIndex'] as num?)?.toInt() ?? 0,
      );
}

class ListeningLibrary {
  const ListeningLibrary();

  Future<ListeningPosition?> load(String bookId) async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final raw = jsonDecode(await file.readAsString());
      if (raw is Map<String, dynamic>) {
        final value = raw[bookId];
        if (value is Map<String, dynamic>) {
          return ListeningPosition.fromJson(value);
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> save(String bookId, ListeningPosition position) async {
    final file = await _file();
    var all = <String, dynamic>{};
    try {
      if (await file.exists()) {
        final raw = jsonDecode(await file.readAsString());
        if (raw is Map<String, dynamic>) all = raw;
      }
    } catch (_) {}
    all[bookId] = position.toJson();
    await file.writeAsString(jsonEncode(all), flush: true);
  }

  Future<void> clear(String bookId) async {
    final file = await _file();
    if (!await file.exists()) return;
    try {
      final all = jsonDecode(await file.readAsString());
      if (all is Map<String, dynamic>) {
        all.remove(bookId);
        await file.writeAsString(jsonEncode(all), flush: true);
      }
    } catch (_) {}
  }

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(
      '${dir.path}${Platform.pathSeparator}vellum_listening.json',
    );
  }
}