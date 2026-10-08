import 'package:flutter/material.dart';

import 'tokens.dart';

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.light ? SavrColors.light : SavrColors.dark;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.primary,
    onPrimary: c.onPrimary,
    primaryContainer: c.primarySoft,
    onPrimaryContainer: c.primary,
    secondary: c.deal,
    onSecondary: c.onDeal,
    secondaryContainer: c.dealSoft,
    onSecondaryContainer: c.onDealSoft,
    error: c.danger,
    onError: Colors.white,
    surface: c.surface,
    onSurface: c.ink,
    onSurfaceVariant: c.inkMuted,
    // Dialogs, menus and sheets float over content, so they stay opaque.
    surfaceContainerLowest: c.surfaceSolid,
    surfaceContainerLow: c.surfaceSolid,
    surfaceContainer: c.surfaceSolid,
    surfaceContainerHigh: c.surfaceSolid,
    surfaceContainerHighest: c.surfaceSolid,
    outline: c.line,
    outlineVariant: c.line,
  );

  // Type scale: 1.2 minor-third ratio from a 15px body. Tight negative
  // tracking on large sizes, neutral on body for legibility.
  final text = TextTheme(
    headlineMedium: TextStyle(
      fontFamily: 'Inter',
      fontSize: 26,
      height: 1.15,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.6,
      color: c.ink,
    ),
    titleLarge: TextStyle(
      fontFamily: 'Inter',
      fontSize: 21,
      height: 1.2,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
      color: c.ink,
    ),
    titleMedium: TextStyle(
      fontFamily: 'Inter',
      fontSize: 17,
      height: 1.25,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
      color: c.ink,
    ),
    titleSmall: TextStyle(fontFamily: 'Inter', fontSize: 15, height: 1.3, fontWeight: FontWeight.w600, color: c.ink),
    bodyLarge: TextStyle(fontFamily: 'Inter', fontSize: 16, height: 1.45, fontWeight: FontWeight.w400, color: c.ink),
    bodyMedium: TextStyle(fontFamily: 'Inter', fontSize: 15, height: 1.45, fontWeight: FontWeight.w400, color: c.ink),
    bodySmall: TextStyle(
      fontFamily: 'Inter',
      fontSize: 13,
      height: 1.4,
      fontWeight: FontWeight.w400,
      color: c.inkMuted,
    ),
    labelLarge: TextStyle(fontFamily: 'Inter', fontSize: 15, height: 1.2, fontWeight: FontWeight.w600, color: c.ink),
    labelMedium: TextStyle(fontFamily: 'Inter', fontSize: 13, height: 1.2, fontWeight: FontWeight.w500, color: c.ink),
    labelSmall: TextStyle(
      fontFamily: 'Inter',
      fontSize: 11,
      height: 1.2,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.4,
      color: c.inkMuted,
    ),
  );

  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(Radii.lg),
    borderSide: BorderSide(color: c.line),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: 'Inter',
    textTheme: text,
    scaffoldBackgroundColor: c.bg,
    extensions: [c],
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent, // the Backdrop shows through
      foregroundColor: c.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleMedium,
    ),
    dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      hintStyle: text.bodyMedium!.copyWith(color: c.inkMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: 14),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(borderSide: BorderSide(color: c.primary, width: 1.6)),
      errorBorder: border.copyWith(borderSide: BorderSide(color: c.danger)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.primary,
        foregroundColor: c.onPrimary,
        minimumSize: const Size(48, 50),
        textStyle: text.labelLarge,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.ink,
        minimumSize: const Size(48, 44),
        side: BorderSide(color: c.line),
        textStyle: text.labelLarge,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: c.primary, textStyle: text.labelLarge),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.surface,
      selectedColor: c.primarySoft,
      side: BorderSide(color: c.line),
      labelStyle: text.labelMedium,
      shape: const StadiumBorder(),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 4),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: brightness == Brightness.dark ? c.surfaceSolid.withValues(alpha: 0.94) : c.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: c.primarySoft,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) =>
            text.labelSmall!.copyWith(letterSpacing: 0.1, color: s.contains(WidgetState.selected) ? c.ink : c.inkMuted),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? c.primary : c.inkMuted),
      ),
    ),
    dialogTheme: DialogThemeData(backgroundColor: c.surfaceSolid, surfaceTintColor: Colors.transparent),
    popupMenuTheme: PopupMenuThemeData(color: c.surfaceSolid, surfaceTintColor: Colors.transparent),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surfaceSolid,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: c.line,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.ink,
      contentTextStyle: text.bodyMedium!.copyWith(color: c.bg),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.onPrimary : c.inkMuted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.primary : c.surfaceAlt),
      trackOutlineColor: WidgetStateProperty.all(c.line),
    ),
  );
}
