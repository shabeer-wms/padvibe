import 'package:flutter/material.dart';

class AppTheme {
  // Brand colors
  static const primaryColor = Color(0xFF6750A4);
  static const secondaryColor = Color(0xFF625B71);

  // Neutral surfaces: Material 3 tints surfaces with the seed color, which
  // reads as purple-grey on a tool UI. Keep the brand color for accents only.
  static final ColorScheme _lightScheme =
      ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: Brightness.light,
      ).copyWith(
        surface: const Color(0xFFFAFAFB),
        surfaceContainerLowest: const Color(0xFFFFFFFF),
        surfaceContainerLow: const Color(0xFFF5F5F7),
        surfaceContainer: const Color(0xFFF0F0F3),
        surfaceContainerHigh: const Color(0xFFEAEAEE),
        surfaceContainerHighest: const Color(0xFFE4E4E9),
        outlineVariant: const Color(0xFFDEDEE4),
      );

  static final ColorScheme _darkScheme =
      ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: Brightness.dark,
      ).copyWith(
        surface: const Color(0xFF111214),
        surfaceContainerLowest: const Color(0xFF0C0D0F),
        surfaceContainerLow: const Color(0xFF151619),
        surfaceContainer: const Color(0xFF1A1B1F),
        surfaceContainerHigh: const Color(0xFF212226),
        surfaceContainerHighest: const Color(0xFF28292E),
        outlineVariant: const Color(0xFF2F3036),
      );

  static final ThemeData lightTheme = _build(_lightScheme);
  static final ThemeData darkTheme = _build(_darkScheme);

  /// Same themes with an explicit font family (used by widget tests, where the
  /// platform default font is not available).
  static ThemeData build(Brightness brightness, {String? fontFamily}) => _build(
    brightness == Brightness.dark ? _darkScheme : _lightScheme,
    fontFamily,
  );

  static ThemeData _build(ColorScheme c, [String? fontFamily]) {
    final radius10 = BorderRadius.circular(10);
    final border = OutlineInputBorder(
      borderRadius: radius10,
      borderSide: BorderSide(color: c.outlineVariant),
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      colorScheme: c,
      scaffoldBackgroundColor: c.surface,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          color: c.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        shape: Border(bottom: BorderSide(color: c.outlineVariant)),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: c.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: c.outlineVariant),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: c.outlineVariant),
        ),
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          color: c.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: c.outlineVariant,
        space: 1,
        thickness: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceContainerLowest,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        hintStyle: TextStyle(
          fontFamily: fontFamily,
          color: c.onSurfaceVariant.withValues(alpha: 0.55),
        ),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: c.primary, width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide(color: c.outlineVariant),
        labelStyle: TextStyle(
          fontFamily: fontFamily,
          color: c.onSurface,
          fontSize: 13,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: radius10),
          ),
          side: WidgetStatePropertyAll(BorderSide(color: c.outlineVariant)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 40),
          shape: RoundedRectangleBorder(borderRadius: radius10),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 40),
          side: BorderSide(color: c.outlineVariant),
          shape: RoundedRectangleBorder(borderRadius: radius10),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: radius10),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: radius10),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: c.outlineVariant),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: radius10),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(8),
        radius: const Radius.circular(4),
        thumbColor: WidgetStatePropertyAll(c.onSurface.withValues(alpha: 0.25)),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(
          color: c.inverseSurface,
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: TextStyle(
          fontFamily: fontFamily,
          color: c.onInverseSurface,
          fontSize: 12,
        ),
      ),
    );
  }
}
