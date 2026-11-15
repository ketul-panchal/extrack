import 'package:spent/core/money/currency.dart';

/// Formats integer minor units (cents, paise…) for display.
///
/// Whole amounts drop their decimals ("₹1,250"); fractional amounts show all
/// of them ("₹1,250.50"). The minus sign is a true minus (U+2212).
class MoneyFormat {
  const MoneyFormat(this.currency, this.style);

  final Currency currency;
  final NumberStyle style;

  static const minus = '−';

  int get decimals => currency.decimals;
  int get unit => _pow10(decimals);

  /// "₹1,250.50". [sign] adds "+" to positive values.
  String format(int minor, {bool sign = false, bool symbol = true, bool forceDecimals = false}) {
    final negative = minor < 0;
    final abs = minor.abs();
    final whole = abs ~/ unit;
    final fraction = abs % unit;
    var number = _group(whole.toString());
    if (decimals > 0 && (fraction != 0 || forceDecimals)) {
      number += style.decimalSeparator + fraction.toString().padLeft(decimals, '0');
    }
    final body = symbol ? _withSymbol(number) : number;
    if (negative) return '$minus$body';
    if (sign && minor > 0) return '+$body';
    return body;
  }

  /// Short form for tight spaces and chart axes: "₹1.2L", "$12.5K", "€3M".
  String compact(int minor, {bool symbol = true, bool sign = false}) {
    final negative = minor < 0;
    final value = minor.abs() / unit;
    String number;
    if (value < 1000) {
      number = _trim(
        value >= 100 ? value.round().toString() : _fixed(value, value % 1 == 0 ? 0 : 1),
      );
      number = number.replaceAll('.', style.decimalSeparator);
    } else {
      final (divisor, suffix) = _compactUnit(value);
      final scaled = value / divisor;
      final digits = scaled >= 100 ? 0 : 1;
      number = _trim(_fixed(scaled, digits)).replaceAll('.', style.decimalSeparator) + suffix;
    }
    final body = symbol ? _withSymbol(number) : number;
    if (negative) return '$minus$body';
    if (sign && minor > 0) return '+$body';
    return body;
  }

  /// Plain editable text for a value, using '.' as the decimal point: "1250.5".
  String toInput(int minor) {
    final abs = minor.abs();
    final whole = abs ~/ unit;
    final fraction = abs % unit;
    if (fraction == 0 || decimals == 0) return whole.toString();
    var f = fraction.toString().padLeft(decimals, '0');
    while (f.endsWith('0')) {
      f = f.substring(0, f.length - 1);
    }
    return '$whole.$f';
  }

  /// Parses user text such as "1,250.50" or "1250,5" into minor units.
  int? parse(String input) {
    final text = input.trim().replaceAll(RegExp(r'[^\d.,]'), '');
    if (text.isEmpty) return null;
    // The last separator followed by 1..decimals digits is the decimal point.
    final match = RegExp(r'[.,](\d+)$').firstMatch(text);
    String whole = text;
    String fraction = '';
    if (match != null && decimals > 0 && match.group(1)!.length <= decimals) {
      whole = text.substring(0, match.start);
      fraction = match.group(1)!;
    }
    whole = whole.replaceAll(RegExp(r'[.,]'), '');
    if (whole.isEmpty) whole = '0';
    final w = int.tryParse(whole);
    if (w == null) return null;
    final f = fraction.isEmpty ? 0 : int.parse(fraction.padRight(decimals, '0'));
    return w * unit + f;
  }

  /// Groups a run of digits according to [style].
  String groupDigits(String digits) => _group(digits);

  String _withSymbol(String number) {
    final s = currency.symbol;
    final wordy = RegExp('[A-Za-z]').hasMatch(s);
    if (style.symbolFirst) return wordy ? '$s $number' : '$s$number';
    return '$number $s';
  }

  String _group(String digits) {
    final sep = style.groupSeparator;
    if (digits.length <= 3) return digits;
    if (style == NumberStyle.indian) {
      final last3 = digits.substring(digits.length - 3);
      var rest = digits.substring(0, digits.length - 3);
      final parts = <String>[];
      while (rest.length > 2) {
        parts.insert(0, rest.substring(rest.length - 2));
        rest = rest.substring(0, rest.length - 2);
      }
      if (rest.isNotEmpty) parts.insert(0, rest);
      return '${parts.join(sep)}$sep$last3';
    }
    final buffer = StringBuffer();
    final lead = digits.length % 3;
    if (lead > 0) buffer.write(digits.substring(0, lead));
    for (var i = lead; i < digits.length; i += 3) {
      if (buffer.isNotEmpty) buffer.write(sep);
      buffer.write(digits.substring(i, i + 3));
    }
    return buffer.toString();
  }

  (double, String) _compactUnit(double value) {
    if (style == NumberStyle.indian) {
      if (value >= 1e7) return (1e7, 'Cr');
      if (value >= 1e5) return (1e5, 'L');
      return (1e3, 'K');
    }
    if (value >= 1e12) return (1e12, 'T');
    if (value >= 1e9) return (1e9, 'B');
    if (value >= 1e6) return (1e6, 'M');
    return (1e3, 'K');
  }

  static String _fixed(double v, int digits) => v.toStringAsFixed(digits);

  static String _trim(String s) => s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;

  static int _pow10(int n) {
    var r = 1;
    for (var i = 0; i < n; i++) {
      r *= 10;
    }
    return r;
  }
}
