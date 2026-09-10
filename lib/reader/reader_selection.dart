import 'package:flutter/cupertino.dart';
import 'package:url_launcher/url_launcher.dart';

import '../util/text_slices.dart' show safeSubstring, buildBingSearchUri;

export '../util/text_slices.dart' show buildBingSearchUri;

Future<void> openSelectionService(
  String text, {
  required bool translate,
}) async {
  final uri = translate
      ? Uri.https('www.deepl.com', '/translator', {
          'source': 'auto',
          'target': 'zh',
          'text': text,
        })
      : buildBingSearchUri(text);
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

Widget buildReaderSelectionToolbar(
  BuildContext context,
  EditableTextState editableTextState,
) {
  final value = editableTextState.textEditingValue;
  final selected = value.selection.textInside(value.text).trim();
  return CupertinoAdaptiveTextSelectionToolbar.buttonItems(
    anchors: editableTextState.contextMenuAnchors,
    buttonItems: [
      ContextMenuButtonItem(
        label: '复制',
        onPressed: () =>
            editableTextState.copySelection(SelectionChangedCause.toolbar),
      ),
      if (selected.isNotEmpty)
        ContextMenuButtonItem(
          label: 'Bing 查询',
          onPressed: () {
            editableTextState.hideToolbar();
            openSelectionService(selected, translate: false);
          },
        ),
      if (selected.isNotEmpty)
        ContextMenuButtonItem(
          label: 'DeepL 翻译',
          onPressed: () {
            editableTextState.hideToolbar();
            openSelectionService(selected, translate: true);
          },
        ),
    ],
  );
}

String bookmarkSummary(List<String> paragraphs, int paragraphIndex) {
  if (paragraphs.isEmpty) return '';
  final index = paragraphIndex.clamp(0, paragraphs.length - 1);
  final text = paragraphs[index];
  return text.length <= 42 ? text : '${safeSubstring(text, 0, 42)}…';
}
