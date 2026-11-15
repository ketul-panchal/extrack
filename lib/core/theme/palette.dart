import 'package:material_ui/material_ui.dart';
import 'package:spent/core/database/enums.dart';

/// The brand accent, chosen in Settings → Appearance.
enum AccentColor {
  emerald('Emerald', Color(0xFF0F9F6E), Color(0xFF34D399), Color(0xFF0B7F55)),
  indigo('Indigo', Color(0xFF5B5BD6), Color(0xFF8D8DF2), Color(0xFF4747C2)),
  ocean('Ocean', Color(0xFF0B84D8), Color(0xFF4DB3F5), Color(0xFF0A6BB0)),
  violet('Violet', Color(0xFF8E4EC6), Color(0xFFB98DE6), Color(0xFF7A3DB3)),
  amber('Amber', Color(0xFFD97706), Color(0xFFFBBF24), Color(0xFFA85A04)),
  rose('Rose', Color(0xFFE5486F), Color(0xFFFB7196), Color(0xFFC22F57)),
  graphite('Graphite', Color(0xFF3A3D42), Color(0xFFD7D9DD), Color(0xFF2B2E33));

  const AccentColor(this.label, this.light, this.dark, this.lightText);

  final String label;

  /// Fill in light mode.
  final Color light;

  /// Fill and text in dark mode.
  final Color dark;

  /// Text/icon on light surfaces (≥ 4.5:1 on white).
  final Color lightText;
}

/// A color a category, account or goal can wear. The light value is what's
/// stored; the dark value is its own selected step for dark surfaces, not an
/// automatic flip. The first eight are the validated categorical order
/// (colorblind-safe as neighbours); the rest add variety for icons.
class EntityColor {
  const EntityColor(this.name, this.light, this.dark);

  final String name;
  final Color light;
  final Color dark;

  Color resolve(Brightness b) => b == Brightness.dark ? dark : light;
}

abstract final class EntityColors {
  static const blue = EntityColor('Blue', Color(0xFF2A78D6), Color(0xFF3987E5));
  static const orange = EntityColor('Orange', Color(0xFFEB6834), Color(0xFFD95926));
  static const aqua = EntityColor('Aqua', Color(0xFF1BAF7A), Color(0xFF199E70));
  static const yellow = EntityColor('Yellow', Color(0xFFEDA100), Color(0xFFC98500));
  static const magenta = EntityColor('Magenta', Color(0xFFE87BA4), Color(0xFFD55181));
  static const green = EntityColor('Green', Color(0xFF008300), Color(0xFF008300));
  static const violet = EntityColor('Violet', Color(0xFF4A3AA7), Color(0xFF9085E9));
  static const red = EntityColor('Red', Color(0xFFE34948), Color(0xFFE66767));
  static const teal = EntityColor('Teal', Color(0xFF0E9FB2), Color(0xFF22B5C8));
  static const indigo = EntityColor('Indigo', Color(0xFF5B5BD6), Color(0xFF7F7FF0));
  static const lime = EntityColor('Lime', Color(0xFF6AA000), Color(0xFF7CB518));
  static const rose = EntityColor('Rose', Color(0xFFD6336C), Color(0xFFE8588A));
  static const slate = EntityColor('Slate', Color(0xFF5F6B7A), Color(0xFF8A96A6));

  static const all = <EntityColor>[
    blue,
    orange,
    aqua,
    yellow,
    magenta,
    green,
    violet,
    red,
    teal,
    indigo,
    lime,
    rose,
    slate,
  ];

  static final Map<int, EntityColor> _byValue = {for (final c in all) c.light.toARGB32(): c};

  /// Resolves a stored color for the current brightness.
  static Color resolve(int stored, Brightness brightness) {
    final known = _byValue[stored];
    if (known != null) return known.resolve(brightness);
    return Color(stored);
  }

  static EntityColor? find(int stored) => _byValue[stored];
}

