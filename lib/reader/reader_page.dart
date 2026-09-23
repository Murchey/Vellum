import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/book_importer.dart';
import '../services/book_library.dart';
import '../services/notes_library.dart';
import '../services/reading_stats.dart';
import '../theme/vellum_theme.dart';
import 'reader_chrome.dart';
import 'reader_controls.dart';
import 'reader_font_picker.dart';
import 'reader_gestures.dart';
import 'reader_markup.dart';
import 'reader_models.dart';
import 'reader_pagination.dart';
import 'reader_paragraph.dart';
import 'reader_platform.dart';
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

class _ReaderPageState extends State<ReaderPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late double _fontSize;
  late String _readerFontFamily;
  late ReaderFontWeight _readerFontWeight;
  late ReaderLineSpacing _lineSpacing;
  Color? _background;
  late ReadingMode _readingMode;
  late PageTurnStyle _pageTurnStyle;
  late final AnimationController _coverAnim;
  int? _coverFromPage;
  int? _coverToPage;
  bool _coverJumping = false;
  int _pendingPageDelta = 0;
  bool _slideBusy = false;
  final _notesLibrary = const NotesLibrary();
  String _lastSelectedText = '';
  bool _showControls = false;
  late final ScrollController _scrollController;
  late final PageController _pageController;
  int _currentPage = 0;
  int _requestedPage = 0;
  int _currentParagraph = 0;
  late List<int> _bookmarks;
  bool _bookmarkPullArmed = false;
  double _pullDownDistance = 0;
  String? _bookmarkNotice;
  Timer? _bookmarkNoticeTimer;
  int _batteryLevel = -1;
  Timer? _saveTimer;
  Future<void> _saveQueue = Future<void>.value();
  DateTime? _readerPointerDownAt;
  Offset? _readerPointerDownPosition;
  bool _pointerLooksLikeSelection = false;
  bool _bookmarkPullInProgress = false;
  int _pageBeforePointerDown = 0;
  Timer? _selectionHoldTimer;
  final Map<int, GlobalKey> _paragraphKeys = {};
  bool _scrollPositionRestored = false;
  bool _pagePositionRestored = false;
  int _scrollRestoreAttempts = 0;
  late double _brightness;
  late ReaderEyeCare _eyeCare;
  late bool _keepScreenOn;
  late bool _volumeKeys;
  final _platform = const ReaderPlatform();

  /// Highlights and notes for this book, newest first, plus a paragraph-keyed
  /// view so rendering never scans the whole list.
  List<ReadingNote> _notes = const [];
  Map<int, List<String>> _highlights = const {};

  /// Chapter entries are scanned once: the footer needs them on every frame.
  late final List<MapEntry<int, String>> _chapters = chapterEntries(
    widget.book,
  );

  /// Table-of-contents paragraph indexes, for heading detection in O(1).
  late final Set<int> _tocParagraphs = {
    for (final entry in widget.book.tocEntries) entry.paragraphIndex,
  };

  final _statsService = const ReadingStatsService();
  final _sessionSeconds = ValueNotifier<int>(0);
  final _todaySeconds = ValueNotifier<int>(0);
  Stopwatch? _readStopwatch;
  Timer? _readTimer;
  int _unflushedReadSeconds = 0;
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
    _pageTurnStyle = PageTurnStyle.fromStorage(widget.initialState.pageTurn);
    _brightness = widget.initialState.brightness;
    _eyeCare = ReaderEyeCare.fromStorage(widget.initialState.eyeCare);
    _keepScreenOn = widget.initialState.keepScreenOn;
    _volumeKeys = widget.initialState.volumeKeys;
    _pager = ProgressiveBookPager(
      widget.book,
      const PageLayoutConfig(
        fontSize: 19,
        lineSpacing: ReaderLineSpacing.standard,
        fontFamily: 'Georgia',
        fontWeight: ReaderFontWeight.regular,
        availableHeight: 600,
        contentWidth: 360,
        screenHeight: 800,
        title: '',
      ),
    );
    _coverAnim = AnimationController(
      vsync: this,
      // Fanqie's page-turn animation is short enough to feel immediate; a
      // 240ms ease-in-out reads as "waiting for the app" instead of turning.
      duration: const Duration(milliseconds: 200),
    );
    _scrollController = ScrollController()
      ..addListener(() {
        _scheduleSave();
        if (_readingMode != ReadingMode.scroll || !mounted) return;
        final estimated =
            (_scrollController.offset /
                    (_fontSize * (_lineSpacing.height + 1.3)))
                .floor();
        final clamped = estimated.clamp(
          0,
          widget.book.paragraphs.isEmpty
              ? 0
              : widget.book.paragraphs.length - 1,
        );
        if (clamped != _currentParagraph) {
          setState(() => _currentParagraph = clamped);
        }
      });
    _pageController = PageController()..addListener(_scheduleSave);
    _loadBatteryLevel();
    _startReadingTimer();
    _loadTodayReading();
    _loadNotes();
    _syncPlatformSettings();
  }

  /// Screen brightness / keep-awake / volume-key paging are window-level
  /// settings on Android, so they follow the reader's lifetime.
  Future<void> _syncPlatformSettings() async {
    await _platform.setBrightness(_brightness);
    await _platform.setKeepScreenOn(_keepScreenOn);
    await _syncVolumeKeys();
  }

  Future<void> _syncVolumeKeys() async {
    await _platform.setVolumeKeyPaging(_volumeKeys);
    _platform.listenForVolumeKeys(_volumeKeys ? _handleVolumeKey : null);
  }

  DateTime? _lastVolumeTurn;

  void _handleVolumeKey(int direction) {
    if (!mounted || !_volumeKeys) return;
    // Fanqie throttles volume-key paging to 300 ms so a held key does not
    // flip dozens of pages.
    final now = DateTime.now();
    final last = _lastVolumeTurn;
    if (last != null &&
        now.difference(last) < ReaderGestures.volumeKeyThrottle) {
      return;
    }
    _lastVolumeTurn = now;
    if (_readingMode == ReadingMode.page) {
      _changePage(context, direction);
      return;
    }
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (!position.hasPixels || !position.haveDimensions) return;
    final delta = position.viewportDimension * .9 * direction;
    _scrollController.jumpTo(
      (_scrollController.offset + delta).clamp(0.0, position.maxScrollExtent),
    );
    _scheduleSave();
  }

  Future<void> _loadNotes() async {
    final notes = await _notesLibrary.loadForBook(_bookId);
    if (!mounted) return;
    setState(() {
      _notes = notes;
      _highlights = _groupHighlights(notes);
    });
  }

  Map<int, List<String>> _groupHighlights(List<ReadingNote> notes) {
    final map = <int, List<String>>{};
    for (final note in notes) {
      if (note.selectedText.isEmpty) continue;
      (map[note.paragraphIndex] ??= []).add(note.selectedText);
    }
    return map;
  }

  /// Toggles a highlight for the selected passage — selecting it again removes
  /// it, which is how the reader-style apps behave.
  Future<void> _toggleHighlight(String selected, int paragraphIndex) async {
    final value = selected.trim();
    if (value.isEmpty) return;
    final existing = [
      for (final note in _notes)
        if (note.paragraphIndex == paragraphIndex && note.selectedText == value)
          note,
    ];
    if (existing.isNotEmpty) {
      await _notesLibrary.delete(existing.first.id);
      if (mounted) _showBookmarkNotice('已取消划线');
    } else {
      await _notesLibrary.add(
        bookId: _bookId,
        bookTitle: widget.book.title,
        paragraphIndex: paragraphIndex,
        selectedText: value,
        style: ReadingNoteStyle.highlight,
      );
      if (mounted) _showBookmarkNotice('已划线，可在目录的「笔记」里查看');
    }
    await _loadNotes();
  }

  Future<void> _removeNote(String id) async {
    await _notesLibrary.delete(id);
    if (!mounted) return;
    setState(() {
      _notes = [
        for (final note in _notes)
          if (note.id != id) note,
      ];
      _highlights = _groupHighlights(_notes);
    });
  }

  String get _bookId => widget.book.storageId;

  Future<void> _loadTodayReading() async {
    if (Platform.environment['FLUTTER_TEST'] == 'true') return;
    try {
      final stats = await _statsService.load().timeout(
        const Duration(seconds: 2),
      );
      if (mounted) _todaySeconds.value = stats.todaySeconds;
    } catch (_) {}
  }

  void _startReadingTimer() {
    // Flutter tests set FLUTTER_TEST; a periodic timer would keep
    // pumpAndSettle busy forever.
    if (Platform.environment['FLUTTER_TEST'] == 'true') return;
    _readStopwatch ??= Stopwatch()..start();
    if (!_readStopwatch!.isRunning) _readStopwatch!.start();
    _readTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      final watch = _readStopwatch;
      if (watch == null || !watch.isRunning) return;
      final elapsed = watch.elapsed.inSeconds;
      if (elapsed > _sessionSeconds.value) {
        _unflushedReadSeconds += elapsed - _sessionSeconds.value;
        _sessionSeconds.value = elapsed;
      }
      // Persist often enough that killing the app still keeps most time.
      if (_unflushedReadSeconds >= 10) {
        _flushReadingTime();
      }
    });
  }

  void _pauseReadingTimer() {
    _readStopwatch?.stop();
    _flushReadingTime();
  }

  void _flushReadingTime() {
    final seconds = _unflushedReadSeconds;
    if (seconds <= 0) return;
    _unflushedReadSeconds = 0;
    _statsService.addSeconds(bookId: _bookId, seconds: seconds).then((stats) {
      if (mounted) _todaySeconds.value = stats.todaySeconds;
    });
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
        _currentParagraph =
            (requestedOffset / (_fontSize * (_lineSpacing.height + 1.3)))
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
          widget.book.paragraphs.isEmpty
              ? 0
              : widget.book.paragraphs.length - 1,
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
    if (state == AppLifecycleState.resumed) {
      _startReadingTimer();
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _pauseReadingTimer();
      _saveTimer?.cancel();
      await _saveState();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _selectionHoldTimer?.cancel();
    _readTimer?.cancel();
    _readStopwatch?.stop();
    _flushReadingTime();
    _saveTimer?.cancel();
    _bookmarkNoticeTimer?.cancel();
    _saveState();
    // Release the window-level reader settings.
    _platform.listenForVolumeKeys(null);
    _platform.setBrightness(-1);
    _platform.setKeepScreenOn(false);
    _platform.setVolumeKeyPaging(false);
    _coverAnim.dispose();
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
    if (widget.book.paragraphs.isEmpty) return;
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

  Future<void> _toggleBookmarkAtCurrentPosition() async {
    if (widget.book.paragraphs.isEmpty) return;
    final paragraph = _activeParagraph.clamp(
      0,
      widget.book.paragraphs.length - 1,
    );
    if (_bookmarks.contains(paragraph)) {
      await _removeBookmark(paragraph);
      if (mounted) _showBookmarkNotice('书签已取消');
    } else {
      await _addBookmarkAtCurrentPosition();
    }
  }

  Future<void> _removeBookmark(int paragraph) async {
    if (!_bookmarks.contains(paragraph)) return;
    setState(() => _bookmarks.remove(paragraph));
    await _saveState();
  }

  bool _handleBookmarkPull(ScrollNotification notification) {
    if (_readingMode != ReadingMode.scroll) return false;
    if (_pointerLooksLikeSelection || _lastSelectedText.isNotEmpty) {
      return false;
    }
    if (notification is OverscrollNotification &&
        notification.metrics.pixels <= 0 &&
        notification.overscroll < 0) {
      _bookmarkPullArmed = true;
    }
    if (notification is ScrollEndNotification && _bookmarkPullArmed) {
      _bookmarkPullArmed = false;
      _toggleBookmarkAtCurrentPosition();
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
      pageTurn: _pageTurnStyle.name,
      bookId: _bookId,
      brightness: _brightness,
      eyeCare: _eyeCare.name,
      keepScreenOn: _keepScreenOn,
      volumeKeys: _volumeKeys,
    );
    _saveQueue = _saveQueue.then((_) => callback(state));
    await _saveQueue;
  }

  /// Reading-surface insets, matched to the reference reader's page metrics
  /// (左右 24dp，底部预留给状态胶囊): controls are a floating overlay and must
  /// not change these, so opening the menu never reflows or re-paginates.
  static const double _readerSideInset = 24;
  static const double _readerTopInset = 24;

  /// Fanqie page foot is tight so body text fills the column.
  static const double _readerBottomInset = 18;

  /// Viewport height for pagination. Shares the same fixed bottom reservation
  /// as list/page padding so layout stays identical with controls open or not.
  double _pageAvailableHeight(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final view = MediaQuery.viewPaddingOf(context);
    // Must match PageView/list padding, inside SafeArea.
    // Pagination subtracts an extra measurement slack internally.
    return size.height -
        view.top -
        view.bottom -
        _readerTopInset -
        _readerBottomInset;
  }

  double _pageContentWidth(BuildContext context) {
    final media = MediaQuery.of(context);
    return media.size.width -
        media.padding.left -
        media.padding.right -
        _readerSideInset * 2;
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

  /// How many measured pages to keep ahead of the current reading position.
  static const int _pagesAhead = 100;
  late ProgressiveBookPager _pager;
  bool _paginateBusy = false;
  Size? _lastMeasuredSize;
  double? _lastMeasuredFontSize;
  ReaderLineSpacing? _lastMeasuredLineSpacing;
  String? _lastMeasuredFontFamily;
  ReaderFontWeight? _lastMeasuredFontWeight;
  double? _lastMeasuredPageHeight;
  double? _lastMeasuredPageWidth;
  double? _lastMeasuredBottomInset;

  List<List<PageFragment>> get _pages => _pager.pages;
  int get _pageCount => _pager.pageCount;

  bool _layoutNeedsReset(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pageHeight = _pageAvailableHeight(context);
    final pageWidth = _pageContentWidth(context);
    final bottomInset = _readerBottomInset;
    return _lastMeasuredSize != size ||
        _lastMeasuredFontSize != _fontSize ||
        _lastMeasuredLineSpacing != _lineSpacing ||
        _lastMeasuredFontFamily != _readerFontFamily ||
        _lastMeasuredFontWeight != _readerFontWeight ||
        _lastMeasuredPageHeight != pageHeight ||
        _lastMeasuredPageWidth != pageWidth ||
        _lastMeasuredBottomInset != bottomInset;
  }

  void _recordLayoutMetrics(BuildContext context) {
    _lastMeasuredSize = MediaQuery.sizeOf(context);
    _lastMeasuredFontSize = _fontSize;
    _lastMeasuredLineSpacing = _lineSpacing;
    _lastMeasuredFontFamily = _readerFontFamily;
    _lastMeasuredFontWeight = _readerFontWeight;
    _lastMeasuredPageHeight = _pageAvailableHeight(context);
    _lastMeasuredPageWidth = _pageContentWidth(context);
    _lastMeasuredBottomInset = _readerBottomInset;
  }

  /// Progressive pagination: measure ahead of the current position in
  /// small slices so first paint stays fast; extend as the reader advances.
  void _ensurePages(BuildContext context) {
    if (_layoutNeedsReset(context)) {
      _pager = ProgressiveBookPager(widget.book, _pageLayoutConfig(context));
      _recordLayoutMetrics(context);
      final resumePara = widget.initialState.paragraphIndex.clamp(
        0,
        widget.book.paragraphs.isEmpty ? 0 : widget.book.paragraphs.length - 1,
      );
      _pager.paginateThrough(resumePara);
      final resumePage = _pager.exactPageForParagraph(resumePara) ?? 0;
      _pager.paginateUntilPages(resumePage + _pagesAhead);
    } else {
      final target = _currentPage + _pagesAhead;
      if (!_pager.fullyPaginated && _pager.pageCount < target) {
        _paginateAsync(targetPages: target);
      }
    }
  }

  void _paginateAsync({required int targetPages}) {
    if (_paginateBusy) return;
    _paginateBusy = true;
    Future<void>(() async {
      while (mounted && _paginateBusy) {
        if (_pager.fullyPaginated || _pager.pageCount >= targetPages) break;
        final sw = Stopwatch()..start();
        while (mounted &&
            !_pager.fullyPaginated &&
            _pager.pageCount < targetPages &&
            sw.elapsedMilliseconds < 12) {
          _pager.paginateSlice(maxParagraphs: 20);
        }
        if (!mounted) break;
        setState(() {});
        if (_pager.fullyPaginated || _pager.pageCount >= targetPages) break;
        await Future<void>.delayed(Duration.zero);
      }
      _paginateBusy = false;
    });
  }

  void _maybeExtendPagination() {
    if (_readingMode != ReadingMode.page || _pager.fullyPaginated) return;
    final remaining = _pager.pageCount - _currentPage;
    if (remaining < 24) {
      _paginateAsync(targetPages: _currentPage + _pagesAhead);
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
    if (paragraphIndex > _pager.nextParagraph) {
      _pager.paginateThrough(paragraphIndex);
    }
    final exact = _pager.exactPageForParagraph(paragraphIndex);
    if (exact != null) {
      return exact.clamp(0, (_pager.pageCount - 1).clamp(0, exact));
    }
    final ref = _pager.pageRefForParagraph(paragraphIndex);
    return (ref.page1 - 1).clamp(0, _pager.pageCount - 1);
  }

  void _restorePageWhenReady() {
    if (_pagePositionRestored || _readingMode != ReadingMode.page) return;
    final requested = widget.initialState.paragraphIndex;
    final starts = _pages;
    if (starts.isEmpty) return;
    final target = _pageForParagraph(requested).clamp(0, starts.length - 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pagePositionRestored) return;
      if (!_pageController.hasClients) {
        return;
      }
      // Consume the one-shot restore. Never re-apply after the user navigates
      // (TOC, progress, or tap paging).
      _pagePositionRestored = true;
      if (target == 0) return;
      if (_currentPage != 0 || _requestedPage != 0) return;
      final live = _pageController.page;
      if (live == null || live != 0) return;
      _jumpToPageExact(target);
      setState(() {
        _currentPage = target;
        _requestedPage = target;
      });
    });
  }

  /// Jump to [page]. [SnapPageScrollPhysics] suppresses any residual spring
  /// that [PageController.jumpToPage] would otherwise start via `goBallistic`.
  void _jumpToPageExact(int page) {
    if (!_pageController.hasClients) return;
    _pageController.jumpToPage(page);
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

  Map<int, String> _chapterPageLabels() {
    final labels = <int, String>{};
    for (final entry in _chapters) {
      final ref = _pager.pageRefForParagraph(entry.key);
      labels[entry.key] = ref.exact ? '第 ${ref.page1} 页' : '约第 ${ref.page1} 页';
    }
    return labels;
  }

  List<MapEntry<int, String>> _chapterEntries() => _chapters;

  /// Index of the chapter containing [paragraph], or -1 when before the first.
  int _chapterIndexFor(int paragraph) {
    var low = 0;
    var high = _chapters.length - 1;
    var found = -1;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      if (_chapters[mid].key <= paragraph) {
        found = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return found;
  }

  /// Chapter title only — top-left / menu bar (Fanqie running head).
  String get _chapterLabel {
    if (_chapters.isEmpty) return '';
    final index = _chapterIndexFor(_activeParagraph);
    if (index < 0) return '开篇';
    return _chapters[index].value;
  }

  /// Fanqie bottom indicator: page number only (no percent / paragraph).
  String get _pageProgress {
    if (_readingMode == ReadingMode.page) {
      final total = _pager.estimatedTotalPageCount;
      final current = (_currentPage + 1).clamp(1, total);
      return _pager.fullyPaginated ? '$current / $total' : '$current / ~$total';
    }
    final percent = (_progress * 100).clamp(0, 100).round();
    return '$percent%';
  }

  String get _batteryText => _batteryLevel < 0 ? '' : '$_batteryLevel%';
  double get _progress {
    if (_readingMode == ReadingMode.page) {
      final total = _pager.estimatedTotalPageCount;
      if (total <= 1) return 0;
      return (_currentPage / (total - 1)).clamp(0.0, 1.0);
    }
    if (!_scrollController.hasClients) return 0;
    final position = _scrollController.position;
    // Dimensions may not be applied yet on the first frames.
    if (!position.hasPixels || !position.haveDimensions) return 0;
    final max = position.maxScrollExtent;
    if (max <= 0) return 0;
    final raw = _scrollController.offset / max;
    if (raw <= 0.002) return 0.0;
    if (raw >= 0.998) return 1.0;
    return raw.clamp(0.0, 1.0);
  }

  bool get _canSeekProgress {
    if (_readingMode == ReadingMode.page) {
      return _pager.estimatedTotalPageCount > 1 ||
          widget.book.paragraphs.length > 1;
    }
    if (!_scrollController.hasClients) return false;
    final position = _scrollController.position;
    return position.hasPixels &&
        position.haveDimensions &&
        position.maxScrollExtent > 0;
  }

  void _jumpToProgress(double value) {
    final target = value.clamp(0.0, 1.0);
    if (_readingMode == ReadingMode.page) {
      final totalParas = widget.book.paragraphs.length;
      if (totalParas <= 0) return;
      final para = (target * (totalParas - 1)).round().clamp(0, totalParas - 1);
      // Measure through the destination so TOC/page numbers stay consistent.
      _pager.paginateThrough(para);
      final page = _pageForParagraph(para);
      _paginateAsync(targetPages: page + _pagesAhead);
      setState(() {
        _currentPage = page;
        _requestedPage = page;
      });
      if (_pageController.hasClients) {
        _jumpToPageExact(page);
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

  /// Fanqie progress semantics: SeekBar drives chapter index, not 0–100%.
  void _jumpToChapter(int chapterIndex) {
    final entries = _chapters;
    if (entries.isEmpty) return;
    final index = chapterIndex.clamp(0, entries.length - 1);
    _jumpToParagraph(entries[index].key);
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

  Widget _bookmarkPullIndicator(BuildContext context) {
    final threshold = ReaderGestures.bookmarkPullThreshold;
    final progress = (_pullDownDistance / threshold).clamp(0.0, 1.2);
    final armed = _pullDownDistance >= threshold;
    final already = _isCurrentViewBookmarked;
    final label = already
        ? (armed ? '松开取消书签' : '下拉取消书签')
        : (armed ? '松开添加书签' : '下拉添加书签');
    return BookmarkRibbon(
      surface: _backgroundFor(context),
      progress: progress,
      armed: armed,
      alreadyBookmarked: already,
      label: label,
    );
  }

  Color _backgroundFor(BuildContext context) =>
      _background ??
      (CupertinoTheme.of(context).brightness == Brightness.dark
          ? VellumTheme.readerNight
          : VellumTheme.readerWhite);
  bool _isScrollIdle() => true;
  void _handleReaderPointerMove(PointerMoveEvent event) {
    final down = _readerPointerDownPosition;
    if (down == null) return;
    // Only treat a clear intentional slide as "dismiss chrome". A 18px
    // threshold made every careful tap near a button feel broken.
    if (_showControls) {
      final dx = event.position.dx - down.dx;
      final dy = event.position.dy - down.dy;
      if (dx * dx + dy * dy > 72 * 72) {
        setState(() => _showControls = false);
      }
    }
    final atTop =
        _readingMode != ReadingMode.scroll ||
        (!_scrollController.hasClients || _scrollController.offset <= 2);
    if (!atTop) {
      if (_pullDownDistance != 0) {
        setState(() => _pullDownDistance = 0);
      }
      return;
    }
    final dy = event.position.dy - down.dy;
    final dx = event.position.dx - down.dx;
    // A deliberate downward bookmark pull owns this gesture. Interrupt the
    // PageView as soon as the vertical intent is clear so a slight diagonal
    // movement cannot turn the page underneath the bookmark interaction.
    if (_readingMode == ReadingMode.page &&
        !_pointerLooksLikeSelection &&
        dy > 18 &&
        dy > dx.abs() * 1.25) {
      _bookmarkPullInProgress = true;
      _restorePageAfterBookmarkPull();
    }
    final next = dy > 0 ? dy : 0.0;
    if ((next - _pullDownDistance).abs() > 0.5) {
      setState(() => _pullDownDistance = next);
    }
  }

  void _restorePageAfterBookmarkPull() {
    if (_readingMode != ReadingMode.page ||
        !_pageController.hasClients ||
        _pageCount <= 0) {
      return;
    }
    final page = _pageBeforePointerDown.clamp(0, _pageCount - 1);
    _pageController.jumpToPage(page);
    if (_currentPage != page) {
      setState(() {
        _currentPage = page;
        _requestedPage = page;
      });
    }
  }

  void _handleReaderPointerUp(BuildContext context, PointerUpEvent event) {
    final pressedAt = _readerPointerDownAt;
    final pressedPosition = _readerPointerDownPosition;
    final selectionGesture =
        _pointerLooksLikeSelection ||
        (_lastSelectedText.isNotEmpty && _pullDownDistance > 0);
    final wasBookmarkPull = _bookmarkPullInProgress;
    if (wasBookmarkPull) _restorePageAfterBookmarkPull();
    _bookmarkPullInProgress = false;
    _readerPointerDownAt = null;
    _readerPointerDownPosition = null;
    _pointerLooksLikeSelection = false;
    if (_pullDownDistance != 0) {
      setState(() => _pullDownDistance = 0);
    }
    final size = MediaQuery.sizeOf(context);
    final beginsAtScrollTop =
        _readingMode != ReadingMode.scroll ||
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
      selectionGesture: selectionGesture,
    );
    switch (action) {
      case ReaderTapAction.none:
        break;
      case ReaderTapAction.toggleBookmark:
        _bookmarkPullArmed = false;
        _toggleBookmarkAtCurrentPosition();
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
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          // System/edge back: chrome first, then leave the reader.
          if (_showControls) {
            setState(() => _showControls = false);
            return;
          }
          final navigator = Navigator.of(context);
          if (navigator.canPop()) navigator.pop();
        },
        child: SafeArea(
          child: Stack(
            children: [
              Localizations.override(
                context: context,
                delegates: const [DefaultMaterialLocalizations.delegate],
                child: SelectionArea(
                  onSelectionChanged: (content) {
                    _lastSelectedText = content?.plainText.trim() ?? '';
                  },
                  contextMenuBuilder: (context, selectableRegionState) {
                    final selected = _lastSelectedText.trim();
                    final buttonItems = <ContextMenuButtonItem>[
                      // Keep the platform copy action (SelectionArea handles it).
                      ...selectableRegionState.contextMenuButtonItems,
                      if (selected.isNotEmpty)
                        ContextMenuButtonItem(
                          label: 'Bing 查询',
                          onPressed: () {
                            selectableRegionState.hideToolbar();
                            openSelectionService(selected, translate: false);
                          },
                        ),
                      if (selected.isNotEmpty)
                        ContextMenuButtonItem(
                          label: 'DeepL 翻译',
                          onPressed: () {
                            selectableRegionState.hideToolbar();
                            openSelectionService(selected, translate: true);
                          },
                        ),
                      if (selected.isNotEmpty)
                        ContextMenuButtonItem(
                          label: '笔记',
                          onPressed: () async {
                            selectableRegionState.hideToolbar();
                            await showAddNoteSheet(
                              context,
                              bookId: _bookId,
                              bookTitle: widget.book.title,
                              paragraphIndex: _currentParagraph,
                              selectedText: selected,
                              notesLibrary: _notesLibrary,
                            );
                          },
                        ),
                    ];
                    return CupertinoAdaptiveTextSelectionToolbar.buttonItems(
                      anchors: selectableRegionState.contextMenuAnchors,
                      buttonItems: buttonItems,
                    );
                  },
                  child: Listener(
                    onPointerDown: (event) {
                      _readerPointerDownAt = DateTime.now();
                      _readerPointerDownPosition = event.position;
                      _bookmarkPullInProgress = false;
                      _pageBeforePointerDown = _currentPage;
                      _pointerLooksLikeSelection = false;
                      _selectionHoldTimer?.cancel();
                      _selectionHoldTimer = Timer(
                        const Duration(milliseconds: 400),
                        () {
                          _pointerLooksLikeSelection = true;
                        },
                      );
                    },
                    onPointerMove: _handleReaderPointerMove,
                    onPointerCancel: (_) {
                      _selectionHoldTimer?.cancel();
                      _readerPointerDownAt = null;
                      _readerPointerDownPosition = null;
                      _pointerLooksLikeSelection = false;
                      if (_bookmarkPullInProgress) {
                        _restorePageAfterBookmarkPull();
                        _bookmarkPullInProgress = false;
                      }
                      if (_pullDownDistance != 0) {
                        setState(() => _pullDownDistance = 0);
                      }
                    },
                    onPointerUp: (event) {
                      _selectionHoldTimer?.cancel();
                      _handleReaderPointerUp(context, event);
                    },
                    child: _readingMode == ReadingMode.scroll
                        ? NotificationListener<ScrollNotification>(
                            onNotification: _handleBookmarkPull,
                            child: ListView.builder(
                              controller: _scrollController,
                              padding: EdgeInsets.fromLTRB(
                                _readerSideInset,
                                _readerTopInset,
                                _readerSideInset,
                                _readerBottomInset,
                              ),
                              itemCount: widget.book.paragraphs.length + 2,
                              itemBuilder: (context, index) {
                                if (index == 0) return _title(context);
                                if (index == 1) {
                                  return const SizedBox(height: 30);
                                }
                                final paragraphIndex = index - 2;
                                final isHeading =
                                    ReaderMarkup.heading.hasMatch(
                                      widget.book.paragraphs[paragraphIndex],
                                    ) ||
                                    _tocParagraphs.contains(paragraphIndex);
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
                                          .book
                                          .paragraphs[paragraphIndex],
                                      paragraphIndex: paragraphIndex,
                                      fontSize: _fontSize,
                                      fontFamily: _readerFontFamily,
                                      lineSpacing: _lineSpacing,
                                      fontWeight: _readerFontWeight,
                                      ink: VellumTheme.readerInkFor(
                                        _backgroundFor(context),
                                      ),
                                      contextMenuBuilder:
                                          createReaderSelectionToolbar(
                                            bookId: _bookId,
                                            bookTitle: widget.book.title,
                                            currentParagraph: () =>
                                                paragraphIndex,
                                            notesLibrary: _notesLibrary,
                                            onHighlight: _toggleHighlight,
                                          ),
                                      highlights:
                                          _highlights[paragraphIndex] ??
                                          const [],
                                      isChapterHeading: _tocParagraphs.contains(
                                        paragraphIndex,
                                      ),
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
                                physics: const SnapPageScrollPhysics(),
                                allowImplicitScrolling: true,
                                itemCount: _pageCount,
                                onPageChanged: (index) {
                                  if (_bookmarkPullInProgress) {
                                    return;
                                  }
                                  if (_coverJumping || _slideBusy) {
                                    return;
                                  }
                                  setState(() {
                                    _currentPage = index;
                                    _requestedPage = index;
                                  });
                                  _maybeExtendPagination();
                                  _scheduleSave();
                                },
                                itemBuilder: (context, index) => Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    _readerSideInset,
                                    _readerTopInset,
                                    _readerSideInset,
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
              if (_pullDownDistance > 8) _bookmarkPullIndicator(context),
              if (_coverFromPage != null) _coverTurnOverlay(context),
              if (_eyeCare != ReaderEyeCare.off)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(
                      color: const Color(
                        0xffd9a441,
                      ).withValues(alpha: _eyeCare.opacity),
                    ),
                  ),
                ),
              // Fanqie BottomIndicator: page + battery only when chrome is hidden.
              if (!_showControls)
                ReaderStatusBar(
                  pageLabel: _pageProgress,
                  batteryLabel: _batteryText,
                  surface: _backgroundFor(context),
                ),
              if (!_showControls)
                ReaderRunningHead(
                  chapterLabel: _chapterLabel,
                  surface: _backgroundFor(context),
                ),
              if (_isCurrentViewBookmarked)
                Semantics(
                  label: '当前阅读页面已添加书签',
                  child: BookmarkRibbon(
                    surface: _backgroundFor(context),
                    progress: 1,
                    armed: false,
                    alreadyBookmarked: true,
                    label: '',
                    pinned: true,
                    showLabel: false,
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
              // Fanqie ReaderMenu: Stack overlay (not Dialog), top bar -44dp /
              // bottom bar height, both 300ms. Font picker stays wired via
              // onShowFonts → existing FontPickerSheet.
              ReaderMenu(
                visible: _showControls,
                bookTitle: widget.book.title,
                bookmarked: _isCurrentViewBookmarked,
                // Fanqie TopBar exit: leave the reader route. Progress is
                // flushed in dispose()/didChangeAppLifecycle.
                onBack: () {
                  final navigator = Navigator.of(context);
                  if (navigator.canPop()) {
                    navigator.pop();
                  } else {
                    setState(() => _showControls = false);
                  }
                },
                // Tap outside only collapses chrome — not an exit.
                onDismiss: () => setState(() => _showControls = false),
                onToggleBookmark: _toggleBookmarkAtCurrentPosition,
                progress: _progress,
                chapterCount: _chapters.length,
                currentChapterIndex: _chapterIndexFor(_activeParagraph) < 0
                    ? 0
                    : _chapterIndexFor(_activeParagraph),
                chapterTitle: _chapterLabel,
                canSeek: _canSeekProgress,
                onSeekProgress: _jumpToProgress,
                onSeekChapter: _jumpToChapter,
                fontSize: _fontSize,
                readerFontWeight: _readerFontWeight,
                lineSpacing: _lineSpacing,
                background: _backgroundFor(context),
                readingMode: _readingMode,
                pageTurnStyle: _pageTurnStyle,
                brightness: _brightness,
                eyeCare: _eyeCare,
                keepScreenOn: _keepScreenOn,
                volumeKeys: _volumeKeys,
                chapters: _chapterEntries(),
                chapterPageLabels: _chapterPageLabels(),
                bookmarks: [
                  for (final bookmark in _bookmarks)
                    MapEntry(
                      bookmark,
                      bookmarkSummary(widget.book.paragraphs, bookmark),
                    ),
                ],
                notes: _notes,
                currentParagraph: _activeParagraph,
                onJumpToParagraph: (paragraph) {
                  setState(() => _showControls = false);
                  _jumpToParagraph(paragraph);
                },
                onRemoveBookmark: _removeBookmark,
                onRemoveNote: _removeNote,
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
                onPageTurnStyle: (value) {
                  setState(() => _pageTurnStyle = value);
                  _saveTimer?.cancel();
                  _saveState();
                },
                onBrightness: (value) {
                  setState(() => _brightness = value);
                  _platform.setBrightness(value);
                  _scheduleSave();
                },
                onEyeCare: (value) {
                  setState(() => _eyeCare = value);
                  _saveTimer?.cancel();
                  _saveState();
                },
                onKeepScreenOn: (value) {
                  setState(() => _keepScreenOn = value);
                  _platform.setKeepScreenOn(value);
                  _saveTimer?.cancel();
                  _saveState();
                },
                onVolumeKeys: (value) {
                  setState(() => _volumeKeys = value);
                  _syncVolumeKeys();
                  _saveTimer?.cancel();
                  _saveState();
                },
                onShowFonts: _showFontPicker,
                onToggleUiTheme: widget.onToggleUiTheme,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _readingPage(
    BuildContext context,
    int pageIndex, {
    bool selectable = true,
  }) {
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
            child: ClipRect(
              clipBehavior: Clip.hardEdge,
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
                          contextMenuBuilder: createReaderSelectionToolbar(
                            bookId: _bookId,
                            bookTitle: widget.book.title,
                            currentParagraph: () =>
                                fragments[index].paragraphIndex,
                            notesLibrary: _notesLibrary,
                            onHighlight: _toggleHighlight,
                          ),
                          highlights:
                              _highlights[fragments[index].paragraphIndex] ??
                              const [],
                          isChapterHeading: _tocParagraphs.contains(
                            fragments[index].paragraphIndex,
                          ),
                          showImage: fragments[index].showImage,
                          showLinkAction:
                              selectable && fragments[index].showLinkAction,
                          indentFirstLine: fragments[index].indentFirstLine,
                          selectable: selectable,
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
        surface: _backgroundFor(context),
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
    final live = _pageController.hasClients
        ? _pageController.page?.round()
        : null;
    var base = (live ?? _requestedPage).clamp(0, pageCount - 1);
    if (_coverFromPage != null) base = _coverToPage ?? base;
    if (_slideBusy) base = _requestedPage.clamp(0, pageCount - 1);
    final target = (base + delta).clamp(0, pageCount - 1);
    if (target == base && !_coverAnim.isAnimating && !_slideBusy) return;

    if (_pageTurnStyle == PageTurnStyle.none) {
      setState(() {
        _requestedPage = target;
        _currentPage = target;
      });
      _jumpToPageExact(target);
      _scheduleSave();
      return;
    }

    if (_pageTurnStyle == PageTurnStyle.slide) {
      _startSlideTurn(target);
      return;
    }

    // Cover (and default): queue rapid taps instead of dropping them.
    if (_coverAnim.isAnimating) {
      _pendingPageDelta += delta;
      return;
    }
    _startCoverTurn(base, target);
  }

  void _startSlideTurn(int target) {
    if (!_pageController.hasClients) return;
    if (_slideBusy) {
      _requestedPage = target;
      _pageController.jumpToPage(_requestedPage);
    }
    _slideBusy = true;
    setState(() => _requestedPage = target);
    _pageController
        .animateToPage(
          target,
          // 180ms easeOutCubic: snappy tap-to-turn. Fanqie's slide mode uses a
          // short custom-Scroller fling; long durations feel laggy on tap.
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() {
          if (!mounted) return;
          setState(() {
            _currentPage = target;
            _requestedPage = target;
          });
          _slideBusy = false;
          _scheduleSave();
        });
  }

  void _startCoverTurn(int from, int to) {
    _coverFromPage = from;
    _coverToPage = to;
    // Measure the destination page before the animation starts so the
    // overlay never shows a half-paginated page that reflows mid-turn.
    if (!_pager.fullyPaginated && to >= _pager.pageCount) {
      _pager.paginateUntilPages(to + 1);
    }
    // Keep PageView on [from] during the overlay so the underlying page does
    // not re-layout mid-animation (avoids visible “reflow” under the cover).
    setState(() {
      _requestedPage = to;
    });
    _coverAnim
      ..reset()
      ..forward().whenComplete(() {
        if (!mounted) return;
        _finishCoverTurn(to);
      });
  }

  void _finishCoverTurn(int to) {
    _coverJumping = true;
    _jumpToPageExact(to);
    setState(() {
      _currentPage = to;
      _requestedPage = to;
    });
    // Drop the overlay one frame after the jump so the user never sees
    // PageView rebuild/layout under the cover.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _coverFromPage = null;
        _coverToPage = null;
      });
      _coverJumping = false;
      _scheduleSave();
      final pending = _pendingPageDelta;
      _pendingPageDelta = 0;
      if (pending != 0) {
        final pageCount = _pageCount;
        final base = to.clamp(0, pageCount - 1);
        final next = (base + pending).clamp(0, pageCount - 1);
        if (next != base) _startCoverTurn(base, next);
      }
    });
  }

  Widget _coverTurnOverlay(BuildContext context) {
    final from = _coverFromPage;
    final to = _coverToPage;
    if (from == null || to == null) return const SizedBox.shrink();
    final isNext = to > from;
    // Fanqie「覆盖」mode 2 (`pager/s.java` `w()`):
    // - 下一页: slipTarget = current；current **向左滑出**，next 钉在底下不动。
    // - 上一页: slipTarget = previous；previous **从左盖上来**，current 不动。
    // (Vellum used to slide the destination in from the right on next — reversed.)
    final movingPage = isNext ? from : to;
    final staticPage = isNext ? to : from;
    // Page surfaces are built once (as AnimatedBuilder.child) and only the
    // slide offset updates each frame. RepaintBoundary lets Flutter rasterize
    // the expensive text layers once, then just move them.
    return Positioned.fill(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(child: _coverPageSurface(context, staticPage)),
                AnimatedBuilder(
                  animation: _coverAnim,
                  child: RepaintBoundary(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: CupertinoColors.black.withValues(alpha: .22),
                            blurRadius: 18,
                            spreadRadius: 1,
                            // Leading edge sits on the right in both directions
                            // (next exits left; prev enters from the left).
                            offset: const Offset(10, 0),
                          ),
                        ],
                      ),
                      child: _coverPageSurface(context, movingPage),
                    ),
                  ),
                  builder: (context, child) {
                    // easeOutCubic: fast start, gentle settle — matches the
                    // "flick and it goes" feel of Fanqie's custom Scroller.
                    final progress = Curves.easeOutCubic.transform(
                      _coverAnim.value,
                    );
                    // Next: current slides out to the left (dx 0→-1).
                    // Prev: previous slides in from the left (dx -1→0).
                    final dx = isNext ? -progress : -1 + progress;
                    return FractionalTranslation(
                      translation: Offset(dx, 0),
                      child: child,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _coverPageSurface(BuildContext context, int page) {
    if (page < 0 || page >= _pageCount) return const SizedBox.expand();
    return ColoredBox(
      color: _backgroundFor(context),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          _readerSideInset,
          _readerTopInset,
          _readerSideInset,
          _readerBottomInset,
        ),
        // selectable:true matches the PageView builder exactly. Rendering the
        // overlay with selectable:false used SelectableText vs Text and let
        // the two widgets lay out differently — the page visibly "settled"
        // (paragraph spacing shifted) the moment the animation ended.
        // The overlay is already wrapped in IgnorePointer.
        child: _readingPage(context, page, selectable: true),
      ),
    );
  }
}
