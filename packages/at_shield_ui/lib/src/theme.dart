import 'package:flutter/material.dart';

/// Tokens alinhados ao protótipo HTML A.T. Shield (screenshots → hex).
class AtShieldColors {
  static const bg = Color(0xFF0D0D0D);
  static const surface = Color(0xFF1A1A1A);
  static const surface2 = Color(0xFF222222);
  static const modalFoot = Color(0xFF161616);
  static const border = Color(0xFF333333);
  static const borderSubtle = Color(0xA6333333);
  static const text = Color(0xFFF4F4F5);
  static const muted = Color(0xFF9A9A9A);
  static const accent = Color(0xFFE51E25);
  static const accentDim = Color(0xFF3D1518);
  static const success = Color(0xFF3DCF6A);
  static const warn = Color(0xFFEAB308);
  static const danger = Color(0xFFE51E25);
  static const sidebar = Color(0xFF0A0A0A);
  static const overlay = Color(0x8C000000);
}

class AtShieldTheme {
  static const radius = 8.0;
  static const radiusSm = 6.0;
  static const modalRadius = 10.0;

  static const mono = TextStyle(
    fontFamily: 'Consolas',
    fontFamilyFallback: [
      'Cascadia Mono',
      'SF Mono',
      'Menlo',
      'monospace',
    ],
  );

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      surface: AtShieldColors.surface,
      primary: AtShieldColors.accent,
      onPrimary: Colors.white,
      secondary: AtShieldColors.accentDim,
      onSurface: AtShieldColors.text,
      outline: AtShieldColors.border,
      error: AtShieldColors.danger,
      // trava Material 3 pra não vazar lilás/indigo nos chips/switches
      tertiary: AtShieldColors.accent,
      onTertiary: Colors.white,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AtShieldColors.bg,
      // ponytail: sem asset de IBM Plex — Segoe/SF/Ubuntu cobrem Win/Mac/Linux
      fontFamily: 'Segoe UI',
      fontFamilyFallback: const [
        'SF Pro Text',
        'Ubuntu',
        'Noto Sans',
        'sans-serif',
      ],
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.02,
          height: 1.15,
          color: AtShieldColors.text,
        ),
        titleMedium: TextStyle(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.01,
          color: AtShieldColors.text,
        ),
        bodyMedium: TextStyle(
          color: AtShieldColors.text,
          height: 1.5,
          fontWeight: FontWeight.w400,
        ),
        bodySmall: TextStyle(
          color: AtShieldColors.muted,
          letterSpacing: 0.01,
          height: 1.5,
        ),
        labelSmall: TextStyle(
          color: AtShieldColors.muted,
          letterSpacing: 0.08,
          fontWeight: FontWeight.w600,
          fontSize: 10,
        ),
      ),
      dividerColor: AtShieldColors.border,
      cardTheme: CardThemeData(
        color: AtShieldColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: AtShieldColors.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AtShieldColors.surface,
        barrierColor: AtShieldColors.overlay,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(modalRadius),
          side: const BorderSide(color: AtShieldColors.border),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AtShieldColors.surface2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          side: const BorderSide(color: AtShieldColors.border),
        ),
        textStyle: const TextStyle(
          color: AtShieldColors.text,
          fontSize: 13,
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AtShieldColors.surface2,
        contentTextStyle: TextStyle(color: AtShieldColors.text),
        behavior: SnackBarBehavior.floating,
      ),
      iconTheme: const IconThemeData(
        color: AtShieldColors.muted,
        size: 18,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AtShieldColors.accent;
          }
          return AtShieldColors.surface2;
        }),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        side: const BorderSide(color: AtShieldColors.border),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AtShieldColors.accent;
          }
          return AtShieldColors.muted;
        }),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AtShieldColors.surface,
        selectedColor: AtShieldColors.accentDim,
        disabledColor: AtShieldColors.surface2,
        labelStyle: const TextStyle(
          color: AtShieldColors.muted,
          fontSize: 12,
          fontFamily: 'Consolas',
        ),
        secondaryLabelStyle: const TextStyle(
          color: AtShieldColors.text,
          fontSize: 12,
        ),
        side: const BorderSide(color: AtShieldColors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        showCheckmark: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AtShieldColors.bg,
        hintStyle: const TextStyle(color: AtShieldColors.muted, fontSize: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: AtShieldColors.borderSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: AtShieldColors.borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: BorderSide(
            color: Color.lerp(
                  AtShieldColors.accent,
                  AtShieldColors.border,
                  0.55,
                ) ??
                AtShieldColors.accent,
            width: 1,
          ),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        isDense: true,
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor:
              const WidgetStatePropertyAll(AtShieldColors.surface2),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusSm),
              side: const BorderSide(color: AtShieldColors.border),
            ),
          ),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AtShieldColors.accent,
        circularTrackColor: AtShieldColors.border,
      ),
    );
  }
}
