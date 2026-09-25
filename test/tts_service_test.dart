import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vellum/services/tts_client.dart';
import 'package:vellum/services/tts_preferences.dart';
import 'package:vellum/services/tts_text.dart';

void main() {
  group('speakable text', () {
    test('strips reader markup and skips silent paragraphs', () {
      final segments = buildSpeakableSegments([
        '', // empty
        '[[image:3]]', // image-only
        '[[vellum-heading:2]]第一章 起风。',
        '这是[[b]]粗体[[/b]]、[[i]]斜体[[/i]]和 [[image:2]] 的混排段。',
      ]);

      expect(segments, hasLength(2));
      expect(segments[0].text, '第一章 起风。');
      expect(segments[0].paragraphIndex, 2);
      expect(segments[0].sentenceIndex, 0);
      expect(segments[1].text, '这是粗体、斜体和 的混排段。');
      expect(segments[1].paragraphIndex, 3);
    });

    test('one segment per sentence (sentence-granular queue)', () {
      final sentence = '一句话有十个汉字哦。';
      final segments = buildSpeakableSegments([sentence * 200], maxChars: 100);

      // 200 sentences → 200 segments, each ending at its own 句界.
      expect(segments, hasLength(200));
      expect(segments.first.text, sentence);
      expect(segments.last.text, sentence);
      expect(segments.every((s) => s.paragraphIndex == 0), isTrue);
      expect(
        segments.map((s) => s.sentenceIndex).toList(),
        List.generate(200, (index) => index),
      );
    });

    test('sentenceAt returns the tapped sentence span', () {
      const text = '第一句。第二句！第三句？';
      final first = sentenceAt(text, 0)!;
      expect(text.substring(first.start, first.end), '第一句。');
      final second = sentenceAt(text, 5)!;
      expect(text.substring(second.start, second.end), '第二句！');
      final third = sentenceAt(text, text.length - 1)!;
      expect(text.substring(third.start, third.end), '第三句？');
    });

    test('a sentence-free wall of text gets hard-cut, not dropped', () {
      final segments = buildSpeakableSegments(['字' * 250], maxChars: 100);
      expect(segments, hasLength(3));
      expect(segments.map((s) => s.text.length).toList(), [100, 100, 50]);
      expect(segments.map((s) => s.sentenceIndex).toList(), [0, 1, 2]);
    });
  });

  group('TtsPreferences', () {
    test('round-trips through storage format', () {
      const prefs = TtsPreferences(
        provider: TtsProvider.azure,
        baseUrl: 'eastasia',
        apiKey: 'secret',
        model: '',
        voice: 'zh-CN-YunxiNeural',
        speed: 1.25,
      );
      final restored = TtsPreferences.fromJson(prefs.toJson());
      expect(restored.provider, TtsProvider.azure);
      expect(restored.baseUrl, 'eastasia');
      expect(restored.voice, 'zh-CN-YunxiNeural');
      expect(restored.speed, 1.25);
      expect(restored.isConfigured, isTrue);
    });

    test('empty preferences are unconfigured', () {
      expect(const TtsPreferences().isConfigured, isFalse);
    });
  });

  group('OpenAI-compatible client', () {
    TtsPreferences prefs({String model = 'tts-1', String voice = 'alloy'}) =>
        TtsPreferences(
          baseUrl: 'https://tts.example.com/v1',
          apiKey: 'k-test',
          model: model,
          voice: voice,
        );

    test('posts to /v1/audio/speech and returns the bytes', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response.bytes(
          Uint8List.fromList([1, 2, 3]),
          200,
        );
      });

      final bytes = await TtsClient.forPreferences(
        prefs(),
        httpClient: client,
      ).synthesize('你好');

      expect(bytes, [1, 2, 3]);
      expect(captured.url.toString(), 'https://tts.example.com/v1/audio/speech');
      expect(captured.headers['Authorization'], 'Bearer k-test');
      expect(captured.body, contains('"input":"你好"'));
      expect(captured.body, contains('"model":"tts-1"'));
      expect(captured.body, contains('"voice":"alloy"'));
      // Speed 1.0 is the API default — not sent.
      expect(captured.body, isNot(contains('speed')));
    });

    test('accepts bare hosts and missing /v1', () async {
      // Endpoint joining is exercised through the request URL.
      late Uri captured;
      final client = MockClient((request) async {
        captured = request.url;
        return http.Response.bytes(Uint8List.fromList([1]), 200);
      });
      final bare = prefs().copyWith(baseUrl: 'tts.example.com');
      await TtsClient.forPreferences(bare, httpClient: client).synthesize('x');
      expect(captured.toString(), 'https://tts.example.com/v1/audio/speech');

      final noSlash = prefs().copyWith(baseUrl: 'https://tts.example.com/');
      await TtsClient.forPreferences(noSlash, httpClient: client).synthesize('x');
      expect(captured.toString(), 'https://tts.example.com/v1/audio/speech');
    });

    test('maps status codes to actionable failures', () async {
      Future<TtsFailure> run(int status) async {
        final client = MockClient(
          (request) async => http.Response.bytes(
            Uint8List.fromList([]),
            status,
          ),
        );
        try {
          await TtsClient.forPreferences(
            prefs(),
            httpClient: client,
          ).synthesize('x');
          return TtsFailure.badResponse;
        } on TtsException catch (error) {
          return error.failure;
        }
      }

      expect(await run(401), TtsFailure.invalidKey);
      expect(await run(403), TtsFailure.invalidKey);
      expect(await run(429), TtsFailure.quota);
      expect(await run(500), TtsFailure.server);
      expect(await run(200), TtsFailure.badResponse); // empty body
    });
  });

  group('Azure client', () {
    test('posts SSML with the voice and rate to the region endpoint', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response.bytes(Uint8List.fromList([9]), 200);
      });
      final prefs = TtsPreferences(
        provider: TtsProvider.azure,
        baseUrl: 'eastasia',
        apiKey: 'az-key',
        voice: 'zh-CN-YunxiNeural',
        speed: 1.25,
      );

      final bytes = await TtsClient.forPreferences(
        prefs,
        httpClient: client,
      ).synthesize('含有<尖括号>的正文');

      expect(bytes, [9]);
      expect(
        captured.url.toString(),
        'https://eastasia.tts.speech.microsoft.com/cognitiveservices/v1',
      );
      expect(captured.headers['Ocp-Apim-Subscription-Key'], 'az-key');
      expect(captured.headers['X-Microsoft-OutputFormat'], contains('mp3'));
      expect(captured.body, contains('zh-CN-YunxiNeural'));
      // 1.25× → +25%.
      expect(captured.body, contains('rate="25%"'));
      // XML-escaped text.
      expect(captured.body, contains('&lt;尖括号&gt;'));
    });
  });
}