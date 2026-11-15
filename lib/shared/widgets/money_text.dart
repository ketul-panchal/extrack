import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spent/core/money/money_format.dart';
import 'package:spent/core/settings/settings.dart';
import 'package:spent/core/theme/app_theme.dart';
import 'package:spent/core/theme/tokens.dart';

String maskedAmount(MoneyFormat f) =>
    f.style.symbolFirst ? '${f.currency.symbol}••••' : '•••• ${f.currency.symbol}';

/// An amount in the user's currency. Respects privacy mode.
class MoneyText extends ConsumerWidget {
  const MoneyText(
    this.minor, {
    super.key,
    this.style,
    this.color,
    this.sign = false,
    this.compact = false,
    this.tabular = true,
    this.textAlign,
    this.reveal = false,
  });

  final int minor;
  final TextStyle? style;
  final Color? color;

  /// Prefix positive amounts with "+".
  final bool sign;
  final bool compact;
  final bool tabular;
  final TextAlign? textAlign;

  /// Ignore privacy mode (e.g. inside the editor).
  final bool reveal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final money = ref.watch(moneyFormatProvider);
    final hidden = !reveal && ref.watch(hideAmountsProvider);
    final text = hidden
        ? maskedAmount(money)
        : compact
        ? money.compact(minor, sign: sign)
        : money.format(minor, sign: sign);
    var s = (style ?? context.text.titleSmall!).copyWith(color: color);
    if (tabular) s = s.tabular;
    return Text(
      text,
      style: s,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.fade,
      textAlign: textAlign,
    );
  }
}

/// A large amount that counts to its new value whenever it changes.
class AnimatedMoney extends ConsumerWidget {
  const AnimatedMoney(
    this.minor, {
    super.key,
    this.style,
    this.color,
    this.sign = false,
    this.countUp = true,
    this.duration = Motion.slower,
  });

  final int minor;
  final TextStyle? style;
  final Color? color;
  final bool sign;

  /// Count from zero the first time it appears.
  final bool countUp;
  final Duration duration;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final money = ref.watch(moneyFormatProvider);
    final hidden = ref.watch(hideAmountsProvider);
    final s = (style ?? context.text.displayMedium!).copyWith(color: color);
    if (hidden) {
      return Text(maskedAmount(money), style: s, maxLines: 1);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: countUp ? 0 : minor.toDouble(), end: minor.toDouble()),
      duration: Motion.of(context, duration),
      curve: Motion.emphasized,
      builder: (context, value, _) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: Text(money.format(value.round(), sign: sign), style: s, maxLines: 1),
      ),
    );
  }
}
