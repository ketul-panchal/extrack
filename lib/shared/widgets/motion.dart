import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:spent/core/theme/tokens.dart';

/// Fades and lifts its child into place once, staggered by [index].
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.index = 0,
    this.offset = 16,
    this.duration = Motion.slow,
    this.stagger = const Duration(milliseconds: 45),
  });

  final Widget child;
  final int index;
  final double offset;
  final Duration duration;
  final Duration stagger;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: Motion.emphasized);
  bool _started = false;
  Timer? _delay;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (Motion.reduced(context)) {
      _c.value = 1;
      return;
    }
    final delay = widget.stagger * math.min(widget.index, 10);
    if (delay == Duration.zero) {
      _c.forward();
    } else {
      _delay = Timer(delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _t,
    builder: (context, child) => Opacity(
      opacity: _t.value.clamp(0, 1),
      child: Transform.translate(offset: Offset(0, (1 - _t.value) * widget.offset), child: child),
    ),
    child: widget.child,
  );
}

/// Shakes horizontally each time [trigger] changes (wrong PIN, invalid input).
class Shake extends StatefulWidget {
  const Shake({super.key, required this.trigger, required this.child});

  final int trigger;
  final Widget child;

  @override
  State<Shake> createState() => _ShakeState();
}

class _ShakeState extends State<Shake> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
  );

  @override
  void didUpdateWidget(Shake old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, child) {
      final t = _c.value;
      final dx = math.sin(t * math.pi * 6) * 10 * (1 - t);
      return Transform.translate(offset: Offset(dx, 0), child: child);
    },
    child: widget.child,
  );
}

/// Gently bobs its child up and down; for empty-state illustrations.
class Float extends StatefulWidget {
  const Float({super.key, required this.child, this.amplitude = 4});

  final Widget child;
  final double amplitude;

  @override
  State<Float> createState() => _FloatState();
}

class _FloatState extends State<Float> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!Motion.reduced(context) && !_c.isAnimating) _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, child) => Transform.translate(
      offset: Offset(
        0,
        Curves.easeInOut.transform(_c.value) * widget.amplitude * 2 - widget.amplitude,
      ),
      child: child,
    ),
    child: widget.child,
  );
}
