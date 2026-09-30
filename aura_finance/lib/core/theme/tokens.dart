import 'package:flutter/material.dart';

/// Design tokens diturunkan dari referensi "Aura".
/// Satu sumber kebenaran untuk warna, radius, jarak, dan tipografi.
@immutable
class AuraPalette {
  const AuraPalette({
    required this.brightness,
    required this.surface,
    required this.surfaceLow,
    required this.surfaceContainer,
    required this.surfaceHigh,
    required this.surfaceLowest,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.outline,
    required this.outlineVariant,
    required this.primary,
    required this.primaryContainer,
    required this.primaryFixed,
    required this.onPrimaryFixed,
    required this.secondary,
    required this.secondaryContainer,
    required this.secondaryFixed,
    required this.tertiary,
    required this.tertiaryContainer,
    required this.tertiaryFixed,
    required this.onTertiaryFixed,
    required this.error,
    required this.shadowLight,
    required this.shadowDark,
  });

  final Brightness brightness;
  final Color surface;
  final Color surfaceLow;
  final Color surfaceContainer;
  final Color surfaceHigh;
  final Color surfaceLowest;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color outline;
  final Color outlineVariant;
  final Color primary;
  final Color primaryContainer;
  final Color primaryFixed;
  final Color onPrimaryFixed;
  final Color secondary;
  final Color secondaryContainer;
  final Color secondaryFixed;
  final Color tertiary;
  final Color tertiaryContainer;
  final Color tertiaryFixed;
  final Color onTertiaryFixed;
  final Color error;

  /// Pasangan bayangan neumorph: sorotan kiri-atas & bayangan kanan-bawah.
  final Color shadowLight;
  final Color shadowDark;

  bool get isDark => brightness == Brightness.dark;

  /// Warna semantik uang.
  Color get income => tertiary;
  Color get expense => secondary;

  static const light = AuraPalette(
    brightness: Brightness.light,
    surface: Color(0xFFFFF8F7),
    surfaceLow: Color(0xFFFBF1F1),
    surfaceContainer: Color(0xFFF6ECEC),
    surfaceHigh: Color(0xFFF0E6E6),
    surfaceLowest: Color(0xFFFFFFFF),
    onSurface: Color(0xFF1F1A1B),
    onSurfaceVariant: Color(0xFF574147),
    outline: Color(0xFF8A7077),
    outlineVariant: Color(0xFFDDBFC7),
    primary: Color(0xFFAF2365),
    primaryContainer: Color(0xFFFE64A3),
    primaryFixed: Color(0xFFFFD9E3),
    onPrimaryFixed: Color(0xFF3E001F),
    secondary: Color(0xFF8C4C4A),
    secondaryContainer: Color(0xFFFEACA8),
    secondaryFixed: Color(0xFFFFDAD8),
    tertiary: Color(0xFF5A6245),
    tertiaryContainer: Color(0xFF979F7E),
    tertiaryFixed: Color(0xFFDEE6C2),
    onTertiaryFixed: Color(0xFF181E07),
    error: Color(0xFFBA1A1A),
    shadowLight: Color(0xD9FFFFFF),
    shadowDark: Color(0x66B4A0A5),
  );

  /// Mode gelap: plum hangat, bukan hitam pekat, agar neumorph tetap terbaca.
  static const dark = AuraPalette(
    brightness: Brightness.dark,
    surface: Color(0xFF221C1E),
    surfaceLow: Color(0xFF261F21),
    surfaceContainer: Color(0xFF2A2325),
    surfaceHigh: Color(0xFF30282A),
    surfaceLowest: Color(0xFF1C1718),
    onSurface: Color(0xFFF1E4E6),
    onSurfaceVariant: Color(0xFFD5BEC4),
    outline: Color(0xFF9F8990),
    outlineVariant: Color(0xFF574147),
    primary: Color(0xFFFFB0C9),
    primaryContainer: Color(0xFFFE64A3),
    primaryFixed: Color(0xFF5C1236),
    onPrimaryFixed: Color(0xFFFFD9E3),
    secondary: Color(0xFFFFB3B0),
    secondaryContainer: Color(0xFF703534),
    secondaryFixed: Color(0xFF4A2120),
    tertiary: Color(0xFFC2CAA7),
    tertiaryContainer: Color(0xFF979F7E),
    tertiaryFixed: Color(0xFF3A4128),
    onTertiaryFixed: Color(0xFFDEE6C2),
    error: Color(0xFFFFB4AB),
    shadowLight: Color(0x14FFFFFF),
    shadowDark: Color(0x99000000),
  );
}

abstract final class AuraSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const margin = 20.0;
}

abstract final class AuraRadius {
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const pill = 999.0;
}

/// Skala tipografi Plus Jakarta Sans dari referensi.
abstract final class AuraType {
  static const displayLg = TextStyle(fontSize: 40, height: 48 / 40, letterSpacing: -1.2, fontWeight: FontWeight.w700);
  static const currency = TextStyle(fontSize: 36, height: 44 / 36, letterSpacing: -1.08, fontWeight: FontWeight.w700);
  static const headlineLg = TextStyle(fontSize: 28, height: 36 / 28, letterSpacing: -0.56, fontWeight: FontWeight.w700);
  static const headlineMd = TextStyle(fontSize: 22, height: 30 / 22, letterSpacing: -0.33, fontWeight: FontWeight.w600);
  static const headlineSm = TextStyle(fontSize: 18, height: 26 / 18, letterSpacing: -0.18, fontWeight: FontWeight.w600);
  static const bodyLg = TextStyle(fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w500);
  static const bodyMd = TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w400);
  static const bodySm = TextStyle(fontSize: 12, height: 18 / 12, fontWeight: FontWeight.w400);
  static const labelLg = TextStyle(fontSize: 14, height: 20 / 14, letterSpacing: 0.14, fontWeight: FontWeight.w600);
  static const labelMd = TextStyle(fontSize: 12, height: 16 / 12, letterSpacing: 0.24, fontWeight: FontWeight.w600);
  static const labelSm = TextStyle(fontSize: 10, height: 14 / 10, letterSpacing: 0.5, fontWeight: FontWeight.w700);
}
