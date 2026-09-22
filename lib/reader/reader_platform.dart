import 'package:flutter/services.dart';

/// Platform knobs the reader drives through the `vellum/device` channel:
/// screen brightness, keeping the screen awake and volume-button paging.
///
/// Every call is best-effort — non-Android targets simply ignore them.
class ReaderPlatform {
  const ReaderPlatform();

  static const _channel = MethodChannel('vellum/device');

  /// [value] is `0..1` for an absolute brightness, or `-1` to follow the
  /// system.
  Future<void> setBrightness(double value) async {
    try {
      await _channel.invokeMethod<void>('setScreenBrightness', {
        'value': value.clamp(-1.0, 1.0),
      });
    } on PlatformException {
      // Desktop targets have no window brightness override.
    } on MissingPluginException {
      // Same.
    }
  }

  Future<void> setKeepScreenOn(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setKeepScreenOn', {
        'enabled': enabled,
      });
    } on PlatformException {
      // Ignored.
    } on MissingPluginException {
      // Ignored.
    }
  }

  /// Turns native volume-key paging on/off for the current screen.
  Future<void> setVolumeKeyPaging(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setVolumeKeyPaging', {
        'enabled': enabled,
      });
    } on PlatformException {
      // Ignored.
    } on MissingPluginException {
      // Ignored.
    }
  }

  /// Registers (or clears, with null) the handler for volume-key events.
  /// [onTurn] receives `-1` for previous and `1` for next.
  void listenForVolumeKeys(void Function(int direction)? onTurn) {
    _channel.setMethodCallHandler(
      onTurn == null
          ? null
          : (call) async {
              if (call.method != 'volumeKey') return null;
              final direction = call.arguments;
              if (direction is int) onTurn(direction);
              return null;
            },
    );
  }
}
