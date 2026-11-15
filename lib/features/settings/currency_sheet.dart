import 'package:material_ui/material_ui.dart';
import 'package:spent/core/money/currency.dart';
import 'package:spent/core/theme/app_theme.dart';
import 'package:spent/core/theme/tokens.dart';
import 'package:spent/shared/widgets/sheets.dart';

/// Searchable currency list. Resolves to the chosen currency.
Future<Currency?> showCurrencySheet(BuildContext context, {required String selected}) =>
    showAppSheet<Currency>(context, builder: (_) => _CurrencySheet(selected: selected));

class _CurrencySheet extends StatefulWidget {
  const _CurrencySheet({required this.selected});

  final String selected;

  @override
  State<_CurrencySheet> createState() => _CurrencySheetState();
}

class _CurrencySheetState extends State<_CurrencySheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final q = _q.trim().toLowerCase();
    final list = Currency.all
        .where(
          (c) =>
              q.isEmpty ||
              c.code.toLowerCase().contains(q) ||
              c.name.toLowerCase().contains(q) ||
              c.symbol.toLowerCase() == q,
        )
        .toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SheetHeader(title: 'Currency'),
        Padding(
          padding: const EdgeInsets.fromLTRB(Insets.page, 0, Insets.page, Insets.sm),
          child: TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: const InputDecoration(
              hintText: 'Search',
              prefixIcon: Icon(Icons.search_rounded, size: 20),
            ),
          ),
        ),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: list.length,
            itemBuilder: (context, i) {
              final c = list[i];
              final selected = c.code == widget.selected;
              return OptionRow(
                leading: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? p.primary : p.surface2,
                    shape: BoxShape.circle,
                  ),
                  child: FittedBox(
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text(
                        c.symbol,
                        style: context.text.titleSmall?.copyWith(
                          color: selected ? p.onPrimary : p.ink,
                        ),
                      ),
                    ),
                  ),
                ),
                title: c.name,
                subtitle: c.code,
                selected: selected,
                onTap: () => Navigator.pop(context, c),
              );
            },
          ),
        ),
      ],
    );
  }
}
