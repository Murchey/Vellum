import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Scrollbar;

import '../services/book_search.dart';
import '../services/library_models.dart';
import '../services/notes_library.dart';
import '../theme/vellum_theme.dart';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import '../services/reader_background.dart';
import 'reader_color_picker.dart';
import 'reader_models.dart';

class ReaderDirectoryPanel extends StatefulWidget {
  const ReaderDirectoryPanel({
    required this.chapters,
    required this.bookmarks,
    required this.notes,
    required this.chapterPageLabels,
    required this.currentParagraph,
    required this.readingMode,
    required this.onJumpToParagraph,
    required this.onRemoveBookmark,
    required this.onRemoveNote,
    required this.onClose,
    this.onJumpToSearchHit,
    this.paragraphs,
    this.pageLabelForParagraph,
    this.bookTitle = '',
    this.surface,
    this.onSearchingChanged,
    super.key,
  });

  /// Height of the book-name line plus the tab row.
  ///
  /// Searching no longer shares this header — it uses [searchHeaderHeight] —
  /// so this is the full (non-search) chrome. [ReaderMenu] keeps the sheet at
  /// least as tall as [minPanelHeight], because a sheet shorter than its own
  /// header is exactly what overflows — and the soft keyboard is what makes a
  /// sheet that short.
  static double get headerHeight => _bookTitleHeight + _tabRowHeight + 0.5;

  /// Header height the panel falls back to when the sheet is too short for the
  /// book-name line: a compact app bar, one row of tabs, their rule, and a small
  /// margin so sub-pixel rounding never turns into an overflow stripe.
  static double get compactHeaderHeight =>
      _compactBarHeight + _compactTabHeight + 0.5 + _compactSlack;

  static const double _compactSlack = 4;

  /// Height of the search summary bar (counts + step buttons).
  static const double _searchSummaryHeight = 48;

  /// Minimum room the tab's list needs to stay usable.
  static const double _minBodyHeight = 40;

  /// Smallest sheet the panel can render without overflowing.
  ///
  /// The search view is the tallest fixed content: the compact header plus the
  /// summary bar, with a little list left underneath.
  static double get minPanelHeight =>
      compactHeaderHeight + _searchSummaryHeight + _minBodyHeight;

  /// Height of the search-only header (query field + 取消).
  ///
  /// While searching the tab row and book name are noise; this is all the
  /// chrome the results list needs, so the list keeps the rest of the sheet.
  static double get searchHeaderHeight => _searchRowHeight + _searchHeaderSlack;

  static const double _searchHeaderSlack = 8;

  static const double _compactBarHeight = 46;
  static const double _compactTabHeight = 34;
  static const double _bookTitleHeight = 14 + 17 + 8;
  static const double _tabRowHeight = 44;
  static const double _searchRowHeight = 36 + 14;

  /// Fanqie reader catalog item height (`caloglayout/a.java` setItemHeight 54).
  static const double itemExtent = 54;

  /// Test-only alias so widget tests can assert the Fanqie height.
  static const double itemExtentForTest = itemExtent;

  final List<MapEntry<int, String>> chapters;
  final List<MapEntry<int, String>> bookmarks;
  final List<ReadingNote> notes;
  final Map<int, String> chapterPageLabels;
  final int currentParagraph;
  final ReadingMode readingMode;
  final ValueChanged<int> onJumpToParagraph;
  final Future<void> Function(int) onRemoveBookmark;
  final Future<void> Function(String) onRemoveNote;
  final VoidCallback onClose;
  final String bookTitle;

  /// Body text, enabling 全文搜索 in the catalogue tab. Null on panels that only
  /// list the existing indexes.
  final List<String>? paragraphs;

  /// Tapping a search result: jumps to the paragraph **and** carries the query,
  /// so the reader can mark the passage it was searching for.
  final void Function(int paragraphIndex, String query)? onJumpToSearchHit;

  /// Page label for a paragraph (e.g. `第 132 页`), shown on search results so a
  /// hit can be placed in the book. Null when the reader has no page numbers.
  final String Function(int paragraphIndex)? pageLabelForParagraph;

  /// Panel background (reading paper). Ink is derived from this so night
  /// paper stays readable even when the app theme is light.
  final Color? surface;

  /// Notifies the parent when 全文搜索 opens/closes, so the sheet can expand
  /// for the keyboard instead of staying a half-screen card over the seek bar.
  final ValueChanged<bool>? onSearchingChanged;

  @override
  State<ReaderDirectoryPanel> createState() => _ReaderDirectoryPanelState();
}

class _ReaderDirectoryPanelState extends State<ReaderDirectoryPanel> {
  var _tab = 0;

  /// Fanqie-style catalog order toggle (正序/倒序).
  var _descending = false;
  final _scrollController = ScrollController();
  var _didAutoScroll = false;

  /// 全文搜索 state (catalogue tab only).
  var _searching = false;
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _searchScrollController = ScrollController();
  String _query = '';
  SearchResults _results = SearchResults.empty;

  /// Paragraph of the result row the reader is stepping through, so the list can
  /// scroll to it and mark it.
  int? _activeHit;

  /// Full-book scanning is a single pass over every paragraph — fast on a normal
  /// book, ~100 ms on a 二十四史-sized one — so typing waits for a short pause
  /// instead of scanning per keystroke.
  Timer? _searchDebounce;

  /// Below this length the scan matches too much to be useful; CJK words are
  /// short, so two characters is the useful floor.
  static const int _minQueryLength = 2;
  static const Duration _searchDebounceDelay = Duration(milliseconds: 180);

  /// How long after the field takes focus a spontaneous loss still counts as the
  /// keyboard failing to settle, rather than the reader dismissing it.
  static const Duration _keyboardSettleWindow = Duration(seconds: 2);

  /// Delay before recovering from such a loss, so it cannot turn into a fight
  /// with a deliberate dismissal.
  static const Duration _keyboardRefocusDelay = Duration(milliseconds: 250);
  Timer? _focusLossTimer;
  DateTime? _searchOpenedAt;

  /// Estimated height of one result row, used to scroll a stepped-to hit into
  /// view (rows vary by a line or two; this only needs to be close).
  static const double _searchRowHeight = 96;

  /// Stable identity for the query field, so the element that owns the text
  /// input connection survives panel rebuilds (including a header layout swap
  /// while the soft keyboard animates the viewport).
  final _searchFieldKey = GlobalKey(debugLabel: 'reader-search-field');

  bool get _canSearch => (widget.paragraphs?.isNotEmpty ?? false);

  static const double itemExtent = ReaderDirectoryPanel.itemExtent;

