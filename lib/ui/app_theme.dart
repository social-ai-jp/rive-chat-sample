import 'package:flutter/material.dart';

import 'app_palette.dart';

class AppTheme {
  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppPalette.primaryAccent,
      brightness: Brightness.light,
      primary: AppPalette.primaryAccent,
      secondary: AppPalette.secondaryAccent,
      surface: AppPalette.pinkWhite,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: Colors.transparent,
      fontFamily: 'Andika',
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: AppPalette.navyBlack,
      ),
      dividerColor: AppPalette.navyBlack.withValues(alpha: 0.12),
      textTheme: base.textTheme.apply(
        bodyColor: AppPalette.navyBlack,
        displayColor: AppPalette.navyBlack,
      ),
    );
  }
}

