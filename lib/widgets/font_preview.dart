import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../services/book_library.dart';

class FontPreview extends StatefulWidget {
  const FontPreview({required this.font, super.key});

  final InstalledFont font;

  @override
  State<FontPreview> createState() => _FontPreviewState();
}

class _FontPreviewState extends State<FontPreview> {
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadFont();
  }

  Future<void> _loadFont() async {
    try {
      final bytes = await const BookLibrary().loadFontByName(widget.font.name);
      if (bytes == null) return;
      final loader = FontLoader(widget.font.family)
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
      if (mounted) setState(() => _loaded = true);
    } catch (_) {
      // Keep the preview readable with the system fallback if a font is invalid.
    }
  }

  @override
  Widget build(BuildContext context) {
    final previewColor = CupertinoTheme.of(context).textTheme.textStyle.color;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '中文示例：阅读改变生活',
          style: TextStyle(
            fontFamily: _loaded ? widget.font.family : null,
            fontSize: 20,
            color: previewColor,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'English: Reading changes life',
          style: TextStyle(
            fontFamily: _loaded ? widget.font.family : null,
            fontSize: 18,
            color: previewColor,
          ),
        ),
      ],
    );
  }
}
