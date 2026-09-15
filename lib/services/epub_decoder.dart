import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

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
      final manifest = <String, _ManifestItem>{};
      for (final match in RegExp(
        r'<item\b[^>]*/?>',
        caseSensitive: false,
      ).allMatches(opf)) {
        final tag = match.group(0)!;
        final id = attributeInTag(tag, 'id');
        final href = attributeInTag(tag, 'href');
        if (id == null || href == null) continue;
        manifest[id] = _ManifestItem(
          href: href,
          mediaType: attributeInTag(tag, 'media-type') ?? '',
          properties: attributeInTag(tag, 'properties') ?? '',
        );
      }
      final slash = packagePath.lastIndexOf('/');
      final opfDir = slash < 0 ? '' : packagePath.substring(0, slash + 1);

      final contents = <_SpineDocument>[];
      for (final match in RegExp(
        r'<itemref\b[^>]*/?>',
        caseSensitive: false,
      ).allMatches(opf)) {
        final id = attributeInTag(match.group(0)!, 'idref');
        final item = id == null ? null : manifest[id];
        if (item == null) continue;
        final href = _normalizePath(opfDir, item.href);
        if (href == null) continue;
        final raw = _tryFileText(archive, href);
        if (raw == null) continue;
        contents.add(
          _SpineDocument(
            path: href,
            content: pipeline.convert(raw, href),
          ),
        );
      }
      if (contents.isEmpty) {
        throw const BookImportException('EPUB 中没有可阅读的正文。');
      }

      final paragraphs = <String>[];
      final anchors = <String, int>{};
      final documentStart = <String, int>{};
      final unresolvedLinks = <int, String>{};
      for (final doc in contents) {
        final offset = paragraphs.length;
        documentStart[doc.path] = offset;
        paragraphs.addAll(doc.content.paragraphs);
        for (final entry in doc.content.anchors.entries) {
          anchors[entry.key] = offset + entry.value;
        }
        for (final entry in doc.content.links.entries) {
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

      final tocEntries = _parseToc(
        archive: archive,
        packagePath: packagePath,
        opf: opf,
        opfDir: opfDir,
        manifest: manifest,
        anchors: anchors,
        documentStart: documentStart,
        paragraphs: paragraphs,
      );

      return ImportedBook(
        title: title,
        format: BookFormat.epub,
        paragraphs: paragraphs,
        linkTargets: linkTargets,
        tocEntries: tocEntries,
      );
    } on BookImportException {
      rethrow;
    } catch (_) {
      throw const BookImportException('无法读取此 EPUB 文件。');
    }
  }

  List<BookTocEntry> _parseToc({
    required Archive archive,
    required String packagePath,
    required String opf,
    required String opfDir,
    required Map<String, _ManifestItem> manifest,
    required Map<String, int> anchors,
    required Map<String, int> documentStart,
    required List<String> paragraphs,
  }) {
    final raw = <_RawTocItem>[];

    final ncxPath = _findNcxPath(opf, opfDir, manifest);
    if (ncxPath != null) {
      final ncx = _tryFileText(archive, ncxPath);
      if (ncx != null) raw.addAll(_parseNcx(ncx, ncxPath));
    }

    if (raw.isEmpty) {
      final navPath = _findNavPath(opfDir, manifest);
      if (navPath != null) {
        final nav = _tryFileText(archive, navPath);
        if (nav != null) raw.addAll(_parseNav(nav, navPath));
      }
    }

    return _mapTocItems(
      raw,
      anchors: anchors,
      documentStart: documentStart,
      paragraphs: paragraphs,
    );
  }

  String? _findNcxPath(
    String opf,
    String opfDir,
    Map<String, _ManifestItem> manifest,
  ) {
    final spineToc = RegExp(
      r'''<spine\b[^>]*\btoc\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(opf)?.group(1);
    if (spineToc != null && manifest[spineToc] != null) {
      return _normalizePath(opfDir, manifest[spineToc]!.href);
    }
    for (final item in manifest.values) {
      if (item.mediaType.toLowerCase().contains('dtbncx')) {
        return _normalizePath(opfDir, item.href);
      }
    }
    for (final item in manifest.values) {
      if (item.href.toLowerCase().endsWith('.ncx')) {
        return _normalizePath(opfDir, item.href);
      }
    }
    return null;
  }

  String? _findNavPath(String opfDir, Map<String, _ManifestItem> manifest) {
    for (final item in manifest.values) {
      if (item.properties.toLowerCase().split(RegExp(r'\s+')).contains('nav')) {
        return _normalizePath(opfDir, item.href);
      }
    }
    return null;
  }

  List<_RawTocItem> _parseNcx(String source, String ncxPath) {
    final dir = _dirOf(ncxPath);
    final items = <_RawTocItem>[];
    // Match every content/src; attach the nearest preceding navLabel text so
    // nested navPoints still resolve correctly.
    final contentPattern = RegExp(
      r'''<content\b[^>]*\bsrc\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
    );
    for (final match in contentPattern.allMatches(source)) {
      final src = match.group(1)!.trim();
      if (src.isEmpty) continue;
      final before = source.substring(0, match.start);
      final labelMatches = RegExp(
        r'<text\b[^>]*>([\s\S]*?)</text\s*>',
        caseSensitive: false,
      ).allMatches(before).toList();
      if (labelMatches.isEmpty) continue;
      final title = _decodeEntities(
        labelMatches.last.group(1)!.replaceAll(RegExp(r'<[^>]+>'), ''),
      ).trim();
      if (title.isEmpty) continue;
      items.add(_RawTocItem(title: title, href: src, baseDir: dir));
    }
    return items;
  }

  List<_RawTocItem> _parseNav(String source, String navPath) {
    final dir = _dirOf(navPath);
    final items = <_RawTocItem>[];
    final fragment = html_parser.parseFragment(source);
    dom.Element? tocRoot;
    for (final node in fragment.nodes.whereType<dom.Element>()) {
      if (node.localName?.toLowerCase() != 'nav') continue;
      final type = (node.attributes['epub:type'] ?? node.attributes['type'] ?? '')
          .toLowerCase();
      if (type.contains('toc') || tocRoot == null) {
        tocRoot = node;
        if (type.contains('toc')) break;
      }
    }
    tocRoot ??= fragment.querySelector('nav');
    if (tocRoot == null) return items;
    for (final anchor in tocRoot.querySelectorAll('a')) {
      final href = anchor.attributes['href']?.trim();
      final title = anchor.text.trim();
      if (href == null || href.isEmpty || title.isEmpty) continue;
      items.add(_RawTocItem(title: title, href: href, baseDir: dir));
    }
    return items;
  }

  List<BookTocEntry> _mapTocItems(
    List<_RawTocItem> items, {
    required Map<String, int> anchors,
    required Map<String, int> documentStart,
    required List<String> paragraphs,
  }) {
    final entries = <BookTocEntry>[];
    final seen = <int>{};
    for (final item in items) {
      final index = _resolveParagraphIndex(
        item,
        anchors: anchors,
        documentStart: documentStart,
      );
      if (index == null) continue;
      final clamped = index.clamp(0, paragraphs.length - 1);
      if (!seen.add(clamped)) continue;
      entries.add(BookTocEntry(title: item.title, paragraphIndex: clamped));
    }
    entries.sort((a, b) => a.paragraphIndex.compareTo(b.paragraphIndex));
    return entries;
  }

  int? _resolveParagraphIndex(
    _RawTocItem item, {
    required Map<String, int> anchors,
    required Map<String, int> documentStart,
  }) {
    final resolved = _resolveHref(item.baseDir, item.href);
    if (resolved == null) return null;
    final exact = anchors[resolved];
    if (exact != null) return exact;

    final hash = resolved.indexOf('#');
    final path = hash < 0 ? resolved : resolved.substring(0, hash);
    final fragment = hash < 0 ? '' : resolved.substring(hash + 1);

    if (fragment.isNotEmpty) {
      // Some generators rewrite ids; try a suffix match on the fragment.
      for (final entry in anchors.entries) {
        if (entry.key.endsWith('#$fragment')) return entry.value;
      }
    }

    final start = documentStart[path];
    if (start != null) return start;

    // Last resort: match by file name only (OPF hrefs sometimes differ by ./).
    final fileName = path.split('/').last;
    for (final entry in documentStart.entries) {
      if (entry.key.split('/').last == fileName) return entry.value;
    }
    return null;
  }

  String? _resolveHref(String baseDir, String href) {
    var value = href.trim();
    if (value.isEmpty) return null;
    // Strip query; keep fragment.
    final query = value.indexOf('?');
    if (query >= 0) value = value.substring(0, query);
    if (value.startsWith('#')) {
      return baseDir.isEmpty ? value : '$baseDir$value';
    }
    return _normalizePath(baseDir, value);
  }

  String? _normalizePath(String baseDir, String href) {
    var value = href.trim();
    if (value.isEmpty) return null;
    // Decode common percent-escapes used in OPF hrefs.
    value = _decodeEntities(Uri.decodeFull(value));
    final hash = value.indexOf('#');
    final fragment = hash < 0 ? '' : value.substring(hash);
    var path = hash < 0 ? value : value.substring(0, hash);
    if (path.contains('://')) return null;
    final combined = path.startsWith('/') ? path.substring(1) : '$baseDir$path';
    final parts = <String>[];
    for (final segment in combined.split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        if (parts.isNotEmpty) parts.removeLast();
        continue;
      }
      parts.add(segment);
    }
    return parts.isEmpty ? null : '${parts.join('/')}$fragment';
  }

  String _dirOf(String path) {
    final slash = path.lastIndexOf('/');
    return slash < 0 ? '' : path.substring(0, slash + 1);
  }

  String _decodeEntities(String source) {
    if (!source.contains('&')) return source;
    return source
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&amp;', '&');
  }

  String? _tryFileText(Archive archive, String name) {
    final file = archive.findFile(name);
    if (file == null || !file.isFile) return null;
    try {
      return utf8.decode(file.readBytes()!, allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  String fileText(Archive archive, String name) {
    final text = _tryFileText(archive, name);
    if (text == null) {
      throw BookImportException('EPUB 缺少文件：$name');
    }
    return text;
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

class _ManifestItem {
  const _ManifestItem({
    required this.href,
    required this.mediaType,
    required this.properties,
  });
  final String href;
  final String mediaType;
  final String properties;
}

class _SpineDocument {
  const _SpineDocument({required this.path, required this.content});
  final String path;
  final HtmlContent content;
}

class _RawTocItem {
  const _RawTocItem({
    required this.title,
    required this.href,
    required this.baseDir,
  });
  final String title;
  final String href;
  final String baseDir;
}