  List<MapEntry<int, String>> get _entries {
    final raw = _tab == 0 ? widget.chapters : widget.bookmarks;
    if (!_descending || raw.isEmpty) return raw;
    return raw.reversed.toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(_onSearchFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoScrollToCurrent());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _focusLossTimer?.cancel();
    _searchFocus.removeListener(_onSearchFocusChanged);
    if (_searching) widget.onSearchingChanged?.call(false);
    _scrollController.dispose();
    _searchScrollController.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _openSearch() {
    setState(() {
      _searching = true;
      _query = '';
      _results = SearchResults.empty;
      _activeHit = null;
    });
    widget.onSearchingChanged?.call(true);
    // The query field mounts on the next frame, where its own `autofocus` claims
    // the caret and raises the keyboard. Asking the platform to show it from here
    // as well opened a second input session for the same field: Android finished
    // the first (`onFinishInputView`) and started another (`onStartInput`), which
    // is what left the keyboard flickering or never settling.
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusSearchField());
  }

  /// Refocuses the query field if it is on screen but has lost the caret
  /// (after clearing it, or switching tabs).
  ///
  /// It deliberately does not ask the platform to show the keyboard: the field's
  /// own `autofocus` already does that when it opens, and a second request opens
  /// a second input session for the same field. Android then finishes the first
  /// (`onFinishInputView`) and starts another (`onStartInput`) — the keyboard
  /// flicker in the device log.
  void _focusSearchField() {
    if (!_searching) return;
    final node = _searchFocus;
    if (node.hasFocus) return;
    if (!node.canRequestFocus) return;
    node.requestFocus();
  }

  /// Watches for the keyboard being dropped shortly after it opens.
  ///
  /// The field keeps focus in every case we can reproduce, so a spontaneous loss
  /// means the platform's input session went away. One delayed refocus recovers
  /// from that without fighting the reader: dismissing the search (取消, the
  /// sheet grabber, tapping away) clears `_searching` first, and a loss that
  /// happens after the keyboard has settled is left alone.
  void _onSearchFocusChanged() {
    _focusLossTimer?.cancel();
    if (_searchFocus.hasFocus) {
      _searchOpenedAt = DateTime.now();
      return;
    }
    if (!_searching) return;
    final openedAt = _searchOpenedAt;
    if (openedAt == null) return;
    if (DateTime.now().difference(openedAt) > _keyboardSettleWindow) return;
    _focusLossTimer = Timer(_keyboardRefocusDelay, () {
      if (!mounted || !_searching || _searchFocus.hasFocus) return;
      _searchFocus.requestFocus();
    });
  }

  void _closeSearch() {
    _searchDebounce?.cancel();
    _focusLossTimer?.cancel();
    _searchController.clear();
    setState(() {
      _searching = false;
      _query = '';
      _results = SearchResults.empty;
      _activeHit = null;
    });
    widget.onSearchingChanged?.call(false);
  }

  /// Restarts the debounce window; [_runSearch] does the actual scan.
  void _onQueryChanged(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();
    // Clearing or falling below the floor shows the prompt immediately.
    if (query.length < _minQueryLength) {
      _runSearch(value);
      return;
    }
    _searchDebounce = Timer(_searchDebounceDelay, () {
      if (mounted) _runSearch(value);
    });
  }

  void _runSearch(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();
    setState(() {
      _query = query;
      _results = query.length < _minQueryLength
          ? SearchResults.empty
          : searchBook(
              paragraphs: widget.paragraphs!,
              query: query,
              chapters: widget.chapters,
            );
      // A new scan starts from the top of the list.
      _activeHit = _results.isEmpty ? null : _results.hits.first.paragraphIndex;
    });
    if (_searchScrollController.hasClients) {
      _searchScrollController.jumpTo(0);
    }
  }

