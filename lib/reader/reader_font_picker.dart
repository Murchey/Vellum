import 'package:flutter/cupertino.dart';

import '../services/book_library.dart';
import '../theme/vellum_theme.dart';
import '../widgets/font_preview.dart';

/// Fanqie-style font picker data: only the built-in system font is listed by
/// default. User-imported fonts are appended from the real installed list;
/// unavailable licensed fonts are never advertised.
const fanqieReaderFonts = <ReaderFontOption>[
  ReaderFontOption('Default', '系统字体'),
];

class ReaderFontOption {
  const ReaderFontOption(this.family, this.title);
  final String family;
  final String title;
}

/// Fanqie-style font picker: a plain full-width list, preview glyph on the
/// right, orange selected state, and no decorative card treatment.
class ReaderFontPickerSheet extends StatelessWidget {
  const ReaderFontPickerSheet({
    required this.installedFonts,
    required this.activeFamily,
    required this.onSelectSystemFont,
    required this.onSelectImportedFont,
    this.surface,
    super.key,
  });

  final List<InstalledFont> installedFonts;
  final String activeFamily;
  final ValueChanged<String> onSelectSystemFont;
  final Future<void> Function(InstalledFont) onSelectImportedFont;

  /// Active reading paper. The sheet sits over the page, so its surface and
  /// ink must follow the page's paper in light and dark themes alike.
  final Color? surface;

  @override
  Widget build(BuildContext context) {
    final bg = surface ?? VellumTheme.readerChromeOf(context);
    final ink = VellumTheme.readerChromeInk(bg);
    final muted = ink.withValues(alpha: .55);
    final accent = VellumTheme.readerAccentOf(context);
    final itemCount = fanqieReaderFonts.length + installedFonts.length;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .78,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            SizedBox(
              height: 52,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Text(
                    '选择字体',
                    style: TextStyle(
                      color: ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      onPressed: () => Navigator.pop(context),
                      child: Text('完成', style: TextStyle(color: accent)),
                    ),
                  ),
                ],
              ),
            ),
            Container(height: .5, color: ink.withValues(alpha: .1)),
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: itemCount,
                separatorBuilder: (_, _) =>
                    Container(height: .5, color: ink.withValues(alpha: .08)),
                itemBuilder: (context, index) {
                  if (index < fanqieReaderFonts.length) {
                    final option = fanqieReaderFonts[index];
                    return _row(
                      title: option.title,
                      family: option.family == 'Default' ? null : option.family,
                      selected:
                          activeFamily == option.family ||
                          (option.family == 'Default' &&
                              (activeFamily.isEmpty ||
                                  activeFamily == 'Georgia')),
                      muted: muted,
                      accent: accent,
                      ink: ink,
                      onTap: () => onSelectSystemFont(
                        option.family == 'Default' ? 'Georgia' : option.family,
                      ),
                    );
                  }
                  final font = installedFonts[index - fanqieReaderFonts.length];
                  return _row(
                    title: font.label,
                    family: font.family,
                    selected: activeFamily == font.family,
                    muted: muted,
                    accent: accent,
                    ink: ink,
                    custom: FontPreview(font: font, compact: true, ink: muted),
                    onTap: () => onSelectImportedFont(font),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row({
    required String title,
    required String? family,
    required bool selected,
    required Color muted,
    required Color accent,
    required Color ink,
    required VoidCallback onTap,
    Widget? custom,
  }) => CupertinoButton(
    padding: EdgeInsets.zero,
    onPressed: onTap,
    child: Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      color: selected ? accent.withValues(alpha: .08) : null,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: selected ? accent : ink,
                fontSize: 16,
                fontFamily: family,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          if (custom != null)
            SizedBox(width: 150, child: custom)
          else
            Text(
              '永Aa',
              style: TextStyle(color: muted, fontSize: 16, fontFamily: family),
            ),
          if (selected) ...[
            const SizedBox(width: 12),
            Icon(CupertinoIcons.checkmark_alt, size: 18, color: accent),
          ],
        ],
      ),
    ),
  );
}
