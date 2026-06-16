import 'package:flutter/material.dart';

/// Overlays a pulsing "now playing" glow on its [child] while [active] is true.
/// The animation controller only runs while active, so the dozens of idle key
/// tiles don't each drive an animation every frame.
class PlayPulse extends StatefulWidget {
  final bool active;
  final BorderRadius radius;
  final Widget child;
  const PlayPulse({
    super.key,
    required this.active,
    required this.radius,
    required this.child,
  });

  @override
  State<PlayPulse> createState() => _PlayPulseState();
}

class _PlayPulseState extends State<PlayPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600));

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(PlayPulse old) {
    super.didUpdateWidget(old);
    // Start/stop the loop only on a real active-state change, and reset the
    // outline to fully faded when it stops.
    if (widget.active && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.active && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (widget.active)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _c,
                builder: (_, _) {
                  final t = Curves.easeInOut.transform(_c.value);
                  // Subtle: a thin orange outline that gently fades in/out.
                  return Container(
                    decoration: BoxDecoration(
                      borderRadius: widget.radius,
                      border: Border.all(
                        color: Colors.orangeAccent
                            .withValues(alpha: 0.35 + 0.45 * t),
                        width: 1.5,
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
