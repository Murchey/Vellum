import 'dart:ui' show Offset;

import 'reader_models.dart';

enum ReaderTapAction {
  none,
  toggleBookmark,
  toggleControls,
  previousPage,
  nextPage,
}

/// Pure gesture classification for the reader surface.
abstract final class ReaderGestures {
  static bool isCenterTap(Offset position, double width, double height) {
    final dx = (position.dx - width / 2).abs();
    final dy = (position.dy - height / 2).abs();
    return dx < width * 0.3 && dy < height * 0.25;
  }

  static const double bookmarkPullThreshold = 96;

  /// Long-press to select text then drag down must not arm bookmark.
  /// Bookmark requires a quick, mostly vertical downward flick at the top.
  static const Duration bookmarkMaxHold = Duration(milliseconds: 400);

  static ReaderTapAction resolvePointerUp({
    required DateTime? downAt,
    required Offset? downPosition,
    required Offset upPosition,
    required ReadingMode mode,
    required bool beginsAtScrollTop,
    required bool isIdle,
    required double screenWidth,
    required double screenHeight,
    bool selectionGesture = false,
  }) {
    if (downAt == null || downPosition == null) return ReaderTapAction.none;

    final elapsed = DateTime.now().difference(downAt);
    final delta = upPosition - downPosition;
    final downwardPull = delta.dy > bookmarkPullThreshold;
    final horizontalShift = delta.dx.abs();
    final quickFlick = elapsed < bookmarkMaxHold && !selectionGesture;
    final mostlyVertical = horizontalShift < 48;
    if (downwardPull && beginsAtScrollTop && quickFlick && mostlyVertical) {
      return ReaderTapAction.toggleBookmark;
    }
    // A long-press drag is selection, not a tap action.
    if (elapsed >= const Duration(milliseconds: 450) || delta.distance > 12) {
      return ReaderTapAction.none;
    }
    if (!isIdle) return ReaderTapAction.none;

    if (mode != ReadingMode.page) {
      if (isCenterTap(upPosition, screenWidth, screenHeight)) {
        return ReaderTapAction.toggleControls;
      }
      return ReaderTapAction.none;
    }

    if (upPosition.dx < screenWidth * .3) return ReaderTapAction.previousPage;
    if (upPosition.dx > screenWidth * .7) return ReaderTapAction.nextPage;
    return ReaderTapAction.toggleControls;
  }
}
