import 'package:material_ui/material_ui.dart';

/// Spacing on a 4-pt grid.
abstract final class Insets {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  /// Horizontal page gutter.
  static const double page = 20;
}

abstract final class Radii {
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 22;
  static const double xl = 28;
  static const double pill = 999;

  static const BorderRadius card = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius tile = BorderRadius.all(Radius.circular(md));
  static const BorderRadius chip = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius sheet = BorderRadius.vertical(top: Radius.circular(xl));
}

/// Motion tokens. Everything animates on these so the app moves as one.
abstract final class Motion {
  static const Duration instant = Duration(milliseconds: 90);
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration medium = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 420);
  static const Duration slower = Duration(milliseconds: 650);
  static const Duration chart = Duration(milliseconds: 900);

  /// Material 3 "emphasized decelerate": quick start, long soft landing.
  static const Curve emphasized = Cubic(0.05, 0.7, 0.1, 1.0);
  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
  static const Curve standard = Curves.easeInOutCubic;
  static const Curve overshoot = Curves.easeOutBack;

  /// True when the OS asks for reduced motion.
  static bool reduced(BuildContext context) => MediaQuery.of(context).disableAnimations;

  /// [d], or zero when reduced motion is on.
  static Duration of(BuildContext context, Duration d) => reduced(context) ? Duration.zero : d;
}

class Gap extends StatelessWidget {
  const Gap(this.size, {super.key});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size);
}
