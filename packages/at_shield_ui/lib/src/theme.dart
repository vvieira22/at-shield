import 'package:flutter/material.dart';

/// Dark charcoal + strategic red. Not Inter, not purple-AI defaults.
class AtShieldColors {
  static const bg = Color(0xFF0C0C0E);
  static const surface = Color(0xFF141417);
  static const surface2 = Color(0xFF1A1A1F);
  static const border = Color(0xFF2A2A32);
  static const text = Color(0xFFF4F4F5);
  static const muted = Color(0xFFA1A1AA);
  static const accent = Color(0xFFE11D2E);
  static const accentDim = Color(0xFF8B121C);
  static const success = Color(0xFF22C55E);
  static const sidebar = Color(0xFF0A0A0C);
}

class AtShieldTheme {
  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      surface: AtShieldColors.surface,
      primary: AtShieldColors.accent,
      onPrimary: Colors.white,
      secondary: AtShieldColors.accentDim,
      onSurface: AtShieldColors.text,
      outline: AtShieldColors.border,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AtShieldColors.bg,
      fontFamily: 'Segoe UI',
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.4,
          color: AtShieldColors.text,
        ),
        titleMedium: TextStyle(
          fontWeight: FontWeight.w600,
          color: AtShieldColors.text,
        ),
        bodyMedium: TextStyle(color: AtShieldColors.text, height: 1.35),
        bodySmall: TextStyle(color: AtShieldColors.muted),
        labelSmall: TextStyle(
          color: AtShieldColors.muted,
          letterSpacing: 0.12,
          fontWeight: FontWeight.w600,
        ),
      ),
      dividerColor: AtShieldColors.border,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AtShieldColors.surface2,
        hintStyle: const TextStyle(color: AtShieldColors.muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AtShieldColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AtShieldColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AtShieldColors.accent),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}
