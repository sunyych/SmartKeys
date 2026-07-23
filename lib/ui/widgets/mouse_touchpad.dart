import 'package:flutter/material.dart';

import '../../models/config.dart';

class MouseTouchpad extends StatefulWidget {
  const MouseTouchpad({
    super.key,
    required this.config,
    required this.inputEpoch,
    required this.onMove,
    required this.onScroll,
    required this.onPrimaryTap,
    required this.onSecondaryTap,
  });

  final WheelConfig config;
  final int inputEpoch;
  final ValueChanged<Offset> onMove;
  final ValueChanged<double> onScroll;
  final VoidCallback onPrimaryTap;
  final VoidCallback onSecondaryTap;

  @override
  State<MouseTouchpad> createState() => _MouseTouchpadState();
}

class _MouseTouchpadState extends State<MouseTouchpad> {
  static const _tapSlop = 10.0;
  static const _maxTapDuration = Duration(milliseconds: 350);

  final Map<int, Offset> _pointers = {};
  final Map<int, Offset> _startPositions = {};
  DateTime? _gestureStartedAt;
  Offset? _lastMovePosition;
  Offset? _lastTwoFingerCentroid;
  int _maxPointerCount = 0;
  bool _moving = false;
  bool _movedBeyondTapSlop = false;

  @override
  void didUpdateWidget(covariant MouseTouchpad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.inputEpoch != widget.inputEpoch) {
      _resetGesture(notify: false);
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_pointers.isEmpty) {
      _gestureStartedAt = DateTime.now();
      _maxPointerCount = 0;
      _moving = false;
      _movedBeyondTapSlop = false;
      _lastMovePosition = null;
      _lastTwoFingerCentroid = null;
      _startPositions.clear();
    }
    _pointers[event.pointer] = event.localPosition;
    _startPositions[event.pointer] = event.localPosition;
    _maxPointerCount = _maxPointerCount < _pointers.length
        ? _pointers.length
        : _maxPointerCount;
    if (_maxPointerCount > 1) {
      if (_moving) _movedBeyondTapSlop = true;
      _moving = false;
      _lastMovePosition = null;
      _lastTwoFingerCentroid = _centroid;
    }
    setState(() {});
  }

  void _handlePointerMove(PointerMoveEvent event) {
    final start = _startPositions[event.pointer];
    if (start == null || !_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.localPosition;

    if (_maxPointerCount > 1 || _pointers.length > 1) {
      if (_pointers.length != 2) return;
      final centroid = _centroid;
      if (!_movedBeyondTapSlop) {
        if ((event.localPosition - start).distance > _tapSlop) {
          _movedBeyondTapSlop = true;
          _lastTwoFingerCentroid = centroid;
          setState(() {});
        }
        return;
      }
      final previous = _lastTwoFingerCentroid;
      _lastTwoFingerCentroid = centroid;
      if (previous != null) widget.onScroll((centroid - previous).dy);
      return;
    }

    if (!_moving) {
      if ((event.localPosition - start).distance <= _tapSlop) return;
      _moving = true;
      _movedBeyondTapSlop = true;
      _lastMovePosition = event.localPosition;
      setState(() {});
      return;
    }

    final previous = _lastMovePosition;
    _lastMovePosition = event.localPosition;
    if (previous == null) return;
    final delta = event.localPosition - previous;
    if (delta != Offset.zero) widget.onMove(delta);
  }

  void _handlePointerUp(PointerUpEvent event) {
    final start = _startPositions[event.pointer];
    if (start != null && (event.localPosition - start).distance > _tapSlop) {
      _movedBeyondTapSlop = true;
    }
    _pointers.remove(event.pointer);
    _startPositions.remove(event.pointer);
    if (_pointers.isNotEmpty) {
      _lastTwoFingerCentroid = null;
      setState(() {});
      return;
    }

    final startedAt = _gestureStartedAt;
    final isTap =
        startedAt != null &&
        !_movedBeyondTapSlop &&
        _maxPointerCount <= 2 &&
        DateTime.now().difference(startedAt) <= _maxTapDuration;
    final secondary = _maxPointerCount == 2;
    _resetGesture();
    if (isTap) {
      if (secondary) {
        widget.onSecondaryTap();
      } else {
        widget.onPrimaryTap();
      }
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _pointers.remove(event.pointer);
    _startPositions.remove(event.pointer);
    _movedBeyondTapSlop = true;
    if (_pointers.isEmpty) {
      _resetGesture();
    } else {
      setState(() {});
    }
  }

  void _resetGesture({bool notify = true}) {
    _pointers.clear();
    _startPositions.clear();
    _gestureStartedAt = null;
    _lastMovePosition = null;
    _lastTwoFingerCentroid = null;
    _maxPointerCount = 0;
    _moving = false;
    _movedBeyondTapSlop = false;
    if (notify && mounted) setState(() {});
  }

  Offset get _centroid {
    if (_pointers.isEmpty) return Offset.zero;
    final total = _pointers.values.fold<Offset>(
      Offset.zero,
      (sum, position) => sum + position,
    );
    return total / _pointers.length.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final configuredLabel = widget.config.modeLabel.trim();
    final label = configuredLabel.isEmpty || configuredLabel == 'Mouse'
        ? 'Touchpad'
        : configuredLabel;
    final active = _pointers.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Expanded(
          child: Semantics(
            label: 'Mouse touchpad',
            hint:
                'Move with one finger, tap for left click, scroll with two fingers, or two-finger tap for right click',
            child: Listener(
              key: const ValueKey('mouse-touchpad'),
              behavior: HitTestBehavior.opaque,
              onPointerDown: _handlePointerDown,
              onPointerMove: _handlePointerMove,
              onPointerUp: _handlePointerUp,
              onPointerCancel: _handlePointerCancel,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF25354A), Color(0xFF101923)],
                  ),
                  border: Border.all(
                    color: active
                        ? const Color(0xFF6ED7E8)
                        : const Color(0xFF3D526D),
                    width: active ? 2 : 1.5,
                  ),
                  boxShadow: active
                      ? const [
                          BoxShadow(color: Color(0x554DE7FF), blurRadius: 18),
                        ]
                      : const [
                          BoxShadow(
                            color: Colors.black38,
                            blurRadius: 14,
                            offset: Offset(0, 7),
                          ),
                        ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      _moving ? Icons.near_me : Icons.touch_app_outlined,
                      size: 52,
                      color: active ? const Color(0xFF8CEBFA) : Colors.white24,
                    ),
                    if (_pointers.isNotEmpty)
                      Positioned(
                        top: 16,
                        left: 16,
                        child: _PointerCount(count: _pointers.length),
                      ),
                    const Positioned(
                      left: 16,
                      right: 16,
                      bottom: 13,
                      child: Text(
                        '1 finger: move / tap  •  2 fingers: scroll / right click',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PointerCount extends StatelessWidget {
  const _PointerCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF071016).withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        '$count finger${count == 1 ? '' : 's'}',
        style: const TextStyle(color: Color(0xFF8CEBFA), fontSize: 11),
      ),
    );
  }
}
