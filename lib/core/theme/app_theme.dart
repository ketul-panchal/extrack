import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spent/core/theme/palette.dart';
import 'package:spent/core/theme/tokens.dart';

abstract final class AppTheme {
  static const fontFamily = 'Manrope';

  static ThemeData light(AccentColor accent) => _build(AppPalette.light(accent));
  static ThemeData dark(AccentColor accent) => _build(AppPalette.dark(accent));

  static TextTheme _textTheme(AppPalette p) {
    TextStyle s(double size, FontWeight w, double height, double tracking, Color color) =>
        TextStyle(
          fontFamily: fontFamily,
          fontSize: size,
          fontWeight: w,
          height: height,
          letterSpacing: tracking,
          color: color,
        );
    return TextTheme(
      // Hero numbers.
      displayLarge: s(48, FontWeight.w700, 1.05, -1.8, p.ink),
      displayMedium: s(38, FontWeight.w700, 1.08, -1.3, p.ink),
      displaySmall: s(30, FontWeight.w700, 1.12, -0.9, p.ink),
      // Screen and section titles.
      headlineLarge: s(30, FontWeight.w800, 1.15, -0.9, p.ink),
      headlineMedium: s(26, FontWeight.w800, 1.18, -0.7, p.ink),
      headlineSmall: s(21, FontWeight.w700, 1.24, -0.4, p.ink),
      titleLarge: s(18, FontWeight.w700, 1.3, -0.25, p.ink),
      titleMedium: s(16, FontWeight.w600, 1.35, -0.15, p.ink),
      titleSmall: s(14, FontWeight.w600, 1.35, -0.05, p.ink),
      bodyLarge: s(16, FontWeight.w500, 1.45, -0.1, p.ink),
      bodyMedium: s(14, FontWeight.w500, 1.45, 0, p.ink),
      bodySmall: s(12.5, FontWeight.w500, 1.4, 0.05, p.ink2),
      labelLarge: s(15, FontWeight.w700, 1.2, -0.05, p.ink),
      labelMedium: s(13, FontWeight.w600, 1.2, 0, p.ink2),
      labelSmall: s(11, FontWeight.w700, 1.2, 0.4, p.ink3),
    );
  }

