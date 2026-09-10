import 'dart:ui' show Offset;

import 'reader_models.dart';

enum ReaderTapAction {
  none,
  addBookmark,
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

  static ReaderTapAction resolvePointerUp({
    required DateTime? downAt,
    required Offset? downPosition,
    required Offset upPosition,
    required ReadingMode mode,
    required bool beginsAtScrollTop,
    required bool isIdle,
    required double screenWidth,
    required double screenHeight,
  }) {
    if (downAt == null || downPosition == null) return ReaderTapAction.none;

    final downwardPull = upPosition.dy - downPosition.dy > 110;
    if (downwardPull && beginsAtScrollTop) {
      return ReaderTapAction.addBookmark;
    }

    if (DateTime.now().difference(downAt) >= const Duration(milliseconds: 450) ||
        (upPosition - downPosition).distance > 12) {
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
