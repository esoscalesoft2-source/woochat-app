import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/wa_colors.dart';

/// WhatsApp-style back: drag in from the left edge and a round ← bubble
/// follows the finger; let go once it lights up and the screen goes back.
///
/// iOS only. On Android the system draws this same bubble for its own back
/// gesture, and the edge never reaches the app, so [child] is returned as is.
class EdgeSwipeBack extends StatefulWidget {
  const EdgeSwipeBack({super.key, required this.child});

  final Widget child;

  @override
  State<EdgeSwipeBack> createState() => _EdgeSwipeBackState();
}

class _EdgeSwipeBackState extends State<EdgeSwipeBack>
    with SingleTickerProviderStateMixin {
  /// How far in from the edge a drag may start.
  static const double _edgeWidth = 24;

  /// Drag distance at which letting go means "back".
  static const double _trigger = 72;

  /// The bubble stops following past this.
  static const double _maxDrag = 110;

  static const double _bubble = 44;

  /// Runs 1 → 0 to tuck the bubble away after the finger lifts.
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  )..addListener(() => setState(() {}));

  double _dx = 0;
  double _y = 0;
  bool _dragging = false;
  bool _armed = false;

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  double get _shown => _dragging ? _dx : _dx * _settle.value;

  void _onStart(DragStartDetails details) {
    _settle.stop();
    setState(() {
      _dragging = true;
      _armed = false;
      _dx = 0;
      _y = details.localPosition.dy;
    });
  }

  void _onUpdate(DragUpdateDetails details) {
    final dx = (_dx + details.delta.dx).clamp(0.0, _maxDrag);
    final armed = dx >= _trigger;
    if (armed && !_armed) HapticFeedback.selectionClick();
    setState(() {
      _dx = dx;
      _armed = armed;
      _y = details.localPosition.dy;
    });
  }

  void _onEnd(DragEndDetails details) {
    // A quick flick counts too, as long as it travelled a little.
    final flung = (details.primaryVelocity ?? 0) > 700 && _dx > 24;
    final goBack = _armed || flung;
    setState(() => _dragging = false);
    _settle.value = 1;
    _settle.reverse();
    if (goBack) Navigator.of(context).maybePop();
  }

  void _onCancel() {
    setState(() => _dragging = false);
    _settle.value = 1;
    _settle.reverse();
  }

  @override
  Widget build(BuildContext context) {
    if (Theme.of(context).platform != TargetPlatform.iOS) return widget.child;

    final progress = (_shown / _trigger).clamp(0.0, 1.0);
    final armed = _armed && _dragging;

    return Stack(
      children: <Widget>[
        widget.child,
        // Always in the tree, so the edge detector below keeps its place —
        // inserting this mid-drag rebuilt the detector and lost the gesture.
        Positioned(
          key: const ValueKey<String>('edge-bubble'),
          // Slides out from behind the edge as the drag grows.
          left: -_bubble + progress * (_bubble + 12),
          top: _y - _bubble / 2,
          child: IgnorePointer(
            child: Opacity(
              opacity: progress,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: _bubble,
                height: _bubble,
                decoration: BoxDecoration(
                  color: armed ? Wa.accent : Wa.input,
                  shape: BoxShape.circle,
                  boxShadow: const <BoxShadow>[
                    BoxShadow(color: Color(0x66000000), blurRadius: 8),
                  ],
                ),
                child: Icon(
                  Icons.arrow_back_ios_new,
                  size: 18,
                  color: armed ? Wa.onAccent : Wa.title,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          key: const ValueKey<String>('edge-detector'),
          left: 0,
          top: 0,
          bottom: 0,
          width: _edgeWidth,
          child: GestureDetector(
            // Taps near the edge still reach what is underneath.
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: _onStart,
            onHorizontalDragUpdate: _onUpdate,
            onHorizontalDragEnd: _onEnd,
            onHorizontalDragCancel: _onCancel,
          ),
        ),
      ],
    );
  }
}
