import 'package:flutter/painting.dart' show FontWeight;
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/services/writing_library.dart';

void main() {
  group('WritingTypography', () {
    test('defaults and clamp', () {
      const t = WritingTypography();
      expect(t.fontSize, 16);
      expect(t.fontFamily, isNull);
      expect(t.weightIndex, 1);
      expect(t.fontWeight, FontWeight.w400);
    });

    test('json round-trip', () {
      const t = WritingTypography(
        fontFamily: 'serif',
        fontSize: 22,
        weightIndex: 3,
      );
      final r = WritingTypography.fromJson(t.toJson());
      expect(r.fontFamily, 'serif');
      expect(r.fontSize, 22);
      expect(r.weightIndex, 3);
      expect(r.fontWeight, FontWeight.w700);
    });

    test('clearFont resets to system default', () {
      const t = WritingTypography(fontFamily: 'monospace');
      expect(t.copyWith(clearFont: true).fontFamily, isNull);
    });

    test('out-of-range values clamp', () {
      final t = WritingTypography.fromJson(const {
        'fontSize': 100,
        'weightIndex': 9,
      });
      expect(t.fontSize, WritingTypography.maxSize);
      expect(t.weightIndex, 3);
    });
  });
}
