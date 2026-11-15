import 'package:flutter_test/flutter_test.dart';
import 'package:spent/core/money/amount_input.dart';
import 'package:spent/core/money/currency.dart';
import 'package:spent/core/money/money_format.dart';

void main() {
  final usd = MoneyFormat(Currency.byCode('USD'), NumberStyle.western);
  final inr = MoneyFormat(Currency.byCode('INR'), NumberStyle.indian);
  final eur = MoneyFormat(Currency.byCode('EUR'), NumberStyle.european);
  final jpy = MoneyFormat(Currency.byCode('JPY'), NumberStyle.western);
  final chf = MoneyFormat(Currency.byCode('CHF'), NumberStyle.western);

  group('MoneyFormat.format', () {
    test('groups thousands and drops zero decimals', () {
      expect(usd.format(123456789), r'$1,234,567.89');
      expect(usd.format(125000), r'$1,250');
      expect(usd.format(5), r'$0.05');
      expect(usd.format(0), r'$0');
    });

    test('uses lakh/crore grouping for Indian style', () {
      expect(inr.format(1234567800), '₹1,23,45,678');
      expect(inr.format(10000000), '₹1,00,000');
      expect(inr.format(99900), '₹999');
    });

    test('European style puts the symbol after with comma decimals', () {
      expect(eur.format(123456), '1.234,56 €');
    });

    test('zero-decimal currencies and wordy symbols', () {
      expect(jpy.format(1500), '¥1,500');
      expect(chf.format(1000), 'CHF 10');
    });

    test('signs use a true minus and optional plus', () {
      expect(usd.format(-250), '${MoneyFormat.minus}\$2.50');
      expect(usd.format(250, sign: true), r'+$2.50');
      expect(usd.format(0, sign: true), r'$0');
    });
  });

  group('MoneyFormat.compact', () {
    test('western suffixes', () {
      expect(usd.compact(99900), r'$999');
      expect(usd.compact(125000), r'$1.3K');
      expect(usd.compact(1250000000), r'$12.5M');
    });

    test('Indian suffixes', () {
      expect(inr.compact(25000000), '₹2.5L');
      expect(inr.compact(1200000000), '₹1.2Cr');
    });
  });

  group('MoneyFormat.parse', () {
    test('reads plain and grouped input', () {
      expect(usd.parse('1250.5'), 125050);
      expect(usd.parse('1,250.50'), 125050);
      expect(usd.parse(r'$ 12'), 1200);
      expect(eur.parse('1.234,56'), 123456);
      expect(usd.parse(''), isNull);
    });

    test('round-trips with toInput', () {
      for (final v in [0, 5, 100, 125050, 999999999]) {
        expect(usd.parse(usd.toInput(v)) ?? 0, v);
      }
      expect(usd.toInput(125050), '1250.5');
    });
  });

  group('AmountInput', () {
    AmountInput type(String keys, {int decimals = 2}) {
      var a = AmountInput.empty(decimals);
      for (final ch in keys.split('')) {
        a = switch (ch) {
          '.' => a.dot(),
          '+' => a.operator(CalcOp.add),
          '-' => a.operator(CalcOp.subtract),
          '*' => a.operator(CalcOp.multiply),
          '/' => a.operator(CalcOp.divide),
          '<' => a.backspace(),
          _ => a.digit(int.parse(ch)),
        };
      }
      return a;
    }

    test('builds a number and limits decimals', () {
      expect(type('12.345').evaluate(100), 1234);
      expect(type('007').evaluate(100), 700);
      expect(type('.5').evaluate(100), 50);
    });

    test('respects operator precedence', () {
      expect(type('2+3*4').evaluate(100), 1400);
      expect(type('10-4/2').evaluate(100), 800);
      expect(type('100/3').evaluate(100), 3333);
    });

    test('trailing operator is ignored, repeated operators replace', () {
      expect(type('50+').evaluate(100), 5000);
      expect(type('50+*2').evaluate(100), 10000);
    });

    test('division by zero is invalid', () {
      expect(type('5/0').evaluate(100), isNull);
    });

    test('backspace removes characters then tokens', () {
      expect(type('12+3<<').evaluate(100), 1200);
      expect(type('1<').isEmpty, isTrue);
    });

    test('display groups digits and shows operators', () {
      expect(type('120000+45').display(inr), '1,20,000 + 45');
      expect(type('').display(usd), '0');
    });

    test('no decimal point for zero-decimal currencies', () {
      expect(type('1.5', decimals: 0).evaluate(1), 15);
    });
  });
}
