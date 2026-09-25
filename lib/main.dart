import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/cupertino.dart';

import 'app.dart';
import 'reader/tts_audio_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // First frame first: the Android launch theme stays on screen (a white
  // screen) until runApp runs, so nothing may block or throw before it.
  runApp(const VellumApp());
  // Listening (听书) is prepared afterwards. just_audio has no Windows
  // backend, and any plugin failure must simply leave the button hidden
  // instead of breaking startup.
  unawaited(_initListening());
}

Future<void> _initListening() async {
  if (!(Platform.isAndroid || Platform.isIOS)) return;
  try {
    ttsHandler = await AudioService.init(
      builder: () => VellumAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.example.vellum.listening',
        androidNotificationChannelName: 'Vellum 听书',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    ).timeout(const Duration(seconds: 8));
  } catch (_) {
    // Missing service declaration, plugin channel problems, or a timeout —
    // listening stays unavailable, the reader works as usual.
    ttsHandler = null;
  }
}