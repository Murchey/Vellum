import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/services/book_search.dart';

void main() {
  final paragraphs = [
    '第一章 起兵',
    '太祖本纪，岁在甲子，天下大乱。',
    '群雄并起，民不聊生。',
    '第二章 定鼎',
    '天下既定，乃修文德。',
    'Chapter 3 The End',
  ];
  const chapters = [
    MapEntry(0, '第一章 起兵'),
    MapEntry(3, '第二章 定鼎'),
    MapEntry(5, 'Chapter 3 The End'),
  ];

  SearchResults run(String query, {List<String>? texts}) => searchBook(
    paragraphs: texts ?? paragraphs,
    query: query,
    chapters: chapters,
  );

  group('scanning', () {
    test('finds every paragraph that contains the query, in reading order', () {
      final hits = run('天下').hits;
      expect(hits.map((h) => h.paragraphIndex), [1, 4]);
      expect(hits.every((h) => h.first.snippet.contains('天下')), isTrue);
    });

    test('records which chapter each hit belongs to', () {
      final hits = run('天下').hits;
      expect(hits[0].chapterTitle, '第一章 起兵');
      expect(hits[1].chapterTitle, '第二章 定鼎');
    });

    test('counts paragraphs and occurrences separately', () {
      final results = run('天下');
      expect(results.paragraphCount, 2);
      expect(results.totalOccurrences, 2);
      expect(results.truncated, isFalse);
    });

    test('matching is case-insensitive for latin text', () {
      expect(run('chapter').hits.single.paragraphIndex, 5);
      expect(run('CHAPTER').hits.single.paragraphIndex, 5);
    });

    test('internal whitespace in the query is collapsed', () {
      final results = searchBook(
        paragraphs: ['太祖  本纪，岁在甲子。'],
        query: '太祖 本纪',
      );
      expect(results.hits, hasLength(1));
      // The highlight still frames the real text, not the normalised copy.
      final match = results.hits.single.first;
      expect(
        match.snippet.substring(match.matchStart, match.matchEnd),
        '太祖  本纪',
      );
    });

    test('an empty or blank query matches nothing', () {
      expect(run('').isEmpty, isTrue);
      expect(run('   ').isEmpty, isTrue);
    });

    test('a book without chapters still returns hits', () {
      final hits = searchParagraphs(paragraphs: paragraphs, query: '天下');
      expect(hits, hasLength(2));
      expect(hits.every((h) => h.chapterTitle.isEmpty), isTrue);
    });

    test('stops at the paragraph cap and says so', () {
      final many = [for (var i = 0; i < 500; i++) '重复内容'];
      final results = searchBook(
        paragraphs: many,
        query: '重复',
        maxParagraphs: 25,
      );
      expect(results.paragraphCount, 25);
      expect(results.truncated, isTrue);
    });

    test('a scan that reaches the end is not reported as truncated', () {
      final results = run('天下');
      expect(results.truncated, isFalse);
    });
  });

  group('matches inside one paragraph', () {
    test('keeps every occurrence, capped per paragraph', () {
      final hits = searchParagraphs(paragraphs: ['啊啊啊'], query: '啊');
      expect(hits.single.matchCount, 3);

      final capped = searchBook(
        paragraphs: ['啊啊啊啊啊啊啊啊啊啊'],
        query: '啊',
        maxMatchesPerParagraph: 4,
      );
      expect(capped.hits.single.matchCount, 4);
      expect(capped.totalOccurrences, 4);
    });

    test('each occurrence has its own snippet and highlight offsets', () {
      // Long enough that the two occurrences sit outside each other's snippet.
      final paragraph = '${'前' * 40}目标${'中' * 40}目标${'后' * 40}';
      final hits = searchParagraphs(paragraphs: [paragraph], query: '目标');
      final matches = hits.single.matches;
      expect(matches, hasLength(2));
      for (final match in matches) {
        expect(
          match.snippet.substring(match.matchStart, match.matchEnd),
          '目标',
          reason: 'offsets must frame the query in that snippet',
        );
      }
      // The two snippets describe different parts of the paragraph.
      expect(matches[0].snippet, isNot(matches[1].snippet));
    });

    test('the snippet is trimmed with ellipsis markers', () {
      final long = '${'前' * 60}目标${'后' * 60}';
      final hits = searchParagraphs(
        paragraphs: [long],
        query: '目标',
        snippetRadius: 10,
      );
      final match = hits.single.first;
      expect(match.snippet.startsWith('…'), isTrue);
      expect(match.snippet.endsWith('…'), isTrue);
      expect(match.snippet.length, lessThan(long.length));
    });
  });

  group('context lines', () {
    test('reports the whole line the match is on, with neighbours', () {
      final results = searchBook(
        paragraphs: ['第一行\n第二行 目标 在这里\n第三行'],
        query: '目标',
      );
      final match = results.hits.single.first;
      expect(match.lineNumber, 2);
      expect(match.leadingContext, '第一行');
      expect(match.trailingContext, '第三行');
    });

    test('a single-line paragraph has no context and reports line 1', () {
      final match = run('天下').hits.first.first;
      expect(match.lineNumber, 1);
      expect(match.leadingContext, isEmpty);
      expect(match.trailingContext, isEmpty);
    });

    test('the first and last lines of a paragraph have one-sided context', () {
      final first = searchBook(paragraphs: ['目标\n后一行'], query: '目标')
          .hits
          .single
          .first;
      expect(first.leadingContext, isEmpty);
      expect(first.trailingContext, '后一行');

      final last = searchBook(paragraphs: ['前一行\n目标'], query: '目标')
          .hits
          .single
          .first;
      expect(last.leadingContext, '前一行');
      expect(last.trailingContext, isEmpty);
    });

    test('context can be turned off', () {
      final match = searchBook(
        paragraphs: ['前一行\n目标'],
        query: '目标',
        contextLines: 0,
      ).hits.single.first;
      expect(match.leadingContext, isEmpty);
      expect(match.trailingContext, isEmpty);
    });
  });

  group('chapter grouping', () {
    test('groups hits by chapter in reading order', () {
      final hits = searchBook(
        paragraphs: [
          '第一章',
          '目标一',
          '仍属第一章',
          '第二章',
          '目标二',
          '目标三',
        ],
        query: '目标',
        chapters: const [MapEntry(0, '第一章'), MapEntry(3, '第二章')],
      ).hits;

      final groups = groupHitsByChapter(hits);
      expect(groups, hasLength(2));
      expect(groups[0].title, '第一章');
      expect(groups[0].hits.single.paragraphIndex, 1);
      expect(groups[1].title, '第二章');
      expect(groups[1].hits.map((h) => h.paragraphIndex), [4, 5]);
      expect(groups[1].occurrences, 2);
    });

    test('hits with no chapter land in one group', () {
      final hits = searchParagraphs(
        paragraphs: ['目标一', '目标二'],
        query: '目标',
      );
      final groups = groupHitsByChapter(hits);
      expect(groups, hasLength(1));
      expect(groups.single.title, isEmpty);
      expect(groups.single.hits, hasLength(2));
    });

    test('a chapter without hits produces no group', () {
      final hits = searchBook(
        paragraphs: ['第一章', '目标', '第二章', '无关'],
        query: '目标',
        chapters: const [MapEntry(0, '第一章'), MapEntry(2, '第二章')],
      ).hits;
      final groups = groupHitsByChapter(hits);
      expect(groups.map((g) => g.title), ['第一章']);
    });
  });

  group('query normalisation', () {
    test('trims, folds case and collapses whitespace', () {
      expect(normalizeQuery('  天下  '), '天下');
      expect(normalizeQuery('Chapter  3'), 'chapter 3');
      expect(normalizeQuery('a\nb\tc'), 'a b c');
      expect(normalizeQuery('   '), '');
    });
  });
}
