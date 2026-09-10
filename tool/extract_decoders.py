from pathlib import Path
import re

src = Path("lib/services/book_importer.dart").read_text(encoding="utf-8")
src = re.sub(r"\n\s*\n", "\n", src.replace("\r\n", "\n"))

# Extract method bodies by class-like anchors
def grab(start, end):
    a = src.index(start)
    b = src.index(end, a)
    return src[a:b].strip() + "\n\n"

mobi = grab("ImportedBook _decodeMobi(", "ImportedBook _decodeTxt(")
mobi += grab("int? _firstImageRecord(", "/// MOBI `recindex` is 1-based")
mobi += grab("/// MOBI `recindex` is 1-based", "Uint8List? _mobiCover(")
mobi += grab("Uint8List? _mobiCover(", "String _decodeMobiText(")
mobi += grab("String _decodeMobiText(", "List<int> _palmDoc(")
mobi += grab("List<int> _palmDoc(", "ImportedBook _decodeTxt(")
mobi += grab("List<BookTocEntry> _mobiTocEntries(", "List<int> _utf8OffsetsToStringOffsets(")
mobi += grab("List<int> _utf8OffsetsToStringOffsets(", "HtmlContent _htmlContent(")

epub = grab("ImportedBook _decodeEpub(", "List<BookTocEntry> _mobiTocEntries(")
epub += grab("String _fileText(", "String? _attribute(")
epub += grab("String? _attribute(", "String? _attributeInTag(")
epub += grab("String? _attributeInTag(", "String? _elementText(")
epub += grab("String? _elementText(", "List<BookTocEntry> _mobiTocEntries(")

# Convert instance methods to class methods: drop leading two spaces already ok
# Replace helper calls that moved to pipeline
for old, new in [
    ("_htmlContent(", "pipeline.convert("),
    ("_titleFromFilename(", "pipeline.titleFromFilename("),
    ("_mobiTocEntries(", "mobiTocEntries("),
    ("_utf8OffsetsToStringOffsets(", "utf8OffsetsToStringOffsets("),
    ("_decodeMobiText(", "decodeMobiText("),
    ("_palmDoc(", "palmDoc("),
    ("_firstImageRecord(", "firstImageRecord("),
    ("_mobiImage(", "mobiImage("),
    ("_mobiCover(", "mobiCover("),
    ("_fileText(", "fileText("),
    ("_attributeInTag(", "attributeInTag("),
    ("_attribute(", "attribute("),
    ("_elementText(", "elementText("),
]:
    mobi = mobi.replace(old, new)
    epub = epub.replace(old, new)

# Fix decode method names to public
mobi = (
    mobi.replace("ImportedBook _decodeMobi(", "ImportedBook decode(")
    .replace("int? _firstImageRecord(", "int? firstImageRecord(")
    .replace("Uint8List? _mobiImage(", "Uint8List? mobiImage(")
    .replace("Uint8List? _mobiCover(", "Uint8List? mobiCover(")
    .replace("String _decodeMobiText(", "String decodeMobiText(")
    .replace("List<int> _palmDoc(", "List<int> palmDoc(")
    .replace("List<BookTocEntry> _mobiTocEntries(", "List<BookTocEntry> mobiTocEntries(")
    .replace("List<int> _utf8OffsetsToStringOffsets(", "List<int> utf8OffsetsToStringOffsets(")
)
epub = (
    epub.replace("ImportedBook _decodeEpub(", "ImportedBook decode(")
    .replace("String _fileText(", "String fileText(")
    .replace("String? _attribute(", "String? attribute(")
    .replace("String? _attributeInTag(", "String? attributeInTag(")
    .replace("String? _elementText(", "String? elementText(")
)

# toc still calls pipeline.htmlToText via htmlToText after convert path
mobi = mobi.replace("_htmlToText(", "pipeline.htmlToText(")

mobi_file = f"""import 'dart:convert';
import 'dart:typed_data';

import 'book_models.dart';
import 'html_text_pipeline.dart';

class MobiDecoder {{
  const MobiDecoder({{this.pipeline = const HtmlTextPipeline()}});

  final HtmlTextPipeline pipeline;

{mobi}}}
"""

epub_file = f"""import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'book_models.dart';
import 'html_text_pipeline.dart';

class EpubDecoder {{
  const EpubDecoder({{this.pipeline = const HtmlTextPipeline()}});

  final HtmlTextPipeline pipeline;

{epub}}}
"""

Path("lib/services/mobi_decoder.dart").write_text(mobi_file, encoding="utf-8")
Path("lib/services/epub_decoder.dart").write_text(epub_file, encoding="utf-8")
print("mobi", len(mobi_file.splitlines()), "epub", len(epub_file.splitlines()))
