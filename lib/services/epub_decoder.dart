import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'book_models.dart';
import 'html_text_pipeline.dart';

class EpubDecoder {
  const EpubDecoder({this.pipeline = const HtmlTextPipeline()});

  final HtmlTextPipeline pipeline;

  ImportedBook decode(String filename, Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes, verify: true);
      final container = fileText(archive, 'META-INF/container.xml');
      final packagePath = attribute(container, 'rootfile', 'full-path');
      if (packagePath == null) {
        throw const BookImportException('EPUB 缺少 OPF 书籍目录。');
      }
      final opf = fileText(archive, packagePath);
      final title =
          elementText(opf, 'dc:title') ?? pipeline.titleFromFilename(filename);
      final manifest = <String, String>{};
      for (final match in RegExp(
        r'<item\b[^>]*>',
        caseSensitive: false,
      ).allMatches(opf)) {
        final item = match.group(0)!;
        final id = attributeInTag(item, 'id');
        final href = attributeInTag(item, 'href');
        if (id != null && href != null) manifest[id] = href;
      }
      final slash = packagePath.lastIndexOf('/');
      final base = slash < 0 ? '' : packagePath.substring(0, slash + 1);
      final contents = <HtmlContent>[];
      for (final match in RegExp(
        r'<itemref\b[^>]*>',
        caseSensitive: false,
      ).allMatches(opf)) {
        final id = attributeInTag(match.group(0)!, 'idref');
        final href = id == null ? null : manifest[id];
        if (href != null) {
          final documentPath = '$base$href';
          contents.add(
            pipeline.convert(fileText(archive, documentPath), documentPath),
          );
        }
      }
      final paragraphs = <String>[];
      final anchors = <String, int>{};
      final unresolvedLinks = <int, String>{};
      for (final content in contents) {
        final offset = paragraphs.length;
        paragraphs.addAll(content.paragraphs);
        for (final entry in content.anchors.entries) {
          anchors[entry.key] = offset + entry.value;
        }
        for (final entry in content.links.entries) {
          unresolvedLinks[offset + entry.key] = entry.value;
        }
      }
      final linkTargets = <int, int>{
        for (final entry in unresolvedLinks.entries)
          if (anchors[entry.value] != null) entry.key: anchors[entry.value]!,
      };
      if (paragraphs.isEmpty) {
        throw const BookImportException('EPUB 中没有可阅读的正文。');
      }
      return ImportedBook(
        title: title,
        format: BookFormat.epub,
        paragraphs: paragraphs,
        linkTargets: linkTargets,
      );
    } on BookImportException {
      rethrow;
    } catch (_) {
      throw const BookImportException('无法读取此 EPUB 文件。');
    }
  }

  String fileText(Archive archive, String name) {
    final file = archive.findFile(name);
    if (file == null || !file.isFile) {
      throw BookImportException('EPUB 缺少文件：$name');
    }
    return utf8.decode(file.readBytes()!, allowMalformed: false);
  }

  String? attribute(String source, String tag, String attribute) {
    final match = RegExp(
      '<$tag\\b[^>]*>',
      caseSensitive: false,
    ).firstMatch(source);
    return match == null ? null : attributeInTag(match.group(0)!, attribute);
  }

  String? attributeInTag(String tag, String attribute) => RegExp(
    '$attribute\\s*=\\s*["\\\']([^"\\\']+)["\\\']',
    caseSensitive: false,
  ).firstMatch(tag)?.group(1);

  String? elementText(String source, String tag) => RegExp(
    '<$tag\\b[^>]*>([\\s\\S]*?)</$tag>',
    caseSensitive: false,
  ).firstMatch(source)?.group(1)?.trim();
}
