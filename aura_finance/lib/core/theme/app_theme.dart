import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'tokens.dart';

/// Membuat [AuraPalette] tersedia lewat `context.aura`.
class AuraThemeExt extends ThemeExtension<AuraThemeExt> {
  const AuraThemeExt(this.palette);
  final AuraPalette palette;

  @override
  AuraThemeExt copyWith({AuraPalette? palette}) => AuraThemeExt(palette ?? this.palette);

  @override
  AuraThemeExt lerp(covariant AuraThemeExt? other, double t) => t < 0.5 ? this : (other ?? this);
}

extension AuraContext on BuildContext {
  AuraPalette get aura => Theme.of(this).extension<AuraThemeExt>()!.palette;
}

abstract final class AppTheme {
  static ThemeData material(AuraPalette p) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: p.brightness,
      scaffoldBackgroundColor: p.surface,
      colorScheme: ColorScheme(
        brightness: p.brightness,
        primary: p.primary,
        onPrimary: p.isDark ? p.onPrimaryFixed : Colors.white,
        secondary: p.secondary,
        onSecondary: Colors.white,
        tertiary: p.tertiary,
        error: p.error,
        onError: Colors.white,
        surface: p.surface,
        onSurface: p.onSurface,
        onSurfaceVariant: p.onSurfaceVariant,
        outline: p.outline,
        outlineVariant: p.outlineVariant,
      ),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      extensions: [AuraThemeExt(p)],
    );
    return base.copyWith(
      textTheme: GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(
        bodyColor: p.onSurface,
        displayColor: p.onSurface,
      ),
    );
  }

  static ShadThemeData shad(AuraPalette p) {
    return ShadThemeData(
      brightness: p.brightness,
      radius: BorderRadius.circular(AuraRadius.md),
      textTheme: ShadTextTheme.fromGoogleFont(GoogleFonts.plusJakartaSans),
      colorScheme: ShadColorScheme(
        background: p.surface,
        foreground: p.onSurface,
        card: p.surfaceLow,
        cardForeground: p.onSurface,
        popover: p.surfaceLow,
        popoverForeground: p.onSurface,
        primary: p.primary,
        primaryForeground: p.isDark ? p.onPrimaryFixed : Colors.white,
        secondary: p.surfaceContainer,
        secondaryForeground: p.onSurface,
        muted: p.surfaceHigh,
        mutedForeground: p.onSurfaceVariant,
        accent: p.primaryFixed,
        accentForeground: p.onPrimaryFixed,
        destructive: p.error,
        destructiveForeground: Colors.white,
        border: p.outlineVariant.withValues(alpha: 0.6),
        input: p.outlineVariant,
        ring: p.primaryContainer,
        selection: p.primaryContainer.withValues(alpha: 0.3),
      ),
    );
  }
}
