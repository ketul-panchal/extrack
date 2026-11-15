import 'package:spent/core/money/money_format.dart';

enum CalcOp {
  add('+'),
  subtract('−'),
  multiply('×'),
  divide('÷');

  const CalcOp(this.symbol);
  final String symbol;
}

/// Immutable state of the amount keypad: a tiny calculator that supports
/// `+ − × ÷` with normal precedence and evaluates to minor units.
///
/// Tokens alternate number, operator, number… The last token may be an
/// operator while the user is still typing.
class AmountInput {
  const AmountInput._(this._tokens, this.decimals);

  factory AmountInput.empty(int decimals) => AmountInput._(const [], decimals);

  factory AmountInput.fromMinor(int minor, MoneyFormat format) {
    if (minor <= 0) return AmountInput.empty(format.decimals);
    return AmountInput._([format.toInput(minor)], format.decimals);
  }

  /// Numbers are stored as plain strings with '.' as the decimal point;
  /// operators as [CalcOp].
  final List<Object> _tokens;
  final int decimals;

  static const maxWholeDigits = 10;

  bool get isEmpty => _tokens.isEmpty;
  bool get hasOperator => _tokens.any((t) => t is CalcOp);
  bool get endsWithOperator => _tokens.isNotEmpty && _tokens.last is CalcOp;

  AmountInput digit(int d) {
    assert(d >= 0 && d <= 9);
    final tokens = [..._tokens];
    if (tokens.isEmpty || tokens.last is CalcOp) {
      tokens.add('$d');
      return AmountInput._(tokens, decimals);
    }
    final current = tokens.last as String;
    if (current.contains('.')) {
      final fraction = current.split('.')[1];
      if (fraction.length >= decimals) return this;
      tokens[tokens.length - 1] = '$current$d';
    } else {
      if (current == '0') {
        tokens[tokens.length - 1] = '$d';
      } else {
        if (current.length >= maxWholeDigits) return this;
        tokens[tokens.length - 1] = '$current$d';
      }
    }
    return AmountInput._(tokens, decimals);
  }

  AmountInput doubleZero() => digit(0).digit(0);

  AmountInput dot() {
    if (decimals == 0) return this;
    final tokens = [..._tokens];
    if (tokens.isEmpty || tokens.last is CalcOp) {
      tokens.add('0.');
      return AmountInput._(tokens, decimals);
    }
    final current = tokens.last as String;
    if (current.contains('.')) return this;
    tokens[tokens.length - 1] = '$current.';
    return AmountInput._(tokens, decimals);
  }

  AmountInput operator(CalcOp op) {
    if (_tokens.isEmpty) return this;
    final tokens = [..._tokens];
    if (tokens.last is CalcOp) {
      tokens[tokens.length - 1] = op;
    } else {
      tokens.add(op);
    }
    return AmountInput._(tokens, decimals);
  }

  AmountInput backspace() {
    if (_tokens.isEmpty) return this;
    final tokens = [..._tokens];
    final last = tokens.last;
    if (last is CalcOp) {
      tokens.removeLast();
    } else {
      final s = last as String;
      if (s.length <= 1 || s == '0.') {
        tokens.removeLast();
      } else {
        tokens[tokens.length - 1] = s.substring(0, s.length - 1);
      }
    }
    return AmountInput._(tokens, decimals);
  }

  AmountInput clear() => AmountInput._(const [], decimals);

  /// Collapses the expression into its result, ready for further typing.
  AmountInput resolve(MoneyFormat format) {
    final value = evaluate(format.unit);
    if (value == null || value <= 0) return this;
    return AmountInput.fromMinor(value, format);
  }

  /// The result in minor units, rounded half away from zero. Null when the
  /// expression can't be evaluated (division by zero, nothing typed).
  int? evaluate(int unit) {
    final tokens = [..._tokens];
    if (tokens.isNotEmpty && tokens.last is CalcOp) tokens.removeLast();
    if (tokens.isEmpty) return null;

    // First pass: × and ÷.
    final terms = <double>[];
    final ops = <CalcOp>[];
    double? acc;
    CalcOp? pending;
    for (final token in tokens) {
      if (token is CalcOp) {
        if (token == CalcOp.multiply || token == CalcOp.divide) {
          pending = token;
        } else {
          terms.add(acc!);
          ops.add(token);
          acc = null;
          pending = null;
        }
        continue;
      }
      final n = double.tryParse(_normalize(token as String)) ?? 0;
      if (acc == null) {
        acc = n;
      } else if (pending == CalcOp.multiply) {
        acc = acc * n;
      } else if (pending == CalcOp.divide) {
        if (n == 0) return null;
        acc = acc / n;
      }
    }
    if (acc != null) terms.add(acc);

    // Second pass: + and −, left to right.
    var result = terms.first;
    for (var i = 0; i < ops.length && i + 1 < terms.length; i++) {
      result = ops[i] == CalcOp.add ? result + terms[i + 1] : result - terms[i + 1];
    }
    final scaled = result * unit;
    if (scaled.isNaN || scaled.isInfinite || scaled.abs() > 9e15) return null;
    // Nudge before rounding so 1.005 * 100 = 100.49999… still becomes 101.
    return (scaled + (scaled >= 0 ? 1e-7 : -1e-7)).round();
  }

  /// The expression as the user sees it, with grouping and the locale's
  /// decimal separator: "1,20,000 + 45.5".
  String display(MoneyFormat format) {
    if (_tokens.isEmpty) return '0';
    final buffer = StringBuffer();
    for (final token in _tokens) {
      if (token is CalcOp) {
        buffer.write(' ${token.symbol} ');
      } else {
        buffer.write(_formatNumber(token as String, format));
      }
    }
    return buffer.toString().trimRight();
  }

  static String _normalize(String s) => s.endsWith('.') ? s.substring(0, s.length - 1) : s;

  static String _formatNumber(String raw, MoneyFormat format) {
    final parts = raw.split('.');
    final whole = format.groupDigits(parts[0].isEmpty ? '0' : parts[0]);
    if (parts.length == 1) return whole;
    return '$whole${format.style.decimalSeparator}${parts[1]}';
  }

  @override
  bool operator ==(Object other) =>
      other is AmountInput &&
      other.decimals == decimals &&
      other._tokens.length == _tokens.length &&
      Iterable<int>.generate(_tokens.length).every((i) => other._tokens[i] == _tokens[i]);

  @override
  int get hashCode => Object.hash(decimals, Object.hashAll(_tokens));
}
