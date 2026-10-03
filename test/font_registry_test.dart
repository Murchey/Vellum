import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/services/font_registry.dart';

/// Regression guard for the font-switching crash.
///
/// The engine keeps every family handed to `FontLoader` resident for the life
/// of the process, and registering the same family again adds another copy
/// rather than replacing the previous one (measured: ≈1.9× the font file size
/// per call, never released). The reader used to register on every font switch
/// and every picker preview row, so a handful of taps could exhaust the heap.
void main() {
  late List<String> engineCalls;

  setUp(() {
    FontRegistry.forgetAll();
    engineCalls = [];
  });

  tearDown(() {
    FontRegistry.forgetAll();
    FontRegistry.register = (family, bytes) async {};
  });

  /// Counts engine registrations instead of loading a real font.
  void countRegistrations() {
    FontRegistry.register = (family, bytes) async {
      engineCalls.add(family);
    };
  }

  Uint8List fontBytes({int length = 2048, int seed = 0}) => Uint8List.fromList(
    List<int>.generate(length, (i) => (i * 31 + seed) % 251),
  );

  test('a family is registered once, however often it is asked for', () async {
    countRegistrations();
    final bytes = fontBytes();
    const family = 'Font_42';

    expect(await FontRegistry.load(family, bytes), isTrue);
    // The picker preview and the activation both ask for the same family.
    expect(await FontRegistry.load(family, bytes), isFalse);
    // A fresh read from disk hands over different byte objects: still the same
    // font, so it must still not register again.
    expect(await FontRegistry.load(family, fontBytes()), isFalse);

    expect(engineCalls, [family]);
    expect(FontRegistry.isRegistered(family), isTrue);
  });

  test('parallel callers share one registration', () async {
    var calls = 0;
    FontRegistry.register = (family, bytes) async {
      calls++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    };
    final bytes = fontBytes();

    final results = await Future.wait([
      FontRegistry.load('Font_1', bytes),
      FontRegistry.load('Font_1', bytes),
      FontRegistry.load('Font_1', bytes),
    ]);

    expect(calls, 1);
    expect(results.where((registered) => registered).length, 1);
  });

  test('re-importing changed bytes replaces the stale registration', () async {
    countRegistrations();
    const family = 'Font_7';

    await FontRegistry.load(family, fontBytes(seed: 1));
    expect(await FontRegistry.load(family, fontBytes(seed: 1)), isFalse);
    // Delete + import of the same filename: same family, genuinely new font.
    expect(await FontRegistry.load(family, fontBytes(seed: 99)), isTrue);

    expect(engineCalls, [family, family]);
  });

  test('forget() lets a deleted font be re-imported', () async {
    countRegistrations();
    final bytes = fontBytes();
    const family = 'Font_9';

    await FontRegistry.load(family, bytes);
    FontRegistry.forget(family);
    expect(FontRegistry.isRegistered(family), isFalse);
    expect(await FontRegistry.load(family, bytes), isTrue);
    expect(engineCalls, [family, family]);
  });

  test('an invalid font never blocks a later attempt', () async {
    FontRegistry.register = (family, bytes) async {
      throw Exception('invalid font');
    };
    expect(await FontRegistry.load('Font_bad', fontBytes()), isFalse);
    expect(FontRegistry.isRegistered('Font_bad'), isFalse);

    countRegistrations();
    expect(await FontRegistry.load('Font_bad', fontBytes()), isTrue);
  });

  test('empty input is ignored', () async {
    countRegistrations();
    expect(await FontRegistry.load('', fontBytes()), isFalse);
    expect(await FontRegistry.load('Font_x', Uint8List(0)), isFalse);
    expect(engineCalls, isEmpty);
  });
}
