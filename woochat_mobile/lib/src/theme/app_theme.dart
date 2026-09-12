import 'package:flutter/material.dart';

import 'wa_colors.dart';

/// The app's single theme: WhatsApp dark, built from the [Wa] palette.
///
/// There is no light theme. The app used to hand Flutter a seed colour and
/// follow the system setting, which on a light-mode machine left dialogs,
/// pickers, snackbars, progress spinners and selection handles in Material's
/// default blues while the screens around them were hand-painted dark. Every
/// Material component is now told its colour here, so nothing falls back.
class AppTheme {
  const AppTheme._();

  /// Bubble colour for a message the tenant sent.
  static const Color outgoingBubbleDark = Wa.outboundBubble;

  static ThemeData dark() => _whatsappDark;

  /// Kept so existing call sites compile; there is only the one theme.
  static ThemeData light() => _whatsappDark;

  /// Bubble colour for a message the tenant sent.
  static Color outgoingBubble(BuildContext context) => Wa.outboundBubble;

  static final ThemeData _whatsappDark = _build();

  static ThemeData _build() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: Wa.accent,
      onPrimary: Colors.white,
      secondary: Wa.accent,
      onSecondary: Colors.white,
      surface: Wa.background,
      onSurface: Wa.title,
      error: Wa.error,
      onError: Wa.background,
      // Material 3 tonal surfaces, mapped onto the palette's panels.
      surfaceContainerLowest: Wa.chatBackground,
      surfaceContainerLow: Wa.background,
      surfaceContainer: Wa.header,
      surfaceContainerHigh: Wa.menu,
      surfaceContainerHighest: Wa.input,
      onSurfaceVariant: Wa.secondaryText,
      outline: Wa.border,
      outlineVariant: Wa.border,
      inverseSurface: Wa.title,
      onInverseSurface: Wa.background,
      inversePrimary: Wa.accent,
      surfaceTint: Colors.transparent,
    );

    const bodyText = TextStyle(color: Wa.title);
    const mutedText = TextStyle(color: Wa.secondaryText);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: Wa.background,
      canvasColor: Wa.background,
      cardColor: Wa.header,
      dividerColor: Wa.border,
      hintColor: Wa.secondaryText,
      splashColor: Wa.accent.withValues(alpha: 0.12),
      highlightColor: Wa.menuHover,
      hoverColor: Wa.menuHover,
      focusColor: Wa.accent.withValues(alpha: 0.16),

      appBarTheme: const AppBarTheme(
        backgroundColor: Wa.header,
        foregroundColor: Wa.title,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: Wa.icon),
        actionsIconTheme: IconThemeData(color: Wa.icon),
        titleTextStyle: TextStyle(
          color: Wa.title,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),

      iconTheme: const IconThemeData(color: Wa.icon),
      primaryIconTheme: const IconThemeData(color: Wa.icon),

      textTheme: const TextTheme(
        displayLarge: bodyText,
        displayMedium: bodyText,
        displaySmall: bodyText,
        headlineLarge: bodyText,
        headlineMedium: bodyText,
        headlineSmall: bodyText,
        titleLarge: bodyText,
        titleMedium: bodyText,
        titleSmall: bodyText,
        bodyLarge: bodyText,
        bodyMedium: bodyText,
        bodySmall: mutedText,
        labelLarge: bodyText,
        labelMedium: mutedText,
        labelSmall: mutedText,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Wa.input,
        hintStyle: mutedText,
        labelStyle: mutedText,
        prefixIconColor: Wa.icon,
        suffixIconColor: Wa.icon,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Wa.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Wa.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Wa.accent),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Wa.error),
        ),
      ),

      textSelectionTheme: TextSelectionThemeData(
        cursorColor: Wa.accent,
        selectionColor: Wa.accent.withValues(alpha: 0.35),
        selectionHandleColor: Wa.accent,
      ),

      // Full width: the login and Create Admin buttons rely on it. A button
      // in a Row must set its own minimumSize (see the schedule sheet).
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: Wa.accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Wa.accent.withValues(alpha: 0.4),
          disabledForegroundColor: Colors.white70,
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Wa.accent,
          foregroundColor: Colors.white,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: Wa.accent),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Wa.accent,
          side: const BorderSide(color: Wa.border),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: Wa.icon),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Wa.accent,
        foregroundColor: Colors.white,
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: Wa.menu,
        surfaceTintColor: Colors.transparent,
        textStyle: bodyText,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Wa.menu,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: const TextStyle(
          color: Wa.title,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: mutedText.copyWith(fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Wa.sheet,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: Wa.sheet,
        dragHandleColor: Wa.secondaryText,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: Wa.menu,
        contentTextStyle: bodyText,
        actionTextColor: Wa.accent,
        behavior: SnackBarBehavior.floating,
      ),
      datePickerTheme: const DatePickerThemeData(
        backgroundColor: Wa.menu,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: Wa.header,
        headerForegroundColor: Wa.title,
      ),
      timePickerTheme: const TimePickerThemeData(
        backgroundColor: Wa.menu,
        dialBackgroundColor: Wa.input,
        hourMinuteColor: Wa.input,
        hourMinuteTextColor: Wa.title,
        dialHandColor: Wa.accent,
        dialTextColor: Wa.title,
        entryModeIconColor: Wa.icon,
      ),

      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Wa.header,
        selectedItemColor: Wa.accent,
        unselectedItemColor: Wa.icon,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Wa.header,
        indicatorColor: Wa.accent.withValues(alpha: 0.2),
        surfaceTintColor: Colors.transparent,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: Wa.accent,
        unselectedLabelColor: Wa.secondaryText,
        indicatorColor: Wa.accent,
        dividerColor: Wa.border,
      ),

      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        textColor: Wa.title,
        iconColor: Wa.icon,
      ),
      dividerTheme: const DividerThemeData(color: Wa.border, thickness: 0.5),
      chipTheme: ChipThemeData(
        backgroundColor: Wa.input,
        selectedColor: Wa.accent,
        labelStyle: bodyText,
        side: BorderSide.none,
        shape: const StadiumBorder(),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: Wa.accent,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? Wa.accent : Wa.input,
        ),
        checkColor: const WidgetStatePropertyAll(Colors.white),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? Wa.accent : Wa.icon,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Wa.accent.withValues(alpha: 0.4)
              : Wa.input,
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? Wa.accent : Wa.icon,
        ),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: Wa.accent,
        thumbColor: Wa.accent,
        inactiveTrackColor: Wa.input,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: Wa.menu,
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: bodyText.copyWith(fontSize: 12),
      ),
    );
  }
}
