import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/services/ttf_name_reader.dart';

void main() {
  test('uses the TTF internal full name before the filename', () {
    expect(
      resolveImportedFontDisplayName(
        bytes: _minimalTtfWithFullName('思源宋体'),
        filename: 'SourceHanSerif-Regular',
      ),
      '思源宋体',
    );
  });

  test('uses the filename when the TTF name table is unavailable', () {
    expect(
      resolveImportedFontDisplayName(
        bytes: Uint8List.fromList([0, 1, 2, 3]),
        filename: 'MyImportedFont',
      ),
      'MyImportedFont',
    );
  });
}

Uint8List _minimalTtfWithFullName(String value) {
  final encoded = <int>[];
  for (final unit in value.codeUnits) {
    encoded
      ..add(unit >> 8)
      ..add(unit & 0xff);
  }
  const nameOffset = 28;
  const stringOffset = 18;
  final bytes = Uint8List(nameOffset + stringOffset + encoded.length);
  final data = ByteData.sublistView(bytes);
  data.setUint32(0, 0x00010000, Endian.big);
  data.setUint16(4, 1, Endian.big);
  bytes.setRange(12, 16, 'name'.codeUnits);
  data.setUint32(20, nameOffset, Endian.big);
  data.setUint16(nameOffset + 2, 1, Endian.big);
  data.setUint16(nameOffset + 4, stringOffset, Endian.big);
  final record = nameOffset + 6;
  data.setUint16(record, 3, Endian.big);
  data.setUint16(record + 2, 1, Endian.big);
  data.setUint16(record + 4, 0x0804, Endian.big);
  data.setUint16(record + 6, 4, Endian.big);
  data.setUint16(record + 8, encoded.length, Endian.big);
  data.setUint16(record + 10, 0, Endian.big);
  bytes.setRange(nameOffset + stringOffset, bytes.length, encoded);
  return bytes;
}
