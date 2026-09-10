import 'package:flutter/cupertino.dart';

import '../theme/vellum_theme.dart';

class WritingPlaceholder extends StatelessWidget {
  const WritingPlaceholder({super.key});
  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: CupertinoNavigationBar(middle: Text('写作')),
    child: Center(
      child: Text(
        '写作功能将在阅读基础完成后接入。',
        style: TextStyle(color: VellumTheme.mutedOf(context)),
      ),
    ),
  );
}
