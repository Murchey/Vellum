import 'package:flutter/cupertino.dart';

import '../services/book_library.dart';
import '../theme/vellum_theme.dart';
import '../widgets/font_preview.dart';

class FontManagerSheet extends StatelessWidget {
  final List<InstalledFont> installedFonts;
  final String activeFontName;
  final Future<void> Function(String) onActivateFont;
  final Future<void> Function(String) onDeleteFont;
  final Future<void> Function() onImportFonts;
  final String appName = 'Vellum';

  const FontManagerSheet({
    super.key,
    required this.installedFonts,
    required this.activeFontName,
    required this.onActivateFont,
    required this.onDeleteFont,
    required this.onImportFonts,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      decoration: BoxDecoration(
        color: CupertinoTheme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text(
                  '字体管理',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    Navigator.pop(context);
                    onImportFonts();
                  },
                  child: const Icon(CupertinoIcons.plus_circle),
                ),
              ],
            ),
          ),
          Container(height: 1, color: VellumTheme.lineOf(context)),
          Flexible(
            child: installedFonts.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        Icon(
                          CupertinoIcons.textformat,
                          size: 48,
                          color: VellumTheme.mutedOf(context),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '暂无字体',
                          style: TextStyle(
                            fontSize: 16,
                            color: VellumTheme.mutedOf(context),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '点击右上角 + 导入字体',
                          style: TextStyle(
                            fontSize: 14,
                            color: VellumTheme.mutedOf(context),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: installedFonts.length,
                    itemBuilder: (context, index) {
                      final font = installedFonts[index];
                      final isActive = font.name == activeFontName;
                      return _FontCard(
                        font: font,
                        isActive: isActive,
                        onActivate: () {
                          Navigator.pop(context);
                          onActivateFont(font.name);
                        },
                        onDelete: () => _confirmDelete(context, font.name),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: CupertinoButton(
                color: VellumTheme.cardOf(context),
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, String fontName) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('删除字体'),
        content: Text('确定要删除 "$fontName" 吗？'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await onDeleteFont(fontName);
      if (context.mounted) Navigator.pop(context);
    }
  }
}

class _FontCard extends StatelessWidget {
  final InstalledFont font;
  final bool isActive;
  final VoidCallback onActivate;
  final VoidCallback onDelete;

  const _FontCard({
    required this.font,
    required this.isActive,
    required this.onActivate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: VellumTheme.cardOf(context),
        borderRadius: BorderRadius.circular(12),
        border: isActive
            ? Border.all(color: VellumTheme.accentOf(context), width: 2)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 字体预览区
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: VellumTheme.cardOf(context),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
            ),
            child: FontPreview(font: font),
          ),
          // 操作区
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        font.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (isActive)
                        Text(
                          '当前使用中',
                          style: TextStyle(
                            fontSize: 12,
                            color: VellumTheme.accentOf(context),
                          ),
                        ),
                    ],
                  ),
                ),
                if (!isActive)
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    onPressed: onActivate,
                    child: const Text('启用'),
                  ),
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  onPressed: onDelete,
                  child: const Icon(
                    CupertinoIcons.trash,
                    color: CupertinoColors.systemRed,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
