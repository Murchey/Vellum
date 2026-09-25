import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/services/reader_background.dart';

void main() {
  group('ReaderBackground', () {
    test('round-trips solid, custom and image papers', () {
      const papers = [
        ReaderBackground.preset(0xffded9c5, tone: BackgroundTone.light),
        ReaderBackground.customColor(0xff262626, tone: BackgroundTone.dark),
        ReaderBackground.customImage(
          '42_wall.png',
          underlayColor: 0xfff7e4cf,
          imageOpacity: 0.55,
          tone: BackgroundTone.dark,
          inkColorValue: 0xffe8e0d0,
        ),
      ];
      for (final paper in papers) {
        final restored = ReaderBackground.fromJson(paper.toJson());
        expect(restored.kind, paper.kind);
        expect(restored.colorValue, paper.colorValue);
        expect(restored.imageFileName, paper.imageFileName);
        expect(restored.imageOpacity, paper.imageOpacity);
        expect(restored.tone, paper.tone);
        expect(restored.inkColorValue, paper.inkColorValue);
        expect(restored.usesImage, paper.usesImage);
      }
    });

    test('image underlay and opacity survive copyWith', () {
      const paper = ReaderBackground.customImage('a.png', underlayColor: 0xff112233);
      expect(paper.colorValue, 0xff112233);
      final faded = paper.copyWith(imageOpacity: 0.4);
      expect(faded.imageOpacity, 0.4);
      expect(faded.clampedImageOpacity, 0.4);
      final cleared = faded.copyWith(clearColor: true);
      expect(cleared.colorValue, isNull);
      expect(cleared.usesImage, isTrue);
    });

    test('custom ink overrides the tone slot', () {
      final paper = const ReaderBackground.customColor(
        0xffffffff,
        tone: BackgroundTone.light,
      ).copyWith(inkColorValue: 0xff3355ff);
      expect(paper.inkValue, 0xff3355ff);
      expect(paper.copyWith(clearInk: true).inkValue, 0xff000000);
    });

    test('image chrome uses the underlay colour when present', () {
      expect(
        const ReaderBackground.customImage(
          'a.png',
          underlayColor: 0xff224466,
        ).chromeColorValue,
        0xff224466,
      );
    });

    test('suggests the ink tone from luminance', () {
      expect(
        ReaderBackground.suggestTone(0xff262626),
        BackgroundTone.dark,
      );
      expect(
        ReaderBackground.suggestTone(0xfff7e4cf),
        BackgroundTone.light,
      );
    });

    test('ink follows the tone slot, not the background colour', () {
      expect(
        const ReaderBackground.customColor(0xff000000).inkValue,
        0xff000000,
      );
      expect(
        const ReaderBackground.customColor(
          0xff000000,
          tone: BackgroundTone.dark,
        ).inkValue,
        0xffb7b7b7,
      );
      expect(
        const ReaderBackground.customColor(
          0xffffff00,
          tone: BackgroundTone.standard,
        ).inkValue,
        0xff8c8c8c,
      );
    });

    test('chrome falls back by tone when the paper is an image', () {
      expect(
        const ReaderBackground.customColor(0xffded9c5).chromeColorValue,
        0xffded9c5,
      );
      expect(
        const ReaderBackground.customImage('a.png').chromeColorValue,
        0xfff6f6f6,
      );
      expect(
        const ReaderBackground.customImage(
          'a.png',
          tone: BackgroundTone.dark,
        ).chromeColorValue,
        0xff0e0e0e,
      );
    });

    test('files written before custom backgrounds still load', () {
      final legacy = ReaderBackground.fromJson(const {'colorValue': 0xffded9c5});
      expect(legacy.kind, BackgroundKind.solid);
      expect(legacy.tone, BackgroundTone.light);
      expect(legacy.usesImage, isFalse);
      expect(legacy.imageOpacity, 1.0);
      expect(legacy.inkColorValue, isNull);
    });
  });
}