import 'package:flutter/material.dart';

class AppTheme {
  // Colors
  static const Color primary = Color(0xFFFF6B35);
  static const Color secondary = Color(0xFF4ECDC4);
  static const Color background = Color(0xFFF8F9FA);
  static const Color surface = Colors.white;
  static const Color textPrimary = Color(0xFF2D3436);
  static const Color textSecondary = Color(0xFF636E72);
  static const Color divider = Color(0xFFE9ECEF);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFFFF6B35), Color(0xFFFF8E53)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient waveformGradient = LinearGradient(
    colors: [Color(0xFFFF6B35), Color(0xFFFFB347)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  // Text Styles
  static const TextStyle heading1 = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.bold,
    color: textPrimary,
  );

  static const TextStyle heading2 = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  static const TextStyle body = TextStyle(
    fontSize: 16,
    color: textPrimary,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 14,
    color: textSecondary,
  );

  // Decorations
  static BoxDecoration cardDecoration = BoxDecoration(
    color: surface,
    borderRadius: BorderRadius.circular(16),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.05),
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
    ],
  );

  static BoxDecoration gradientButtonDecoration = BoxDecoration(
    gradient: primaryGradient,
    borderRadius: BorderRadius.circular(30),
    boxShadow: [
      BoxShadow(
        color: primary.withOpacity(0.3),
        blurRadius: 15,
        offset: const Offset(0, 6),
      ),
    ],
  );

  // Theme Data
  static ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: background,
    colorScheme: ColorScheme.light(
      primary: primary,
      secondary: secondary,
      surface: surface,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: background,
      elevation: 0,
      iconTheme: IconThemeData(color: textPrimary),
      titleTextStyle: heading2,
    ),
  );
}