  /// Moves to the next/previous result, as one flat sequence over the grouped
  /// list, and scrolls it into view.
  void _stepHit(int delta) {
    final hits = _results.hits;
    if (hits.isEmpty) return;
    final current = hits.indexWhere((hit) => hit.paragraphIndex == _activeHit);
    final next = current < 0
        ? (delta >= 0 ? 0 : hits.length - 1)
        : (current + delta).clamp(0, hits.length - 1);
    setState(() => _activeHit = hits[next].paragraphIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollSearchTo(hits[next].paragraphIndex);
    });
  }

  void _scrollSearchTo(int paragraphIndex) {
    if (!_searchScrollController.hasClients) return;
    final groups = groupHitsByChapter(_results.hits);
    var row = 0;
    for (final group in groups) {
      row++; // chapter header
      for (final hit in group.hits) {
        if (hit.paragraphIndex == paragraphIndex) {
          final max = _searchScrollController.position.maxScrollExtent;
          _searchScrollController.animateTo(
            (row * _searchRowHeight).clamp(0.0, max),
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
          );
          return;
        }
        row++;
      }
    }
  }

  void _toggleOrder() {
    setState(() {
      _descending = !_descending;
      _didAutoScroll = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoScrollToCurrent());
  }

  /// Current chapter in the *displayed* list order (handles 倒序).
  bool _isCurrentChapter(
    int paragraphIndex,
    int index,
    List<MapEntry<int, String>> entries,
  ) {
    final current = widget.currentParagraph;
    if (_descending) {
      // Displayed[i] is original[n-1-i]. Range is (prevDisplay.key, this.key]
      // inverted: current is in this chapter when
      // current >= this.key && (next display is smaller chapter start OR last).
      final higherNeighbor = index > 0 ? entries[index - 1].key : 1 << 30;
      return current >= paragraphIndex && current < higherNeighbor;
    }
    final next = index + 1 < entries.length ? entries[index + 1].key : 1 << 30;
    return current >= paragraphIndex && current < next;
  }

  /// Fanqie `wl5/e.M3` three-state title colour:
  /// - current (`p3`): accent (`b5.n`) + left icon + title leftMargin 16
  /// - read (`!z2 && progress > 0`): `yz4.j.y(theme, 0.6f)` body @ 60%
  /// - unread: full body (`getReaderConfig().d1()`)
  /// Vellum approximates Fanqie's per-chapter progress % as "chapter start
  /// is strictly before the paragraph currently on screen".
  bool _isReadChapter(int paragraphIndex) =>
      paragraphIndex < widget.currentParagraph;

  /// Fanqie `P3`/`S3` secondary labels (always 60% body):
  /// - current: `读到 x/y 页` / `读到x%`
  /// - read: `已读x%` / `上次读到 x/y 页`
  /// - also word count / first-pass time when available.
  String _readStateLabel(int paragraphIndex, bool isCurrent, bool isRead) {
    if (widget.readingMode == ReadingMode.page) {
      final page = widget.chapterPageLabels[paragraphIndex];
      if (page != null && page.isNotEmpty) {
        return isCurrent ? '读到 $page' : '上次读到 $page';
      }
    }
    if (isCurrent) return '当前章节';
    if (isRead) return '已读';
    return '';
  }

  void _autoScrollToCurrent() {
    if (_didAutoScroll || !_scrollController.hasClients) return;
    final entries = _entries;
    if (entries.isEmpty) return;
    var target = 0;
    if (_descending) {
      // Reverse list: unread later chapters sit first; current is the first
      // entry whose start is <= currentParagraph.
      for (var i = 0; i < entries.length; i++) {
        if (entries[i].key <= widget.currentParagraph) {
          target = i;
          break;
        }
      }
    } else {
      for (var i = 0; i < entries.length; i++) {
        if (entries[i].key <= widget.currentParagraph) {
          target = i;
        } else {
          break;
        }
      }
    }
    _didAutoScroll = true;
    final maxOffset = _scrollController.position.maxScrollExtent;
    final offset = (target * itemExtent - 96).clamp(0.0, maxOffset);
    _scrollController.jumpTo(offset);
  }

  String _secondaryLabel(int paragraphIndex, bool isCurrent, bool isRead) {
    if (_tab == 1) return '第 ${paragraphIndex + 1} 段';
    if (_tab == 2) return '';
    return _readStateLabel(paragraphIndex, isCurrent, isRead);
  }

  /// Fanqie caloglayout structure: book name → tabs → divider → list.
  /// Parent supplies full band height; panel fills it.
  @override
  Widget build(BuildContext context) {
    final surface = widget.surface ?? VellumTheme.readerChromeOf(context);
    final ink = VellumTheme.readerChromeInk(surface);
    final muted = ink.withValues(alpha: .55);
    final accent = VellumTheme.readerAccentOf(context);
    final entries = _entries;
    final emptyMessage = switch (_tab) {
      0 => '这本书暂未识别出章节标题。',
      1 => '下拉阅读页面即可添加书签。',
      _ => '选中正文后可以划线或写笔记。',
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        // The sheet is a fixed slot between the reader's top bar and the bottom
        // chrome, and the soft keyboard shrinks the viewport without shrinking
        // that slot. Below [headerHeight] the book-name line and the query field
        // no longer fit, so the panel drops to a compact header instead of
        // painting the black/yellow overflow stripes.
        //
        // Searching always uses the slim search header: tabs and the book name
        // do not help while typing, and a full header plus the summary bar left
        // the result list a stripe once the keyboard took the rest of the
        // screen. One layout for the whole search session also avoids swapping
        // headers mid-keyboard-animation (which drops the input connection).
        if (_searching) {
          return _searchLayout(context, ink: ink, muted: muted, accent: accent);
        }
        if (constraints.maxHeight < headerHeight) {
          return _compactLayout(
            context,
            entries: entries,
            emptyMessage: emptyMessage,
            ink: ink,
            muted: muted,
            accent: accent,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context, ink: ink, muted: muted, accent: accent),
            Expanded(
              child: _body(
                context,
                entries: entries,
                emptyMessage: emptyMessage,
                ink: ink,
                muted: muted,
                accent: accent,
              ),
            ),
          ],
        );
      },
    );
  }

  /// Search-only sheet: query field + 取消, then the results.
  ///
  /// Dropped book name and tabs so a keyboard-squeezed viewport still shows
  /// a usable list instead of three rows of chrome over a stripe of results.
  Widget _searchLayout(
    BuildContext context, {
    required Color ink,
    required Color muted,
    required Color accent,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: _searchField(
                  context,
                  ink: ink,
                  muted: muted,
                  accent: accent,
                ),
              ),
              CupertinoButton(
                padding: const EdgeInsets.only(left: 8, right: 8),
                minimumSize: const Size(48, 36),
                onPressed: _closeSearch,
                child: Text('取消', style: TextStyle(color: accent)),
              ),
            ],
          ),
        ),
        Container(height: 0.5, color: ink.withValues(alpha: .08)),
        Expanded(
          child: _buildSearchResults(
            context,
            ink: ink,
            muted: muted,
            accent: accent,
          ),
        ),
      ],
    );
  }

  /// Header + one row of tabs, for a sheet too short for the full header.
  ///
  /// Everything the reader needs to get out of the squeezed state survives: the
  /// close button, the tab switch, and the search field when it is open.
  Widget _compactLayout(
    BuildContext context, {
    required List<MapEntry<int, String>> entries,
    required String emptyMessage,
    required Color ink,
    required Color muted,
    required Color accent,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: ReaderDirectoryPanel._compactBarHeight,
          child: Row(
            children: [
              if (_searching)
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(48, 36),
                  onPressed: _closeSearch,
                  child: Text('取消', style: TextStyle(color: accent)),
                )
              else ...[
                const SizedBox(width: 8),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 44),
                  onPressed: widget.onClose,
                  child: Icon(CupertinoIcons.clear, size: 19, color: muted),
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: _searching
                    ? _searchField(
                        context,
                        ink: ink,
                        muted: muted,
                        accent: accent,
                      )
                    : Text(
                        widget.bookTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: ink.withValues(alpha: .55),
                          fontSize: 13,
                        ),
                      ),
              ),
              if (!_searching && _canSearch)
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(44, 44),
                  onPressed: _openSearch,
                  child: Icon(CupertinoIcons.search, size: 18, color: accent),
                ),
              const SizedBox(width: 4),
            ],
          ),
        ),
        // Tabs are not useful while typing a query; [_searchLayout] is the
        // normal search path, and this is only the fallback if search opens
        // mid-squeeze.
        if (!_searching)
          SizedBox(
            height: ReaderDirectoryPanel._compactTabHeight,
            child: _tabRow(
              context,
              ink: ink,
              muted: muted,
              accent: accent,
              withTrailingControls: false,
            ),
          ),
        Container(height: 0.5, color: ink.withValues(alpha: .08)),
        Expanded(
          child: _body(
            context,
            entries: entries,
            emptyMessage: emptyMessage,
            ink: ink,
            muted: muted,
            accent: accent,
          ),
        ),
      ],
    );
  }

  /// Height of the book-name line plus the tab row (non-search full header).
  ///
  /// Part of the panel's contract: [ReaderMenu] keeps the sheet at least this
  /// tall, because a sheet shorter than its own header is what overflows.
  static double get headerHeight => _bookTitleHeight + _tabRowHeight + 0.5;

  static const double _bookTitleHeight = 14 + 17 + 8;
  static const double _tabRowHeight = 44;

  /// Tabs, the search entry point, the order toggle and the close button.
  /// Shared by the full and the compact header; the compact bar already carries
  /// the trailing controls, so [withTrailingControls] turns them off there.
  ///
  /// The tabs are laid out with [Expanded] and [Wrap] rather than a fixed
  /// `Spacer` row: at a large system font scale the three labels plus the three
  /// controls are wider than a phone, and a fixed row simply overflowed.
  Widget _tabRow(
    BuildContext context, {
    required Color ink,
    required Color muted,
    required Color accent,
    bool withTrailingControls = true,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final (index, label) in [
                    (0, '目录'),
                    (1, '书签'),
                    (2, '笔记'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 24),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          setState(() => _tab = index);
                          _didAutoScroll = false;
                          WidgetsBinding.instance.addPostFrameCallback(
                            (_) => _autoScrollToCurrent(),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            label,
                            style: TextStyle(
                              color: _tab == index ? accent : muted,
                              fontSize: 16,
                              fontWeight: _tab == index
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (withTrailingControls) ...[
            // 全文搜索 lives in the catalogue tab, where a reader looks for a
            // passage they half remember. Fanqie's catalog order toggle shares
            // the slot and hides while searching.
            if (_tab == 0 && _canSearch && !_searching)
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(44, 44),
                onPressed: _openSearch,
                child: Icon(CupertinoIcons.search, size: 19, color: accent),
              ),
            if (_tab == 0 && !_searching)
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(52, 44),
                onPressed: _toggleOrder,
                child: Text(
                  _descending ? '倒序' : '正序',
                  style: TextStyle(color: accent, fontSize: 13),
                ),
              ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(44, 44),
              onPressed: widget.onClose,
              child: Icon(CupertinoIcons.clear, size: 20, color: muted),
            ),
          ],
        ],
      ),
    );
  }

  /// The query field plus its 取消 button.
  Widget _searchField(
    BuildContext context, {
    required Color ink,
    required Color muted,
    required Color accent,
  }) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(CupertinoIcons.search, size: 16, color: muted),
          const SizedBox(width: 6),
          Expanded(
            // Its own element, so a panel rebuild cannot recreate the input
            // connection — which on Android tears the session down
            // (`onFinishInputView`) and starts another (`onStartInput`). The key
            // keeps that element alive even if the surrounding header layout
            // (full vs compact) swaps while the keyboard animates the viewport.
            child: _SearchQueryField(
              key: _searchFieldKey,
              controller: _searchController,
              focusNode: _searchFocus,
              onChanged: _onQueryChanged,
              showClear: _query.isNotEmpty,
              onClear: () {
                _searchController.clear();
                _runSearch('');
              },
              style: TextStyle(color: ink, fontSize: 14),
              placeholderStyle: TextStyle(color: muted, fontSize: 14),
              cursorColor: accent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(
    BuildContext context, {
    required Color ink,
    required Color muted,
    required Color accent,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1) Book name (Fanqie V1: 14sp, alpha 0.4 day / 0.6 night)
        if (widget.bookTitle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Text(
              widget.bookTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: ink.withValues(alpha: .45), fontSize: 14),
            ),
          ),

        // 2) SlidingTabLayout-style tabs (Fanqie 16sp). Searching uses
        // [_searchLayout] instead — tabs and the book name are not useful
        // while typing a query.
        _tabRow(context, ink: ink, muted: muted, accent: accent),

        // 3) Divider (Fanqie alj / item: 0.5dp)
        Container(height: 0.5, color: ink.withValues(alpha: .08)),
      ],
    );
  }

  /// The tab's list: search results, notes, or the index itself.
  Widget _body(
    BuildContext context, {
    required List<MapEntry<int, String>> entries,
    required String emptyMessage,
    required Color ink,
    required Color muted,
    required Color accent,
  }) {
    if (_searching) {
      return _buildSearchResults(
        context,
        ink: ink,
        muted: muted,
        accent: accent,
      );
    }
    if (_tab == 2) return _buildNotes(context);
    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            emptyMessage,
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, fontSize: 14),
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.zero,
      itemCount: entries.length,
      itemExtent: itemExtent,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final isCurrent =
            _tab == 0 && _isCurrentChapter(entry.key, index, entries);
        // Fanqie wl5/e.M3: read = body @ 60% (`yz4.j.y(..., 0.6f)`).
        final isRead = _tab == 0 && _isReadChapter(entry.key);
        final titleColor = isCurrent
            ? accent
            : isRead
            ? ink.withValues(alpha: .6)
            : ink;
        // Fanqie S3/P3: secondary always at 60% body.
        final metaColor = ink.withValues(alpha: .45);
        final secondary = _secondaryLabel(entry.key, isCurrent, isRead);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onJumpToParagraph(entry.key),
          child: Container(
            // Fanqie reader catalog item: 54dp, padH 20dp
            // (caloglayout/a.java setItemHeight 54; avr 72 is audio).
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: ink.withValues(alpha: .06),
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [
                if (isCurrent)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      CupertinoIcons.bookmark_fill,
                      size: 14,
                      color: accent,
                    ),
                  ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: titleColor,
                          fontSize: 15,
                          fontWeight: isCurrent
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                      if (secondary.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          secondary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: metaColor, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_tab == 1)
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(32, 32),
                    onPressed: () async {
                      await widget.onRemoveBookmark(entry.key);
                      if (mounted) setState(() {});
                    },
                    child: Icon(CupertinoIcons.delete, size: 17, color: muted),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Search results, grouped by chapter.
  ///
  /// A flat list of "第 N 段" is hard to navigate in a long book, so results are
  /// grouped under chapter headers; each row leads with the passage (query
  /// highlighted) and follows with the line before it for context, plus the page
  /// the hit sits on. A summary bar counts them and steps through them.
  Widget _buildSearchResults(
    BuildContext context, {
    required Color ink,
    required Color muted,
    required Color accent,
  }) {
    final hits = _results.hits;
    if (hits.isEmpty) {
      final message = _query.isEmpty
          ? '输入至少 $_minQueryLength 个字开始搜索'
          : _query.length < _minQueryLength
          ? '再输入 ${_minQueryLength - _query.length} 个字'
          : '没有找到「$_query」';
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, fontSize: 14),
          ),
        ),
      );
    }

    final groups = groupHitsByChapter(hits);
    final activeIndex = hits.indexWhere(
      (hit) => hit.paragraphIndex == _activeHit,
    );
    final summary = _searchSummary(
      context,
      ink: ink,
      muted: muted,
      accent: accent,
      activeIndex: activeIndex,
    );
    final list = ListView.builder(
      controller: _searchScrollController,
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: hits.length + groups.length,
      itemBuilder: (context, row) => _searchRow(
        context,
        row,
        groups: groups,
        ink: ink,
        muted: muted,
        accent: accent,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          summary,
          Expanded(
            // Showing the bar permanently makes it paint every frame, and it
            // asserts when its list has no position yet (an empty or squeezed
            // result view). It shows while scrolling instead.
            child: constraints.maxHeight < _searchListRoom
                ? list
                : Scrollbar(child: list),
          ),
        ],
      ),
    );
  }

  /// Room the results list needs before its scrollbar is worth painting.
  static const double _searchListRoom = 96;

  /// Counts, the "showing the first N" caveat, and the step-through buttons.
  Widget _searchSummary(
    BuildContext context, {
    required Color ink,
    required Color muted,
    required Color accent,
    required int activeIndex,
  }) {
    final hits = _results.hits;
    final position = activeIndex < 0 ? 1 : activeIndex + 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 6, 12, 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ink.withValues(alpha: .06), width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${_results.paragraphCount} 段 · ${_results.totalOccurrences} 处'
              '${_results.truncated ? '（仅显示前面这些）' : ''}',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ),
          Text(
            '$position/${hits.length}',
            style: TextStyle(color: muted, fontSize: 12),
          ),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            minimumSize: const Size(44, 44),
            onPressed: activeIndex <= 0 ? null : () => _stepHit(-1),
            child: Icon(
              CupertinoIcons.chevron_up,
              size: 16,
              color: activeIndex <= 0 ? muted.withValues(alpha: .4) : accent,
            ),
          ),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            minimumSize: const Size(44, 44),
            onPressed: activeIndex >= hits.length - 1
                ? null
                : () => _stepHit(1),
            child: Icon(
              CupertinoIcons.chevron_down,
              size: 16,
              color: activeIndex >= hits.length - 1
                  ? muted.withValues(alpha: .4)
                  : accent,
            ),
          ),
        ],
      ),
    );
  }

  /// One row of the grouped results: either a chapter header or a hit.
  Widget _searchRow(
    BuildContext context,
    int row, {
    required List<SearchGroup> groups,
    required Color ink,
    required Color muted,
    required Color accent,
  }) {
    var remaining = row;
    for (final group in groups) {
      if (remaining == 0) {
        return _chapterHeaderRow(group, ink: ink, muted: muted, accent: accent);
      }
      remaining--;
      if (remaining < group.hits.length) {
        final hit = group.hits[remaining];
        return _hitRow(hit, ink: ink, muted: muted, accent: accent);
      }
      remaining -= group.hits.length;
    }
    return const SizedBox.shrink();
  }

  Widget _chapterHeaderRow(
    SearchGroup group, {
    required Color ink,
    required Color muted,
    required Color accent,
  }) {
    final title = group.title.isEmpty ? '未分章' : group.title;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
      color: ink.withValues(alpha: .03),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: accent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '${group.occurrences} 处',
            style: TextStyle(color: muted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _hitRow(
    SearchHit hit, {
    required Color ink,
    required Color muted,
    required Color accent,
  }) {
    final active = hit.paragraphIndex == _activeHit;
    final page = widget.pageLabelForParagraph?.call(hit.paragraphIndex) ?? '';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        final query = _query;
        _closeSearch();
        final jump = widget.onJumpToSearchHit;
        if (jump != null) {
          jump(hit.paragraphIndex, query);
        } else {
          widget.onJumpToParagraph(hit.paragraphIndex);
        }
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
        decoration: BoxDecoration(
          color: active ? accent.withValues(alpha: .07) : null,
          border: Border(
            bottom: BorderSide(color: ink.withValues(alpha: .06), width: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Context line above the match: tells the reader what leads into it.
            if (hit.first.leadingContext.isNotEmpty)
              Text(
                hit.first.leadingContext,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: ink.withValues(alpha: .35),
                  fontSize: 12,
                ),
              ),
            const SizedBox(height: 2),
            _matchText(hit.first, ink: ink, accent: accent),
            if (hit.first.trailingContext.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                hit.first.trailingContext,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: ink.withValues(alpha: .35),
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  '第 ${hit.paragraphIndex + 1} 段'
                  '${hit.first.lineNumber > 1 ? ' · 第 ${hit.first.lineNumber} 行' : ''}',
                  style: TextStyle(color: muted, fontSize: 11),
                ),
                if (page.isNotEmpty) ...[
                  Text(
                    ' · $page',
                    style: TextStyle(color: muted, fontSize: 11),
                  ),
                ],
                const Spacer(),
                if (hit.matchCount > 1)
                  Text(
                    '本段 ${hit.matchCount} 处',
                    style: TextStyle(
                      color: accent.withValues(alpha: .8),
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Snippet with the query picked out, so a hit is recognisable at a glance.
  Widget _matchText(
    SearchMatch match, {
    required Color ink,
    required Color accent,
  }) {
    final text = match.snippet;
    final start = match.matchStart.clamp(0, text.length);
    final end = match.matchEnd.clamp(start, text.length);
    final base = TextStyle(
      color: ink.withValues(alpha: .92),
      fontSize: 14,
      height: 1.35,
    );
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          if (start > 0) TextSpan(text: text.substring(0, start)),
          if (end > start)
            TextSpan(
              text: text.substring(start, end),
              style: base.copyWith(
                color: accent,
                fontWeight: FontWeight.w600,
                backgroundColor: accent.withValues(alpha: .18),
              ),
            ),
          if (end < text.length) TextSpan(text: text.substring(end)),
        ],
      ),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildNotes(BuildContext context) {
    final notes = widget.notes;
    final surface = widget.surface ?? VellumTheme.readerChromeOf(context);
    final ink = VellumTheme.readerChromeInk(surface);
    final muted = ink.withValues(alpha: .55);
    final accent = VellumTheme.readerAccentOf(context);
    if (notes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(CupertinoIcons.text_badge_plus, size: 30, color: muted),
              const SizedBox(height: 10),
              Text(
                '选中正文后可以划线或写笔记。',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, height: 1.35),
              ),
            ],
          ),
        ),
      );
    }
    return Scrollbar(
      thumbVisibility: true,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        itemCount: notes.length,
        itemBuilder: (context, index) {
          final note = notes[index];
          // Imported notes whose book was never identified are tagged, and this
          // list is where the reader meets them for the current book.
          final orphaned = note.bookId == unmatchedBookId;
          final quote = note.selectedText.trim();
          final comment = note.note.trim();
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: ink.withValues(alpha: .035),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: ink.withValues(alpha: .08)),
              ),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => widget.onJumpToParagraph(note.paragraphIndex),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: .12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              note.kind.label,
                              style: TextStyle(
                                color: accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              [
                                '第 ${note.paragraphIndex + 1} 段',
                                if (orphaned) '$unmatchedBookTitle · 可重新关联',
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: muted, fontSize: 12),
                            ),
                          ),
                          Semantics(
                            button: true,
                            label: '删除笔记',
                            child: CupertinoButton(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(44, 44),
                              onPressed: () async {
                                await widget.onRemoveNote(note.id);
                                if (mounted) setState(() {});
                              },
                              child: Icon(
                                CupertinoIcons.delete,
                                size: 17,
                                color: muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (quote.isNotEmpty) ...[
                        const SizedBox(height: 9),
                        Container(
                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: .08),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            quote,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: ink,
                              fontSize: 14,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                      if (comment.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          comment,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: ink.withValues(alpha: .82),
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The reader's search query field.
///
/// It exists only while searching, so `autofocus` is what claims the caret and
/// raises the soft keyboard: a focus request made from the panel lands before
/// this field is mounted and is dropped. It is a separate widget so panel
/// rebuilds cannot recreate its input connection.
class _SearchQueryField extends StatefulWidget {
  const _SearchQueryField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.showClear,
    required this.onClear,
    required this.style,
    required this.placeholderStyle,
    required this.cursorColor,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final bool showClear;
  final VoidCallback onClear;
  final TextStyle style;
  final TextStyle placeholderStyle;
  final Color cursorColor;

  @override
  State<_SearchQueryField> createState() => _SearchQueryFieldState();
}

class _SearchQueryFieldState extends State<_SearchQueryField> {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: CupertinoTextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            autofocus: true,
            onChanged: widget.onChanged,
            placeholder: '搜索全书内容',
            placeholderStyle: widget.placeholderStyle,
            style: widget.style,
            padding: EdgeInsets.zero,
            decoration: const BoxDecoration(),
            cursorColor: widget.cursorColor,
          ),
        ),
        if (widget.showClear)
          GestureDetector(
            onTap: widget.onClear,
            child: Icon(
              CupertinoIcons.xmark_circle_fill,
              size: 16,
              color: widget.placeholderStyle.color,
            ),
          ),
      ],
    );
  }
}

class ReaderSettingsPanel extends StatefulWidget {
  const ReaderSettingsPanel({
    required this.fontSize,
    required this.readerFontWeight,
    required this.lineSpacing,
    required this.background,
    required this.readingMode,
    required this.pageTurnStyle,
    required this.brightness,
    required this.eyeCare,
    required this.keepScreenOn,
    required this.volumeKeys,
    required this.onFontSize,
    required this.onReaderFontWeight,
    required this.onLineSpacing,
    required this.onBackground,
    required this.onReadingMode,
    required this.onPageTurnStyle,
    required this.onBrightness,
    required this.onEyeCare,
    required this.onKeepScreenOn,
    required this.onVolumeKeys,
    required this.onShowFonts,
    required this.onClose,
    this.surface,
    super.key,
  });

  final double fontSize;
  final ReaderFontWeight readerFontWeight;
  final ReaderLineSpacing lineSpacing;
  final ReaderBackground background;
  final ReadingMode readingMode;
  final PageTurnStyle pageTurnStyle;
  final double brightness;
  final ReaderEyeCare eyeCare;
  final bool keepScreenOn;
  final bool volumeKeys;
  final ValueChanged<double> onFontSize;
  final ValueChanged<ReaderFontWeight> onReaderFontWeight;
  final ValueChanged<ReaderLineSpacing> onLineSpacing;
  final ValueChanged<ReaderBackground> onBackground;
  final ValueChanged<ReadingMode> onReadingMode;
  final ValueChanged<PageTurnStyle> onPageTurnStyle;
  final ValueChanged<double> onBrightness;
  final ValueChanged<ReaderEyeCare> onEyeCare;
  final ValueChanged<bool> onKeepScreenOn;
  final ValueChanged<bool> onVolumeKeys;
  final VoidCallback onShowFonts;
  final VoidCallback onClose;
  final Color? surface;

  @override
  State<ReaderSettingsPanel> createState() => _ReaderSettingsPanelState();
}

/// First level keeps mid-book controls (mode, font size, paper, font,
/// line spacing). Rarer options live behind 「更多设置」.
class _ReaderSettingsPanelState extends State<ReaderSettingsPanel> {
  bool _showMore = false;
  bool _showBackground = false;
  // Inline pickers replace the old third-level 取色 page: one tap expands
  // a live HSV pad under the row and every drag paints the reader at once.
  bool _showInkPicker = false;
  bool _showUnderlayPicker = false;

  /// A sub-page should always start at its title. Preserving the previous
  /// scroll offset could leave the new title outside the viewport, so the
  /// back icon painted but its hit target was clipped by the scroll view.
  final ScrollController _scrollController = ScrollController();

  static const double _followSystemBrightness = -1;

  bool get _followsSystem => widget.brightness < 0;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _resetSubpageScroll() {
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  void _setSubpage(VoidCallback change) {
    setState(change);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _resetSubpageScroll();
    });
  }

  Color get _surface => widget.surface ?? VellumTheme.readerChromeOf(context);
  Color get _ink => VellumTheme.readerChromeInk(_surface);
  Color get _muted => _ink.withValues(alpha: .55);

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _showBackground
              ? _backgroundSettings(context)
              : (_showMore ? _moreSettings(context) : _mainSettings(context)),
        ),
      ),
    );
  }

  static const _presetPapers = <Color>[
    VellumTheme.readerWhite,
    VellumTheme.readerSepia,
    VellumTheme.readerMint,
    VellumTheme.readerBlue,
    VellumTheme.readerNight,
    VellumTheme.readerCharcoal,
    VellumTheme.readerSoftBlack,
  ];

  /// Second level: imported image + underlay + image opacity + ink picker +
  /// eye-care. Basic swatches live on the first level.
  List<Widget> _backgroundSettings(BuildContext context) => [
    ReaderPanelTitle(
      icon: CupertinoIcons.photo,
      title: '自定义背景',
      surface: _surface,
      onClose: widget.onClose,
      onBack: () => _setSubpage(() {
        _showInkPicker = false;
        _showUnderlayPicker = false;
        _showBackground = false;
      }),
    ),
    _studioLabel('背景图'),
    Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: widget.background.usesImage
                ? Color(
                    widget.background.colorValue ?? 0xfff6f6f6,
                  ).withValues(alpha: widget.background.clampedImageOpacity)
                : Color(widget.background.colorValue ?? 0xfff6f6f6),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _ink.withValues(alpha: .2)),
          ),
          clipBehavior: Clip.antiAlias,
          child: widget.background.usesImage
              ? const Icon(CupertinoIcons.photo, size: 18)
              : null,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(0, 34),
            onPressed: _pickBackgroundImage,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.photo_on_rectangle, size: 16, color: _ink),
                const SizedBox(width: 4),
                Text('导入图片', style: TextStyle(fontSize: 13, color: _ink)),
              ],
            ),
          ),
        ),
        if (widget.background.usesImage)
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(0, 34),
            onPressed: () => widget.onBackground(
              widget.background.copyWith(
                clearImage: true,
                kind: BackgroundKind.solid,
              ),
            ),
            child: Text('移除', style: TextStyle(fontSize: 13, color: _muted)),
          ),
      ],
    ),
    if (widget.background.usesImage) ...[
      const SizedBox(height: 12),
      _studioLabel('背景色（图片底下的纯色）'),
      Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Color(
                widget.background.colorValue ??
                    VellumTheme.readerWhite.toARGB32(),
              ),
              shape: BoxShape.circle,
              border: Border.all(color: _ink.withValues(alpha: .25)),
            ),
          ),
          const SizedBox(width: 10),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(0, 34),
            onPressed: () => _setSubpage(() {
              _showInkPicker = false;
              _showUnderlayPicker = !_showUnderlayPicker;
            }),
            child: Text(
              _showUnderlayPicker ? '收起取色' : '取色',
              style: TextStyle(fontSize: 13, color: _ink),
            ),
          ),
          if (widget.background.colorValue != null)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 34),
              onPressed: () => widget.onBackground(
                widget.background.copyWith(clearColor: true),
              ),
              child: Text(
                '恢复默认',
                style: TextStyle(fontSize: 12, color: _muted),
              ),
            ),
        ],
      ),
      if (_showUnderlayPicker) ...[
        const SizedBox(height: 10),
        ReaderColorPicker(
          color: Color(
            widget.background.colorValue ?? VellumTheme.readerWhite.toARGB32(),
          ),
          previewLabel: '背景色示例',
          onChanged: (c) => widget.onBackground(
            widget.background.copyWith(colorValue: c.toARGB32()),
          ),
        ),
      ],
      const SizedBox(height: 12),
      _studioLabel('背景图透明度'),
      Row(
        children: [
          Expanded(
            child: CupertinoSlider(
              value: widget.background.clampedImageOpacity,
              min: 0,
              max: 1,
              onChanged: (v) => widget.onBackground(
                widget.background.copyWith(imageOpacity: v),
              ),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              '${(widget.background.clampedImageOpacity * 100).round()}%',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12, color: _muted),
            ),
          ),
        ],
      ),
    ],
    const SizedBox(height: 8),
    _studioLabel('正文字色（阅读正文的颜色）'),
    Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Color(widget.background.inkValue),
            shape: BoxShape.circle,
            border: Border.all(color: _ink.withValues(alpha: .25)),
          ),
        ),
        const SizedBox(width: 10),
        CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(0, 34),
          onPressed: () => _setSubpage(() {
            _showUnderlayPicker = false;
            _showInkPicker = !_showInkPicker;
          }),
          child: Text(
            _showInkPicker ? '收起取色' : '取色',
            style: TextStyle(fontSize: 13, color: _ink),
          ),
        ),
        if (widget.background.inkColorValue != null)
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(0, 34),
            onPressed: () =>
                widget.onBackground(widget.background.copyWith(clearInk: true)),
            child: Text('恢复默认', style: TextStyle(fontSize: 12, color: _muted)),
          ),
      ],
    ),
    if (_showInkPicker) ...[
      const SizedBox(height: 10),
      ReaderColorPicker(
        color: Color(widget.background.inkValue),
        previewLabel: '正文示例文字',
        onChanged: (c) => widget.onBackground(
          widget.background.copyWith(inkColorValue: c.toARGB32()),
        ),
      ),
      const SizedBox(height: 6),
      // One-tap common inks so most users never open the pad.
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final entry in const {
            0xff000000: '纯黑',
            0xff333333: '深灰',
            0xff8c8c8c: '中灰',
            0xffb7b7b7: '浅灰',
            0xfff7e4cf: '米黄',
          }.entries)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: const Size(0, 30),
              color: Color(entry.key),
              borderRadius: BorderRadius.circular(15),
              onPressed: () => widget.onBackground(
                widget.background.copyWith(inkColorValue: entry.key),
              ),
              child: Text(
                entry.value,
                style: TextStyle(
                  fontSize: 12,
                  color:
                      ReaderBackground.suggestTone(entry.key) ==
                          BackgroundTone.dark
                      ? CupertinoColors.white
                      : CupertinoColors.black,
                ),
              ),
            ),
        ],
      ),
    ],
    const SizedBox(height: 8),
    _studioLabel('墨色（未自定义字体色时按底色明暗）'),
    _optionGroup<BackgroundTone>(
      groupValue: widget.background.tone,
      options: {for (final tone in BackgroundTone.values) tone: tone.label},
      onChanged: (tone) =>
          widget.onBackground(widget.background.copyWith(tone: tone)),
    ),
    const SizedBox(height: 14),
    _studioLabel('护眼'),
    _optionGroup<ReaderEyeCare>(
      groupValue: widget.eyeCare,
      options: {for (final level in ReaderEyeCare.values) level: level.label},
      onChanged: widget.onEyeCare,
    ),
    const SizedBox(height: 12),
    Text(
      '图片与自定义色只保存在本机 backgrounds/ 目录；护眼为 0.15 覆盖层，亮度走窗口属性，三者互相独立。',
      style: TextStyle(fontSize: 11, color: _muted, height: 1.5),
    ),
    const SizedBox(height: 8),
  ];

  Widget _studioLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: TextStyle(fontSize: 12, color: _muted, letterSpacing: .4),
    ),
  );

  bool _isSelectedColor(int argb) =>
      !widget.background.usesImage && widget.background.colorValue == argb;

  void _applyPresetColor(Color color) {
    final argb = color.toARGB32();
    widget.onBackground(
      ReaderBackground.customColor(
        argb,
        tone: ReaderBackground.suggestTone(argb),
      ),
    );
  }

  Future<void> _pickBackgroundImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
        withData: true,
      );
      final file = result?.files.single;
      final bytes = file?.bytes;
      if (file == null || bytes == null) return;
      final name = await const ReaderBackgroundStore().importImage(
        Uint8List.fromList(bytes),
        file.name,
      );
      widget.onBackground(
        ReaderBackground.customImage(
          name,
          underlayColor: widget.background.colorValue,
          imageOpacity: widget.background.imageOpacity,
          tone: widget.background.tone,
          inkColorValue: widget.background.inkColorValue,
        ),
      );
    } catch (_) {
      // Picking cancelled or the provider returned nothing.
    }
  }

  Widget _optionGroup<T>({
    required T groupValue,
    required Map<T, String> options,
    required ValueChanged<T> onChanged,
  }) {
    final ink = _ink;
    final accent = VellumTheme.readerAccentOf(context);
    final surface = _surface;
    return Container(
      height: 44,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          for (final entry in options.entries)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(entry.key),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: groupValue == entry.key
                        ? surface.withValues(alpha: .95)
                        : const Color(0x00000000),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    entry.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: groupValue == entry.key ? accent : ink,
                      fontWeight: groupValue == entry.key
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _mainSettings(BuildContext context) => [
    ReaderPanelTitle(
      icon: CupertinoIcons.gear,
      title: '阅读设置',
      surface: _surface,
      onClose: widget.onClose,
    ),
    // Reading mode first — page vs scroll is the highest-frequency choice.
    ReaderSettingRow(
      label: '阅读方式',
      surface: _surface,
      child: _optionGroup<ReadingMode>(
        groupValue: widget.readingMode,
        options: const {ReadingMode.scroll: '上下滚动', ReadingMode.page: '左右翻页'},
        onChanged: widget.onReadingMode,
      ),
    ),
    if (widget.readingMode == ReadingMode.page)
      ReaderSettingRow(
        label: '翻页效果',
        surface: _surface,
        child: _optionGroup<PageTurnStyle>(
          groupValue: widget.pageTurnStyle,
          options: {
            for (final style in PageTurnStyle.values) style: style.label,
          },
          onChanged: widget.onPageTurnStyle,
        ),
      ),
    _fontSizeRow(context),
    ReaderSettingRow(
      label: '亮度',
      surface: _surface,
      child: _brightnessRow(context),
    ),
    // Basic papers sit on the first level so the panel opens ready to pick.
    Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text('背景', style: TextStyle(color: _muted, fontSize: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final color in _presetPapers)
                  GestureDetector(
                    onTap: () => _applyPresetColor(color),
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _isSelectedColor(color.toARGB32())
                              ? VellumTheme.readerAccentOf(context)
                              : _ink.withValues(alpha: .2),
                          width: _isSelectedColor(color.toARGB32()) ? 2 : 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(0, 36),
            onPressed: () => _setSubpage(() {
              _showMore = false;
              _showInkPicker = false;
              _showUnderlayPicker = false;
              _showBackground = true;
            }),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('自定义', style: TextStyle(fontSize: 13, color: _ink)),
                Icon(CupertinoIcons.chevron_forward, size: 14, color: _muted),
              ],
            ),
          ),
        ],
      ),
    ),
    // Font entry preserved (FontPickerSheet) — whole row is tappable.
    GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onShowFonts,
      child: ReaderSettingRow(
        label: '字体',
        surface: _surface,
        child: Row(
          children: [
            Expanded(
              child: Text(
                '系统 / 导入',
                style: TextStyle(fontSize: 13, color: _muted),
              ),
            ),
            Icon(CupertinoIcons.chevron_forward, size: 16, color: _muted),
          ],
        ),
      ),
    ),
    ReaderSettingRow(
      label: '行间距',
      surface: _surface,
      child: _optionGroup<ReaderLineSpacing>(
        groupValue: widget.lineSpacing,
        options: {
          for (final spacing in ReaderLineSpacing.values)
            spacing: spacing.label,
        },
        onChanged: widget.onLineSpacing,
      ),
    ),
    GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _setSubpage(() => _showMore = true),
      child: ReaderSettingRow(
        label: '更多',
        surface: _surface,
        child: Row(
          children: [
            Expanded(
              child: Text('更多设置', style: TextStyle(fontSize: 13, color: _ink)),
            ),
            Icon(CupertinoIcons.chevron_forward, size: 16, color: _muted),
          ],
        ),
      ),
    ),
  ];

  List<Widget> _moreSettings(BuildContext context) => [
    ReaderPanelTitle(
      icon: CupertinoIcons.slider_horizontal_3,
      title: '更多设置',
      surface: _surface,
      onClose: widget.onClose,
      onBack: () => _setSubpage(() => _showMore = false),
    ),
    ReaderSettingRow(
      label: '字重',
      surface: _surface,
      child: _optionGroup<ReaderFontWeight>(
        groupValue: widget.readerFontWeight,
        options: {
          for (final weight in ReaderFontWeight.values) weight: weight.label,
        },
        onChanged: widget.onReaderFontWeight,
      ),
    ),
    _switchRow(
      context,
      label: '常亮',
      detail: '阅读时保持屏幕常亮',
      value: widget.keepScreenOn,
      onChanged: widget.onKeepScreenOn,
    ),
    _switchRow(
      context,
      label: '音量键',
      detail: '用音量键翻页',
      value: widget.volumeKeys,
      onChanged: widget.onVolumeKeys,
    ),
  ];

  Widget _fontSizeRow(BuildContext context) => ReaderSettingRow(
    label: '字号',
    surface: _surface,
    child: Row(
      children: [
        CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          minimumSize: const Size(44, 44),
          onPressed: () => widget.onFontSize(
            (widget.fontSize - 1).clamp(kReaderFontMin, kReaderFontMax),
          ),
          child: Text('A−', style: TextStyle(fontSize: 14, color: _ink)),
        ),
        Expanded(
          child: CupertinoSlider(
            value: widget.fontSize.clamp(kReaderFontMin, kReaderFontMax),
            min: kReaderFontMin,
            max: kReaderFontMax,
            onChanged: widget.onFontSize,
          ),
        ),
        CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          minimumSize: const Size(44, 44),
          onPressed: () => widget.onFontSize(
            (widget.fontSize + 1).clamp(kReaderFontMin, kReaderFontMax),
          ),
          child: Text('A+', style: TextStyle(fontSize: 14, color: _ink)),
        ),
        SizedBox(
          width: 28,
          child: Text(
            '${widget.fontSize.round()}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: _muted),
          ),
        ),
      ],
    ),
  );

  Widget _brightnessRow(BuildContext context) => Row(
    children: [
      Icon(CupertinoIcons.sun_min, size: 16, color: _muted),
      Expanded(
        child: CupertinoSlider(
          value: (_followsSystem ? 0.6 : widget.brightness).clamp(0.05, 1.0),
          min: 0.05,
          max: 1,
          onChanged: widget.onBrightness,
        ),
      ),
      CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        minimumSize: const Size(44, 44),
        onPressed: () => widget.onBrightness(_followSystemBrightness),
        child: Text(
          _followsSystem ? '跟随系统' : '恢复跟随',
          style: TextStyle(
            fontSize: 12,
            color: _followsSystem
                ? _muted
                : VellumTheme.readerAccentOf(context),
          ),
        ),
      ),
    ],
  );

  Widget _switchRow(
    BuildContext context, {
    required String label,
    required String detail,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => ReaderSettingRow(
    label: label,
    surface: _surface,
    child: Row(
      children: [
        Expanded(
          child: Text(detail, style: TextStyle(fontSize: 12, color: _muted)),
        ),
        CupertinoSwitch(value: value, onChanged: onChanged),
      ],
    ),
  );
}

class ReaderPanelTitle extends StatelessWidget {
  const ReaderPanelTitle({
    required this.icon,
    required this.title,
    required this.onClose,
    this.onBack,
    this.surface,
    super.key,
  });

  final IconData icon;
  final String title;
  final VoidCallback onClose;
  final VoidCallback? onBack;
  final Color? surface;

  @override
  Widget build(BuildContext context) {
    final bg = surface ?? VellumTheme.readerChromeOf(context);
    final ink = VellumTheme.readerChromeInk(bg);
    final muted = ink.withValues(alpha: .55);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
      child: Row(
        children: [
          if (onBack != null)
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(44, 44),
              pressedOpacity: .65,
              onPressed: onBack,
              child: Icon(CupertinoIcons.chevron_back, size: 20, color: muted),
            )
          else
            Icon(icon, size: 18, color: VellumTheme.readerAccentOf(context)),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              color: ink,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(44, 44),
            pressedOpacity: .65,
            onPressed: onClose,
            child: Icon(CupertinoIcons.chevron_down, size: 20, color: muted),
          ),
        ],
      ),
    );
  }
}

class ReaderSettingRow extends StatelessWidget {
  const ReaderSettingRow({
    required this.label,
    required this.child,
    this.surface,
    super.key,
  });

  final String label;
  final Widget child;
  final Color? surface;

  @override
  Widget build(BuildContext context) {
    final bg = surface ?? VellumTheme.readerChromeOf(context);
    final muted = VellumTheme.readerChromeInk(bg).withValues(alpha: .55);
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 56,
              child: Text(label, style: TextStyle(color: muted, fontSize: 12)),
            ),
            const SizedBox(width: 10),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
