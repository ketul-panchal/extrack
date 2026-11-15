import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spent/core/money/amount_input.dart';
import 'package:spent/core/services/haptics.dart';
import 'package:spent/core/theme/app_theme.dart';
import 'package:spent/core/theme/tokens.dart';
import 'package:spent/shared/widgets/pressable.dart';

sealed class KeypadKey {
  const KeypadKey();
}

class DigitKey extends KeypadKey {
  const DigitKey(this.digit);
  final int digit;
}

class DotKey extends KeypadKey {
  const DotKey();
}

class BackspaceKey extends KeypadKey {
  const BackspaceKey();
}

class ClearKey extends KeypadKey {
  const ClearKey();
}

class OpKey extends KeypadKey {
  const OpKey(this.op);
  final CalcOp op;
}

/// A calculator keypad: digits on quiet keys, operators in a side column.
class AmountKeypad extends StatelessWidget {
  const AmountKeypad({
    super.key,
    required this.onKey,
    required this.decimalSeparator,
    this.allowDecimal = true,
    this.keyHeight = 56,
  });

  final ValueChanged<KeypadKey> onKey;
  final String decimalSeparator;
  final bool allowDecimal;
  final double keyHeight;

  @override
  Widget build(BuildContext context) {
    Widget row(List<Widget> children) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Gap(8),
            Expanded(flex: i == children.length - 1 ? 3 : 4, child: children[i]),
          ],
        ],
      ),
    );
    Widget digit(int d) => _Key(height: keyHeight, label: '$d', onTap: () => onKey(DigitKey(d)));
    Widget op(CalcOp o) => _Key(
      height: keyHeight,
      label: o.symbol,
      operator: true,
      semantic: switch (o) {
        CalcOp.add => 'plus',
        CalcOp.subtract => 'minus',
        CalcOp.multiply => 'times',
        CalcOp.divide => 'divided by',
      },
      onTap: () => onKey(OpKey(o)),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        row([digit(7), digit(8), digit(9), op(CalcOp.divide)]),
        row([digit(4), digit(5), digit(6), op(CalcOp.multiply)]),
        row([digit(1), digit(2), digit(3), op(CalcOp.subtract)]),
        row([
          _Key(
            height: keyHeight,
            label: allowDecimal ? decimalSeparator : '00',
            semantic: allowDecimal ? 'decimal point' : 'double zero',
            onTap: () => onKey(allowDecimal ? const DotKey() : const DigitKey(-1)),
          ),
          digit(0),
          _Key(
            height: keyHeight,
            icon: Icons.backspace_outlined,
            semantic: 'delete',
            onTap: () => onKey(const BackspaceKey()),
            onLongPress: () => onKey(const ClearKey()),
          ),
          op(CalcOp.add),
        ]),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    required this.height,
    required this.onTap,
    this.label,
    this.icon,
    this.operator = false,
    this.onLongPress,
    this.semantic,
  });

  final double height;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String? label;
  final IconData? icon;
  final bool operator;
  final String? semantic;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fg = operator ? p.accentText : p.ink;
    return Pressable(
      haptic: false,
      pressedScale: 0.92,
      semanticLabel: semantic ?? label,
      onTap: () {
        Haptics.selection();
        onTap();
      },
      onLongPress: onLongPress,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: operator ? p.accentSoft : (p.isDark ? p.surface2 : p.surface),
          borderRadius: BorderRadius.circular(18),
          boxShadow: operator || p.isDark
              ? null
              : [
                  BoxShadow(
                    color: p.shadow.withValues(alpha: 0.05),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        alignment: Alignment.center,
        child: icon != null
            ? Icon(icon, size: 24, color: fg)
            : Text(
                label!,
                style: context.text.headlineSmall?.copyWith(
                  color: fg,
                  fontWeight: operator ? FontWeight.w600 : FontWeight.w600,
                  fontSize: operator ? 26 : 24,
                ),
              ),
      ),
    );
  }
}

/// Text whose characters roll in individually as they change.
class RollingText extends StatelessWidget {
  const RollingText(this.text, {super.key, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final chars = text.characters.toList();
    final duration = Motion.of(context, const Duration(milliseconds: 220));
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        for (var i = 0; i < chars.length; i++)
          AnimatedSwitcher(
            duration: duration,
            switchInCurve: Motion.emphasized,
            switchOutCurve: Motion.exit,
            transitionBuilder: (child, anim) => ClipRect(
              child: FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, 0.45), end: Offset.zero).animate(anim),
                  child: child,
                ),
              ),
            ),
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.bottomCenter,
              children: [
                ...previous.map((w) => Opacity(opacity: 0, child: w)),
                ?current,
              ],
            ),
            child: Text(chars[i], key: ValueKey('$i${chars[i]}'), style: style),
          ),
      ],
    );
  }
}

/// Maps hardware keys to keypad keys (tablets, emulators, desktop).
KeypadKey? keypadKeyFor(KeyEvent event) {
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) return null;
  final ch = event.character;
  if (ch != null && ch.length == 1) {
    final code = ch.codeUnitAt(0);
    if (code >= 48 && code <= 57) return DigitKey(code - 48);
    switch (ch) {
      case '.' || ',':
        return const DotKey();
      case '+':
        return const OpKey(CalcOp.add);
      case '-':
        return const OpKey(CalcOp.subtract);
      case '*' || 'x':
        return const OpKey(CalcOp.multiply);
      case '/':
        return const OpKey(CalcOp.divide);
    }
  }
  if (event.logicalKey == LogicalKeyboardKey.backspace) return const BackspaceKey();
  if (event.logicalKey == LogicalKeyboardKey.delete) return const ClearKey();
  return null;
}
