import 'dart:convert';
import 'dart:typed_data';

/// Reads the human-readable font name from a TTF/OTF `name` table.
/// Prefers Full name (ID 4), then Typographic Family (16), then Family (1).
String? readTtfDisplayName(Uint8List bytes) {
  try {
    if (bytes.length < 12) return null;
    final data = ByteData.sublistView(bytes);
    final tag = ascii.decode(bytes.sublist(0, 4), allowInvalid: true);
    // OTTO = CFF OpenType; \x00\x01\x00\x00 or 'true' = TTF.
    final isSfnt =
        tag == '\u0000\u0001\u0000\u0000' ||
        tag == 'true' ||
        tag == 'OTTO' ||
        tag == 'typ1';
    if (!isSfnt) return null;

    final numTables = data.getUint16(4, Endian.big);
    var nameOffset = -1;
    for (var i = 0; i < numTables; i++) {
      final rec = 12 + i * 16;
      if (rec + 16 > bytes.length) break;
      final tableTag = ascii.decode(
        bytes.sublist(rec, rec + 4),
        allowInvalid: true,
      );
      if (tableTag == 'name') {
        nameOffset = data.getUint32(rec + 8, Endian.big);
        break;
      }
    }
    if (nameOffset < 0 || nameOffset + 6 > bytes.length) return null;

    final nameCount = data.getUint16(nameOffset + 2, Endian.big);
    final stringOffset = data.getUint16(nameOffset + 4, Endian.big);
    final stringsStart = nameOffset + stringOffset;

    String? full;
    String? typographic;
    String? family;
    for (var i = 0; i < nameCount; i++) {
      final rec = nameOffset + 6 + i * 12;
      if (rec + 12 > bytes.length) break;
      final platformId = data.getUint16(rec, Endian.big);
      final nameId = data.getUint16(rec + 6, Endian.big);
      if (nameId != 1 && nameId != 4 && nameId != 16) continue;
      final length = data.getUint16(rec + 8, Endian.big);
      final offset = data.getUint16(rec + 10, Endian.big);
      final start = stringsStart + offset;
      if (start < 0 || start + length > bytes.length || length == 0) {
        continue;
      }
      final raw = bytes.sublist(start, start + length);
      // Windows (3) name records are UTF-16BE; Mac (1) is usually ASCII.
      final value = platformId == 3
          ? _decodeUtf16Be(raw).trim()
          : utf8.decode(raw, allowMalformed: true).trim();
      if (value.isEmpty) continue;
      if (nameId == 4 && full == null) full = value;
      if (nameId == 16 && typographic == null) typographic = value;
      if (nameId == 1 && family == null) family = value;
    }
    return full ?? typographic ?? family;
  } catch (_) {
    return null;
  }
}

String _decodeUtf16Be(List<int> bytes) {
  final units = <int>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    units.add((bytes[i] << 8) | bytes[i + 1]);
  }
  return String.fromCharCodes(units);
}
