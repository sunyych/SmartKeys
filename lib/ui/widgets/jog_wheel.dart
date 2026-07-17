import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/config.dart';

class JogWheel extends StatefulWidget {
  const JogWheel({
    super.key,
    required this.config,
    required this.inputEpoch,
    required this.onStep,
    required this.onCenterPress,
    required this.onCenterRelease,
  });

  final WheelConfig config;
  final int inputEpoch;
  final ValueChanged<bool> onStep;
  final VoidCallback onCenterPress;
  final VoidCallback onCenterRelease;

  @override
  State<JogWheel> createState() => _JogWheelState();
}

class _JogWheelState extends State<JogWheel>
    with SingleTickerProviderStateMixin {
  static const stepAngle = math.pi / 12;
  static const _centerSizeFactor = 0.34;
  static const _returnDuration = Duration(milliseconds: 260);

  double? _lastAngle;
  double _accumulated = 0;
  Offset _centerOffset = Offset.zero;
  Offset _pointerDownPosition = Offset.zero;
  Offset _pointerDownOffset = Offset.zero;
  Offset _dragStartPosition = Offset.zero;
  Offset _dragStartOffset = Offset.zero;
  Offset _returnStartOffset = Offset.zero;
  bool _pointerDownOnCenter = false;
  bool _draggingCenter = false;
  bool _centerPressed = false;
  late final AnimationController _returnController;

  @override
  void initState() {
    super.initState();
    _returnController = AnimationController(
      vsync: this,
      duration: _returnDuration,
    )..addListener(_animateReturn);
  }

  @override
  void dispose() {
    _returnController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant JogWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.inputEpoch != widget.inputEpoch ||
        oldWidget.config != widget.config) {
      _resetGesture();
    }
  }

  void _resetRotaryGesture() {
    _lastAngle = null;
    _accumulated = 0;
  }

  void _resetGesture() {
    _returnController.stop();
    _resetRotaryGesture();
    _centerOffset = Offset.zero;
    _pointerDownOnCenter = false;
    _draggingCenter = false;
    _centerPressed = false;
  }

  void _animateReturn() {
    final progress = Curves.easeOutBack.transform(_returnController.value);
    setState(() {
      _centerOffset = Offset.lerp(_returnStartOffset, Offset.zero, progress)!;
    });
  }

  double _angle(Offset point, Size size) =>
      math.atan2(point.dy - size.height / 2, point.dx - size.width / 2);

  void _recordPointerDown(DragDownDetails details, Size size) {
    final wheelCenter = Offset(size.width / 2, size.height / 2);
    final centerRadius =
        math.min(size.width, size.height) * _centerSizeFactor / 2;
    _pointerDownOnCenter =
        (details.localPosition - wheelCenter - _centerOffset).distance <=
        centerRadius;
    if (_pointerDownOnCenter) {
      _returnController.stop();
      _pointerDownPosition = details.localPosition;
      _pointerDownOffset = _centerOffset;
    }
  }

  void _start(DragStartDetails details, Size size) {
    _lastAngle = _angle(details.localPosition, size);
    _accumulated = 0;

    if (_pointerDownOnCenter) {
      setState(() {
        _draggingCenter = true;
        _dragStartPosition = _pointerDownPosition;
        _dragStartOffset = _pointerDownOffset;
      });
    }
  }

  void _update(DragUpdateDetails details, Size size) {
    if (_draggingCenter) {
      final requestedOffset =
          _dragStartOffset + details.localPosition - _dragStartPosition;
      setState(() {
        _centerOffset = _clampCenterOffset(requestedOffset, size);
      });
    }

    final current = _angle(details.localPosition, size);
    final last = _lastAngle;
    _lastAngle = current;
    if (last == null) return;
    var delta = current - last;
    if (delta > math.pi) delta -= math.pi * 2;
    if (delta < -math.pi) delta += math.pi * 2;
    _accumulated += delta;
    while (_accumulated.abs() >= stepAngle) {
      final clockwise = _accumulated > 0;
      widget.onStep(clockwise);
      _accumulated += clockwise ? -stepAngle : stepAngle;
    }
  }

  Offset _clampCenterOffset(Offset offset, Size size) {
    // The blue control behaves like a spring-loaded puck. Its center may reach
    // the wheel rim before it springs back, which keeps motion 1:1 on compact
    // landscape layouts instead of clipping the user's drag early.
    final maxDistance = math.min(size.width, size.height) / 2;
    final distance = offset.distance;
    if (distance == 0 || distance <= maxDistance) return offset;
    return offset / distance * maxDistance;
  }

  void _finishGesture() {
    _resetRotaryGesture();
    final shouldReturnCenter = _pointerDownOnCenter || _draggingCenter;
    _pointerDownOnCenter = false;
    if (!shouldReturnCenter) return;
    if (_draggingCenter) setState(() => _draggingCenter = false);
    if (_centerOffset == Offset.zero) return;
    _returnStartOffset = _centerOffset;
    _returnController.forward(from: 0);
  }

  void _pressCenter() {
    if (!_centerPressed) setState(() => _centerPressed = true);
    widget.onCenterPress();
  }

  void _releaseCenter() {
    if (_centerPressed) {
      setState(() => _centerPressed = false);
      widget.onCenterRelease();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          widget.config.modeLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 6),
        Flexible(
          child: AspectRatio(
            aspectRatio: 1,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                return GestureDetector(
                  key: const ValueKey('jog-wheel-gesture'),
                  behavior: HitTestBehavior.opaque,
                  onPanDown: (details) => _recordPointerDown(details, size),
                  onPanStart: (details) => _start(details, size),
                  onPanUpdate: (details) => _update(details, size),
                  onPanEnd: (_) => _finishGesture(),
                  onPanCancel: _finishGesture,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        colors: [Color(0xFF273445), Color(0xFF111923)],
                        stops: [0.55, 1],
                      ),
                      border: Border.all(
                        color: const Color(0xFF35465D),
                        width: 2,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black45,
                          blurRadius: 16,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        ...List.generate(12, (index) {
                          final angle = index * math.pi * 2 / 12;
                          return Transform.rotate(
                            angle: angle,
                            child: const Align(
                              alignment: Alignment.topCenter,
                              child: Padding(
                                padding: EdgeInsets.only(top: 9),
                                child: SizedBox(
                                  width: 2,
                                  height: 8,
                                  child: ColoredBox(color: Colors.white24),
                                ),
                              ),
                            ),
                          );
                        }),
                        Transform.translate(
                          offset: _centerOffset,
                          child: FractionallySizedBox(
                            widthFactor: _centerSizeFactor,
                            heightFactor: _centerSizeFactor,
                            child: AnimatedScale(
                              scale: _draggingCenter || _centerPressed
                                  ? 0.94
                                  : 1,
                              duration: const Duration(milliseconds: 90),
                              child: GestureDetector(
                                key: const ValueKey('jog-wheel-center'),
                                behavior: HitTestBehavior.opaque,
                                onTapDown: (_) => _pressCenter(),
                                onTapUp: (_) => _releaseCenter(),
                                onTapCancel: _releaseCenter,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    border: Border.all(color: Colors.white24),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black38,
                                        blurRadius: 8,
                                        offset: Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.circle,
                                    size: 12,
                                    color: Colors.black54,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
