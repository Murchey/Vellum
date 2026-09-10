import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/book_importer.dart';
import '../services/book_library.dart';
import '../theme/vellum_theme.dart';
import 'reader_chrome.dart';
import 'reader_controls.dart';
import 'reader_font_picker.dart';
import 'reader_gestures.dart';
import 'reader_markup.dart';
import 'reader_models.dart';
import 'reader_pagination.dart';
import 'reader_paragraph.dart';
import 'reader_selection.dart';
import 'reader_toc.dart';

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

class _ReaderPageState extends State<ReaderPage> with WidgetsBindingObserver {
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
  final Map<int, GlobalKey> _paragraphKeys = {};
  bool _scrollPositionRestored = false;
  int _scrollRestoreAttempts = 0;
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
    _scrollController = ScrollController()
      ..addListener(() {
        _scheduleSave();
        if (_readingMode != ReadingMode.scroll || !mounted) return;
        final estimated = (_scrollController.offset /
                (_fontSize * (_lineSpacing.height + 1.3)))
            .floor();
        final clamped = estimated.clamp(
          0,
          widget.book.paragraphs.isEmpty ? 0 : widget.book.paragraphs.length - 1,
        );
        if (clamped != _currentParagraph) {
          setState(() => _currentParagraph = clamped);
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
        if (_scrollRestoreAttempts < 8) _restoreScrollPositionWhenReady();
        return;
      }
      final maxExtent = _scrollController.position.maxScrollExtent;
      final requestedOffset = widget.initialState.position;
      if (requestedOffset > 0 && maxExtent <= 0) {
        _scrollRestoreAttempts++;
        if (_scrollRestoreAttempts < 8) _restoreScrollPositionWhenReady();
        return;
      }
      if (requestedOffset > 0) {
        _scrollController.jumpTo(requestedOffset.clamp(0.0, maxExtent));
        _currentParagraph = (requestedOffset /
                (_fontSize * (_lineSpacing.height + 1.3)))
            .floor()
            .clamp(
              0,
              widget.book.paragraphs.isEmpty
                  ? 0
                  : widget.book.paragraphs.length - 1,
            );
      } else {
        final paragraph = widget.initialState.paragraphIndex.clamp(
          0,
          widget.book.paragraphs.isEmpty ? 0 : widget.book.paragraphs.length - 1,
        );
        final estimated =
            paragraph * (_fontSize * (_lineSpacing.height + 22 / _fontSize));
        _scrollController.jumpTo(estimated.clamp(0.0, maxExtent));
        _currentParagraph = paragraph;
      }
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
  static const double _readerBottomInset = 96;
  double _pageAvailableHeight(BuildContext context) {
    final media = MediaQuery.of(context);
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

  PageLayoutConfig _pageLayoutConfig(BuildContext context) {
    final media = MediaQuery.of(context);
    return PageLayoutConfig(
      fontSize: _fontSize,
      lineSpacing: _lineSpacing,
      fontFamily: _readerFontFamily,
      fontWeight: _readerFontWeight,
      availableHeight: _pageAvailableHeight(context),
      contentWidth: _pageContentWidth(context),
      screenHeight: media.size.height,
      title: widget.book.title,
    );
  }

  int get _pageCount => _pages.length;
  List<List<PageFragment>> _pages = const [[]];
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
      try {
        _pages = computeBookPages(widget.book, _pageLayoutConfig(context));
      } catch (_) {
        final cfg = _pageLayoutConfig(context);
        _pages = computeBookPages(widget.book, cfg);
      }
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
        _pages[_currentPage.clamp(0, _pages.length - 1)].isEmpty) {
      return 0;
    }
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

  Map<int, int> _chapterStartPages() =>
      chapterStartPages(_chapterEntries(), _pageForParagraph);
  List<MapEntry<int, String>> _chapterEntries() => chapterEntries(widget.book);
  String get _pageProgress {
    if (_readingMode == ReadingMode.page) {
      return '${_currentPage + 1} / $_pageCount';
    }
    final percent = (_progress * 100).clamp(0, 100).round();
    final paragraph = (_currentParagraph + 1).clamp(
      1,
      widget.book.paragraphs.length,
    );
    return '$percent% · $paragraph / ${widget.book.paragraphs.length}';
  }

  String get _batteryText => _batteryLevel < 0 ? '电量 —' : '电量 $_batteryLevel%';
  double get _progress {
    if (_readingMode == ReadingMode.page) {
      if (_pageCount <= 1) return 0;
      return (_currentPage / (_pageCount - 1)).clamp(0.0, 1.0);
    }
    if (!_scrollController.hasClients ||
        _scrollController.position.maxScrollExtent <= 0) {
      return 0;
    }
    final raw =
        _scrollController.offset /
        _scrollController.position.maxScrollExtent;
    if (raw <= 0.002) return 0.0;
    if (raw >= 0.998) return 1.0;
    return raw.clamp(0.0, 1.0);
  }

  bool get _canSeekProgress {
    if (_readingMode == ReadingMode.page) return _pageCount > 1;
    return _scrollController.hasClients &&
        _scrollController.position.maxScrollExtent > 0;
  }

  void _jumpToProgress(double value) {
    final target = value.clamp(0.0, 1.0);
    if (_readingMode == ReadingMode.page) {
      if (_pageCount <= 0) return;
      final page = (target * (_pageCount - 1)).round().clamp(0, _pageCount - 1);
      setState(() {
        _currentPage = page;
        _requestedPage = page;
      });
      if (_pageController.hasClients) {
        _pageController.jumpToPage(page);
      }
      _scheduleSave();
      return;
    }
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.maxScrollExtent <= 0) return;
    _scrollController.jumpTo(target * position.maxScrollExtent);
    _scheduleSave();
  }

  void _jumpToScrollParagraph(int target) {
    final count = widget.book.paragraphs.length;
    if (count == 0 || !_scrollController.hasClients) return;
    final index = target.clamp(0, count - 1);
    final fraction = count <= 1 ? 0.0 : index / (count - 1);
    final position = _scrollController.position;
    _scrollController.jumpTo(
      (fraction * position.maxScrollExtent).clamp(
        0.0,
        position.maxScrollExtent,
      ),
    );
    setState(() => _currentParagraph = index);
    _scheduleSave();
    _refineScrollJump(index);
  }

  void _refineScrollJump(int target, {int attempt = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      var ctx = _paragraphKeys[target]?.currentContext;
      if (ctx == null) {
        // Target not built yet: step toward the nearest mounted paragraph so
        // the lazy list materializes the destination.
        int? nearest;
        var nearestDistance = 1 << 30;
        for (final entry in _paragraphKeys.entries) {
          final child = entry.value.currentContext;
          if (child == null) continue;
          final distance = (entry.key - target).abs();
          if (distance < nearestDistance) {
            nearestDistance = distance;
            nearest = entry.key;
          }
        }
        if (nearest != null && nearestDistance > 0) {
          ctx = _paragraphKeys[nearest]!.currentContext;
        }
      }
      if (ctx != null) {
        await Scrollable.ensureVisible(
          ctx,
          alignment: 0.08,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
        );
      }
      if (!mounted) return;
      // Retry exact target after the list has had another frame to build it.
      final exact = _paragraphKeys[target]?.currentContext;
      if (exact != null && exact.mounted && ctx != exact) {
        await Scrollable.ensureVisible(
          exact,
          alignment: 0.08,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOutCubic,
        );
      }
      if (mounted) {
        setState(() => _currentParagraph = target);
        _scheduleSave();
      }
      if (exact == null && attempt < 8) {
        _refineScrollJump(target, attempt: attempt + 1);
      }
    });
  }

