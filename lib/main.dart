import 'dart:async';
import 'dart:io';
import 'dart:isolate' show TransferableTypedData;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart'
    show
        Divider,
        LinearProgressIndicator,
        Scrollbar,
        SelectableText,
        SelectionArea,
        DefaultMaterialLocalizations;
import 'package:url_launcher/url_launcher.dart';

import 'services/book_importer.dart';
import 'services/book_library.dart';
import 'services/vellum_update_service.dart';

Uri buildBingSearchUri(String query) {
  final encodedQuery = Uri.encodeQueryComponent(query.trim());
  return Uri.parse('https://cn.bing.com/search?q=$encodedQuery&form=QBLH');
}

ImportedBook _decodeBookInBackground(Map<String, dynamic> message) {
  final path = message['path'] as String?;
  final source = message['bytes'];
  final bytes = path != null
      ? File(path).readAsBytesSync()
      : (source as TransferableTypedData).materialize().asUint8List();
  return const BookImporter().decode(
    filename: message['filename'] as String,
    bytes: bytes,
  );
}

void main() => runApp(const VellumApp());

class VellumApp extends StatefulWidget {
  const VellumApp({super.key});

  @override
  State<VellumApp> createState() => _VellumAppState();
}

class _VellumAppState extends State<VellumApp> with WidgetsBindingObserver {
  Brightness _brightness =
      WidgetsBinding.instance.platformDispatcher.platformBrightness;
  Brightness? _manualBrightness;
  final _library = const BookLibrary();
  List<InstalledFont> _installedFonts = [];
  String _activeFontName = '';
  bool _useFontForUi = false;
  bool _useFontForContent = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadFonts();
  }

  Future<void> _loadFonts() async {
    final fonts = await _library.listFonts();
    final prefs = await _library.loadFontPreferences();
    if (!mounted) return;

    setState(() {
      _installedFonts = fonts;
      _activeFontName = prefs.activeFont;
      _useFontForUi = prefs.useForUi;
      _useFontForContent = prefs.useForContent;
    });

    // 加载激活的字体
    if (_activeFontName.isNotEmpty) {
      await _activateFont(_activeFontName);
    }
  }

  Future<void> _activateFont(String name) async {
    final bytes = await _library.loadFontByName(name);
    if (bytes == null) return;

    final family = 'Font_${name.hashCode.abs()}';
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();

    if (!mounted) return;
    setState(() {
      _activeFontName = name;
      VellumTheme.fontFamily = _useFontForUi ? family : 'Georgia';
      VellumTheme.contentFontFamily = _useFontForContent ? family : 'Georgia';
    });

    await _library.saveFontPreferences(
      FontPreferences(
        useForUi: _useFontForUi,
        useForContent: _useFontForContent,
        activeFont: name,
      ),
    );
  }

  Future<void> _importFonts() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ttf'],
      withData: true,
      allowMultiple: true,
    );
    if (result == null) return;

    for (final file in result.files) {
      if (file.bytes == null) continue;
      final name = file.name.replaceAll('.ttf', '');
      await _library.saveFontWithName(name, Uint8List.fromList(file.bytes!));
    }

    await _loadFonts();
  }

  Future<void> _deleteFont(String name) async {
    await _library.deleteFontByName(name);
    if (_activeFontName == name) {
      _activeFontName = '';
      VellumTheme.fontFamily = 'Georgia';
      VellumTheme.contentFontFamily = 'Georgia';
      await _library.saveFontPreferences(const FontPreferences());
    }
    await _loadFonts();
  }

  Future<void> _setFontUsage({
    required bool useForUi,
    required bool useForContent,
  }) async {
    final family = _activeFontName.isNotEmpty
        ? 'Font_${_activeFontName.hashCode.abs()}'
        : 'Georgia';

    setState(() {
      _useFontForUi = useForUi;
      _useFontForContent = useForContent;
      VellumTheme.fontFamily = useForUi ? family : 'Georgia';
      VellumTheme.contentFontFamily = useForContent ? family : 'Georgia';
    });

    await _library.saveFontPreferences(
      FontPreferences(
        useForUi: useForUi,
        useForContent: useForContent,
        activeFont: _activeFontName,
      ),
    );
  }

  @override
  void didChangePlatformBrightness() {
    setState(() {
      _brightness =
          WidgetsBinding.instance.platformDispatcher.platformBrightness;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CupertinoApp(
    debugShowCheckedModeBanner: false,
    title: 'Vellum',
    theme: VellumTheme.forBrightness(
      _manualBrightness ?? _brightness,
      fontFamily: _useFontForUi && _activeFontName.isNotEmpty
          ? 'Font_${_activeFontName.hashCode.abs()}'
          : 'Georgia',
    ),
    home: LibraryShell(
      onToggleTheme: () => setState(() {
        final current = _manualBrightness ?? _brightness;
        _manualBrightness = current == Brightness.dark
            ? Brightness.light
            : Brightness.dark;
      }),
      isDark: (_manualBrightness ?? _brightness) == Brightness.dark,
      installedFonts: _installedFonts,
      activeFontName: _activeFontName,
      useFontForUi: _useFontForUi,
      useFontForContent: _useFontForContent,
      onImportFonts: _importFonts,
      onActivateFont: _activateFont,
      onDeleteFont: _deleteFont,
      onFontUsageChanged: _setFontUsage,
    ),
  );
}

abstract final class VellumTheme {
  static String fontFamily = 'Georgia';
  static String contentFontFamily = 'Georgia';
  static const paper = Color(0xfff1ece1);
  static const card = Color(0xfffbf8f1);
  static const ink = Color(0xff1c1917);
  static const muted = Color(0xff78716c);
  static const accent = Color(0xffa33d2e);
  static const line = Color(0xffe2dbcd);
  // Reader fallback for the global dark UI. Reader paper choices stay
  // independent and may use their own deliberate text contrast.
  static const darkPaper = Color(0xff111110);
  static const darkCard = Color(0xff1c1917);
  static const darkInk = Color(0xfff0ebe1);
  static const darkMuted = Color(0xffa8a29e);
  static const darkAccent = Color(0xffd97757);
  static const darkLine = Color(0xff3a3530);

  static const light = CupertinoThemeData(
    brightness: Brightness.light,
    primaryColor: accent,
    scaffoldBackgroundColor: paper,
    barBackgroundColor: paper,
    textTheme: CupertinoTextThemeData(
      textStyle: TextStyle(color: ink, fontFamily: 'Georgia'),
      navTitleTextStyle: TextStyle(
        color: ink,
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  static const dark = CupertinoThemeData(
    brightness: Brightness.dark,
    primaryColor: darkAccent,
    scaffoldBackgroundColor: darkPaper,
    barBackgroundColor: darkPaper,
    textTheme: CupertinoTextThemeData(
      textStyle: TextStyle(color: darkInk, fontFamily: 'Georgia'),
      navTitleTextStyle: TextStyle(
        color: darkInk,
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  static CupertinoThemeData forBrightness(
    Brightness brightness, {
    String fontFamily = 'Georgia',
  }) {
    final base = brightness == Brightness.dark ? dark : light;
    return base.copyWith(
      textTheme: CupertinoTextThemeData(
        textStyle: base.textTheme.textStyle.copyWith(fontFamily: fontFamily),
        navTitleTextStyle: base.textTheme.navTitleTextStyle.copyWith(
          fontFamily: fontFamily,
        ),
      ),
    );
  }

  static Color inkOf(BuildContext context) =>
      CupertinoTheme.of(context).brightness == Brightness.dark ? darkInk : ink;
  static const readerNight = Color(0xff0e0e0e);
  static const readerNightInk = Color(0xffb5b5b5);
  static const readerMint = Color(0xffe4f0d8);
  static const readerSepia = Color(0xffe8e3cf);
  static const readerCharcoal = Color(0xff262626);
  static const readerCharcoalInk = Color(0xff929292);
  static const readerBlue = Color(0xffd8e4f0);
  static const readerWhite = Color(0xffffffff);

  static Color readerInkFor(Color background) {
    if (background == darkPaper) return CupertinoColors.white;
    if (background == readerNight) return readerNightInk;
    if (background == readerCharcoal) return readerCharcoalInk;
    return CupertinoColors.black;
  }

  static Color mutedOf(BuildContext context) =>
      CupertinoTheme.of(context).brightness == Brightness.dark
      ? darkMuted
      : muted;
  static Color accentOf(BuildContext context) =>
      CupertinoTheme.of(context).brightness == Brightness.dark
      ? darkAccent
      : accent;
  static Color lineOf(BuildContext context) =>
      CupertinoTheme.of(context).brightness == Brightness.dark
      ? darkLine
      : line;
  static Color cardOf(BuildContext context) =>
      CupertinoTheme.of(context).brightness == Brightness.dark
      ? darkCard
      : card;
  static Color readerChromeOf(BuildContext context) =>
      CupertinoTheme.of(context).brightness == Brightness.dark
      ? darkPaper
      : card;

  static Color softAccentOf(BuildContext context) => accentOf(
    context,
  ).withValues(alpha: .12);
}

class LibraryShell extends StatefulWidget {
  final VoidCallback onToggleTheme;
  final bool isDark;
  final List<InstalledFont> installedFonts;
  final String activeFontName;
  final bool useFontForUi;
  final bool useFontForContent;
  final Future<void> Function() onImportFonts;
  final Future<void> Function(String) onActivateFont;
  final Future<void> Function(String) onDeleteFont;
  final Future<void> Function({
    required bool useForUi,
    required bool useForContent,
  })
  onFontUsageChanged;
  const LibraryShell({
    required this.onToggleTheme,
    required this.isDark,
    required this.installedFonts,
    required this.activeFontName,
    required this.useFontForUi,
    required this.useFontForContent,
    required this.onImportFonts,
    required this.onActivateFont,
    required this.onDeleteFont,
    required this.onFontUsageChanged,
    super.key,
  });
  @override
  State<LibraryShell> createState() => _LibraryShellState();
}

class _LibraryShellState extends State<LibraryShell> {
  final _books = <ImportedBook>[];
  final _library = const BookLibrary();
  ReadingState? _continueState;
  int _tab = 0;
  bool _importing = false;
  String _importStage = '';

  @override
  void initState() {
    super.initState();
    _loadLibrary();
  }

  Future<void> _loadLibrary() async {
    final books = await _library.load();
    ReadingState? continueState;
    if (books.isNotEmpty) {
      continueState = await _library.loadReadingState(books.first);
    }
    if (!mounted) return;
    setState(() {
      _books
        ..clear()
        ..addAll(books);
      _continueState = continueState;
    });
  }

  void _setImportStage(String stage) {
    if (mounted) setState(() => _importStage = stage);
  }

  Future<void> _importBook() async {
    if (_importing) return;
    setState(() {
      _importing = true;
      _importStage = '正在打开文件选择器…';
    });
    // Allow the busy overlay to paint before the platform picker takes focus.
    await Future<void>.delayed(Duration.zero);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['epub', 'mobi', 'txt'],
        // On Android, let the worker read the picker cache path itself. Asking
        // the picker for a second full in-memory copy is what made large MOBIs
        // exhaust the UI process before parsing could even begin.
        withData: !Platform.isAndroid,
      );
      if (result == null) return;
      final file = result.files.single;
      final path = file.path;
      final bytes = file.bytes;
      if (path == null && bytes == null) {
        throw const BookImportException(
          '文件提供方没有返回可读数据。请将 MOBI 复制到设备 Download 后重试。',
        );
      }

      _setImportStage('正在解析《${file.name}》…');
      await Future<void>.delayed(Duration.zero);
      final book = await compute(_decodeBookInBackground, <String, dynamic>{
        'filename': file.name,
        if (Platform.isAndroid && bytes != null)
          'bytes': TransferableTypedData.fromList([bytes])
        else if (path != null)
          'path': path
        else
          'bytes': TransferableTypedData.fromList([bytes!]),
      });

      _setImportStage('正在保存到书库…');
      // Persist first. Do not show a book in the UI until its complete content
      // has been durably written, otherwise a failed large-book save looks like
      // a successful import that disappears on restart.
      final updatedBooks = <ImportedBook>[
        book,
        for (final existing in _books)
          if (existing.title != book.title || existing.format != book.format)
            existing,
      ];
      await _library.save(updatedBooks);
      if (!mounted) return;
      setState(() {
        _books
          ..removeWhere(
            (existing) =>
                existing.title == book.title && existing.format == book.format,
          )
          ..insert(0, book);
      });
      await _openBook(book);
    } on BookImportException catch (error) {
      if (mounted) await _showError(error.message);
    } catch (error) {
      if (mounted) await _showError('导入失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _importing = false;
          _importStage = '';
        });
      }
    }
  }

  Future<void> _convertEbookToTxt() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['epub', 'mobi'],
        withData: !Platform.isAndroid,
      );
      if (result == null) return;
      final selected = result.files.single;
      final bytes = selected.bytes ?? await File(selected.path!).readAsBytes();
      final book = await compute(_decodeBookInBackground, <String, dynamic>{
        'filename': selected.name,
        'bytes': TransferableTypedData.fromList([bytes]),
      });
      final output = await _library.exportAsTxt(book);
      if (!mounted) return;
      await showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('转换完成'),
          content: Text('《${book.title}》已导出为 TXT。\n${output.path}'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('好'),
            ),
          ],
        ),
      );
    } on BookImportException catch (error) {
      if (mounted) await _showError(error.message);
    } catch (error) {
      if (mounted) await _showError('转换失败：$error');
    }
  }

  Future<void> _showError(String message) => showCupertinoDialog<void>(
    context: context,
    builder: (context) => CupertinoAlertDialog(
      title: Text('无法导入'),
      content: Text(message),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(context),
          child: Text('好'),
        ),
      ],
    ),
  );

  Future<void> _activateReaderFont(String name) async {
    await widget.onActivateFont(name);
  }

  Future<void> _openBook(ImportedBook book) async {
    final full = await _library.loadBookContent(book);
    final state = await _library.loadReadingState(full);
    if (!mounted) return;
    await Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => ReaderPage(
          book: full,
          initialState: state,
          onStateChanged: (value) => _library.saveReadingState(full, value),
          installedFonts: widget.installedFonts,
          activeFontName: widget.activeFontName,
          onActivateFont: _activateReaderFont,
          onToggleUiTheme: widget.onToggleTheme,
        ),
      ),
    );
    if (!mounted) return;
    final latest = await _library.loadReadingState(full);
    if (mounted) setState(() => _continueState = latest);
  }

  Future<void> _deleteBook(ImportedBook book) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('删除这本书？'),
        content: Text('《${book.title}》和它的阅读记录将被删除，此操作不可恢复。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _books.remove(book));
    await _library.save(_books);
    await _library.deleteBook(book);
    await _library.deleteReadingState(book);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        CupertinoTabScaffold(
          tabBar: CupertinoTabBar(
            currentIndex: _tab,
            onTap: (value) => setState(() => _tab = value),
            activeColor: VellumTheme.accentOf(context),
            inactiveColor: VellumTheme.mutedOf(context),
            iconSize: 22,
            border: Border(top: BorderSide(color: VellumTheme.lineOf(context))),
            backgroundColor: VellumTheme.readerChromeOf(context),
            items: const [
              BottomNavigationBarItem(
                icon: Icon(CupertinoIcons.book),
                label: '阅读',
              ),
              BottomNavigationBarItem(
                icon: Icon(CupertinoIcons.square_stack_3d_up),
                label: '书库',
              ),
              BottomNavigationBarItem(
                icon: Icon(CupertinoIcons.pencil),
                label: '写作',
              ),
              BottomNavigationBarItem(
                icon: Icon(CupertinoIcons.gear),
                label: '设置',
              ),
            ],
          ),
          tabBuilder: (_, index) {
            if (index == 0) {
              return HomePage(
                books: _books,
                continueState: _continueState,
                onOpen: _openBook,
                onImport: _importBook,
              );
            }
            if (index == 1) {
              return LibraryPage(
                books: _books,
                onOpen: _openBook,
                onImport: _importBook,
                onDelete: _deleteBook,
              );
            }
            if (index == 2) return const WritingPlaceholder();
            return SettingsPage(
              onToggleTheme: widget.onToggleTheme,
              isDark: widget.isDark,
              installedFonts: widget.installedFonts,
              activeFontName: widget.activeFontName,
              useFontForUi: widget.useFontForUi,
              useFontForContent: widget.useFontForContent,
              onImportFonts: widget.onImportFonts,
              onActivateFont: widget.onActivateFont,
              onDeleteFont: widget.onDeleteFont,
              onFontUsageChanged: widget.onFontUsageChanged,
              storageUsage: _library.storageUsage,
              onClearBooks: () async {
                await _library.clearBooks();
                await _library.clearReadingStates();
                if (mounted) setState(() => _books.clear());
              },
              onClearReadingStates: _library.clearReadingStates,
              onConvertEbookToTxt: _convertEbookToTxt,
            );
          },
        ),
        if (_importing)
          Positioned.fill(
            child: ColoredBox(
              color: const Color(0x66000000),
              child: Center(
                child: Container(
                  width: 280,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: VellumTheme.cardOf(context),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: VellumTheme.lineOf(context)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CupertinoActivityIndicator(radius: 14),
                      const SizedBox(height: 18),
                      Text(
                        '正在导入电子书',
                        style: TextStyle(
                          color: VellumTheme.inkOf(context),
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _importStage,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: VellumTheme.mutedOf(context),
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '大型 MOBI 需要一点时间，请不要关闭应用。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: VellumTheme.mutedOf(context),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class HomePage extends StatelessWidget {
  final List<ImportedBook> books;
  final ReadingState? continueState;
  final ValueChanged<ImportedBook> onOpen;
  final VoidCallback onImport;
  const HomePage({
    required this.books,
    required this.onOpen,
    required this.onImport,
    this.continueState,
    super.key,
  });

  double get _continueProgress {
    final state = continueState;
    if (state == null || books.isEmpty) return 0;
    final total = books.first.paragraphCount;
    if (total <= 1) return 0;
    return (state.paragraphIndex / (total - 1)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final ink = VellumTheme.inkOf(context);
    final muted = VellumTheme.mutedOf(context);

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(
          'VELLUM',
          style: TextStyle(
            fontFamily: VellumTheme.fontFamily,
            letterSpacing: 2.2,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: onImport,
          child: const Icon(CupertinoIcons.add),
        ),
      ),
      child: SafeArea(
        child: books.isEmpty
            ? EmptyLibrary(onImport: onImport)
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  Text(
                    '继续阅读',
                    style: TextStyle(
                      fontFamily: VellumTheme.fontFamily,
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      color: ink,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _ContinueCard(
                    book: books.first,
                    progress: _continueProgress,
                    onTap: () => onOpen(books.first),
                  ),
                  if (books.length > 1) ...[
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        Text(
                          '最近加入',
                          style: TextStyle(
                            fontSize: 13,
                            color: muted,
                            fontWeight: FontWeight.w600,
                            letterSpacing: .4,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${books.length - 1} 本',
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: VellumTheme.cardOf(context),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: VellumTheme.lineOf(context)),
                      ),
                      child: Column(
                        children: [
                          for (var i = 1; i < books.length; i++) ...[
                            if (i > 1)
                              Divider(
                                height: 1,
                                indent: 74,
                                color: VellumTheme.lineOf(context),
                              ),
                            BookRow(
                              book: books[i],
                              onTap: () => onOpen(books[i]),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Center(
                    child: Text(
                      '安静地读一本书',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({
    required this.book,
    required this.progress,
    required this.onTap,
  });

  final ImportedBook book;
  final double progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = VellumTheme.inkOf(context);
    final muted = VellumTheme.mutedOf(context);
    final accent = VellumTheme.accentOf(context);
    final percent = (progress * 100).round();

    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: VellumTheme.cardOf(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: VellumTheme.lineOf(context)),
          boxShadow: [
            BoxShadow(
              color: CupertinoColors.black.withValues(
                alpha: CupertinoTheme.of(context).brightness == Brightness.dark
                    ? .25
                    : .05,
              ),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CoverThumb(book: book, width: 78, height: 112),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: VellumTheme.fontFamily,
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                      color: ink,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${book.format.name.toUpperCase()} · ${book.paragraphCount} 段',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                  const SizedBox(height: 18),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      minHeight: 4,
                      backgroundColor: VellumTheme.softAccentOf(context),
                      valueColor: AlwaysStoppedAnimation(accent),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    percent == 0 ? '从这里开始' : '已读 $percent%',
                    style: TextStyle(
                      fontSize: 12,
                      color: accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_right,
              size: 16,
              color: muted.withValues(alpha: .7),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoverThumb extends StatelessWidget {
  const _CoverThumb({
    required this.book,
    required this.width,
    required this.height,
    this.radius = 6,
  });

  final ImportedBook book;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: VellumTheme.lineOf(context)),
      ),
      position: DecorationPosition.foreground,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: book.coverBytes == null
            ? _DefaultCover(book: book)
            : Image.memory(
                book.coverBytes!,
                fit: BoxFit.cover,
                cacheWidth: (width * 2.5).round(),
                errorBuilder: (_, _, _) => _DefaultCover(book: book),
              ),
      ),
    ),
  );
}

class LibraryPage extends StatelessWidget {
  final List<ImportedBook> books;
  final ValueChanged<ImportedBook> onOpen;
  final VoidCallback onImport;
  final ValueChanged<ImportedBook> onDelete;
  const LibraryPage({
    required this.books,
    required this.onOpen,
    required this.onImport,
    required this.onDelete,
    super.key,
  });
  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: CupertinoNavigationBar(
      middle: const Text('书库'),
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: onImport,
        child: const Icon(CupertinoIcons.add),
      ),
    ),
    child: SafeArea(
      child: books.isEmpty
          ? EmptyLibrary(onImport: onImport)
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 20,
                childAspectRatio: .62,
              ),
              itemCount: books.length,
              itemBuilder: (context, index) => BookGridCard(
                book: books[index],
                onTap: () => onOpen(books[index]),
                onDelete: () => onDelete(books[index]),
              ),
            ),
    ),
  );
}

class EmptyLibrary extends StatelessWidget {
  final VoidCallback onImport;
  const EmptyLibrary({required this.onImport, super.key});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: VellumTheme.softAccentOf(context),
              shape: BoxShape.circle,
            ),
            child: Icon(
              CupertinoIcons.book,
              size: 34,
              color: VellumTheme.accentOf(context),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            '书库是空的',
            style: TextStyle(
              fontFamily: VellumTheme.fontFamily,
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: VellumTheme.inkOf(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '导入 EPUB、MOBI 或 TXT，开始你的私人书房。',
            textAlign: TextAlign.center,
            style: TextStyle(color: VellumTheme.mutedOf(context), height: 1.4),
          ),
          const SizedBox(height: 24),
          CupertinoButton.filled(
            borderRadius: BorderRadius.circular(14),
            onPressed: onImport,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Text('导入电子书'),
            ),
          ),
        ],
      ),
    ),
  );
}

class BookGridCard extends StatelessWidget {
  final ImportedBook book;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const BookGridCard({
    required this.book,
    required this.onTap,
    required this.onDelete,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final muted = VellumTheme.mutedOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: onTap,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: VellumTheme.lineOf(context),
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: CupertinoColors.black.withValues(alpha: .06),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    position: DecorationPosition.foreground,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: book.coverBytes == null
                          ? _DefaultCover(book: book)
                          : Image.memory(
                              book.coverBytes!,
                              fit: BoxFit.cover,
                              cacheWidth: 640,
                              errorBuilder: (_, _, _) =>
                                  _DefaultCover(book: book),
                            ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: CupertinoButton(
                  padding: const EdgeInsets.all(6),
                  minimumSize: const Size(30, 30),
                  onPressed: onDelete,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: CupertinoColors.systemGrey6.resolveFrom(context),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: VellumTheme.lineOf(context),
                        width: .8,
                      ),
                    ),
                    child: const Icon(
                      CupertinoIcons.delete,
                      color: CupertinoColors.systemRed,
                      size: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          book.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: VellumTheme.inkOf(context),
            fontFamily: VellumTheme.fontFamily,
            fontSize: 13,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${book.format.name.toUpperCase()} · ${book.paragraphCount} 段',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, fontSize: 11),
        ),
      ],
    );
  }
}

class _DefaultCover extends StatelessWidget {
  final ImportedBook book;
  const _DefaultCover({required this.book});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          VellumTheme.accentOf(context).withValues(alpha: .88),
          VellumTheme.accentOf(context).withValues(alpha: .62),
        ],
      ),
    ),
    alignment: Alignment.center,
    padding: const EdgeInsets.all(12),
    child: Text(
      book.format.name.toUpperCase(),
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: CupertinoColors.white,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
      ),
    ),
  );
}

class BookRow extends StatelessWidget {
  final ImportedBook book;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  const BookRow({
    required this.book,
    required this.onTap,
    this.onDelete,
    super.key,
  });
  @override
  Widget build(BuildContext context) => CupertinoButton(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    onPressed: onTap,
    child: Row(
      children: [
        _CoverThumb(book: book, width: 42, height: 58, radius: 4),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                book.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: VellumTheme.inkOf(context),
                  fontFamily: VellumTheme.fontFamily,
                  fontSize: 16,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${book.paragraphCount} 段 · ${book.format.name.toUpperCase()}',
                style: TextStyle(
                  color: VellumTheme.mutedOf(context),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        if (onDelete != null)
          CupertinoButton(
            padding: const EdgeInsets.only(left: 8),
            minimumSize: const Size(36, 36),
            onPressed: onDelete,
            child: const Icon(
              CupertinoIcons.delete,
              color: CupertinoColors.systemRed,
              size: 19,
            ),
          )
        else
          Icon(
            CupertinoIcons.chevron_right,
            size: 16,
            color: VellumTheme.mutedOf(context).withValues(alpha: .7),
          ),
      ],
    ),
  );
}

enum ReadingMode { scroll, page }

enum ReaderLineSpacing {
  compact('紧凑', 1.55),
  comfortable('舒适', 1.9),
  relaxed('宽松', 2.2);

  const ReaderLineSpacing(this.label, this.height);

  final String label;
  final double height;

  static ReaderLineSpacing fromStorage(String value) =>
      ReaderLineSpacing.values.firstWhere(
        (spacing) => spacing.name == value,
        orElse: () => ReaderLineSpacing.comfortable,
      );
}

enum ReaderFontWeight {
  light('细', FontWeight.w300),
  regular('常规', FontWeight.w400),
  bold('粗', FontWeight.w600);

  const ReaderFontWeight(this.label, this.value);

  final String label;
  final FontWeight value;

  static ReaderFontWeight fromStorage(String value) =>
      ReaderFontWeight.values.firstWhere(
        (weight) => weight.name == value,
        orElse: () => ReaderFontWeight.regular,
      );
}

class _PageFragment {
  const _PageFragment({
    required this.paragraphIndex,
    required this.text,
    this.showImage = false,
    this.showLinkAction = false,
    this.compactPadding = false,
    this.indentFirstLine = true,
  });

  final int paragraphIndex;
  final String text;
  final bool showImage;
  final bool showLinkAction;
  final bool compactPadding;
  final bool indentFirstLine;
}

class ReaderPage extends StatefulWidget {
  final ImportedBook book;
  final ReadingState initialState;
  final Future<void> Function(ReadingState)? onStateChanged;
  final List<InstalledFont> installedFonts;
  final String activeFontName;
  final Future<void> Function(String)? onActivateFont;
  final VoidCallback? onToggleUiTheme;
  const ReaderPage({
    required this.book,
    this.initialState = const ReadingState(),
    this.onStateChanged,
    this.installedFonts = const [],
    this.activeFontName = '',
    this.onActivateFont,
    this.onToggleUiTheme,
    super.key,
  });
  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late double _fontSize;
  late String _readerFontFamily;
  late ReaderFontWeight _readerFontWeight;
  late ReaderLineSpacing _lineSpacing;
  Color? _background;
  late ReadingMode _readingMode;
  bool _showControls = false;
  late final ScrollController _scrollController;
  late final PageController _pageController;
  int _currentPage = 0;
  int _requestedPage = 0;
  final List<int> _coverPageQueue = [];
  AnimationController? _coverPageController;
  int? _coverFromPage;
  int? _coverToPage;
  bool _coverJumpingPage = false;
  int _currentParagraph = 0;
  late List<int> _bookmarks;
  bool _bookmarkPullArmed = false;
  String? _bookmarkNotice;
  Timer? _bookmarkNoticeTimer;
  int _batteryLevel = -1;
  Timer? _saveTimer;
  Future<void> _saveQueue = Future<void>.value();
  DateTime? _readerPointerDownAt;
  Offset? _readerPointerDownPosition;
  bool _scrollPositionRestored = false;
  int _scrollRestoreAttempts = 0;
  int? _pendingParagraphJump;
  int _paragraphJumpAttempts = 0;
  final GlobalKey _paragraphJumpKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fontSize = widget.initialState.fontSize;
    _readerFontFamily = widget.initialState.readerFontFamily;
    _readerFontWeight = ReaderFontWeight.fromStorage(
      widget.initialState.readerFontWeight,
    );
    _lineSpacing = ReaderLineSpacing.fromStorage(
      widget.initialState.lineSpacing,
    );
    _bookmarks = widget.initialState.bookmarks.toSet().toList()..sort();
    _background = widget.initialState.backgroundValue == null
        ? null
        : Color(widget.initialState.backgroundValue!);
    _readingMode = widget.initialState.mode == 'page'
        ? ReadingMode.page
        : ReadingMode.scroll;
    _scrollController =
        ScrollController(initialScrollOffset: widget.initialState.position)
          ..addListener(() {
            _scheduleSave();
            final estimated =
                (_scrollController.offset /
                        (_fontSize * (_lineSpacing.height + 1.3)))
                    .floor();
            if (estimated != _currentParagraph && mounted) {
              setState(
                () => _currentParagraph = estimated.clamp(
                  0,
                  widget.book.paragraphs.length - 1,
                ),
              );
            }
          });
    _pageController = PageController()..addListener(_scheduleSave);
    _loadBatteryLevel();
  }

  void _restoreScrollPositionWhenReady() {
    if (_scrollPositionRestored || _readingMode != ReadingMode.scroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _scrollPositionRestored) return;
      if (!_scrollController.hasClients) {
        _scrollRestoreAttempts++;
        if (_scrollRestoreAttempts < 4) _restoreScrollPositionWhenReady();
        return;
      }
      final position = _scrollController.position;
      final requested = widget.initialState.position;
      if (requested > 0 &&
          position.maxScrollExtent <= 0 &&
          _scrollRestoreAttempts < 4) {
        _scrollRestoreAttempts++;
        _restoreScrollPositionWhenReady();
        return;
      }
      final target = requested.clamp(0.0, position.maxScrollExtent);
      if ((position.pixels - target).abs() > .5) {
        _scrollController.jumpTo(target);
      }
      _currentParagraph = (target / (_fontSize * (_lineSpacing.height + 1.3)))
          .floor()
          .clamp(0, widget.book.paragraphs.length - 1);
      _scrollPositionRestored = true;
    });
  }

  Future<void> _loadBatteryLevel() async {
    try {
      final level = await const MethodChannel(
        'vellum/device',
      ).invokeMethod<int>('batteryLevel');
      if (mounted && level != null) setState(() => _batteryLevel = level);
    } on PlatformException {
      // Battery information is optional on non-Android targets.
    }
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _saveTimer?.cancel();
      await _saveState();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _bookmarkNoticeTimer?.cancel();
    _saveState();
    _coverPageController?.dispose();
    _scrollController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _setReadingMode(ReadingMode mode) async {
    if (_readingMode == mode) return;
    setState(() {
      _readingMode = mode;
      _scrollPositionRestored = mode == ReadingMode.scroll ? false : true;
      _scrollRestoreAttempts = 0;
    });
    _saveTimer?.cancel();
    await _saveState();
  }

  void _showBookmarkNotice(String message) {
    _bookmarkNoticeTimer?.cancel();
    setState(() => _bookmarkNotice = message);
    _bookmarkNoticeTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _bookmarkNotice = null);
    });
  }

  Future<void> _addBookmarkAtCurrentPosition() async {
    final paragraph = _activeParagraph.clamp(
      0,
      widget.book.paragraphs.length - 1,
    );
    if (_bookmarks.contains(paragraph)) {
      _showBookmarkNotice('此处已有书签');
      return;
    }
    setState(() {
      _bookmarks = [..._bookmarks, paragraph]..sort();
    });
    await _saveState();
    if (mounted) _showBookmarkNotice('书签已添加');
  }

  Future<void> _removeBookmark(int paragraph) async {
    if (!_bookmarks.contains(paragraph)) return;
    setState(() => _bookmarks.remove(paragraph));
    await _saveState();
  }

  bool _handleBookmarkPull(ScrollNotification notification) {
    if (_readingMode != ReadingMode.scroll) return false;
    if (notification is OverscrollNotification &&
        notification.metrics.pixels <= 0 &&
        notification.overscroll < 0) {
      _bookmarkPullArmed = true;
    }
    if (notification is ScrollEndNotification && _bookmarkPullArmed) {
      _bookmarkPullArmed = false;
      _addBookmarkAtCurrentPosition();
    }
    return false;
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 350), _saveState);
  }

  Future<void> _saveState() async {
    final callback = widget.onStateChanged;
    if (callback == null) return;

    final paragraphIndex = _readingMode == ReadingMode.page
        ? _firstParagraphOfCurrentPage()
        : _currentParagraph;
    final state = ReadingState(
      fontSize: _fontSize,
      readerFontFamily: _readerFontFamily,
      readerFontWeight: _readerFontWeight.name,
      lineSpacing: _lineSpacing.name,
      backgroundValue: _background?.toARGB32(),
      mode: _readingMode == ReadingMode.page ? 'page' : 'scroll',
      position: _scrollController.hasClients
          ? _scrollController.offset
          : widget.initialState.position,
      page: _currentPage,
      paragraphIndex: paragraphIndex,
      bookmarks: List<int>.unmodifiable(_bookmarks),
    );
    _saveQueue = _saveQueue.then((_) => callback(state));
    await _saveQueue;
  }

  // Reader settings are an overlay. They must never change the reading
  // viewport, page boundaries, scroll offset, or current page.
  static const double _readerBottomInset = 64;

  double _pageAvailableHeight(BuildContext context) {
    final media = MediaQuery.of(context);
    // MediaQuery.size remains the full screen inside SafeArea. Subtract the
    // system insets once, then reserve reader-owned padding and footer space.
    return media.size.height -
        media.padding.top -
        media.padding.bottom -
        20 -
        _readerBottomInset -
        4;
  }

  double _pageContentWidth(BuildContext context) {
    final media = MediaQuery.of(context);
    return media.size.width - media.padding.left - media.padding.right - 56;
  }

  static final RegExp _inlineImagePattern = RegExp(r'\[\[image:\d+\]\]');
  static final RegExp _headingMarkerPattern = RegExp(
    r'^\[\[vellum-heading:([1-6])\]\]',
  );
  static final RegExp _quoteMarkerPattern = RegExp(
    r'^(?:\[\[vellum-quote\]\])+',
  );
  static final RegExp _listMarkerPattern = RegExp(r'^(?:\[\[vellum-list\]\])+');

  String _readerText(String source) => source
      .replaceFirst(_headingMarkerPattern, '')
      .replaceFirst(_quoteMarkerPattern, '')
      .replaceFirst(_listMarkerPattern, '• ');

  String _layoutText(String source) =>
      _readerText(source).replaceAll(_inlineImagePattern, '\uFFFC');

  bool _isStandaloneImageParagraph(String source) =>
      _readerText(source).replaceAll(_inlineImagePattern, '').trim().isEmpty;

  // Layout-aware pagination. Every line is measured with the same font,
  // width and line height that the reader renders; paragraphs that do not fit
  // are split at real line boundaries instead of being clipped in a PageView.
  List<List<_PageFragment>> _computePages(BuildContext context) {
    if (widget.book.paragraphs.length > 2000) {
      return _computeLargeBookPages(context);
    }
    final size = MediaQuery.sizeOf(context);
    final availableHeight = _pageAvailableHeight(context);
    final contentWidth = _pageContentWidth(context);
    final pages = <List<_PageFragment>>[[]];
    var usedHeight = _measureTitleHeight(context, contentWidth) + 30;

    void newPage() {
      pages.add([]);
      usedHeight = 0;
    }

    for (var index = 0; index < widget.book.paragraphs.length; index++) {
      final source = widget.book.paragraphs[index];
      final hasImage = widget.book.imageBytes[index] != null;
      final hasBlockImage = hasImage && _isStandaloneImageParagraph(source);
      final hasLink = widget.book.linkTargets[index] != null;
      final imageHeight = hasBlockImage ? size.height * .42 + 12 : 0.0;
      final linkHeight = hasLink ? 30.0 : 0.0;

      if (source.isEmpty) {
        final needed = imageHeight + linkHeight + 22;
        if (usedHeight + needed > availableHeight && pages.last.isNotEmpty) {
          newPage();
        }
        pages.last.add(
          _PageFragment(
            paragraphIndex: index,
            text: '',
            showImage: hasImage,
            showLinkAction: hasLink,
          ),
        );
        usedHeight += needed;
        continue;
      }

      final displaySource = source.isEmpty ? source : '\u3000\u3000$source';
      final painter = TextPainter(
        text: TextSpan(
          // Keep source offsets intact while splitting fragments. The marker is
          // short and only makes this conservative; rendering replaces it with
          // one inline object below.
          text: displaySource,
          style: TextStyle(
            fontFamily: _readerFontFamily,
            fontSize: _fontSize,
            height: _lineSpacing.height,
            fontWeight: _readerFontWeight.value,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: contentWidth);
      final lines = painter.computeLineMetrics();
      var lineStart = 0;
      var firstFragment = true;

      for (var lineIndex = 0; lineIndex < lines.length;) {
        final fragmentStart = lineStart;
        var fragmentHeight = 0.0;
        var fragmentEnd = lineStart;
        final prefixHeight = firstFragment ? imageHeight : 0.0;

        while (lineIndex < lines.length) {
          final nextHeight = fragmentHeight + lines[lineIndex].height;
          final isLastLine = lineIndex == lines.length - 1;
          final suffixHeight = 22 + (isLastLine ? linkHeight : 0.0);
          final wouldFit =
              usedHeight + prefixHeight + nextHeight + suffixHeight <=
              availableHeight;
          if (!wouldFit && fragmentEnd != fragmentStart) break;
          fragmentHeight = nextHeight;
          fragmentEnd = painter
              .getPositionForOffset(
                Offset(contentWidth, lines[lineIndex].baseline),
              )
              .offset;
          lineIndex++;
          if (!wouldFit ||
              usedHeight + prefixHeight + fragmentHeight + 22 >=
                  availableHeight)
            break;
        }

        if (fragmentEnd == fragmentStart) {
          // A single line is taller than the remaining viewport. Start a fresh
          // page and retry it there; it remains visible rather than clipped.
          newPage();
          continue;
        }

        final isLastFragment = lineIndex == lines.length;
        final needed =
            prefixHeight +
            fragmentHeight +
            22 +
            (isLastFragment ? linkHeight : 0.0);
        if (usedHeight + needed > availableHeight && pages.last.isNotEmpty) {
          lineStart = fragmentStart;
          lineIndex = lines.indexWhere(
            (line) =>
                painter
                    .getPositionForOffset(Offset(contentWidth, line.baseline))
                    .offset >
                fragmentStart,
          );
          newPage();
          continue;
        }

        pages.last.add(
          _PageFragment(
            paragraphIndex: index,
            text: source.substring(
              (fragmentStart - 2).clamp(0, source.length),
              (fragmentEnd - 2).clamp(0, source.length),
            ),
            indentFirstLine: firstFragment,
            showImage: firstFragment && hasImage,
            showLinkAction: isLastFragment && hasLink,
          ),
        );
        usedHeight += needed;
        lineStart = fragmentEnd;
        firstFragment = false;
      }
    }
    return pages;
  }

  List<List<_PageFragment>> _computeLargeBookPages(BuildContext context) {
    return _computeEstimatedLargeBookPages(context);
  }

  // Large MOBI files are paginated incrementally by bounded text slices. This
  // avoids putting a multi-megabyte TextPainter layout on the UI thread.
  List<List<_PageFragment>> _computeEstimatedLargeBookPages(
    BuildContext context,
  ) {
    final size = MediaQuery.sizeOf(context);
    final width = _pageContentWidth(context);
    final availableHeight = _pageAvailableHeight(context);
    final lineHeight = _fontSize * _lineSpacing.height;
    // The constant reader footer is already excluded by _pageAvailableHeight.
    // Keep a small rasterization guard, but do not sacrifice several full
    // lines on every page: that produces visibly sparse reading pages.
    final guardedHeight = (availableHeight - 12).clamp(
      lineHeight * 2,
      availableHeight,
    );
    final avgCharWidth = _estimateAverageCharWidth(
      widget.book.paragraphs.take(40).join(),
    );
    final charsPerLine = (width / (_fontSize * avgCharWidth)).floor().clamp(
      8,
      96,
    );
    final linesPerPage = (guardedHeight / lineHeight).floor().clamp(1, 80);
    final imageReserveLines =
        ((size.height * .36 + 16) / lineHeight).ceil() + 1;
    final titleLines =
        (_measureTitleHeight(context, width) / lineHeight).ceil() + 1;
    final regularCapacity = charsPerLine * linesPerPage;
    final pages = <List<_PageFragment>>[[]];
    var used = titleLines;
    for (var index = 0; index < widget.book.paragraphs.length; index++) {
      final source = widget.book.paragraphs[index];
      final hasImage = widget.book.imageBytes[index] != null;
      final hasBlockImage = hasImage && _isStandaloneImageParagraph(source);
      if (source.isEmpty && !hasBlockImage) continue;

      var start = 0;
      var firstPart = true;
      do {
        final imageLines = firstPart && hasBlockImage ? imageReserveLines : 0;
        var availableLines = linesPerPage - used - imageLines;
        if (availableLines <= 0 && pages.last.isNotEmpty) {
          pages.add([]);
          used = 0;
          availableLines = linesPerPage - imageLines;
        }
        final indentChars = firstPart ? 2 : 0;
        final capacity = (availableLines * charsPerLine - indentChars).clamp(
          1,
          regularCapacity,
        );
        final safeStart = start.clamp(0, source.length);
        final safeEnd = source.isEmpty
            ? 0
            : _estimateBreakOffset(source, safeStart, capacity);
        final text = source.isEmpty ? '' : source.substring(safeStart, safeEnd);
        final textLines = source.isEmpty
            ? 0
            : ((text.length + indentChars) / charsPerLine).ceil().clamp(
                1,
                availableLines,
              );
        final need = textLines + imageLines;
        pages.last.add(
          _PageFragment(
            paragraphIndex: index,
            text: text,
            indentFirstLine: firstPart,
            showImage: firstPart && hasImage,
            compactPadding: true,
          ),
        );
        used += need;
        start = safeEnd;
        firstPart = false;
      } while (start < source.length);
    }
    return pages;
  }

  /// Average advance width as a fraction of fontSize for CJK-heavy text.
  double _estimateAverageCharWidth(String sample) {
    if (sample.isEmpty) return .92;
    var cjk = 0;
    var latin = 0;
    var spaces = 0;
    for (final rune in sample.runes) {
      if (rune == 0x20 || rune == 0x3000) {
        spaces++;
      } else if (rune >= 0x2E80 && rune <= 0x9FFF ||
          rune >= 0xF900 && rune <= 0xFAFF ||
          rune >= 0xFF00 && rune <= 0xFFEF) {
        cjk++;
      } else {
        latin++;
      }
    }
    final total = (cjk + latin + spaces).clamp(1, sample.length);
    final weighted = cjk * 1.0 + latin * .52 + spaces * .3;
    return (weighted / total).clamp(.45, 1.05);
  }

  /// Prefer a sentence-end break near the slice end so pages don't split mid-thought.
  int _estimateBreakOffset(String source, int start, int capacity) {
    final hardEnd = (start + capacity).clamp(start, source.length);
    if (hardEnd >= source.length) return source.length;
    final windowStart = start + (capacity * .82).floor();
    for (var index = hardEnd; index > windowStart; index--) {
      final unit = source.codeUnitAt(index - 1);
      if (unit == 0x3002 || // 。
          unit == 0xFF01 || // ！
          unit == 0xFF1F || // ？
          unit == 0x21 ||
          unit == 0x3F ||
          unit == 0x2E) {
        return index;
      }
    }
    return hardEnd;
  }

  double _measureTitleHeight(BuildContext context, double width) {
    final painter = TextPainter(
      text: TextSpan(
        text: widget.book.title,
        style: TextStyle(
          fontFamily: _readerFontFamily,
          fontSize: _fontSize + 9,
          height: 1.3,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width);
    return painter.height;
  }

  int get _pageCount => _pages.length;
  List<List<_PageFragment>> _pages = const [[]];
  Size? _lastMeasuredSize;
  double? _lastMeasuredFontSize;
  ReaderLineSpacing? _lastMeasuredLineSpacing;
  String? _lastMeasuredFontFamily;
  ReaderFontWeight? _lastMeasuredFontWeight;
  double? _lastMeasuredPageHeight;
  double? _lastMeasuredPageWidth;
  double? _lastMeasuredBottomInset;

  void _ensurePages(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pageHeight = _pageAvailableHeight(context);
    final pageWidth = _pageContentWidth(context);
    final bottomInset = _readerBottomInset;
    if (_pages.length <= 1 ||
        _lastMeasuredSize != size ||
        _lastMeasuredFontSize != _fontSize ||
        _lastMeasuredLineSpacing != _lineSpacing ||
        _lastMeasuredFontFamily != _readerFontFamily ||
        _lastMeasuredFontWeight != _readerFontWeight ||
        _lastMeasuredPageHeight != pageHeight ||
        _lastMeasuredPageWidth != pageWidth ||
        _lastMeasuredBottomInset != bottomInset) {
      _pages = _computePages(context);
      _lastMeasuredSize = size;
      _lastMeasuredFontSize = _fontSize;
      _lastMeasuredLineSpacing = _lineSpacing;
      _lastMeasuredFontFamily = _readerFontFamily;
      _lastMeasuredFontWeight = _readerFontWeight;
      _lastMeasuredPageHeight = pageHeight;
      _lastMeasuredPageWidth = pageWidth;
      _lastMeasuredBottomInset = bottomInset;
    }
  }

  int _firstParagraphOfCurrentPage() {
    if (_pages.isEmpty ||
        _pages[_currentPage.clamp(0, _pages.length - 1)].isEmpty)
      return 0;
    return _pages[_currentPage.clamp(0, _pages.length - 1)]
        .first
        .paragraphIndex;
  }

  int _pageForParagraph(int paragraphIndex) {
    for (var page = 0; page < _pages.length; page++) {
      if (_pages[page].any(
        (fragment) => fragment.paragraphIndex >= paragraphIndex,
      )) {
        return page;
      }
    }
    return _pages.isEmpty ? 0 : _pages.length - 1;
  }

  void _restorePageWhenReady() {
    final requested = widget.initialState.paragraphIndex;
    final starts = _pages;
    if (starts.isEmpty) return;
    final target = _pageForParagraph(requested).clamp(0, starts.length - 1);
    if (target == 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pageController.hasClients && _pageController.page == 0) {
        _pageController.jumpToPage(target);
        setState(() {
          _currentPage = target;
          _requestedPage = target;
        });
      }
    });
  }

  int get _activeParagraph => _readingMode == ReadingMode.page
      ? _firstParagraphOfCurrentPage()
      : _currentParagraph;

  bool get _isCurrentViewBookmarked {
    if (_bookmarks.isEmpty) return false;
    if (_readingMode == ReadingMode.scroll) {
      return _bookmarks.contains(_activeParagraph);
    }
    if (_pages.isEmpty) return false;
    final page = _currentPage.clamp(0, _pages.length - 1);
    return _pages[page].any(
      (fragment) => _bookmarks.contains(fragment.paragraphIndex),
    );
  }

  Map<int, int> _chapterStartPages() => {
    for (final entry in _chapterEntries())
      entry.key: _pageForParagraph(entry.key) + 1,
  };

  List<MapEntry<int, String>> _chapterEntries() {
    if (widget.book.tocEntries.isNotEmpty) {
      return widget.book.tocEntries
          .map((entry) => MapEntry(entry.paragraphIndex, entry.title))
          .toList();
    }
    final chapter = RegExp(r'^\s*第[0-9一二三四五六七八九十百千万零〇]+[章节回].*');
    final entries = <MapEntry<int, String>>[];
    for (var index = 0; index < widget.book.paragraphs.length; index++) {
      final value = widget.book.paragraphs[index].trim();
      if (chapter.hasMatch(value)) entries.add(MapEntry(index, value));
    }
    return entries;
  }

  String get _pageProgress {
    if (_readingMode == ReadingMode.page)
      return '${_currentPage + 1} / $_pageCount';
    final fraction =
        _scrollController.hasClients &&
            _scrollController.position.maxScrollExtent > 0
        ? _scrollController.offset / _scrollController.position.maxScrollExtent
        : 0.0;
    final percent = (fraction * 100).clamp(0, 100).round();
    final paragraph = (_currentParagraph + 1).clamp(
      1,
      widget.book.paragraphs.length,
    );
    return '$percent% · $paragraph / ${widget.book.paragraphs.length}';
  }

  String get _batteryText => _batteryLevel < 0 ? '电量 —' : '电量 $_batteryLevel%';

  double get _progress {
    if (_readingMode == ReadingMode.page) {
      return _pageCount <= 1 ? 0 : _currentPage / (_pageCount - 1);
    }
    if (!_scrollController.hasClients ||
        _scrollController.position.maxScrollExtent <= 0)
      return 0;
    return (_scrollController.offset /
            _scrollController.position.maxScrollExtent)
        .clamp(0.0, 1.0);
  }

  void _jumpToProgress(double value) {
    if (_readingMode == ReadingMode.page) {
      final target = (value * (_pageCount - 1)).round().clamp(
        0,
        _pageCount - 1,
      );
      _pageController.animateToPage(
        target,
        duration: const Duration(milliseconds: 120),
        curve: Curves.linearToEaseOut,
      );
      return;
    }
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        value * _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 120),
        curve: Curves.linearToEaseOut,
      );
    }
  }

  void _jumpToScrollParagraph(int target) {
    if (!_scrollController.hasClients) return;
    setState(() {
      _pendingParagraphJump = target;
      _paragraphJumpAttempts = 0;
    });
    final fraction = widget.book.paragraphs.length <= 1
        ? 0.0
        : target / (widget.book.paragraphs.length - 1);
    final position = _scrollController.position;
    _scrollController.jumpTo(
      (fraction * position.maxScrollExtent).clamp(
        0.0,
        position.maxScrollExtent,
      ),
    );
    _refineScrollParagraphJump();
  }

  void _refineScrollParagraphJump() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _pendingParagraphJump == null) return;
      final targetContext = _paragraphJumpKey.currentContext;
      if (targetContext != null) {
        await Scrollable.ensureVisible(
          targetContext,
          alignment: .08,
          duration: const Duration(milliseconds: 120),
          curve: Curves.linearToEaseOut,
        );
        if (!mounted) return;
        final jumpedParagraph = _pendingParagraphJump!;
        setState(() => _pendingParagraphJump = null);
        _currentParagraph = jumpedParagraph;
        _scheduleSave();
        return;
      }
      if (_paragraphJumpAttempts++ < 5) _refineScrollParagraphJump();
    });
  }

  void _jumpToParagraph(int paragraphIndex) {
    final target = paragraphIndex.clamp(0, widget.book.paragraphs.length - 1);
    if (_readingMode == ReadingMode.page) {
      final page = _pageForParagraph(target);
      _pageController.animateToPage(
        page,
        duration: const Duration(milliseconds: 120),
        curve: Curves.linearToEaseOut,
      );
      return;
    }
    _jumpToScrollParagraph(target);
  }

  String _bookmarkSummary(int paragraphIndex) {
    final text = widget
        .book
        .paragraphs[paragraphIndex.clamp(0, widget.book.paragraphs.length - 1)]
        .replaceAll(_inlineImagePattern, '')
        .trim();
    return text.length <= 42 ? text : '${text.substring(0, 42)}…';
  }

  // ignore: unused_element
  void _showChapters() {
    final chapters = _chapterEntries();
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) {
        var tab = 0;
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final entries = tab == 0
                ? chapters
                : [
                    for (final bookmark in _bookmarks)
                      MapEntry(bookmark, _bookmarkSummary(bookmark)),
                  ];
            final emptyMessage = tab == 0 ? '这本书暂未识别出章节标题。' : '下拉阅读页面即可添加书签。';
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx).height * .7,
              ),
              decoration: BoxDecoration(
                color: VellumTheme.cardOf(ctx),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 4),
                      child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: VellumTheme.lineOf(ctx),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                      child: Row(
                        children: [
                          Icon(
                            tab == 0
                                ? CupertinoIcons.list_bullet
                                : CupertinoIcons.bookmark,
                            color: VellumTheme.accentOf(ctx),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            tab == 0 ? '目录' : '书签',
                            style: TextStyle(
                              color: VellumTheme.inkOf(ctx),
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: () => Navigator.pop(ctx),
                            child: Text(
                              '完成',
                              style: TextStyle(
                                color: VellumTheme.accentOf(ctx),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: CupertinoSlidingSegmentedControl<int>(
                        groupValue: tab,
                        children: const {0: Text('目录'), 1: Text('书签')},
                        onValueChanged: (value) {
                          if (value != null) setSheetState(() => tab = value);
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    Flexible(
                      child: entries.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  24,
                                  18,
                                  24,
                                  32,
                                ),
                                child: Text(
                                  emptyMessage,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: VellumTheme.mutedOf(ctx),
                                  ),
                                ),
                              ),
                            )
                          : Scrollbar(
                              thumbVisibility: true,
                              interactive: true,
                              thickness: 4,
                              radius: const Radius.circular(4),
                              scrollbarOrientation: ScrollbarOrientation.right,
                              child: ListView.builder(
                                primary: true,
                                padding: const EdgeInsets.only(
                                  bottom: 12,
                                  right: 6,
                                ),
                                itemCount: entries.length,
                                itemBuilder: (context, index) {
                                  final entry = entries[index];
                                  return CupertinoListTile(
                                    backgroundColor: VellumTheme.cardOf(ctx),
                                    backgroundColorActivated:
                                        VellumTheme.lineOf(ctx),
                                    title: Text(
                                      entry.value,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: VellumTheme.inkOf(ctx),
                                      ),
                                    ),
                                    additionalInfo: tab == 1
                                        ? Text('第 ${entry.key + 1} 段')
                                        : null,
                                    trailing: tab == 1
                                        ? CupertinoButton(
                                            padding: EdgeInsets.zero,
                                            minimumSize: const Size(32, 32),
                                            onPressed: () async {
                                              await _removeBookmark(entry.key);
                                              if (ctx.mounted)
                                                setSheetState(() {});
                                            },
                                            child: const Icon(
                                              CupertinoIcons.delete,
                                              size: 17,
                                            ),
                                          )
                                        : null,
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      _jumpToParagraph(entry.key);
                                    },
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _readerHeaderPanel(BuildContext context) => SafeArea(
    child: Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: VellumTheme.readerChromeOf(context).withValues(alpha: .96),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: VellumTheme.lineOf(context)),
            boxShadow: [
              BoxShadow(
                color: CupertinoColors.black.withValues(alpha: .08),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: VellumTheme.inkOf(context),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${(_progress * 100).toStringAsFixed(_progress > 0 && _progress < 0.01 ? 1 : 0)}%',
                  style: TextStyle(
                    color: VellumTheme.accentOf(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _readerStatus(BuildContext context) => IgnorePointer(
    child: SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Row(
            children: [
              Text(
                _pageProgress,
                style: TextStyle(
                  color: VellumTheme.mutedOf(context).withValues(alpha: .82),
                  fontSize: 11,
                ),
              ),
              const Spacer(),
              Text(
                _batteryText,
                style: TextStyle(
                  color: VellumTheme.mutedOf(context).withValues(alpha: .82),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Color _backgroundFor(BuildContext context) =>
      _background ??
      (CupertinoTheme.of(context).brightness == Brightness.dark
          ? VellumTheme.darkPaper
          : VellumTheme.paper);

  bool _isScrollIdle() {
    if (_readingMode != ReadingMode.scroll) return true;
    if (!_scrollController.hasClients) return true;
    return !_scrollController.position.isScrollingNotifier.value;
  }

  bool _isCenterTap(Offset position, BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final dx = (position.dx - centerX).abs();
    final dy = (position.dy - centerY).abs();
    // A generous middle zone is deliberate: the drag/long-press and idle
    // checks above protect against accidental opening while keeping portrait
    // reading comfortable on tall phones.
    return dx < size.width * 0.3 && dy < size.height * 0.25;
  }

  void _handleReaderPointerUp(BuildContext context, PointerUpEvent event) {
    final pressedAt = _readerPointerDownAt;
    final pressedPosition = _readerPointerDownPosition;
    _readerPointerDownAt = null;
    _readerPointerDownPosition = null;
    if (pressedAt == null || pressedPosition == null) return;

    final downwardPull = event.position.dy - pressedPosition.dy > 110;
    final beginsAtScrollTop =
        _readingMode != ReadingMode.scroll ||
        (_scrollController.hasClients && _scrollController.offset <= 2);
    if (downwardPull && beginsAtScrollTop) {
      // Use raw pointer displacement rather than ScrollEnd/Overscroll events:
      // Android drag dispatch varies between nested selection and scroll views.
      // Paging has no vertical scroll extent, so the same gesture bookmarks the
      // current page directly.
      _bookmarkPullArmed = false;
      _addBookmarkAtCurrentPosition();
      return;
    }

    if (DateTime.now().difference(pressedAt) >=
            const Duration(milliseconds: 450) ||
        (event.position - pressedPosition).distance > 12) {
      return;
    }

    // 只有在页面静止时才响应
    if (!_isScrollIdle()) return;

    if (_readingMode != ReadingMode.page) {
      // 滚动模式：只在屏幕中央点击时呼出 panel
      // Use the screen-space pointer coordinate so the center zone remains
      // stable even when a ListView child or SafeArea applies a transform.
      if (_isCenterTap(event.position, context)) {
        setState(() => _showControls = !_showControls);
      }
      return;
    }

    // 翻页模式：保持原有逻辑
    final width = MediaQuery.sizeOf(context).width;
    if (event.localPosition.dx < width * .3) {
      _changePage(context, -1);
    } else if (event.localPosition.dx > width * .7) {
      _changePage(context, 1);
    } else {
      setState(() => _showControls = !_showControls);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_readingMode == ReadingMode.page) {
      _ensurePages(context);
    } else {
      _restoreScrollPositionWhenReady();
    }

    return CupertinoPageScaffold(
      backgroundColor: _backgroundFor(context),
      navigationBar: null,
      child: SafeArea(
        child: Stack(
          children: [
            Localizations.override(
              context: context,
              delegates: const [DefaultMaterialLocalizations.delegate],
              child: SelectionArea(
                contextMenuBuilder: (context, selectableRegionState) {
                  final buttonItems = selectableRegionState
                      .contextMenuButtonItems
                      .map(
                        (item) => item.type == ContextMenuButtonType.copy
                            ? ContextMenuButtonItem(
                                label: '复制',
                                onPressed: item.onPressed,
                              )
                            : item,
                      )
                      .toList();
                  return CupertinoAdaptiveTextSelectionToolbar.buttonItems(
                    anchors: selectableRegionState.contextMenuAnchors,
                    buttonItems: buttonItems,
                  );
                },
                child: Listener(
                  onPointerDown: (event) {
                    _readerPointerDownAt = DateTime.now();
                    _readerPointerDownPosition = event.position;
                  },
                  onPointerCancel: (_) {
                    _readerPointerDownAt = null;
                    _readerPointerDownPosition = null;
                  },
                  onPointerUp: (event) =>
                      _handleReaderPointerUp(context, event),
                  child: _readingMode == ReadingMode.scroll
                      ? NotificationListener<ScrollNotification>(
                          onNotification: _handleBookmarkPull,
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: EdgeInsets.fromLTRB(
                              28,
                              28,
                              28,
                              _readerBottomInset,
                            ),
                            itemCount: widget.book.paragraphs.length + 2,
                            itemBuilder: (context, index) {
                              if (index == 0) return _title(context);
                              if (index == 1) return const SizedBox(height: 30);
                              final paragraphIndex = index - 2;
                              final content = Padding(
                                padding: const EdgeInsets.only(bottom: 22),
                                child: _paragraph(
                                  context,
                                  widget.book.paragraphs[paragraphIndex],
                                  paragraphIndex,
                                ),
                              );
                              return _pendingParagraphJump == paragraphIndex
                                  ? KeyedSubtree(
                                      key: _paragraphJumpKey,
                                      child: content,
                                    )
                                  : content;
                            },
                          ),
                        )
                      : Builder(
                          builder: (context) {
                            _restorePageWhenReady();
                            return PageView.builder(
                              controller: _pageController,
                              scrollDirection: Axis.horizontal,
                              physics: const ClampingScrollPhysics(),
                              allowImplicitScrolling: true,
                              itemCount: _pageCount,
                              onPageChanged: (index) {
                                if (_coverJumpingPage) {
                                  _coverJumpingPage = false;
                                  return;
                                }
                                setState(() {
                                  _currentPage = index;
                                  _requestedPage = index;
                                });
                              },
                              itemBuilder: (context, index) => Padding(
                                padding: EdgeInsets.fromLTRB(
                                  28,
                                  20,
                                  28,
                                  _readerBottomInset,
                                ),
                                child: _readingPage(context, index),
                              ),
                            );
                          },
                        ),
                ),
              ),
            ),
            _coverTurnOverlay(context),
            _readerStatus(context),
            if (_showControls) _readerHeaderPanel(context),
            if (_isCurrentViewBookmarked)
              IgnorePointer(
                child: SafeArea(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Semantics(
                      label: '当前阅读页面已添加书签',
                      child: Container(
                        width: 96,
                        height: 5,
                        margin: const EdgeInsets.only(top: 3),
                        decoration: const BoxDecoration(
                          color: CupertinoColors.systemRed,
                          borderRadius: BorderRadius.vertical(
                            bottom: Radius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (_bookmarkNotice != null)
              SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 42),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: VellumTheme.cardOf(context),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: const [
                          BoxShadow(color: Color(0x33000000), blurRadius: 12),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 9,
                        ),
                        child: Text(
                          _bookmarkNotice!,
                          style: TextStyle(
                            color: VellumTheme.inkOf(context),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (_showControls)
              Align(
                alignment: Alignment.bottomCenter,
                child: ReaderBottomControls(
                  fontSize: _fontSize,
                  readerFontWeight: _readerFontWeight,
                  lineSpacing: _lineSpacing,
                  background: _backgroundFor(context),
                  readingMode: _readingMode,
                  progress: _progress,
                  chapters: _chapterEntries(),
                  chapterStartPages: _chapterStartPages(),
                  bookmarks: [
                    for (final bookmark in _bookmarks)
                      MapEntry(bookmark, _bookmarkSummary(bookmark)),
                  ],
                  onProgress: _jumpToProgress,
                  onJumpToParagraph: (paragraph) {
                    setState(() => _showControls = false);
                    _jumpToParagraph(paragraph);
                  },
                  onRemoveBookmark: _removeBookmark,
                  onToggleUiTheme: widget.onToggleUiTheme,
                  onShowFonts: _showFontPicker,
                  onFontSize: (value) {
                    setState(() {
                      _fontSize = value;
                    });
                    _scheduleSave();
                  },
                  onReaderFontWeight: (value) {
                    setState(() => _readerFontWeight = value);
                    _saveTimer?.cancel();
                    _saveState();
                  },
                  onLineSpacing: (value) {
                    setState(() => _lineSpacing = value);
                    _saveTimer?.cancel();
                    _saveState();
                  },
                  onBackground: (value) {
                    setState(() => _background = value);
                    _scheduleSave();
                  },
                  onReadingMode: (value) {
                    _setReadingMode(value);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _enqueueCoverTurn(int target) {
    if (_coverPageQueue.isNotEmpty && _coverPageQueue.last == target) return;
    _coverPageQueue.add(target);
    _runNextCoverTurn();
  }

  void _runNextCoverTurn() {
    if (!mounted ||
        _coverPageController?.isAnimating == true ||
        _coverPageQueue.isEmpty) {
      return;
    }
    final target = _coverPageQueue.removeAt(0);
    final from = _currentPage;
    if (target == from) {
      _runNextCoverTurn();
      return;
    }
    _coverFromPage = from;
    _coverToPage = target;
    setState(() {});
    final controller = _coverPageController ??=
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 320),
        )..addListener(() {
          if (mounted) setState(() {});
        });
    controller
      ..reset()
      ..forward().whenComplete(() {
        if (!mounted) return;
        _coverJumpingPage = true;
        _pageController.jumpToPage(target);
        setState(() {
          _currentPage = target;
          _coverFromPage = null;
          _coverToPage = null;
        });
        _runNextCoverTurn();
      });
  }

  Widget _coverPageSurface(BuildContext context, int page) => ColoredBox(
    color: _backgroundFor(context),
    child: Padding(
      padding: EdgeInsets.fromLTRB(28, 20, 28, _readerBottomInset),
      child: _readingPage(context, page),
    ),
  );

  Widget _coverTurnOverlay(BuildContext context) {
    final from = _coverFromPage;
    final to = _coverToPage;
    final controller = _coverPageController;
    if (from == null || to == null || controller == null) {
      return const SizedBox.shrink();
    }
    final progress = Curves.easeInOutCubic.transform(controller.value);
    final isNext = to > from;
    final width = MediaQuery.sizeOf(context).width;
    final movingOffset = (isNext ? -progress : -1 + progress) * width;
    final movingPage = isNext ? from : to;
    final staticPage = isNext ? to : from;
    return Positioned.fill(
      child: IgnorePointer(
        child: ClipRect(
          child: Stack(
            children: [
              Positioned.fill(child: _coverPageSurface(context, staticPage)),
              Positioned.fill(
                child: Transform.translate(
                  offset: Offset(movingOffset, 0),
                  child: _coverPageSurface(context, movingPage),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _readingPage(BuildContext context, int pageIndex) {
    final fragments = _pages[pageIndex];

    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          SizedBox(
            height: constraints.maxHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (pageIndex == 0) _title(context),
                if (pageIndex == 0) const SizedBox(height: 30),
                for (var index = 0; index < fragments.length; index++) ...[
                  // The last fragment gets a stable baseline. Any slack is
                  // placed immediately above it, never beneath it or inside
                  // the footer.
                  if (index == fragments.length - 1) const Spacer(),
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: index == fragments.length - 1
                          ? 0
                          : (fragments[index].compactPadding ? 0 : 22),
                    ),
                    child: _paragraph(
                      context,
                      fragments[index].text,
                      fragments[index].paragraphIndex,
                      showImage: fragments[index].showImage,
                      showLinkAction: fragments[index].showLinkAction,
                      indentFirstLine: fragments[index].indentFirstLine,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _title(BuildContext context) => Text(
    widget.book.title,
    style: TextStyle(
      fontFamily: _readerFontFamily,
      fontSize: _fontSize + 9,
      height: 1.3,
      fontWeight: FontWeight.w600,
      color: VellumTheme.readerInkFor(_backgroundFor(context)),
    ),
  );

  Future<void> _openSelectionService(
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

  Widget _selectionToolbar(
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
              _openSelectionService(selected, translate: false);
            },
          ),
        if (selected.isNotEmpty)
          ContextMenuButtonItem(
            label: 'DeepL 翻译',
            onPressed: () {
              editableTextState.hideToolbar();
              _openSelectionService(selected, translate: true);
            },
          ),
      ],
    );
  }

  List<InlineSpan> _inlineImageSpans(String source, Uint8List image) {
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final marker in _inlineImagePattern.allMatches(source)) {
      if (marker.start > cursor) {
        spans.add(TextSpan(text: source.substring(cursor, marker.start)));
      }
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Image.memory(
              image,
              width: _fontSize * 1.05,
              height: _fontSize * 1.05,
              fit: BoxFit.contain,
              cacheWidth: (_fontSize * 2.2).round(),
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        ),
      );
      cursor = marker.end;
    }
    if (cursor < source.length)
      spans.add(TextSpan(text: source.substring(cursor)));
    return spans;
  }

  Widget _paragraph(
    BuildContext context,
    String paragraph,
    int paragraphIndex, {
    bool showImage = true,
    bool showLinkAction = true,
    bool indentFirstLine = true,
  }) {
    final image = showImage ? widget.book.imageBytes[paragraphIndex] : null;
    final target = showLinkAction
        ? widget.book.linkTargets[paragraphIndex]
        : null;
    final standaloneImage = _isStandaloneImageParagraph(paragraph);
    final inlineImage = image != null && !standaloneImage;
    final heading = _headingMarkerPattern.firstMatch(paragraph);
    final isQuote = _quoteMarkerPattern.hasMatch(paragraph);
    final isList = _listMarkerPattern.hasMatch(paragraph);
    final isTocHeading = widget.book.tocEntries.any(
      (entry) => entry.paragraphIndex == paragraphIndex,
    );
    final headingLevel = int.tryParse(heading?.group(1) ?? '');
    final effectiveHeading = headingLevel ?? (isTocHeading ? 2 : null);
    // Keep title height aligned with the paginator. Weight, alignment and
    // indentation already differentiate headings without letting a short
    // chapter label overflow the measured page viewport.
    final displayFontSize = _fontSize;
    final textStyle = TextStyle(
      fontFamily: _readerFontFamily,
      fontSize: displayFontSize,
      height: _lineSpacing.height,
      fontWeight: effectiveHeading == null
          ? _readerFontWeight.value
          : FontWeight.w600,
      fontStyle: isQuote ? FontStyle.italic : null,
      color: target == null
          ? VellumTheme.readerInkFor(_backgroundFor(context))
          : VellumTheme.accentOf(context),
      decoration: target == null ? null : TextDecoration.underline,
    );
    final needsFirstLineIndent =
        indentFirstLine &&
        paragraph.isNotEmpty &&
        effectiveHeading == null &&
        !isQuote &&
        !isList;
    final displayParagraph = _readerText(paragraph);
    final spans = <InlineSpan>[
      if (needsFirstLineIndent)
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: SizedBox(
            key: ValueKey('paragraph-indent-$paragraphIndex'),
            width: _fontSize * 2,
            height: 1,
          ),
        ),
      if (inlineImage)
        ..._inlineImageSpans(displayParagraph, image)
      else
        TextSpan(text: _layoutText(displayParagraph)),
    ];
    final text = SelectableText.rich(
      TextSpan(style: textStyle, children: spans),
      contextMenuBuilder: _selectionToolbar,
      textAlign: TextAlign.justify,
    );
    final formattedText = isQuote
        ? Container(
            padding: const EdgeInsets.only(left: 14),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: VellumTheme.accentOf(context).withValues(alpha: .7),
                  width: 3,
                ),
              ),
            ),
            child: text,
          )
        : text;
    final content = <Widget>[
      if (image != null && standaloneImage)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Image.memory(
            image,
            fit: BoxFit.contain,
            width: double.infinity,
            height: MediaQuery.sizeOf(context).height * .36,
            cacheWidth: (MediaQuery.sizeOf(context).width * 2).round(),
            errorBuilder: (context, error, stackTrace) =>
                const SizedBox.shrink(),
          ),
        ),
      if (_layoutText(displayParagraph).isNotEmpty) formattedText,
    ];
    if (target == null)
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: content,
      );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...content,
        CupertinoButton(
          padding: const EdgeInsets.only(top: 2),
          minimumSize: const Size(0, 28),
          onPressed: () => _jumpToParagraph(target),
          child: const Text('跳转至书内链接'),
        ),
      ],
    );
  }

  void _showFontPicker() {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => ReaderFontPickerSheet(
        installedFonts: widget.installedFonts,
        activeFamily: _readerFontFamily,
        onSelectSystemFont: (family) {
          Navigator.pop(ctx);
          setState(() {
            _readerFontFamily = family;
            _lastMeasuredFontFamily = null;
          });
          _saveState();
        },
        onSelectImportedFont: (font) async {
          if (widget.onActivateFont == null) return;
          await widget.onActivateFont!(font.name);
          if (!mounted || !ctx.mounted) return;
          Navigator.pop(ctx);
          setState(() {
            _readerFontFamily = font.family;
            _lastMeasuredFontFamily = null;
          });
          _saveState();
        },
      ),
    );
  }

  void _changePage(BuildContext context, int delta) {
    if (!_pageController.hasClients) return;
    final pageCount = _pageCount;
    // Do not derive the next target from the animated viewport. Keeping an
    // independent requested page makes quick repeated taps accumulate instead
    // of repeatedly targeting the same in-flight page.
    final base = _requestedPage.clamp(0, pageCount - 1);
    final target = (base + delta).clamp(0, pageCount - 1);
    if (target == base) return;
    setState(() => _requestedPage = target);
    _enqueueCoverTurn(target);
  }
}

class ReadingControls extends StatelessWidget {
  final double fontSize;
  final ReaderFontWeight readerFontWeight;
  final ReaderLineSpacing lineSpacing;
  final Color background;
  final ReadingMode readingMode;
  final double progress;
  final ValueChanged<double> onProgress;
  final VoidCallback onShowChapters;
  final VoidCallback onShowFonts;
  final ValueChanged<double> onFontSize;
  final ValueChanged<ReaderLineSpacing> onLineSpacing;
  final ValueChanged<Color> onBackground;
  final ValueChanged<ReadingMode> onReadingMode;
  const ReadingControls({
    required this.fontSize,
    required this.readerFontWeight,
    required this.lineSpacing,
    required this.background,
    required this.readingMode,
    required this.progress,
    required this.onProgress,
    required this.onShowChapters,
    required this.onShowFonts,
    required this.onFontSize,
    required this.onLineSpacing,
    required this.onBackground,
    required this.onReadingMode,
    super.key,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
    decoration: BoxDecoration(
      // This is a true opaque overlay: it must not let reader paragraphs show
      // through the controls. Its visibility never participates in pagination.
      color: VellumTheme.cardOf(context),
      border: Border(top: BorderSide(color: VellumTheme.lineOf(context))),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(
              CupertinoIcons.book,
              size: 18,
              color: VellumTheme.accentOf(context),
            ),
            const SizedBox(width: 8),
            Text(
              '阅读设置',
              style: TextStyle(
                color: VellumTheme.inkOf(context),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              '${(progress * 100).round()}%',
              style: TextStyle(
                color: VellumTheme.mutedOf(context),
                fontSize: 13,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Text('阅读方式', style: TextStyle(color: VellumTheme.mutedOf(context))),
            const SizedBox(width: 18),
            Expanded(
              child: CupertinoSlidingSegmentedControl<ReadingMode>(
                groupValue: readingMode,
                children: const {
                  ReadingMode.scroll: Text('上下滚动'),
                  ReadingMode.page: Text('左右翻页'),
                },
                onValueChanged: (value) {
                  if (value != null) onReadingMode(value);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Text('行间距', style: TextStyle(color: VellumTheme.mutedOf(context))),
            const SizedBox(width: 18),
            Expanded(
              child: CupertinoSlidingSegmentedControl<ReaderLineSpacing>(
                groupValue: lineSpacing,
                children: {
                  for (final spacing in ReaderLineSpacing.values)
                    spacing: Text(spacing.label),
                },
                onValueChanged: (value) {
                  if (value != null) onLineSpacing(value);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Text('字号', style: TextStyle(color: VellumTheme.mutedOf(context))),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              onPressed: () => onFontSize((fontSize - 1).clamp(16, 36)),
              child: const Text('A−'),
            ),
            Expanded(
              child: CupertinoSlider(
                value: fontSize,
                min: 16,
                max: 36,
                onChanged: onFontSize,
              ),
            ),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              onPressed: () => onFontSize((fontSize + 1).clamp(16, 36)),
              child: const Text('A+'),
            ),
            Text(
              '${fontSize.round()}',
              style: TextStyle(color: VellumTheme.mutedOf(context)),
            ),
          ],
        ),
        Row(
          children: [
            Text('背景', style: TextStyle(color: VellumTheme.mutedOf(context))),
            const SizedBox(width: 18),
            ...[
              VellumTheme.readerNight,
              VellumTheme.readerMint,
              VellumTheme.readerSepia,
              VellumTheme.readerCharcoal,
              VellumTheme.readerBlue,
              VellumTheme.readerWhite,
            ].map(
              (color) => GestureDetector(
                onTap: () => onBackground(color),
                child: Container(
                  width: 30,
                  height: 30,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: background == color
                          ? VellumTheme.accentOf(context)
                          : VellumTheme.lineOf(context),
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: onShowChapters,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(CupertinoIcons.list_bullet, size: 17),
                  SizedBox(width: 6),
                  Text('章节'),
                ],
              ),
            ),
            const SizedBox(width: 16),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: onShowFonts,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(CupertinoIcons.textformat, size: 17),
                  SizedBox(width: 6),
                  Text('字体'),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              '阅读进度',
              style: TextStyle(
                color: VellumTheme.mutedOf(context),
                fontSize: 12,
              ),
            ),
            Expanded(
              child: CupertinoSlider(
                value: progress.clamp(0.0, 1.0),
                onChanged: onProgress,
              ),
            ),
            Text(
              '${(progress * 100).round()}%',
              style: TextStyle(
                color: VellumTheme.mutedOf(context),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

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
              _FontPreview(font: font),
            ],
          ),
        ),
      );
}

enum ReaderControlPanel { directory, settings }

class ReaderBottomControls extends StatefulWidget {
  const ReaderBottomControls({
    required this.fontSize,
    required this.readerFontWeight,
    required this.lineSpacing,
    required this.background,
    required this.readingMode,
    required this.progress,
    required this.chapters,
    required this.chapterStartPages,
    required this.bookmarks,
    required this.onProgress,
    required this.onJumpToParagraph,
    required this.onRemoveBookmark,
    this.onToggleUiTheme,
    required this.onShowFonts,
    required this.onFontSize,
    required this.onReaderFontWeight,
    required this.onLineSpacing,
    required this.onBackground,
    required this.onReadingMode,
    super.key,
  });

  final double fontSize;
  final ReaderFontWeight readerFontWeight;
  final ReaderLineSpacing lineSpacing;
  final Color background;
  final ReadingMode readingMode;
  final double progress;
  final List<MapEntry<int, String>> chapters;
  final Map<int, int> chapterStartPages;
  final List<MapEntry<int, String>> bookmarks;
  final ValueChanged<double> onProgress;
  final ValueChanged<int> onJumpToParagraph;
  final Future<void> Function(int) onRemoveBookmark;
  final VoidCallback? onToggleUiTheme;
  final VoidCallback onShowFonts;
  final ValueChanged<double> onFontSize;
  final ValueChanged<ReaderFontWeight> onReaderFontWeight;
  final ValueChanged<ReaderLineSpacing> onLineSpacing;
  final ValueChanged<Color> onBackground;
  final ValueChanged<ReadingMode> onReadingMode;

  @override
  State<ReaderBottomControls> createState() => _ReaderBottomControlsState();
}

class _ReaderBottomControlsState extends State<ReaderBottomControls> {
  ReaderControlPanel? _openPanel;
  var _directoryTab = 0;

  void _togglePanel(ReaderControlPanel panel) {
    setState(() => _openPanel = _openPanel == panel ? null : panel);
  }

  bool get _isDark => CupertinoTheme.of(context).brightness == Brightness.dark;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: VellumTheme.readerChromeOf(context),
      border: Border(top: BorderSide(color: VellumTheme.lineOf(context))),
      boxShadow: [
        BoxShadow(
          color: CupertinoColors.black.withValues(alpha: .08),
          blurRadius: 18,
          offset: const Offset(0, -4),
        ),
      ],
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: _openPanel == null
              ? const SizedBox.shrink()
              : _openPanel == ReaderControlPanel.directory
              ? _directoryPanel(context)
              : _settingsPanel(context),
        ),
        Container(height: 1, color: VellumTheme.lineOf(context)),
        SizedBox(
          height: 64,
          child: Row(
            children: [
              _barButton(
                context,
                icon: CupertinoIcons.list_bullet,
                label: '目录',
                selected: _openPanel == ReaderControlPanel.directory,
                onPressed: () => _togglePanel(ReaderControlPanel.directory),
              ),
              _barButton(
                context,
                icon: _isDark ? CupertinoIcons.sun_max : CupertinoIcons.moon,
                label: _isDark ? '浅色' : '深色',
                selected: false,
                onPressed: widget.onToggleUiTheme ?? () {},
              ),
              _barButton(
                context,
                icon: CupertinoIcons.gear,
                label: '设置',
                selected: _openPanel == ReaderControlPanel.settings,
                onPressed: () => _togglePanel(ReaderControlPanel.settings),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _barButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onPressed,
  }) => Expanded(
    child: CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 20,
            color: selected
                ? VellumTheme.accentOf(context)
                : VellumTheme.mutedOf(context),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              color: selected
                  ? VellumTheme.accentOf(context)
                  : VellumTheme.inkOf(context),
              fontSize: 12,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _directoryPanel(BuildContext context) {
    final entries = _directoryTab == 0 ? widget.chapters : widget.bookmarks;
    final emptyMessage = _directoryTab == 0 ? '这本书暂未识别出章节标题。' : '下拉阅读页面即可添加书签。';
    return SizedBox(
      height: 330,
      child: Column(
        children: [
          _panelTitle(
            context,
            icon: _directoryTab == 0
                ? CupertinoIcons.list_bullet
                : CupertinoIcons.bookmark,
            title: _directoryTab == 0 ? '目录' : '书签',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: CupertinoSlidingSegmentedControl<int>(
              groupValue: _directoryTab,
              children: const {0: Text('目录'), 1: Text('书签')},
              onValueChanged: (value) {
                if (value != null) setState(() => _directoryTab = value);
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Text(
                      emptyMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: VellumTheme.mutedOf(context)),
                    ),
                  )
                : Scrollbar(
                    thumbVisibility: true,
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return CupertinoListTile(
                          backgroundColor: VellumTheme.cardOf(context),
                          backgroundColorActivated: VellumTheme.lineOf(context),
                          title: Text(
                            entry.value,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: VellumTheme.inkOf(context)),
                          ),
                          additionalInfo: _directoryTab == 1
                              ? Text('第 ${entry.key + 1} 段')
                              : Text(
                                  '第 ${widget.chapterStartPages[entry.key] ?? 1} 页',
                                  style: TextStyle(
                                    color: VellumTheme.mutedOf(context),
                                  ),
                                ),
                          trailing: _directoryTab == 1
                              ? CupertinoButton(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(32, 32),
                                  onPressed: () async {
                                    await widget.onRemoveBookmark(entry.key);
                                    if (mounted) setState(() {});
                                  },
                                  child: const Icon(
                                    CupertinoIcons.delete,
                                    size: 17,
                                  ),
                                )
                              : null,
                          onTap: () => widget.onJumpToParagraph(entry.key),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _settingsPanel(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .58,
    ),
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: Column(
        children: [
          _panelTitle(context, icon: CupertinoIcons.gear, title: '阅读设置'),
          _settingRow(
            context,
            '阅读方式',
            CupertinoSlidingSegmentedControl<ReadingMode>(
              groupValue: widget.readingMode,
              children: const {
                ReadingMode.scroll: Text('上下滚动'),
                ReadingMode.page: Text('左右翻页'),
              },
              onValueChanged: (value) {
                if (value != null) widget.onReadingMode(value);
              },
            ),
          ),
          const SizedBox(height: 10),
          _settingRow(
            context,
            '行间距',
            CupertinoSlidingSegmentedControl<ReaderLineSpacing>(
              groupValue: widget.lineSpacing,
              children: {
                for (final spacing in ReaderLineSpacing.values)
                  spacing: Text(spacing.label),
              },
              onValueChanged: (value) {
                if (value != null) widget.onLineSpacing(value);
              },
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text('字号', style: TextStyle(color: VellumTheme.mutedOf(context))),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                onPressed: () =>
                    widget.onFontSize((widget.fontSize - 1).clamp(16, 36)),
                child: const Text('A−'),
              ),
              Expanded(
                child: CupertinoSlider(
                  value: widget.fontSize,
                  min: 16,
                  max: 36,
                  onChanged: widget.onFontSize,
                ),
              ),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                onPressed: () =>
                    widget.onFontSize((widget.fontSize + 1).clamp(16, 36)),
                child: const Text('A+'),
              ),
              Text(
                '${widget.fontSize.round()}',
                style: TextStyle(color: VellumTheme.mutedOf(context)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _settingRow(
            context,
            '字重',
            CupertinoSlidingSegmentedControl<ReaderFontWeight>(
              groupValue: widget.readerFontWeight,
              children: {
                for (final weight in ReaderFontWeight.values)
                  weight: Text(weight.label),
              },
              onValueChanged: (value) {
                if (value != null) widget.onReaderFontWeight(value);
              },
            ),
          ),
          const SizedBox(height: 10),
          _settingRow(
            context,
            '背景',
            Row(
              mainAxisSize: MainAxisSize.min,
              children:
                  [
                        VellumTheme.readerNight,
                        VellumTheme.readerMint,
                        VellumTheme.readerSepia,
                        VellumTheme.readerCharcoal,
                        VellumTheme.readerBlue,
                        VellumTheme.readerWhite,
                      ]
                      .map(
                        (color) => GestureDetector(
                          onTap: () => widget.onBackground(color),
                          child: Container(
                            width: 28,
                            height: 28,
                            margin: const EdgeInsets.only(left: 8),
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: widget.background == color
                                    ? VellumTheme.accentOf(context)
                                    : VellumTheme.lineOf(context),
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
            ),
          ),
          Row(
            children: [
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: widget.onShowFonts,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.textformat, size: 17),
                    SizedBox(width: 6),
                    Text('字体'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '阅读进度',
                style: TextStyle(color: VellumTheme.mutedOf(context)),
              ),
              Expanded(
                child: CupertinoSlider(
                  value: widget.progress.clamp(0.0, 1.0),
                  onChanged: widget.onProgress,
                ),
              ),
              Text(
                '${(widget.progress * 100).round()}%',
                style: TextStyle(color: VellumTheme.mutedOf(context)),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _panelTitle(
    BuildContext context, {
    required IconData icon,
    required String title,
  }) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
    child: Row(
      children: [
        Icon(icon, size: 18, color: VellumTheme.accentOf(context)),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: VellumTheme.inkOf(context),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(32, 28),
          onPressed: () => setState(() => _openPanel = null),
          child: const Icon(CupertinoIcons.chevron_down, size: 18),
        ),
      ],
    ),
  );

  Widget _settingRow(BuildContext context, String label, Widget child) => Row(
    children: [
      SizedBox(
        width: 58,
        child: Text(
          label,
          style: TextStyle(color: VellumTheme.mutedOf(context)),
        ),
      ),
      Expanded(child: child),
    ],
  );
}

class SettingsPage extends StatefulWidget {
  final VoidCallback onToggleTheme;
  final bool isDark;
  final List<InstalledFont> installedFonts;
  final String activeFontName;
  final bool useFontForUi;
  final bool useFontForContent;
  final Future<void> Function() onImportFonts;
  final Future<void> Function(String) onActivateFont;
  final Future<void> Function(String) onDeleteFont;
  final Future<void> Function({
    required bool useForUi,
    required bool useForContent,
  })
  onFontUsageChanged;
  final Future<StorageUsage> Function() storageUsage;
  final Future<void> Function() onClearBooks;
  final Future<void> Function() onClearReadingStates;
  final Future<void> Function() onConvertEbookToTxt;
  const SettingsPage({
    required this.onToggleTheme,
    required this.isDark,
    required this.installedFonts,
    required this.activeFontName,
    required this.useFontForUi,
    required this.useFontForContent,
    required this.onImportFonts,
    required this.onActivateFont,
    required this.onDeleteFont,
    required this.onFontUsageChanged,
    required this.storageUsage,
    required this.onClearBooks,
    required this.onClearReadingStates,
    required this.onConvertEbookToTxt,
    super.key,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late Future<StorageUsage> _usage;
  bool _checkingUpdate = false;

  @override
  void initState() {
    super.initState();
    _usage = widget.storageUsage();
  }

  void _refresh() => setState(() => _usage = widget.storageUsage());

  Future<void> _checkForUpdate() async {
    setState(() => _checkingUpdate = true);
    try {
      final release = await const VellumUpdateService().check();
      if (!mounted) return;
      if (release == null) {
        await _showUpdateDialog('无法连接 GitHub Release，请稍后重试。');
      } else if (!release.hasUpdate) {
        await _showUpdateDialog('当前已是最新版本 V${release.currentVersion}。');
      } else {
        final assets = release.assets.keys.isEmpty
            ? '未发布 APK 资产'
            : release.assets.keys.join('\n');
        await showCupertinoDialog<void>(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: Text('发现新版本 V${release.latestVersion}'),
            content: Text(
              '${release.notes.isEmpty ? 'GitHub Release 已发布更新。' : release.notes}\n\n可用安装包：\n$assets',
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(context),
                child: const Text('稍后'),
              ),
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () async {
                  Navigator.pop(context);
                  await launchUrl(
                    Uri.parse(release.releaseUrl),
                    mode: LaunchMode.externalApplication,
                  );
                },
                child: const Text('前往下载'),
              ),
            ],
          ),
        );
      }
    } catch (_) {
      if (mounted) await _showUpdateDialog('检查更新失败，请稍后重试。');
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  Future<void> _showUpdateDialog(String message) => showCupertinoDialog<void>(
    context: context,
    builder: (context) => CupertinoAlertDialog(
      title: const Text('检查更新'),
      content: Text(message),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('好'),
        ),
      ],
    ),
  );

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _confirm(
    String title,
    String message,
    Future<void> Function() action,
  ) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清理'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await action();
      if (mounted) _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pageBackground = CupertinoTheme.of(context).scaffoldBackgroundColor;
    final pressedBackground = VellumTheme.cardOf(context);
    final hasActiveFont = widget.activeFontName.isNotEmpty;

    return CupertinoPageScaffold(
      backgroundColor: pageBackground,
      navigationBar: const CupertinoNavigationBar(middle: Text('设置')),
      child: SafeArea(
        child: ListView(
          children: [
            CupertinoListSection.insetGrouped(
              backgroundColor: pageBackground,
              header: const Text('外观'),
              children: [
                CupertinoListTile(
                  backgroundColor: pageBackground,
                  backgroundColorActivated: pressedBackground,
                  leading: Icon(
                    widget.isDark
                        ? CupertinoIcons.sun_max
                        : CupertinoIcons.moon,
                  ),
                  title: const Text('界面主题'),
                  additionalInfo: Text(widget.isDark ? '深色' : '浅色'),
                  onTap: widget.onToggleTheme,
                ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              backgroundColor: pageBackground,
              header: const Text('字体管理'),
              children: [
                CupertinoListTile(
                  backgroundColor: pageBackground,
                  backgroundColorActivated: pressedBackground,
                  leading: const Icon(CupertinoIcons.plus_circle),
                  title: const Text('导入字体'),
                  additionalInfo: Text('已导入 ${widget.installedFonts.length} 个'),
                  onTap: widget.onImportFonts,
                ),
                CupertinoListTile(
                  backgroundColor: pageBackground,
                  backgroundColorActivated: pressedBackground,
                  leading: const Icon(CupertinoIcons.textformat),
                  title: const Text('字体列表'),
                  onTap: () => _showFontManager(context),
                ),
                if (hasActiveFont) ...[
                  CupertinoListTile(
                    backgroundColor: pageBackground,
                    backgroundColorActivated: pressedBackground,
                    title: const Text('用于界面字体'),
                    trailing: CupertinoSwitch(
                      value: widget.useFontForUi,
                      onChanged: (value) => widget.onFontUsageChanged(
                        useForUi: value,
                        useForContent: widget.useFontForContent,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            CupertinoListSection.insetGrouped(
              backgroundColor: pageBackground,
              header: const Text('工具'),
              children: [
                CupertinoListTile(
                  backgroundColor: pageBackground,
                  backgroundColorActivated: pressedBackground,
                  leading: const Icon(CupertinoIcons.doc_text),
                  title: const Text('MOBI / EPUB 转 TXT'),
                  additionalInfo: const Text('导出纯文本'),
                  onTap: widget.onConvertEbookToTxt,
                ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              backgroundColor: pageBackground,
              header: const Text('软件更新'),
              children: [
                CupertinoListTile(
                  backgroundColor: pageBackground,
                  backgroundColorActivated: pressedBackground,
                  leading: const Icon(CupertinoIcons.arrow_down_circle),
                  title: const Text('检查 GitHub 更新'),
                  additionalInfo: Text(
                    _checkingUpdate ? '检查中…' : 'Murchey/Vellum',
                  ),
                  onTap: _checkingUpdate ? null : _checkForUpdate,
                ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              backgroundColor: pageBackground,
              header: const Text('存储管理'),
              children: [
                FutureBuilder<StorageUsage>(
                  future: _usage,
                  builder: (context, snapshot) => CupertinoListTile(
                    backgroundColor: pageBackground,
                    backgroundColorActivated: pressedBackground,
                    leading: const Icon(CupertinoIcons.chart_bar),
                    title: const Text('占用空间'),
                    additionalInfo: Text(
                      snapshot.data == null
                          ? '计算中…'
                          : _formatBytes(snapshot.data!.totalBytes),
                    ),
                  ),
                ),
                CupertinoListTile(
                  backgroundColor: pageBackground,
                  backgroundColorActivated: pressedBackground,
                  leading: const Icon(CupertinoIcons.book),
                  title: const Text('清空书库'),
                  onTap: () => _confirm(
                    '清空书库？',
                    '将删除已导入的电子书和对应阅读位置，此操作不可恢复。',
                    widget.onClearBooks,
                  ),
                ),
                CupertinoListTile(
                  backgroundColor: pageBackground,
                  backgroundColorActivated: pressedBackground,
                  leading: const Icon(CupertinoIcons.clock),
                  title: const Text('清除阅读记录'),
                  onTap: () => _confirm(
                    '清除阅读记录？',
                    '将重置所有书籍的字号、背景、阅读方式和阅读位置。',
                    widget.onClearReadingStates,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showFontManager(BuildContext context) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => FontManagerSheet(
        installedFonts: widget.installedFonts,
        activeFontName: widget.activeFontName,
        onActivateFont: widget.onActivateFont,
        onDeleteFont: widget.onDeleteFont,
        onImportFonts: widget.onImportFonts,
      ),
    );
  }
}

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

class _FontPreview extends StatefulWidget {
  const _FontPreview({required this.font});
  final InstalledFont font;

  @override
  State<_FontPreview> createState() => _FontPreviewState();
}

class _FontPreviewState extends State<_FontPreview> {
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
            child: _FontPreview(font: font),
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
