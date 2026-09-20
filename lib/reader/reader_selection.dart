import 'package:flutter/cupertino.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/notes_library.dart';
import '../util/text_slices.dart' show safeSubstring, buildBingSearchUri;

export '../util/text_slices.dart' show buildBingSearchUri;

/// DeepL web translator prefill uses the hash fragment — query `text` is
/// ignored by the current site and left the box empty.
Uri deeplTranslateUri(String text) {
  var payload = text.trim();
  if (payload.length > 1800) {
    payload = safeSubstring(payload, 0, 1800);
  }
  return Uri.parse(
    'https://www.deepl.com/translator#auto/zh/${Uri.encodeComponent(payload)}',
  );
}

Future<void> openSelectionService(
  String text, {
  required bool translate,
}) async {
  final uri = translate ? deeplTranslateUri(text) : buildBingSearchUri(text);
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Selection toolbar factory that can also open DeepL, attach notes and mark
/// the passage with a highlight.
EditableTextContextMenuBuilder createReaderSelectionToolbar({
  required String bookId,
  required String bookTitle,
  required int Function() currentParagraph,
  NotesLibrary notesLibrary = const NotesLibrary(),
  Future<void> Function(String selected, int paragraphIndex)? onHighlight,
}) {
  return (BuildContext context, EditableTextState editableTextState) {
    final value = editableTextState.textEditingValue;
    final selected = value.selection.textInside(value.text).trim();
    final items = <ContextMenuButtonItem>[
      ContextMenuButtonItem(
        label: '复制',
        onPressed: () =>
            editableTextState.copySelection(SelectionChangedCause.toolbar),
      ),
      if (selected.isNotEmpty && onHighlight != null)
        ContextMenuButtonItem(
          label: '划线',
          onPressed: () {
            editableTextState.hideToolbar();
            onHighlight(selected, currentParagraph());
          },
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
      if (selected.isNotEmpty)
        ContextMenuButtonItem(
          label: '笔记',
          onPressed: () async {
            editableTextState.hideToolbar();
            await showAddNoteSheet(
              context,
              bookId: bookId,
              bookTitle: bookTitle,
              paragraphIndex: currentParagraph(),
              selectedText: selected,
              notesLibrary: notesLibrary,
            );
          },
        ),
    ];
    return CupertinoAdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: items,
    );
  };
}

/// Bottom sheet to capture an optional personal note for selected text.
Future<void> showAddNoteSheet(
  BuildContext context, {
  required String bookId,
  required String bookTitle,
  required int paragraphIndex,
  required String selectedText,
  NotesLibrary notesLibrary = const NotesLibrary(),
}) async {
  final controller = TextEditingController();
  try {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) {
        // Lift the sheet above the soft keyboard so the field and buttons
        // stay visible.
        final keyboard = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: keyboard),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                decoration: BoxDecoration(
                  color: CupertinoTheme.of(ctx).barBackgroundColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '添加笔记',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: CupertinoColors.systemGrey6.resolveFrom(ctx),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        selectedText,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.secondaryLabel.resolveFrom(ctx),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    CupertinoTextField(
                      controller: controller,
                      placeholder: '写下你的想法（可选）',
                      maxLines: 3,
                      minLines: 2,
                      padding: const EdgeInsets.all(10),
                      textInputAction: TextInputAction.done,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: CupertinoButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('取消'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: CupertinoButton.filled(
                            onPressed: () async {
                              await notesLibrary.add(
                                bookId: bookId,
                                bookTitle: bookTitle,
                                paragraphIndex: paragraphIndex,
                                selectedText: selectedText,
                                note: controller.text.trim(),
                              );
                              if (ctx.mounted) Navigator.pop(ctx);
                            },
                            child: const Text('保存'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  } finally {
    controller.dispose();
  }
}

String bookmarkSummary(List<String> paragraphs, int paragraphIndex) {
  if (paragraphs.isEmpty) return '';
  final index = paragraphIndex.clamp(0, paragraphs.length - 1);
  final text = paragraphs[index];
  return text.length <= 42 ? text : '${safeSubstring(text, 0, 42)}…';
}