/// Semantic colors for the whole app, available as `context.palette`.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.hairline,
    required this.accent,
    required this.accentText,
    required this.onAccent,
    required this.accentSoft,
    required this.primary,
    required this.onPrimary,
    required this.positive,
    required this.positiveFill,
    required this.negative,
    required this.negativeFill,
    required this.warning,
    required this.warningFill,
    required this.heroBg,
    required this.heroInk,
    required this.heroInk2,
    required this.shadow,
  });

  factory AppPalette.light(AccentColor accent) => AppPalette(
    brightness: Brightness.light,
    bg: const Color(0xFFF6F5F2),
    surface: const Color(0xFFFFFFFF),
    surface2: const Color(0xFFF0EFEB),
    surface3: const Color(0xFFE5E3DE),
    ink: const Color(0xFF16181C),
    ink2: const Color(0xFF5F636B),
    ink3: const Color(0xFF9A9EA6),
    hairline: const Color(0xFFE8E6E1),
    accent: accent.light,
    accentText: accent.lightText,
    onAccent: const Color(0xFFFFFFFF),
    accentSoft: accent.light.withValues(alpha: 0.12),
    primary: const Color(0xFF16181C),
    onPrimary: const Color(0xFFFFFFFF),
    positive: const Color(0xFF0B7F55),
    positiveFill: const Color(0xFF12A66E),
    negative: const Color(0xFFD63A3F),
    negativeFill: const Color(0xFFE5484D),
    warning: const Color(0xFFA86300),
    warningFill: const Color(0xFFF0A020),
    heroBg: const Color(0xFF16181C),
    heroInk: const Color(0xFFFFFFFF),
    heroInk2: const Color(0xFFA3A7AE),
    shadow: const Color(0xFF1B1D22),
  );

  factory AppPalette.dark(AccentColor accent) => AppPalette(
    brightness: Brightness.dark,
    bg: const Color(0xFF0D0E10),
    surface: const Color(0xFF17181B),
    surface2: const Color(0xFF212226),
    surface3: const Color(0xFF2C2E32),
    ink: const Color(0xFFF3F2EF),
    ink2: const Color(0xFFA3A7AE),
    ink3: const Color(0xFF6C7077),
    hairline: const Color(0xFF26282C),
    accent: accent.dark,
    accentText: accent.dark,
    onAccent: const Color(0xFF0B0C0E),
    accentSoft: accent.dark.withValues(alpha: 0.16),
    primary: const Color(0xFFF3F2EF),
    onPrimary: const Color(0xFF0D0E10),
    positive: const Color(0xFF3DD68C),
    positiveFill: const Color(0xFF2FBF7A),
    negative: const Color(0xFFFF6B6B),
    negativeFill: const Color(0xFFF2555A),
    warning: const Color(0xFFFFB547),
    warningFill: const Color(0xFFF0A020),
    heroBg: const Color(0xFF1D1F23),
    heroInk: const Color(0xFFF3F2EF),
    heroInk2: const Color(0xFF9EA2A9),
    shadow: const Color(0xFF000000),
  );

  final Brightness brightness;

  /// Page background.
  final Color bg;

  /// Cards and sheets.
  final Color surface;

  /// Quiet fills: chips, inputs, keypad keys, tracks.
  final Color surface2;

  /// Pressed fills and stronger tracks.
  final Color surface3;

  /// Text: primary, secondary, tertiary.
  final Color ink;
  final Color ink2;
  final Color ink3;
  final Color hairline;

  final Color accent;
  final Color accentText;
  final Color onAccent;
  final Color accentSoft;

  /// The main call-to-action fill (ink in light mode, near-white in dark).
  final Color primary;
  final Color onPrimary;

  /// Money in. Text step / fill step.
  final Color positive;
  final Color positiveFill;

  /// Over budget, destructive.
  final Color negative;
  final Color negativeFill;

  /// Nearing a limit.
  final Color warning;
  final Color warningFill;

  /// The dark balance card on Home.
  final Color heroBg;
  final Color heroInk;
  final Color heroInk2;

  final Color shadow;

  bool get isDark => brightness == Brightness.dark;

  /// Resolves a stored entity color (category/account/goal) for this mode.
  Color entity(int stored) => EntityColors.resolve(stored, brightness);

  /// Translucent wash behind an entity icon.
  Color entitySoft(int stored) => entity(stored).withValues(alpha: isDark ? 0.20 : 0.13);

  List<BoxShadow> get cardShadow => isDark
      ? const []
      : [
          BoxShadow(
            color: shadow.withValues(alpha: 0.04),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
          BoxShadow(
            color: shadow.withValues(alpha: 0.05),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ];

  List<BoxShadow> get floatingShadow => [
    BoxShadow(
      color: shadow.withValues(alpha: isDark ? 0.5 : 0.10),
      blurRadius: 30,
      offset: const Offset(0, 10),
    ),
    BoxShadow(
      color: shadow.withValues(alpha: isDark ? 0.3 : 0.05),
      blurRadius: 6,
      offset: const Offset(0, 2),
    ),
  ];

  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      brightness: t < 0.5 ? brightness : other.brightness,
      bg: c(bg, other.bg),
      surface: c(surface, other.surface),
      surface2: c(surface2, other.surface2),
      surface3: c(surface3, other.surface3),
      ink: c(ink, other.ink),
      ink2: c(ink2, other.ink2),
      ink3: c(ink3, other.ink3),
      hairline: c(hairline, other.hairline),
      accent: c(accent, other.accent),
      accentText: c(accentText, other.accentText),
      onAccent: c(onAccent, other.onAccent),
      accentSoft: c(accentSoft, other.accentSoft),
      primary: c(primary, other.primary),
      onPrimary: c(onPrimary, other.onPrimary),
      positive: c(positive, other.positive),
      positiveFill: c(positiveFill, other.positiveFill),
      negative: c(negative, other.negative),
      negativeFill: c(negativeFill, other.negativeFill),
      warning: c(warning, other.warning),
      warningFill: c(warningFill, other.warningFill),
      heroBg: c(heroBg, other.heroBg),
      heroInk: c(heroInk, other.heroInk),
      heroInk2: c(heroInk2, other.heroInk2),
      shadow: c(shadow, other.shadow),
    );
  }
}

/// Default color per account type, so new accounts look distinct.
int defaultAccountColor(AccountType t) => switch (t) {
  AccountType.cash => EntityColors.green,
  AccountType.bank => EntityColors.blue,
  AccountType.card => EntityColors.violet,
  AccountType.wallet => EntityColors.orange,
  AccountType.savings => EntityColors.aqua,
  AccountType.investment => EntityColors.indigo,
  AccountType.other => EntityColors.slate,
}.light.toARGB32();