  static ThemeData _build(AppPalette p) {
    final text = _textTheme(p);
    final scheme = ColorScheme(
      brightness: p.brightness,
      primary: p.accent,
      onPrimary: p.onAccent,
      primaryContainer: p.accentSoft,
      onPrimaryContainer: p.accentText,
      secondary: p.ink,
      onSecondary: p.onPrimary,
      tertiary: p.positiveFill,
      onTertiary: p.onPrimary,
      error: p.negativeFill,
      onError: Colors.white,
      surface: p.surface,
      onSurface: p.ink,
      onSurfaceVariant: p.ink2,
      surfaceContainerLowest: p.surface,
      surfaceContainerLow: p.surface,
      surfaceContainer: p.surface,
      surfaceContainerHigh: p.surface2,
      surfaceContainerHighest: p.surface3,
      outline: p.ink3,
      outlineVariant: p.hairline,
      shadow: p.shadow,
      scrim: Colors.black,
      inverseSurface: p.ink,
      onInverseSurface: p.surface,
      inversePrimary: p.accent,
      surfaceTint: Colors.transparent,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: p.brightness,
      colorScheme: scheme,
      fontFamily: fontFamily,
      textTheme: text,
      scaffoldBackgroundColor: p.bg,
      canvasColor: p.bg,
      splashFactory: InkSparkle.splashFactory,
      splashColor: p.ink.withValues(alpha: 0.05),
      highlightColor: p.ink.withValues(alpha: 0.03),
      hoverColor: p.ink.withValues(alpha: 0.03),
      dividerColor: p.hairline,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      extensions: [p],
      iconTheme: IconThemeData(color: p.ink, size: 22),
      appBarTheme: AppBarThemeData(
        backgroundColor: p.bg,
        foregroundColor: p.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleSpacing: Insets.page,
        titleTextStyle: text.titleLarge,
        systemOverlayStyle: overlayStyle(p),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: Radii.card),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        modalBackgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
        showDragHandle: false,
        clipBehavior: Clip.antiAlias,
        modalBarrierColor: Colors.black.withValues(alpha: p.isDark ? 0.6 : 0.32),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(26))),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium?.copyWith(color: p.ink2),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: p.surface2,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        hintStyle: text.bodyLarge?.copyWith(color: p.ink3),
        labelStyle: text.bodyMedium?.copyWith(color: p.ink2),
        floatingLabelStyle: text.bodyMedium?.copyWith(color: p.ink2),
        prefixIconColor: p.ink3,
        suffixIconColor: p.ink3,
        border: const OutlineInputBorder(borderRadius: Radii.tile, borderSide: BorderSide.none),
        enabledBorder: const OutlineInputBorder(
          borderRadius: Radii.tile,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: Radii.tile,
          borderSide: BorderSide(color: p.ink.withValues(alpha: 0.85), width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: Radii.tile,
          borderSide: BorderSide(color: p.negativeFill, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: Radii.tile,
          borderSide: BorderSide(color: p.negativeFill, width: 1.4),
        ),
        errorStyle: text.bodySmall?.copyWith(color: p.negative),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.ink,
        selectionColor: p.accent.withValues(alpha: 0.28),
        selectionHandleColor: p.accent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.onAccent : p.surface,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.accent : p.surface3,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        thumbIcon: const WidgetStatePropertyAll(null),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: p.accent,
        inactiveTrackColor: p.surface3,
        thumbColor: p.accent,
        overlayColor: p.accent.withValues(alpha: 0.12),
        trackHeight: 4,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.accent,
        linearTrackColor: p.surface3,
        circularTrackColor: p.surface3,
      ),
      dividerTheme: DividerThemeData(color: p.hairline, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        iconColor: p.ink2,
        textColor: p.ink,
        titleTextStyle: text.titleSmall,
        subtitleTextStyle: text.bodySmall,
        contentPadding: const EdgeInsets.symmetric(horizontal: Insets.page),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.ink,
        contentTextStyle: text.bodyMedium?.copyWith(color: p.surface),
        actionTextColor: p.accent,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: Radii.tile),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: p.ink, borderRadius: Radii.chip),
        textStyle: text.labelMedium?.copyWith(color: p.surface),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(26))),
        headerBackgroundColor: p.surface,
        headerForegroundColor: p.ink,
        headerHeadlineStyle: text.headlineSmall,
        headerHelpStyle: text.labelMedium,
        weekdayStyle: text.labelMedium?.copyWith(color: p.ink3),
        dayStyle: text.bodyMedium,
        yearStyle: text.bodyLarge,
        dayForegroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? p.onAccent
              : s.contains(WidgetState.disabled)
              ? p.ink3.withValues(alpha: 0.5)
              : p.ink,
        ),
        dayBackgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.accent : null,
        ),
        todayForegroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.onAccent : p.accentText,
        ),
        todayBackgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.accent : null,
        ),
        todayBorder: BorderSide(color: p.accent, width: 1.2),
        yearForegroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.onAccent : p.ink,
        ),
        yearBackgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.accent : null,
        ),
        dividerColor: p.hairline,
        cancelButtonStyle: TextButton.styleFrom(foregroundColor: p.ink2),
        confirmButtonStyle: TextButton.styleFrom(foregroundColor: p.accentText),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: p.surface,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(26))),
        hourMinuteColor: p.surface2,
        hourMinuteTextColor: p.ink,
        dialBackgroundColor: p.surface2,
        dialHandColor: p.accent,
        dayPeriodColor: p.accentSoft,
        dayPeriodTextColor: p.ink,
        entryModeIconColor: p.ink2,
        cancelButtonStyle: TextButton.styleFrom(foregroundColor: p.ink2),
        confirmButtonStyle: TextButton.styleFrom(foregroundColor: p.accentText),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.ink,
          textStyle: text.labelLarge,
          shape: const RoundedRectangleBorder(borderRadius: Radii.chip),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: p.shadow.withValues(alpha: 0.2),
        shape: const RoundedRectangleBorder(borderRadius: Radii.tile),
        textStyle: text.bodyMedium,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(p.ink3.withValues(alpha: 0.4)),
        radius: const Radius.circular(8),
        thickness: const WidgetStatePropertyAll(3),
      ),
    );
  }

  static SystemUiOverlayStyle overlayStyle(AppPalette p) => SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: p.isDark ? Brightness.light : Brightness.dark,
    statusBarBrightness: p.isDark ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: p.isDark ? Brightness.light : Brightness.dark,
    systemNavigationBarContrastEnforced: false,
  );
}

extension AppThemeX on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
  TextTheme get text => Theme.of(this).textTheme;
}

extension TextStyleX on TextStyle {
  /// Equal-width digits so columns of amounts line up and counters don't jitter.
  TextStyle get tabular => copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
  TextStyle withColor(Color c) => copyWith(color: c);
  TextStyle get w800 => copyWith(fontWeight: FontWeight.w800);
  TextStyle get w700 => copyWith(fontWeight: FontWeight.w700);
  TextStyle get w600 => copyWith(fontWeight: FontWeight.w600);
}
