import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Speech provider families supported by the listen feature.
enum TtsProvider {
  openai('OpenAI 兼容'),
  azure('Azure');

  const TtsProvider(this.label);

  final String label;

  static TtsProvider fromName(String value) => TtsProvider.values.firstWhere(
    (provider) => provider.name == value,
    orElse: () => TtsProvider.openai,
  );
}

/// User-configured speech service. Everything lives in one local JSON file,
/// matching the app's "data stays on this device" stance.
class TtsPreferences {
  const TtsPreferences({
    this.provider = TtsProvider.openai,
    this.baseUrl = '',
    this.apiKey = '',
    this.model = '',
    this.voice = '',
    this.speed = 1.0,
  });

  final TtsProvider provider;

  /// OpenAI-compatible base URL or Azure region/endpoint, depending on
  /// [provider].
  final String baseUrl;
  final String apiKey;
  final String model;
  final String voice;

  /// Playback rate, `0.5–2.0`.
  final double speed;

  bool get isConfigured => apiKey.trim().isNotEmpty;

  TtsPreferences copyWith({
    TtsProvider? provider,
    String? baseUrl,
    String? apiKey,
    String? model,
    String? voice,
    double? speed,
  }) => TtsPreferences(
    provider: provider ?? this.provider,
    baseUrl: baseUrl ?? this.baseUrl,
    apiKey: apiKey ?? this.apiKey,
    model: model ?? this.model,
    voice: voice ?? this.voice,
    speed: speed ?? this.speed,
  );

  Map<String, dynamic> toJson() => {
    'provider': provider.name,
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'model': model,
    'voice': voice,
    'speed': speed,
  };

  factory TtsPreferences.fromJson(Map<String, dynamic> json) =>
      TtsPreferences(
        provider: TtsProvider.fromName(json['provider'] as String? ?? 'openai'),
        baseUrl: json['baseUrl'] as String? ?? '',
        apiKey: json['apiKey'] as String? ?? '',
        model: json['model'] as String? ?? '',
        voice: json['voice'] as String? ?? '',
        speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
      );
}

class TtsPreferencesStore {
  const TtsPreferencesStore();

  Future<TtsPreferences> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const TtsPreferences();
      final raw = jsonDecode(await file.readAsString());
      if (raw is Map<String, dynamic>) return TtsPreferences.fromJson(raw);
    } catch (_) {}
    return const TtsPreferences();
  }

  Future<void> save(TtsPreferences preferences) async {
    final file = await _file();
    await file.writeAsString(jsonEncode(preferences.toJson()), flush: true);
  }

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}${Platform.pathSeparator}vellum_tts_prefs.json');
  }
}