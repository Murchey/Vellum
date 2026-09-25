import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Where the paper comes from: a solid colour (preset or custom) or a local
/// image. Mirrors the reference reader, where custom backgrounds (图/纯色) live
/// beside the preset swatches.
enum BackgroundKind { solid, image }

/// Paper darkness slot — the reference reader's `ReaderBgColorType`. It only
/// decides body ink (and chrome contrast), never the background itself.
enum BackgroundTone {
  light('亮底'),
  dark('暗底'),
  standard('中性');

  const BackgroundTone(this.label);
  final String label;

  static BackgroundTone fromName(String value) =>
      BackgroundTone.values.firstWhere(
        (tone) => tone.name == value,
        orElse: () => BackgroundTone.light,
      );
}

/// Reading paper for one book (or the global default).
class ReaderBackground {
  const ReaderBackground({
    this.kind = BackgroundKind.solid,
    this.colorValue,
    this.imageFileName,
    this.imageOpacity = 1.0,
    this.tone = BackgroundTone.light,
    this.inkColorValue,
  });

  /// Global default: the sepia paper already used across the app.
  const ReaderBackground.preset(
    int argb, {
    this.tone = BackgroundTone.light,
    this.inkColorValue,
  }) : kind = BackgroundKind.solid,
       colorValue = argb,
       imageFileName = null,
       imageOpacity = 1.0;

  const ReaderBackground.customColor(
    int argb, {
    this.tone = BackgroundTone.light,
    this.inkColorValue,
  }) : kind = BackgroundKind.solid,
       colorValue = argb,
       imageFileName = null,
       imageOpacity = 1.0;

  /// Imported paper. [underlayColor] is the solid colour painted *behind* the
  /// image so transparent PNGs / reduced opacity still sit on a chosen base.
  const ReaderBackground.customImage(
    String fileName, {
    int? underlayColor,
    this.imageOpacity = 1.0,
    this.tone = BackgroundTone.light,
    this.inkColorValue,
  }) : kind = BackgroundKind.image,
       colorValue = underlayColor,
       imageFileName = fileName;

  final BackgroundKind kind;

  /// Solid paper when [kind] is solid; the colour painted *behind* the image
  /// when [kind] is image.
  final int? colorValue;

  /// File name under the `backgrounds/` directory when [kind] is image.
  final String? imageFileName;

  /// Opacity of the imported image (1 = fully opaque). Only used with
  /// [BackgroundKind.image].
  final double imageOpacity;

  final BackgroundTone tone;

  /// User-picked body ink. Null means "derive from [tone]".
  final int? inkColorValue;

  /// Solid chrome colour for menus sitting on this paper. Images use the
  /// underlay colour when set, else the tone's typical chrome.
  int get chromeColorValue => usesImage
      ? (colorValue ??
            (tone == BackgroundTone.dark ? 0xff0e0e0e : 0xfff6f6f6))
      : (colorValue ?? 0xfff6f6f6);

  bool get usesImage =>
      kind == BackgroundKind.image &&
      imageFileName != null &&
      imageFileName!.isNotEmpty;

  double get clampedImageOpacity => imageOpacity.clamp(0.0, 1.0);

  /// Body ink for this paper — custom pick wins, else the tone slot.
  int get inkValue =>
      inkColorValue ??
      switch (tone) {
        BackgroundTone.light => 0xff000000,
        BackgroundTone.dark => 0xffb7b7b7,
        BackgroundTone.standard => 0xff8c8c8c,
      };

