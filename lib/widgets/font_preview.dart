import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../services/book_library.dart';

/// Renders an imported font using the exact runtime family that is assigned
/// when it is selected. The preview binds that family before loading finishes;
/// Flutter replaces the fallback glyphs as soon as [FontLoader] completes.
class FontPreview extends StatefulWidget {
  const FontPreview({
    required this.font,
    this.compact = false,
    this.ink,
    super.key,
  });

  final InstalledFont font;
  final bool compact;

  /// Preview ink. Defaults to the ambient theme text color; the reader font
  /// picker passes the active paper's ink so night/charcoal papers stay right.
  final Color? ink;

  @override
  State<FontPreview> createState() => _FontPreviewState();
}

class _FontPreviewState extends State<FontPreview> {
  @override
  void initState() {
    super.initState();
    _loadFont();
  }

  @override
  void didUpdateWidget(covariant FontPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.font.name != widget.font.name ||
        oldWidget.font.family != widget.font.family) {
      _loadFont();
    }
  }

  Future<void> _loadFont() async {
    try {
      final bytes = await const BookLibrary().loadFontByName(widget.font.name);
      if (bytes == null) return;
      final loader = FontLoader(widget.font.family)
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
      if (mounted) setState(() {});
    } catch (_) {
      // The font row remains legible via the platform fallback if invalid.
    }
  }

  @override
  Widget build(BuildContext context) {
    final color =
        widget.ink ?? CupertinoTheme.of(context).textTheme.textStyle.color;
    if (widget.compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            '永',
            style: TextStyle(
              fontFamily: widget.font.family,
              fontSize: 23,
              color: color,
              height: 1,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            'Aa',
            style: TextStyle(
              fontFamily: widget.font.family,
              fontSize: 18,
              color: color,
              height: 1,
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '中文示例：阅读改变生活',
          style: TextStyle(
            fontFamily: widget.font.family,
            fontSize: 20,
            color: color,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'English: Reading changes life',
          style: TextStyle(
            fontFamily: widget.font.family,
            fontSize: 18,
            color: color,
          ),
        ),
      ],
    );
  }
}
