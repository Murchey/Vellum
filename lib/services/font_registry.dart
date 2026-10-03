import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

/// Central font registration for user-imported TTF files.
///
/// The engine keeps every family handed to [FontLoader] resident for the life
/// of the process, and re-registering a family **adds** another copy instead of
/// replacing the previous one. Measured with 17 MB CJK fonts, one registration
/// costs ≈1.9× the file size in RSS and never shrinks. A reader that switched
/// fonts, or a picker sheet whose rows each loaded their own preview, therefore
/// paid tens of megabytes per tap until the Android heap was gone — the
/// "switching fonts in a big book lags, then the app disappears" report.
///
/// So: register each family at most once, and only re-register when the bytes
/// behind that family actually changed (delete + re-import of the same name).
class FontRegistry {
  FontRegistry._();

  /// Bookkeeping for one family: bytes are held weakly so a preview that only
  /// ever needs them once does not pin 17 MB of Dart heap for the session.
  static final Map<String, _Registration> _registrations = {};

  /// Registrations in flight, keyed by family: parallel callers (a picker
  /// preview and the activation that follows it) join one engine load instead
  /// of racing each other into a second permanent copy.
  static final Map<String, FontRegistryRequest> _inFlight = {};

  /// The actual engine registration. Swapped in tests to assert that a family
  /// is never handed to the engine twice.
  @visibleForTesting
  static Future<void> Function(String family, Uint8List bytes) register =
      _registerWithEngine;

  static Future<void> _registerWithEngine(String family, Uint8List bytes) {
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    return loader.load();
  }

  /// True when [family] is registered. With [bytes], true only when those exact
  /// bytes are the ones that were registered.
  static bool isRegistered(String family, [Uint8List? bytes]) {
    final registration = _registrations[family];
    if (registration == null) return false;
    if (bytes == null) return true;
    final loaded = registration.bytes.target;
    return identical(loaded, bytes) || registration.matches(bytes);
  }

  /// Registers [bytes] under [family] unless that exact font is already live.
  ///
  /// Returns true when this call is the one that registered the font.
  static Future<bool> load(String family, Uint8List bytes) {
    if (family.isEmpty || bytes.isEmpty) return Future<bool>.value(false);
    if (isRegistered(family, bytes)) return Future<bool>.value(false);

    final pending = _inFlight[family];
    if (pending != null) {
      if (identical(pending.bytes, bytes)) {
        return pending.done.then((_) => false);
      }
      // A different font is mid-flight for this family: wait it out, then
      // register ours if it did not already win.
      return pending.done.then((_) => load(family, bytes));
    }

    final request = FontRegistryRequest(bytes);
    _inFlight[family] = request;
    Future<bool> run() async {
      try {
        await register(family, bytes);
        _registrations[family] = _Registration(
          WeakReference(bytes),
          _signal(bytes),
        );
        return true;
      } catch (_) {
        // An invalid font file stays usable through the platform fallback.
        _registrations.remove(family);
        return false;
      } finally {
        _inFlight.remove(family);
        request.complete();
      }
    }

    final result = run();
    // Nothing may await before this point, or a second caller would see no
    // in-flight request and start a duplicate registration.
    return result;
  }

  /// Drops a family's bookkeeping. The engine cannot unload a font, so this
  /// only makes a later registration of changed bytes possible.
  static void forget(String family) {
    _registrations.remove(family);
  }

  static void forgetAll() {
    _registrations.clear();
  }

  /// Cheap identity for a font file: length plus three sampled windows. A
  /// re-import of the same name almost always changes at least one of them,
  /// and this costs O(1) instead of hashing megabytes on the UI thread.
  static String _signal(Uint8List bytes) {
    final length = bytes.length;
    final head = _window(bytes, 0, length);
    final middle = _window(bytes, length ~/ 2, length);
    final tail = _window(bytes, length - 64, length);
    return '$length:$head:$middle:$tail';
  }

  static String _window(Uint8List bytes, int start, int length) {
    if (length <= 0) return '0';
    final from = start.clamp(0, length);
    final to = (from + 64).clamp(0, length);
    if (to <= from) return '0';
    var hash = 0x811c9dc5;
    for (var i = from; i < to; i++) {
      hash = ((hash ^ bytes[i]) * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16);
  }
}

class _Registration {
  _Registration(this.bytes, this.signal);

  /// Weak so one-off previews do not pin the font bytes for the session.
  final WeakReference<Uint8List> bytes;
  final String signal;

  bool matches(Uint8List candidate) => signal == FontRegistry._signal(candidate);
}

/// One in-flight engine registration, awaited by every caller for that family.
class FontRegistryRequest {
  FontRegistryRequest(this.bytes);

  /// Bytes this request is registering; used to recognise a caller asking for
  /// the very same file.
  final Uint8List bytes;

  final Completer<void> _completer = Completer<void>();

  Future<void> get done => _completer.future;

  void complete() {
    if (!_completer.isCompleted) _completer.complete();
  }
}
