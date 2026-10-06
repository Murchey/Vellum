import 'dart:io';

import 'package:flutter/widgets.dart';

import '../services/reader_background.dart';
import '../theme/vellum_theme.dart';

/// Owns persisted reading-paper settings and the cached image provider.
class ReaderPaperController {
  ReaderPaperController({Color? initialBackground})
      : background = initialBackground;

  Color? background;
  String? imageFileName;
  String? imagePath;
  double imageOpacity = 1.0;
  BackgroundTone tone = BackgroundTone.light;
  Color? ink;
  ImageProvider? imageProvider;

  ReaderBackground get value => ReaderBackground(
        kind: imageFileName == null ? BackgroundKind.solid : BackgroundKind.image,
        colorValue: background?.toARGB32(),
        imageFileName: imageFileName,
        imageOpacity: imageOpacity,
        tone: tone,
        inkColorValue: ink?.toARGB32(),
      );

  Color get readerInk => Color(value.inkValue);

  void setImageProvider(String? path) {
    if (path == null) {
      imageProvider = null;
      imagePath = null;
      return;
    }
    if (path == imagePath && imageProvider != null) return;
    imagePath = path;
    imageProvider = FileImage(File(path));
  }

  Future<void> load({required String bookId}) async {
    final store = const ReaderBackgroundStore();
    final stored = await store.load(bookId: bookId);
    if (stored != null) {
      final path = stored.usesImage
          ? await store.imagePathFor(stored.imageFileName!)
          : null;
      background = stored.colorValue == null ? null : Color(stored.colorValue!);
      imageFileName = stored.imageFileName;
      imageOpacity = stored.imageOpacity;
      tone = stored.tone;
      ink = stored.inkColorValue == null ? null : Color(stored.inkColorValue!);
      setImageProvider(path);
      return;
    }
    final color = background;
    if (color == null) return;
    final argb = color.toARGB32();
    final darkPreset = argb == VellumTheme.readerNight.toARGB32() ||
        argb == VellumTheme.readerCharcoal.toARGB32() ||
        argb == VellumTheme.readerSoftBlack.toARGB32();
    tone = darkPreset ? BackgroundTone.dark : ReaderBackground.suggestTone(argb);
    await store.save(
      ReaderBackground(kind: BackgroundKind.solid, colorValue: argb, tone: tone),
      bookId: bookId,
    );
  }

  Future<void> apply(ReaderBackground next, {required String bookId}) async {
    final store = const ReaderBackgroundStore();
    final path = next.usesImage
        ? await store.imagePathFor(next.imageFileName!)
        : null;
    background = next.colorValue == null ? null : Color(next.colorValue!);
    imageFileName = next.imageFileName;
    imageOpacity = next.imageOpacity;
    tone = next.tone;
    ink = next.inkColorValue == null ? null : Color(next.inkColorValue!);
    setImageProvider(path);
    await store.save(next, bookId: bookId);
  }
}
