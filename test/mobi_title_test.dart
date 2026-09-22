import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/services/mobi_decoder.dart';

void main() {
  group('MOBI shelf title heuristics', () {
    test('rejects numeric product ids that used to replace book titles', () {
      expect(MobiDecoder.looksLikeBookTitle('1234567890'), isFalse);
      expect(MobiDecoder.looksLikeBookTitle('23456789'), isFalse);
      expect(MobiDecoder.looksLikeBookTitle('A1B2C3D4E5'), isFalse);
      expect(MobiDecoder.looksLikeBookTitle('EBOK12345678'), isFalse);
      expect(MobiDecoder.looksLikeBookTitle('BOOK000123'), isFalse);
      expect(MobiDecoder.looksLikeBookTitle('9787020000000'), isFalse);
    });

    test('accepts real-looking titles', () {
      expect(MobiDecoder.looksLikeBookTitle('百年孤独'), isTrue);
      expect(MobiDecoder.looksLikeBookTitle('The Little Prince'), isTrue);
      expect(MobiDecoder.looksLikeBookTitle('三体全集'), isTrue);
      expect(MobiDecoder.looksLikeBookTitle('活着'), isTrue);
    });

    test('rejects empty or absurd values', () {
      expect(MobiDecoder.looksLikeBookTitle(''), isFalse);
      expect(MobiDecoder.looksLikeBookTitle('a'), isFalse);
      expect(MobiDecoder.looksLikeBookTitle('!@#\$%^&*()'), isFalse);
    });
  });

  group('MOBI pinyin vs CJK title scoring', () {
    test('detects spaced pinyin but not normal English titles', () {
      expect(MobiDecoder.looksLikePinyin('hali bote'), isTrue);
      expect(MobiDecoder.looksLikePinyin('hali-bote'), isTrue);
      expect(MobiDecoder.looksLikePinyin('哈利·波特'), isFalse);
      expect(MobiDecoder.looksLikePinyin('Harry Potter'), isFalse);
      expect(MobiDecoder.looksLikePinyin('The Little Prince'), isFalse);
    });

    test('CJK metadata beats pinyin when filename is Chinese', () {
      final cjk = MobiDecoder.titleScore('哈利·波特', fileTitle: '哈利·波特');
      final pinyin = MobiDecoder.titleScore('hali bote', fileTitle: '哈利·波特');
      expect(cjk, greaterThan(pinyin));
      expect(cjk, greaterThan(0));
    });

    test('Chinese filename wins over pinyin metadata', () {
      final fileTitle = '哈利·波特';
      final cjkScore = MobiDecoder.titleScore(fileTitle, fileTitle: fileTitle);
      final pinyinScore = MobiDecoder.titleScore(
        'hali bote',
        fileTitle: fileTitle,
      );
      expect(cjkScore, greaterThan(pinyinScore));
    });
  });

  group('MOBI TOC title cleaning', () {
    test('strips tags, entities and filepos leftovers', () {
      expect(MobiDecoder.cleanMobiTocTitle('<b>第一章</b>'), '第一章');
      expect(MobiDecoder.cleanMobiTocTitle('第&nbsp;二&nbsp;章'), '第 二 章');
      expect(
        MobiDecoder.cleanMobiTocTitle('<a filepos="000012345">第三章</a>'),
        '第三章',
      );
      expect(MobiDecoder.cleanMobiTocTitle('&#31532;&#22235;&#31456;'), '第四章');
    });

    test('flags dirty labels', () {
      expect(MobiDecoder.isDirtyTocTitle(''), isTrue);
      expect(MobiDecoder.isDirtyTocTitle('…'), isTrue);
      expect(MobiDecoder.isDirtyTocTitle('— —'), isTrue);
      expect(MobiDecoder.isDirtyTocTitle('������'), isTrue);
      expect(MobiDecoder.isDirtyTocTitle('第一章'), isFalse);
      expect(MobiDecoder.isDirtyTocTitle('Chapter 1'), isFalse);
      expect(MobiDecoder.isDirtyTocTitle('哈利·波特与魔法石'), isFalse);
    });
  });
}