  ReaderBackground copyWith({
    BackgroundKind? kind,
    int? colorValue,
    bool clearColor = false,
    String? imageFileName,
    bool clearImage = false,
    double? imageOpacity,
    BackgroundTone? tone,
    int? inkColorValue,
    bool clearInk = false,
  }) => ReaderBackground(
    kind: kind ?? this.kind,
    colorValue: clearColor ? null : (colorValue ?? this.colorValue),
    imageFileName: clearImage ? null : (imageFileName ?? this.imageFileName),
    imageOpacity: imageOpacity ?? this.imageOpacity,
    tone: tone ?? this.tone,
    inkColorValue: clearInk ? null : (inkColorValue ?? this.inkColorValue),
  );

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'colorValue': colorValue,
    'imageFileName': imageFileName,
    'imageOpacity': imageOpacity,
    'tone': tone.name,
    'inkColorValue': inkColorValue,
  };

  factory ReaderBackground.fromJson(Map<String, dynamic> json) {
    final kindName = json['kind'] as String? ?? 'solid';
    return ReaderBackground(
      kind: kindName == 'image'
          ? BackgroundKind.image
          : BackgroundKind.solid,
      colorValue: (json['colorValue'] as num?)?.toInt(),
      imageFileName: json['imageFileName'] as String?,
      imageOpacity: ((json['imageOpacity'] as num?) ?? 1.0).toDouble(),
      tone: BackgroundTone.fromName(json['tone'] as String? ?? 'light'),
      inkColorValue: (json['inkColorValue'] as num?)?.toInt(),
    );
  }

  /// Recommends a tone from a solid colour's luminance; callers pick the final
  /// slot themselves (the reference reader's three slots are a user choice).
  static BackgroundTone suggestTone(int argb) {
    final r = (argb >> 16) & 0xff;
    final g = (argb >> 8) & 0xff;
    final b = argb & 0xff;
    final luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
    return luminance < 0.45 ? BackgroundTone.dark : BackgroundTone.light;
  }
}

/// Local storage for papers: one JSON file (global default + per-book overrides)
/// plus imported images under `backgrounds/`.
class ReaderBackgroundStore {
  const ReaderBackgroundStore();

  Future<Map<String, dynamic>> _readAll() async {
    try {
      final file = await _file();
      if (!await file.exists()) return <String, dynamic>{};
      final raw = jsonDecode(await file.readAsString());
      if (raw is Map<String, dynamic>) return raw;
    } catch (_) {}
    return <String, dynamic>{};
  }

  Future<ReaderBackground?> load({String? bookId}) async {
    final all = await _readAll();
    if (bookId != null) {
      final books = all['books'];
      if (books is Map<String, dynamic>) {
        final value = books[bookId];
        if (value is Map<String, dynamic>) {
          return ReaderBackground.fromJson(value);
        }
      }
    }
    final global = all['global'];
    return global is Map<String, dynamic>
        ? ReaderBackground.fromJson(global)
        : null;
  }

  Future<void> save(ReaderBackground value, {String? bookId}) async {
    final all = await _readAll();
    if (bookId != null) {
      final books = (all['books'] as Map<String, dynamic>?) ?? {};
      books[bookId] = value.toJson();
      all['books'] = books;
    } else {
      all['global'] = value.toJson();
    }
    final file = await _file();
    await file.writeAsString(jsonEncode(all), flush: true);
  }

  Future<void> clearBook(String bookId) async {
    final all = await _readAll();
    final books = all['books'];
    if (books is Map<String, dynamic>) {
      books.remove(bookId);
      all['books'] = books;
      final file = await _file();
      await file.writeAsString(jsonEncode(all), flush: true);
    }
  }

  /// Copies an imported image into `backgrounds/` and returns its file name.
  Future<String> importImage(Uint8List bytes, String name) async {
    final dir = await imagesDirectory();
    final safe = name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final fileName = '${stamp}_$safe';
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return fileName;
  }

  Future<Directory> imagesDirectory() async {
    final dir = Directory(
      '${(await getApplicationDocumentsDirectory()).path}'
      '${Platform.pathSeparator}backgrounds',
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<String> imagePathFor(String fileName) async {
    final dir = await imagesDirectory();
    return '${dir.path}${Platform.pathSeparator}$fileName';
  }

  Future<void> deleteImage(String fileName) async {
    final dir = await imagesDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    if (await file.exists()) await file.delete();
  }

  Future<int> sizeInBytes() async {
    var total = 0;
    final dir = await imagesDirectory();
    await for (final entity in dir.list()) {
      if (entity is File) total += await entity.length();
    }
    final file = await _file();
    if (await file.exists()) total += await file.length();
    return total;
  }

  Future<void> clearImages() async {
    final dir = await imagesDirectory();
    await for (final entity in dir.list()) {
      if (entity is File) await entity.delete();
    }
  }

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(
      '${dir.path}${Platform.pathSeparator}vellum_backgrounds.json',
    );
  }
}