  void _jumpToParagraph(int paragraphIndex) {
    final maxIndex = widget.book.paragraphs.isEmpty
        ? 0
        : widget.book.paragraphs.length - 1;
    final target = paragraphIndex.clamp(0, maxIndex);
    if (_readingMode == ReadingMode.page) {
      final page = _pageForParagraph(target).clamp(0, _pageCount - 1);
      if (_pageController.hasClients) {
        _pageController.animateToPage(
          page,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
        );
        setState(() {
          _currentPage = page;
          _requestedPage = page;
        });
      }
      return;
    }
    _jumpToScrollParagraph(target);
  }

  Color _backgroundFor(BuildContext context) =>
      _background ??
      (CupertinoTheme.of(context).brightness == Brightness.dark
          ? VellumTheme.darkPaper
          : VellumTheme.paper);
bool _isScrollIdle() => true;
  void _handleReaderPointerUp(BuildContext context, PointerUpEvent event) {
    final pressedAt = _readerPointerDownAt;
    final pressedPosition = _readerPointerDownPosition;
    _readerPointerDownAt = null;
    _readerPointerDownPosition = null;
    final size = MediaQuery.sizeOf(context);
    final beginsAtScrollTop = _readingMode != ReadingMode.scroll ||
        (!_scrollController.hasClients || _scrollController.offset <= 2);
    final action = ReaderGestures.resolvePointerUp(
      downAt: pressedAt,
      downPosition: pressedPosition,
      upPosition: event.position,
      mode: _readingMode,
      beginsAtScrollTop: beginsAtScrollTop,
      isIdle: _isScrollIdle(),
      screenWidth: size.width,
      screenHeight: size.height,
    );
    switch (action) {
      case ReaderTapAction.none:
        break;
      case ReaderTapAction.addBookmark:
        _bookmarkPullArmed = false;
        _addBookmarkAtCurrentPosition();
      case ReaderTapAction.toggleControls:
        setState(() => _showControls = !_showControls);
      case ReaderTapAction.previousPage:
        _changePage(context, -1);
      case ReaderTapAction.nextPage:
        _changePage(context, 1);
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
                              if (index == 1) {
                                return const SizedBox(height: 30);
                              }
                              final paragraphIndex = index - 2;
                              final isHeading = ReaderMarkup.heading
                                      .hasMatch(widget.book.paragraphs[paragraphIndex]) ||
                                  widget.book.tocEntries.any(
                                    (e) => e.paragraphIndex == paragraphIndex,
                                  );
                              return KeyedSubtree(
                                key: _paragraphKeys.putIfAbsent(
                                  paragraphIndex,
                                  () => GlobalKey(),
                                ),
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    bottom: 22,
                                    top: isHeading ? 10 : 0,
                                  ),
                                  child: ReaderParagraph(
                                    book: widget.book,
                                    paragraph: widget
                                        .book.paragraphs[paragraphIndex],
                                    paragraphIndex: paragraphIndex,
                                    fontSize: _fontSize,
                                    fontFamily: _readerFontFamily,
                                    lineSpacing: _lineSpacing,
                                    fontWeight: _readerFontWeight,
                                    ink: VellumTheme.readerInkFor(
                                      _backgroundFor(context),
                                    ),
                                    contextMenuBuilder:
                                        buildReaderSelectionToolbar,
                                    onJumpToParagraph: _jumpToParagraph,
                                  ),
                                ),
                              );
                            },
                          ),
                        )
                      : Builder(
                          builder: (context) {
                            _restorePageWhenReady();
                            return PageView.builder(
                              controller: _pageController,
                              scrollDirection: Axis.horizontal,
                              physics: const PageScrollPhysics(),
                              allowImplicitScrolling: true,
                              itemCount: _pageCount,
                              onPageChanged: (index) {
                                setState(() {
                                  _currentPage = index;
                                  _requestedPage = index;
                                });
                                _scheduleSave();
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
            if (!_showControls)
              ReaderStatusBar(
                progressLabel: _pageProgress,
                batteryLabel: _batteryText,
              ),
            if (_showControls)
              ReaderHeaderPanel(
                title: widget.book.title,
                onBack: () => Navigator.of(context).maybePop(),
              ),
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
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .72,
                  ),
                  child: ReaderBottomControls(
                    fontSize: _fontSize,
                    readerFontWeight: _readerFontWeight,
                    lineSpacing: _lineSpacing,
                    background: _backgroundFor(context),
                    readingMode: _readingMode,
                    progress: _progress,
                    canSeek: _canSeekProgress,
                    currentParagraph: _activeParagraph,
                    chapters: _chapterEntries(),
                    chapterStartPages: _chapterStartPages(),
                    bookmarks: [
                      for (final bookmark in _bookmarks)
                        MapEntry(bookmark, bookmarkSummary(widget.book.paragraphs, bookmark)),
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
              ),
          ],
        ),
      ),
    );
  }

  Widget _readingPage(BuildContext context, int pageIndex) {
    if (_pages.isEmpty) return const SizedBox.shrink();
    final page = pageIndex.clamp(0, _pages.length - 1);
    final fragments = _pages[page];
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          SizedBox(
            height: constraints.maxHeight,
            // Estimated pagination can slightly overshoot. Clip instead of
            // throwing a bottom-overflow error on the page column.
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minHeight: constraints.maxHeight,
                maxHeight: double.infinity,
                maxWidth: constraints.maxWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (page == 0) _title(context),
                    if (page == 0) const SizedBox(height: 30),
                    for (var index = 0; index < fragments.length; index++)
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: index == fragments.length - 1
                              ? 0
                              : (fragments[index].compactPadding ? 0 : 22),
                        ),
                        child: ReaderParagraph(
                          book: widget.book,
                          paragraph: fragments[index].text,
                          paragraphIndex: fragments[index].paragraphIndex,
                          fontSize: _fontSize,
                          fontFamily: _readerFontFamily,
                          lineSpacing: _lineSpacing,
                          fontWeight: _readerFontWeight,
                          ink: VellumTheme.readerInkFor(
                            _backgroundFor(context),
                          ),
                          contextMenuBuilder: buildReaderSelectionToolbar,
                          showImage: fragments[index].showImage,
                          showLinkAction: fragments[index].showLinkAction,
                          indentFirstLine: fragments[index].indentFirstLine,
                          onJumpToParagraph: _jumpToParagraph,
                        ),
                      ),
                  ],
                ),
              ),
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
    if (pageCount <= 0) return;
    final base = _requestedPage.clamp(0, pageCount - 1);
    final target = (base + delta).clamp(0, pageCount - 1);
    if (target == base) return;
    setState(() {
      _requestedPage = target;
      _currentPage = target;
    });
    _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
    _scheduleSave();
  }
}
