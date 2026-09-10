from pathlib import Path

src = Path("lib/services/book_importer.dart").read_text(encoding="utf-8")
# normalize double blank lines from earlier edits
while "\n\n\n" in src:
    src = src.replace("\n\n\n", "\n\n")
src = src.replace("\r\n", "\n")


def body_between(start: str, end: str) -> str:
    a = src.index(start)
    b = src.index(end, a)
    return src[a:b].rstrip() + "\n"


html = body_between("  HtmlContent _htmlContent(", "  List<BookTocEntry> _mobiTocEntries(")
# also utf8 offsets used by mobi toc - put with html or mobi
html += body_between("  List<int> _utf8OffsetsToStringOffsets(", "  HtmlContent _htmlContent(")
# actually utf8 is before html - let me re-extract properly
html = body_between("  List<int> _utf8OffsetsToStringOffsets(", "  String _titleFromFilename(")
# wait title is at end. From utf8 through normalize and title helpers
# Find better slices:
html = body_between("  HtmlContent _htmlContent(", "  String _titleFromFilename(")
utf8 = body_between("  List<int> _utf8OffsetsToStringOffsets(", "  HtmlContent _htmlContent(")
helpers = body_between("  String _titleFromFilename(", "\n}")

mobi = body_between("  ImportedBook _decodeMobi(", "  ImportedBook _decodeTxt(")
epub = body_between("  ImportedBook _decodeEpub(", "  List<BookTocEntry> _mobiTocEntries(")
txt = body_between("  ImportedBook _decodeTxt(", "  ImportedBook _decodeEpub(")
toc = body_between("  List<BookTocEntry> _mobiTocEntries(", "  List<int> _utf8OffsetsToStringOffsets(")

# make methods top-level by stripping two-space indent? Keep as mixins/classes.

def strip_this(s: str) -> str:
    # leave as-is for now; we'll wrap in classes
    return s


Path("tool/_parts_check.txt").write_text(
    f"mobi={len(mobi)} epub={len(epub)} txt={len(txt)} toc={len(toc)} utf8={len(utf8)} html={len(html)} helpers={len(helpers)}\n",
    encoding="utf-8",
)
print("ok")
