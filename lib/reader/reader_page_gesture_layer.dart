import 'package:flutter/widgets.dart';

/// Thin gesture boundary for the reading surface.
///
/// Gesture policy remains in the page state so existing tap, drag, bookmark,
/// and TTS semantics stay unchanged; this widget keeps pointer plumbing out of
/// the page composition tree.
class ReaderGestureLayer extends StatelessWidget {
  const ReaderGestureLayer({
    required this.child,
    required this.onPointerDown,
    required this.onPointerMove,
    required this.onPointerCancel,
    required this.onPointerUp,
    super.key,
  });

  final Widget child;
  final ValueChanged<PointerDownEvent> onPointerDown;
  final ValueChanged<PointerMoveEvent> onPointerMove;
  final ValueChanged<PointerCancelEvent> onPointerCancel;
  final ValueChanged<PointerUpEvent> onPointerUp;

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: onPointerDown,
        onPointerMove: onPointerMove,
        onPointerCancel: onPointerCancel,
        onPointerUp: onPointerUp,
        child: child,
      );
}
