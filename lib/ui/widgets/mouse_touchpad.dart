import 'package:flutter/material.dart';

import '../../mobile_appearance.dart';
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
  int? _scrollStripPointer;
  double? _lastScrollStripY;

  @override
  void dispose() {
    // Raw pointer routes can deliver their final events after the host-switch
    // pending surface has removed this widget. Those gestures are no longer input.
    _resetGesture(notify: false);
    _resetScrollStrip(notify: false);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MouseTouchpad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.inputEpoch != widget.inputEpoch) {
      _resetGesture(notify: false);
      _resetScrollStrip(notify: false);
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
      final delta = event.localPosition - start;
      if (delta != Offset.zero) widget.onMove(delta);
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
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers.remove(event.pointer);
    _startPositions.remove(event.pointer);
    _movedBeyondTapSlop = true;
    if (_pointers.isEmpty) {
      _resetGesture();
    } else {
      setState(() {});
    }
  }

  void _handleScrollStripDown(PointerDownEvent event) {
    if (_scrollStripPointer != null) return;
    _scrollStripPointer = event.pointer;
    _lastScrollStripY = event.localPosition.dy;
    setState(() {});
  }

  void _handleScrollStripMove(PointerMoveEvent event) {
    if (_scrollStripPointer != event.pointer) return;
    final previousY = _lastScrollStripY;
    _lastScrollStripY = event.localPosition.dy;
    if (previousY == null) return;
    final deltaY = event.localPosition.dy - previousY;
    if (deltaY != 0) widget.onScroll(deltaY);
  }

  void _handleScrollStripUp(PointerUpEvent event) {
    if (_scrollStripPointer == event.pointer) _resetScrollStrip();
  }

  void _handleScrollStripCancel(PointerCancelEvent event) {
    if (_scrollStripPointer == event.pointer) _resetScrollStrip();
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

  void _resetScrollStrip({bool notify = true}) {
    _scrollStripPointer = null;
    _lastScrollStripY = null;
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
    final active = _pointers.isNotEmpty;
    final scrollStripActive = _scrollStripPointer != null;
    final colors = Theme.of(context).colorScheme;
    final dark = colors.brightness == Brightness.dark;
    final highlight = dark ? const Color(0xFF8CEBFA) : colors.primary;
    final stripIconColor = dark ? Colors.white54 : colors.onSurfaceVariant;
    return Stack(
      fit: StackFit.expand,
      children: [
        Semantics(
          label: context.mobileText('Mouse touchpad', '鼠标触控板'),
          hint: context.mobileText(
            'Move with one finger, tap for left click, scroll with two fingers, two-finger tap for right click, or use the right edge to scroll directly',
            '单指移动指针，轻点左键，双指滚动，双指轻点右键，也可在右边缘直接滚动。',
          ),
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
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: dark
                      ? const [Color(0xFF25354A), Color(0xFF101923)]
                      : [
                          colors.surfaceContainerLow,
                          colors.surfaceContainerHighest,
                        ],
                ),
                border: Border.all(
                  color: active
                      ? (dark ? const Color(0xFF6ED7E8) : colors.primary)
                      : (dark
                            ? const Color(0xFF3D526D)
                            : colors.outlineVariant),
                  width: active ? 2 : 1.5,
                ),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: dark
                              ? const Color(0x554DE7FF)
                              : colors.primary.withValues(alpha: 0.16),
                          blurRadius: 18,
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: dark
                              ? Colors.black38
                              : colors.shadow.withValues(alpha: 0.12),
                          blurRadius: 14,
                          offset: const Offset(0, 7),
                        ),
                      ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    _moving ? Icons.near_me : Icons.touch_app_outlined,
                    size: 52,
                    color: active
                        ? highlight
                        : (dark ? Colors.white24 : colors.outline),
                  ),
                  if (_pointers.isNotEmpty)
                    Positioned(
                      top: 16,
                      left: 16,
                      child: _PointerCount(count: _pointers.length),
                    ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: 8,
          right: 6,
          bottom: 8,
          width: 38,
          child: Semantics(
            label: context.mobileText('Direct scroll strip', '滚动条'),
            hint: context.mobileText(
              'Slide one finger up or down to scroll',
              '单指上下滑动即可滚动',
            ),
            child: Listener(
              key: const ValueKey('mouse-scroll-strip'),
              behavior: HitTestBehavior.opaque,
              onPointerDown: _handleScrollStripDown,
              onPointerMove: _handleScrollStripMove,
              onPointerUp: _handleScrollStripUp,
              onPointerCancel: _handleScrollStripCancel,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                decoration: BoxDecoration(
                  color: scrollStripActive
                      ? (dark
                            ? const Color(0x663BC9DF)
                            : colors.primaryContainer)
                      : (dark
                            ? const Color(0x33182735)
                            : colors.surfaceContainerHigh),
                  borderRadius: BorderRadius.circular(19),
                  border: Border.all(
                    color: scrollStripActive
                        ? highlight
                        : (dark
                              ? const Color(0x66768CA4)
                              : colors.outlineVariant),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Icon(
                        Icons.keyboard_arrow_up,
                        size: 16,
                        color: stripIconColor,
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      width: 5,
                      height: scrollStripActive ? 32 : 24,
                      decoration: BoxDecoration(
                        color: scrollStripActive
                            ? highlight
                            : (dark ? Colors.white38 : colors.outline),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        size: 16,
                        color: stripIconColor,
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
    final colors = Theme.of(context).colorScheme;
    final dark = colors.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: dark
            ? const Color(0xFF071016).withValues(alpha: 0.72)
            : colors.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        context.mobileText('$count finger${count == 1 ? '' : 's'}', '$count 指'),
        style: TextStyle(
          color: dark ? const Color(0xFF8CEBFA) : colors.onPrimaryContainer,
          fontSize: 11,
        ),
      ),
    );
  }
}
