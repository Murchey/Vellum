import 'package:flutter/cupertino.dart';

import '../services/book_library.dart';
import '../theme/vellum_theme.dart';
import '../widgets/font_preview.dart';

class ReaderFontPickerSheet extends StatelessWidget {
  const ReaderFontPickerSheet({
    required this.installedFonts,
    required this.activeFamily,
    required this.onSelectSystemFont,
    required this.onSelectImportedFont,
    super.key,
  });

  final List<InstalledFont> installedFonts;
  final String activeFamily;
  final ValueChanged<String> onSelectSystemFont;
  final Future<void> Function(InstalledFont) onSelectImportedFont;

  static const _systemFonts = <MapEntry<String, String>>[
    MapEntry('Georgia', '系统默认'),
    MapEntry('serif', '系统衬线'),
    MapEntry('sans-serif', '系统无衬线'),
  ];

  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .72,
    ),
    decoration: BoxDecoration(
      color: VellumTheme.cardOf(context),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
    ),
    child: SafeArea(
      top: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 12, 8),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.textformat,
                  color: VellumTheme.accentOf(context),
                ),
                const SizedBox(width: 8),
                Text(
                  '阅读字体',
                  style: TextStyle(
                    color: VellumTheme.inkOf(context),
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () => Navigator.pop(context),
                  child: const Text('完成'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              children: [
                Text(
                  '系统字体',
                  style: TextStyle(color: VellumTheme.mutedOf(context)),
                ),
                const SizedBox(height: 8),
                for (final font in _systemFonts)
                  _systemFontTile(context, font.key, font.value),
                const SizedBox(height: 14),
                Text(
                  '已导入字体',
                  style: TextStyle(color: VellumTheme.mutedOf(context)),
                ),
                const SizedBox(height: 8),
                if (installedFonts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      '尚未导入字体，可在主页面“设置 → 字体管理”中导入 TTF。',
                      style: TextStyle(color: VellumTheme.mutedOf(context)),
                    ),
                  ),
                for (final font in installedFonts)
                  _importedFontTile(context, font),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _systemFontTile(BuildContext context, String family, String name) =>
      CupertinoButton(
        padding: const EdgeInsets.only(bottom: 8),
        onPressed: () => onSelectSystemFont(family),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: activeFamily == family
                  ? VellumTheme.accentOf(context)
                  : VellumTheme.lineOf(context),
              width: activeFamily == family ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: TextStyle(color: VellumTheme.inkOf(context))),
              const SizedBox(height: 6),
              Text(
                '中文示例：阅读改变生活\nEnglish: Reading changes life',
                style: TextStyle(
                  fontFamily: family,
                  fontSize: 17,
                  height: 1.45,
                  color: VellumTheme.inkOf(context),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _importedFontTile(BuildContext context, InstalledFont font) =>
      CupertinoButton(
        padding: const EdgeInsets.only(bottom: 8),
        onPressed: () => onSelectImportedFont(font),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: activeFamily == font.family
                  ? VellumTheme.accentOf(context)
                  : VellumTheme.lineOf(context),
              width: activeFamily == font.family ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                font.name,
                style: TextStyle(color: VellumTheme.inkOf(context)),
              ),
              const SizedBox(height: 6),
              FontPreview(font: font),
            ],
          ),
        ),
      );
}
