import 'package:flutter/material.dart';

/// Standard Material 3 dark theme with small layout helpers.
abstract final class AppTheme {
  static ThemeData dark() {
    return ThemeData.dark(useMaterial3: true).copyWith(
      cardTheme: const CardThemeData(margin: EdgeInsets.zero),
    );
  }

  static TextStyle sectionTitle(BuildContext context) {
    return Theme.of(context).textTheme.titleMedium!.copyWith(
          fontWeight: FontWeight.w600,
        );
  }

  static TextStyle captionMuted(BuildContext context) {
    return Theme.of(context).textTheme.bodySmall!.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
  }
}
