import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'library_models.dart';

/// Font file persistence, independent of book storage.
class FontStorage {
  const FontStorage();

  Future<Uint8List?> loadFont() async {
    final file = await _fontFile();
    if (!await file.exists()) return null;
    return Uint8List.fromList(await file.readAsBytes());
  }

  Future<void> saveFont(Uint8List bytes) async {
    final file = await _fontFile();
    await file.writeAsBytes(bytes, flush: true);
  }

  Future<FontPreferences> loadFontPreferences() async {
    final file = await _fontPreferencesFile();
    if (!await file.exists()) return const FontPreferences();
    try {
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return FontPreferences(
        useForUi: data['useForUi'] as bool? ?? false,
        useForContent: data['useForContent'] as bool? ?? false,
        activeFont: data['activeFont'] as String? ?? '',
      );
    } catch (_) {
      return const FontPreferences();
    }
  }

  Future<void> saveFontPreferences(FontPreferences preferences) async {
    final file = await _fontPreferencesFile();
    await file.writeAsString(
      jsonEncode({
        'useForUi': preferences.useForUi,
        'useForContent': preferences.useForContent,
        'activeFont': preferences.activeFont,
      }),
    );
  }

  Future<List<InstalledFont>> listFonts() async {
    final dir = await _fontsDir();
    if (!await dir.exists()) return [];

    final fonts = <InstalledFont>[];
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.ttf')) {
        final name = entity.uri.pathSegments.last.replaceAll('.ttf', '');
        final family = 'Font_${name.hashCode.abs()}';
        fonts.add(InstalledFont(name: name, family: family));
      }
    }
    return fonts;
  }

  Future<void> saveFontWithName(String name, Uint8List bytes) async {
    final dir = await _fontsDir();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File('${dir.path}${Platform.pathSeparator}$name.ttf');
    await file.writeAsBytes(bytes, flush: true);
  }

  Future<Uint8List?> loadFontByName(String name) async {
    final dir = await _fontsDir();
    final file = File('${dir.path}${Platform.pathSeparator}$name.ttf');
    if (!await file.exists()) return null;
    return Uint8List.fromList(await file.readAsBytes());
  }

  Future<void> deleteFontByName(String name) async {
    final dir = await _fontsDir();
    final file = File('${dir.path}${Platform.pathSeparator}$name.ttf');
    if (await file.exists()) await file.delete();
  }

  Future<void> clearFont() async {
    final file = await _fontFile();
    if (await file.exists()) await file.delete();
  }

  Future<File> fontFile() => _fontFile();

  Future<Directory> _fontsDir() async => Directory(
    '${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}vellum_fonts',
  );

  Future<File> _fontFile() async => File(
    '${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}vellum_font.ttf',
  );

  Future<File> _fontPreferencesFile() async => File(
    '${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}vellum_font_preferences.json',
  );
}
