import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spent/core/database/database.dart';
import 'package:spent/core/money/currency.dart';
import 'package:spent/core/money/money_format.dart';
import 'package:spent/core/services/haptics.dart';
import 'package:spent/core/services/sample_data.dart';
import 'package:spent/core/settings/settings.dart';
import 'package:spent/core/theme/app_icons.dart';
import 'package:spent/core/theme/app_theme.dart';
import 'package:spent/core/theme/palette.dart';
import 'package:spent/core/theme/tokens.dart';
import 'package:spent/data/providers.dart';
import 'package:spent/features/lock/pin_widgets.dart';
import 'package:spent/features/settings/currency_sheet.dart';
import 'package:spent/shared/widgets/buttons.dart';
import 'package:spent/shared/widgets/motion.dart';
import 'package:spent/shared/widgets/pressable.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pages = PageController();
  int _page = 0;
  bool _working = false;

  final _name = TextEditingController();
  final _cash = TextEditingController();
  final _bank = TextEditingController();
  final _budget = TextEditingController();
  late Currency _currency = Currency.forLocale(PlatformDispatcher.instance.locale.countryCode);
  late NumberStyle _style = _currency.style;
  int _monthStart = 1;

  MoneyFormat get _money => MoneyFormat(_currency, _style);

  @override
  void dispose() {
    _pages.dispose();
    _name.dispose();
    _cash.dispose();
    _bank.dispose();
    _budget.dispose();
    super.dispose();
  }

  void _go(int page) {
    FocusScope.of(context).unfocus();
    Haptics.selection();
    _pages.animateToPage(page, duration: Motion.slow, curve: Motion.emphasized);
  }

  Future<void> _finish({bool sample = false}) async {
    if (_working) return;
    setState(() => _working = true);
    final db = ref.read(databaseProvider);
    await ref.read(categoryRepositoryProvider).seedDefaults();
    final settings = ref.read(settingsProvider.notifier);
    await settings.update(
      (s) => s.copyWith(
        name: _name.text.trim(),
        currencyCode: _currency.code,
        numberStyle: _style,
        monthStartDay: _monthStart,
      ),
    );
    int? defaultAccount;
    if (sample) {
      await SampleData(db, _currency).load();
      await ref.read(recurringRepositoryProvider).processDue(DateTime.now());
    } else {
      final accounts = ref.read(accountRepositoryProvider);
      await accounts.add(
        name: 'Cash',
        type: AccountType.cash,
        icon: AccountType.cash.defaultIcon,
        color: defaultAccountColor(AccountType.cash),
        openingBalance: _money.parse(_cash.text) ?? 0,
      );
      defaultAccount = await accounts.add(
        name: 'Bank account',
        type: AccountType.bank,
        icon: AccountType.bank.defaultIcon,
        color: defaultAccountColor(AccountType.bank),
        openingBalance: _money.parse(_bank.text) ?? 0,
      );
      final budget = _money.parse(_budget.text);
      if (budget != null && budget > 0) await ref.read(budgetRepositoryProvider).set(null, budget);
    }
    Haptics.success();
    await settings.update(
      (s) => s.copyWith(onboarded: true, defaultAccountId: () => defaultAccount),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 56,
              child: AnimatedOpacity(
                opacity: _page == 0 ? 0 : 1,
                duration: Motion.medium,
                child: Row(
                  children: [
                    const Gap(Insets.md),
                    CircleIconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Back',
                      onPressed: _page == 0 ? null : () => _go(_page - 1),
                    ),
                    const Spacer(),
                    for (var i = 1; i <= 3; i++)
                      AnimatedContainer(
                        duration: Motion.medium,
                        curve: Motion.emphasized,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: i == _page ? 22 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: i <= _page ? p.ink : p.surface3,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    const Spacer(),
                    const SizedBox(width: 44 + Insets.md),
                  ],
                ),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _Welcome(
                    working: _working,
                    onStart: () => _go(1),
                    onSample: () => _finish(sample: true),
                  ),
                  _Step(
                    title: 'Make it yours',
                    subtitle: 'Both are optional and can be changed later in Settings.',
                    action: AppButton(label: 'Continue', onPressed: () => _go(2)),
                    children: [
                      const _Label('What should we call you?'),
                      TextField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        maxLength: 24,
                        decoration: const InputDecoration(
                          hintText: 'Your first name',
                          counterText: '',
                        ),
                      ),
                      const Gap(Insets.xl),
                      const _Label('Currency'),
                      Pressable(
                        onTap: () async {
                          final c = await showCurrencySheet(context, selected: _currency.code);
                          if (c != null) {
                            setState(() {
                              _currency = c;
                              _style = c.style;
                            });
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: p.surface2, borderRadius: Radii.tile),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(color: p.primary, shape: BoxShape.circle),
                                child: FittedBox(
                                  child: Padding(
                                    padding: const EdgeInsets.all(6),
                                    child: Text(
                                      _currency.symbol,
                                      style: context.text.titleSmall?.copyWith(color: p.onPrimary),
                                    ),
                                  ),
                                ),
                              ),
                              const Gap(Insets.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_currency.name, style: context.text.titleSmall),
                                    Text(
                                      'Looks like ${_money.format(12345050)}',
                                      style: context.text.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.unfold_more_rounded, color: p.ink3),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  _Step(
                    title: 'Where\'s your money?',
                    subtitle:
                        'Starting balances make your total accurate from day one. Leave blank to start at zero.',
                    action: AppButton(label: 'Continue', onPressed: () => _go(3)),
                    children: [
                      _BalanceField(
                        icon: 'cash',
                        color: defaultAccountColor(AccountType.cash),
                        label: 'Cash',
                        controller: _cash,
                        money: _money,
                      ),
                      const Gap(Insets.md),
                      _BalanceField(
                        icon: 'bank',
                        color: defaultAccountColor(AccountType.bank),
                        label: 'Bank account',
                        controller: _bank,
                        money: _money,
                      ),
                      const Gap(Insets.lg),
                      Text(
                        'Cards, wallets and savings can be added any time from Home → Accounts.',
                        style: context.text.bodySmall?.copyWith(color: p.ink3),
                      ),
                    ],
                  ),
                  _Step(
                    title: 'A monthly budget',
                    subtitle:
                        'Spent will tell you what\'s safe to spend each day. Skip it if you just want to track.',
                    action: AppButton(
                      label: 'Start using Spent',
                      loading: _working,
                      onPressed: _finish,
                    ),
                    children: [
                      TextField(
                        controller: _budget,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                        style: context.text.headlineSmall?.tabular,
                        decoration: InputDecoration(
                          hintText: 'Budget per month',
                          prefixText: _style.symbolFirst ? '${_currency.symbol} ' : null,
                          suffixText: _style.symbolFirst ? null : _currency.symbol,
                        ),
                      ),
                      const Gap(Insets.xl),
                      const _Label('My month starts on'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final d in const [1, 5, 10, 15, 20, 25, 28])
                            SelectChip(
                              label: d == 1 ? 'The 1st' : 'Day $d',
                              dense: true,
                              selected: _monthStart == d,
                              onTap: () => setState(() => _monthStart = d),
                            ),
                        ],
                      ),
                      const Gap(Insets.sm),
                      Text(
                        'Paid on the 25th? Start your month then, and budgets follow your salary.',
                        style: context.text.bodySmall?.copyWith(color: p.ink3),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Insets.sm),
    child: Text(text, style: context.text.labelMedium?.copyWith(color: context.palette.ink2)),
  );
}

class _Step extends StatelessWidget {
  const _Step({
    required this.title,
    required this.subtitle,
    required this.children,
    required this.action,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;
  final Widget action;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Insets.xxl, Insets.lg, Insets.xxl, Insets.xl),
          children: [
            FadeSlideIn(child: Text(title, style: context.text.headlineLarge)),
            const Gap(Insets.sm),
            FadeSlideIn(
              index: 1,
              child: Text(
                subtitle,
                style: context.text.bodyLarge?.copyWith(color: context.palette.ink2),
              ),
            ),
            const Gap(Insets.xxxl),
            FadeSlideIn(
              index: 2,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(Insets.xxl, 0, Insets.xxl, Insets.lg),
        child: action,
      ),
    ],
  );
}

class _BalanceField extends StatelessWidget {
  const _BalanceField({
    required this.icon,
    required this.color,
    required this.label,
    required this.controller,
    required this.money,
  });

  final String icon;
  final int color;
  final String label;
  final TextEditingController controller;
  final MoneyFormat money;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: Radii.tile,
        border: Border.all(color: p.hairline),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: ShapeDecoration(
              color: p.entitySoft(color),
              shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(13)),
            ),
            child: Icon(AppIcons.of(icon), color: p.entity(color), size: 20),
          ),
          const Gap(Insets.md),
          Text(label, style: context.text.titleSmall),
          const Gap(Insets.md),
          Expanded(
            child: TextField(
              controller: controller,
              textAlign: TextAlign.right,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              style: context.text.titleMedium?.tabular,
              decoration: InputDecoration(
                hintText: '0',
                fillColor: Colors.transparent,
                prefixText: money.style.symbolFirst ? '${money.currency.symbol} ' : null,
                suffixText: money.style.symbolFirst ? null : money.currency.symbol,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// First screen: what Spent is, with a little animated preview.
class _Welcome extends StatelessWidget {
  const _Welcome({required this.onStart, required this.onSample, required this.working});

  final VoidCallback onStart;
  final VoidCallback onSample;
  final bool working;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return LayoutBuilder(
      // Scrolls on short screens; otherwise fills the page and centers.
      builder: (context, c) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: Insets.xxl),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight),
          child: IntrinsicHeight(
            child: Column(
              children: [
                const Spacer(),
                _PreviewStack(compact: c.maxHeight < 680),
                const Spacer(),
                const FadeSlideIn(index: 4, child: AppMark(size: 52)),
                const Gap(Insets.xl),
                FadeSlideIn(
                  index: 5,
                  child: Text(
                    'Know where your\nmoney goes.',
                    textAlign: TextAlign.center,
                    style: context.text.headlineLarge?.copyWith(fontSize: 32, height: 1.12),
                  ),
                ),
                const Gap(Insets.md),
                FadeSlideIn(
                  index: 6,
                  child: Text(
                    'Log spending in seconds, see it clearly, and stay on budget. '
                    'Private by design: no account, no cloud — everything stays on this phone.',
                    textAlign: TextAlign.center,
                    style: context.text.bodyLarge?.copyWith(color: p.ink2),
                  ),
                ),
                const Gap(Insets.xxl),
                FadeSlideIn(
                  index: 7,
                  child: AppButton(label: 'Get started', onPressed: working ? null : onStart),
                ),
                const Gap(Insets.sm),
                FadeSlideIn(
                  index: 8,
                  child: AppButton.ghost(
                    label: working ? 'Setting things up…' : 'Explore with sample data',
                    onPressed: working ? null : onSample,
                  ),
                ),
                const Gap(Insets.xl),
                FadeSlideIn(
                  index: 9,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Made by Ketul with ', style: context.text.labelMedium),
                      const Icon(Icons.favorite, color: Colors.red, size: 16),
                    ],
                  ),
                ),
                const Gap(Insets.md),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewStack extends ConsumerWidget {
  const _PreviewStack({this.compact = false});

  /// Two cards instead of three, for short screens.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final items = [
      ('coffee', EntityColors.orange, 'Cappuccino', 'Food & Dining', '−3.60'),
      ('salary', EntityColors.green, 'Salary', 'Bank account', '+2,400.00'),
      ('groceries', EntityColors.green, 'Weekly groceries', 'Groceries', '−48.20'),
    ];
    final count = compact ? 2 : items.length;
    return SizedBox(
      height: compact ? 160 : 230,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (var i = 0; i < count; i++)
            Positioned(
              top: 18.0 + i * 66,
              left: 8.0 + (i == 1 ? 18 : 0),
              right: 8.0 + (i == 1 ? 0 : 18),
              child: FadeSlideIn(
                index: i + 1,
                offset: 28,
                child: Float(
                  amplitude: 2.5 + i,
                  child: Transform.rotate(
                    angle: (i - 1) * 0.025,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: p.surface,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: p.floatingShadow,
                        border: p.isDark ? Border.all(color: p.hairline) : null,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: ShapeDecoration(
                              color: items[i].$2
                                  .resolve(p.brightness)
                                  .withValues(alpha: p.isDark ? 0.2 : 0.13),
                              shape: RoundedSuperellipseBorder(
                                borderRadius: BorderRadius.circular(13),
                              ),
                            ),
                            child: Icon(
                              AppIcons.of(items[i].$1),
                              color: items[i].$2.resolve(p.brightness),
                              size: 20,
                            ),
                          ),
                          const Gap(Insets.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(items[i].$3, style: context.text.titleSmall),
                                Text(items[i].$4, style: context.text.bodySmall),
                              ],
                            ),
                          ),
                          Text(
                            items[i].$5,
                            style: context.text.titleSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: items[i].$5.startsWith('+') ? p.positive : p.ink,
                                )
                                .tabular,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
