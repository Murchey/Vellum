import 'dart:convert';
import 'dart:io';
import 'dart:isolate' show TransferableTypedData;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:path_provider/path_provider.dart';

import '../services/book_importer.dart';
import '../services/book_import_service.dart';
import '../services/book_library.dart';
import '../theme/vellum_theme.dart';

enum _ConvertPhase { idle, pickingSource, parsing, pickingPath, done, failed }

class EbookToTxtPage extends StatefulWidget {
  const EbookToTxtPage({super.key});

  @override
  State<EbookToTxtPage> createState() => _EbookToTxtPageState();
}

class _EbookToTxtPageState extends State<EbookToTxtPage> {
  final _library = const BookLibrary();
  _ConvertPhase _phase = _ConvertPhase.idle;
  String _status = '';
  String? _sourceName;
  String? _savedPath;
  String? _errorMessage;
  int _paragraphCount = 0;

  bool get _busy =>
      _phase == _ConvertPhase.pickingSource ||
      _phase == _ConvertPhase.parsing ||
      _phase == _ConvertPhase.pickingPath;

  Future<void> _startConvert() async {
    if (_busy) return;
    setState(() {
      _phase = _ConvertPhase.pickingSource;
      _status = '请选择 EPUB 或 MOBI 文件…';
      _errorMessage = null;
      _savedPath = null;
      _sourceName = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['epub', 'mobi'],
        withData: !Platform.isAndroid,
      );
      if (result == null) {
        if (!mounted) return;
        setState(() {
          _phase = _ConvertPhase.idle;
          _status = '';
        });
        return;
      }
      final selected = result.files.single;
      final bytes = selected.bytes ?? await File(selected.path!).readAsBytes();
      if (!mounted) return;
      setState(() {
        _phase = _ConvertPhase.parsing;
        _sourceName = selected.name;
        _status = '正在解析《${selected.name}》…';
      });

      final book = await compute(decodeBookInBackground, <String, dynamic>{
        'filename': selected.name,
        'bytes': TransferableTypedData.fromList([bytes]),
      });
      final text = _library.bookAsPlainText(book);
      final suggestedName = _library.suggestedTxtFilename(book);
      final textBytes = Uint8List.fromList(utf8.encode(text));

      if (!mounted) return;
      setState(() {
        _phase = _ConvertPhase.pickingPath;
        _status = '请选择 TXT 保存位置…';
        _paragraphCount = book.paragraphCount;
      });

      final savedPath = await _pickTxtSavePath(
        suggestedName: suggestedName,
        textBytes: textBytes,
        text: text,
      );
      if (!mounted) return;
      if (savedPath == null) {
        setState(() {
          _phase = _ConvertPhase.idle;
          _status = '';
          _sourceName = null;
        });
        return;
      }
      setState(() {
        _phase = _ConvertPhase.done;
        _savedPath = savedPath;
        _status = '已导出《${book.title}》';
      });
    } on BookImportException catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _ConvertPhase.failed;
        _errorMessage = error.message;
        _status = '转换失败';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _ConvertPhase.failed;
        _errorMessage = '转换失败：$error';
        _status = '转换失败';
      });
    }
  }

  Future<String?> _pickTxtSavePath({
    required String suggestedName,
    required Uint8List textBytes,
    required String text,
  }) async {
    final useSaf = Platform.isAndroid || Platform.isIOS;
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '选择 TXT 导出位置',
        fileName: suggestedName,
        type: FileType.custom,
        allowedExtensions: ['txt'],
        bytes: useSaf ? textBytes : null,
      );
      if (path == null || path.isEmpty) return null;
      if (!useSaf) {
        final file = File(path);
        final parent = file.parent;
        if (!await parent.exists()) await parent.create(recursive: true);
        await file.writeAsString(text, encoding: utf8, flush: true);
      }
      return path;
    } catch (_) {
      try {
        final directory = await FilePicker.platform.getDirectoryPath(
          dialogTitle: '选择导出文件夹',
        );
        if (directory == null || directory.isEmpty) return null;
        final file = File('$directory${Platform.pathSeparator}$suggestedName');
        await file.writeAsString(text, encoding: utf8, flush: true);
        return file.path;
      } catch (_) {
        final directory = Directory(
          '${(await getApplicationDocumentsDirectory()).path}'
          '${Platform.pathSeparator}vellum_exports',
        );
        if (!await directory.exists()) {
          await directory.create(recursive: true);
        }
        final file = File(
          '${directory.path}${Platform.pathSeparator}$suggestedName',
        );
        await file.writeAsString(text, encoding: utf8, flush: true);
        return file.path;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ink = VellumTheme.inkOf(context);
    final muted = VellumTheme.mutedOf(context);
    final accent = VellumTheme.accentOf(context);

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('转为 TXT'),
      ),
      backgroundColor: CupertinoTheme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: VellumTheme.softAccentOf(context),
                shape: BoxShape.circle,
              ),
              child: Icon(
                CupertinoIcons.doc_text,
                size: 34,
                color: accent,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '电子书转纯文本',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: VellumTheme.fontFamily,
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '将 EPUB 或 MOBI 导出为 UTF-8 TXT。\n可自由选择保存位置，适合备份或传到其他阅读器。',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, height: 1.45, fontSize: 14),
            ),
            const SizedBox(height: 22),
            DecoratedBox(
              decoration: BoxDecoration(
                color: VellumTheme.cardOf(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: VellumTheme.lineOf(context)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_phase == _ConvertPhase.idle) ...[
                      Text(
                        '选择一本电子书开始转换',
                        style: TextStyle(
                          color: ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '支持 .epub / .mobi，加密 DRM 文件无法转换。',
                        style: TextStyle(color: muted, fontSize: 13),
                      ),
                    ] else ...[
                      Row(
                        children: [
                          if (_busy)
                            const CupertinoActivityIndicator(radius: 10)
                          else if (_phase == _ConvertPhase.done)
                            Icon(
                              CupertinoIcons.checkmark_circle_fill,
                              color: accent,
                              size: 20,
                            )
                          else
                            Icon(
                              CupertinoIcons.exclamationmark_circle_fill,
                              color: CupertinoColors.systemRed,
                              size: 20,
                            ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _status,
                              style: TextStyle(
                                color: ink,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_sourceName != null) ...[
                        const SizedBox(height: 12),
                        _InfoRow(label: '源文件', value: _sourceName!),
                      ],
                      if (_paragraphCount > 0) ...[
                        const SizedBox(height: 8),
                        _InfoRow(
                          label: '段落',
                          value: '$_paragraphCount 段',
                        ),
                      ],
                      if (_savedPath != null) ...[
                        const SizedBox(height: 8),
                        _InfoRow(label: '保存到', value: _savedPath!),
                      ],
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: CupertinoColors.systemRed,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            CupertinoButton.filled(
              borderRadius: BorderRadius.circular(14),
              onPressed: _busy ? null : _startConvert,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  _busy
                      ? '处理中…'
                      : _phase == _ConvertPhase.done || _phase == _ConvertPhase.failed
                      ? '再转一本'
                      : '选择电子书',
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '转换在本机完成，不会上传文件。',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 52,
        child: Text(
          label,
          style: TextStyle(color: VellumTheme.mutedOf(context), fontSize: 13),
        ),
      ),
      Expanded(
        child: Text(
          value,
          style: TextStyle(
            color: VellumTheme.inkOf(context),
            fontSize: 13,
            height: 1.35,
          ),
        ),
      ),
    ],
  );
}
