import 'dart:async';





import 'package:flutter/services.dart';



import 'package:file_picker/file_picker.dart';

import 'package:flutter/cupertino.dart';




import 'pages/library_pages.dart';

import 'pages/settings_page.dart';

import 'pages/writing_placeholder.dart';

import 'reader/reader_page.dart';

import 'services/book_importer.dart';

import 'services/book_import_service.dart' show BookImportService;

import 'services/book_library.dart';

import 'theme/vellum_theme.dart';



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

    const importer = BookImportService();

    setState(() {

      _importing = true;

      _importStage = '正在打开文件选择器…';

    });

    try {

      final book = await importer.pickAndDecode(onStage: _setImportStage);

      if (book == null) return;

      _setImportStage('正在保存到书库…');

      final updated = await importer.persistImported(_library, _books, book);

      if (!mounted) return;

      setState(() {

        _books

          ..clear()

          ..addAll(updated);

      });

      await _openBook(book);

    } on BookImportException catch (error) {

      if (mounted) await _showError(error.message);

    } catch (error) {

      if (mounted) await _showError('导入失败：');

    } finally {

      if (mounted) {

        setState(() {

          _importing = false;

          _importStage = '';

        });

      }

    }

  }



  Future<void> _showError(String message, {String title = '无法导入'}) =>

      showCupertinoDialog<void>(

        context: context,

        builder: (context) => CupertinoAlertDialog(

          title: Text(title),

          content: Text(message),

          actions: [

            CupertinoDialogAction(

              onPressed: () => Navigator.pop(context),

              child: const Text('好'),

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



