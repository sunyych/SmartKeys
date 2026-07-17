import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/config.dart';

class MouseDirectionPad extends StatefulWidget {
  const MouseDirectionPad({
    super.key,
    required this.config,
    required this.inputEpoch,
    required this.onPress,
    required this.onRelease,
  });

  final WheelConfig config;
  final int inputEpoch;
  final ValueChanged<HidAction> onPress;
  final VoidCallback onRelease;

  @override
  State<MouseDirectionPad> createState() => _MouseDirectionPadState();
}

class _MouseDirectionPadState extends State<MouseDirectionPad> {
  String? _activeDirection;

  @override
  void didUpdateWidget(covariant MouseDirectionPad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.inputEpoch != widget.inputEpoch) {
      _activeDirection = null;
    }
  }

  void _press(String direction, HidAction action) {
    if (action.type == ActionType.none) return;
    if (_activeDirection != null && _activeDirection != direction) {
      widget.onRelease();
    }
    setState(() => _activeDirection = direction);
    widget.onPress(action);
  }

  void _release(String direction) {
    if (_activeDirection != direction) return;
    setState(() => _activeDirection = null);
    widget.onRelease();
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
                final extent = math.min(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                final buttonExtent = extent * 0.31;
                final inset = extent * 0.045;
                final centerOffset = (extent - buttonExtent) / 2;
                return Center(
                  child: SizedBox.square(
                    dimension: extent,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const RadialGradient(
                          colors: [Color(0xFF273445), Color(0xFF111923)],
                          stops: [0.42, 1],
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
                        children: [
                          Positioned(
                            top: inset,
                            left: centerOffset,
                            child: _DirectionButton(
                              key: const ValueKey('mouse-move-up'),
                              label: 'Move mouse up',
                              icon: Icons.keyboard_arrow_up_rounded,
                              active: _activeDirection == 'UP',
                              onPress: () => _press('UP', widget.config.up),
                              onRelease: () => _release('UP'),
                              extent: buttonExtent,
                            ),
                          ),
                          Positioned(
                            bottom: inset,
                            left: centerOffset,
                            child: _DirectionButton(
                              key: const ValueKey('mouse-move-down'),
                              label: 'Move mouse down',
                              icon: Icons.keyboard_arrow_down_rounded,
                              active: _activeDirection == 'DOWN',
                              onPress: () => _press('DOWN', widget.config.down),
                              onRelease: () => _release('DOWN'),
                              extent: buttonExtent,
                            ),
                          ),
                          Positioned(
                            left: inset,
                            top: centerOffset,
                            child: _DirectionButton(
                              key: const ValueKey('mouse-move-left'),
                              label: 'Move mouse left',
                              icon: Icons.keyboard_arrow_left_rounded,
                              active: _activeDirection == 'LEFT',
                              onPress: () => _press('LEFT', widget.config.left),
                              onRelease: () => _release('LEFT'),
                              extent: buttonExtent,
                            ),
                          ),
                          Positioned(
                            right: inset,
                            top: centerOffset,
                            child: _DirectionButton(
                              key: const ValueKey('mouse-move-right'),
                              label: 'Move mouse right',
                              icon: Icons.keyboard_arrow_right_rounded,
                              active: _activeDirection == 'RIGHT',
                              onPress: () =>
                                  _press('RIGHT', widget.config.right),
                              onRelease: () => _release('RIGHT'),
                              extent: buttonExtent,
                            ),
                          ),
                          Center(
                            child: Container(
                              width: extent * 0.24,
                              height: extent * 0.24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF101720),
                                border: Border.all(
                                  color: const Color(0xFF4D657F),
                                ),
                              ),
                              child: const Icon(
                                Icons.mouse_outlined,
                                color: Color(0xFF7BD4E4),
                              ),
                            ),
                          ),
                        ],
                      ),
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

class _DirectionButton extends StatelessWidget {
  const _DirectionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.active,
    required this.onPress,
    required this.onRelease,
    required this.extent,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onPress;
  final VoidCallback onRelease;
  final double extent;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => onPress(),
        onTapUp: (_) => onRelease(),
        onTapCancel: onRelease,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          width: extent,
          height: extent,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? const Color(0xFF66C7DA) : const Color(0xFF1B2A3A),
            border: Border.all(
              color: active ? const Color(0xFFA7F0FF) : const Color(0xFF425873),
              width: active ? 2 : 1,
            ),
            boxShadow: active
                ? const [BoxShadow(color: Color(0x664DE7FF), blurRadius: 14)]
                : null,
          ),
          child: Icon(
            icon,
            size: extent * 0.58,
            color: active ? const Color(0xFF071016) : Colors.white,
          ),
        ),
      ),
    );
  }
}
