import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Semantic and surface color tokens for Falcon.
///
/// Restrained engineering palette with 0.5px borders, zero drop shadows,
/// single cobalt accent, and slate dark surfaces (never pure black).
@immutable
class FalconColors extends ThemeExtension<FalconColors> {
  const FalconColors({
    required this.scaffold,
    required this.card,
    required this.cardSubtle,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.accentSoft,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
  });

  final Color scaffold;
  final Color card;
  final Color cardSubtle;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color accent;
  final Color accentSoft;
  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;

  static const light = FalconColors(
    scaffold: Color(0xFFF6F7F9),
    card: Color(0xFFFFFFFF),
    cardSubtle: Color(0xFFF1F3F6),
    border: Color(0xFFE2E5EC),
    textPrimary: Color(0xFF151821),
    textSecondary: Color(0xFF626B7C),
    textMuted: Color(0xFF8A93A4),
    accent: Color(0xFF2563EB),
    accentSoft: Color(0xFFEFF6FF),
    success: Color(0xFF16A34A),
    successSoft: Color(0xFFECFDF3),
    warning: Color(0xFFD97706),
    warningSoft: Color(0xFFFFFBEB),
    danger: Color(0xFFDC2626),
    dangerSoft: Color(0xFFFEF2F2),
  );

  static const dark = FalconColors(
    scaffold: Color(0xFF14171F),
    card: Color(0xFF1C202B),
    cardSubtle: Color(0xFF222735),
    border: Color(0xFF282E3D),
    textPrimary: Color(0xFFE6E9F0),
    textSecondary: Color(0xFF949DB0),
    textMuted: Color(0xFF6B7487),
    accent: Color(0xFF60A5FA),
    accentSoft: Color(0xFF172542),
    success: Color(0xFF16A34A),
    successSoft: Color(0xFF132A1E),
    warning: Color(0xFFD97706),
    warningSoft: Color(0xFF2E2212),
    danger: Color(0xFFDC2626),
    dangerSoft: Color(0xFF33181B),
  );

  static FalconColors of(BuildContext context) =>
      Theme.of(context).extension<FalconColors>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);

  @override
  FalconColors copyWith({
    Color? scaffold,
    Color? card,
    Color? cardSubtle,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? accent,
    Color? accentSoft,
    Color? success,
    Color? successSoft,
    Color? warning,
    Color? warningSoft,
    Color? danger,
    Color? dangerSoft,
  }) {
    return FalconColors(
      scaffold: scaffold ?? this.scaffold,
      card: card ?? this.card,
      cardSubtle: cardSubtle ?? this.cardSubtle,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      success: success ?? this.success,
      successSoft: successSoft ?? this.successSoft,
      warning: warning ?? this.warning,
      warningSoft: warningSoft ?? this.warningSoft,
      danger: danger ?? this.danger,
      dangerSoft: dangerSoft ?? this.dangerSoft,
    );
  }

  @override
  FalconColors lerp(ThemeExtension<FalconColors>? other, double t) {
    if (other is! FalconColors) return this;
    return FalconColors(
      scaffold: Color.lerp(scaffold, other.scaffold, t)!,
      card: Color.lerp(card, other.card, t)!,
      cardSubtle: Color.lerp(cardSubtle, other.cardSubtle, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      success: Color.lerp(success, other.success, t)!,
      successSoft: Color.lerp(successSoft, other.successSoft, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningSoft: Color.lerp(warningSoft, other.warningSoft, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!,
    );
  }
}

abstract final class FalconTheme {
  static const double cardRadius = 12.0;
  static const double borderWidth = 0.5;

  static TextStyle tabular(TextStyle? base) => (base ?? const TextStyle())
      .copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  static TextStyle mono(BuildContext context, {double fontSize = 13, Color? color}) {
    final c = FalconColors.of(context);
    return TextStyle(
      fontFamily: 'monospace',
      fontSize: fontSize,
      height: 1.4,
      color: color ?? c.textPrimary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  static ThemeData light() => _build(Brightness.light, FalconColors.light);

  static ThemeData dark() => _build(Brightness.dark, FalconColors.dark);

  static ThemeData _build(Brightness brightness, FalconColors c) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.accent,
      onPrimary: isDark ? const Color(0xFF0A1424) : Colors.white,
      primaryContainer: c.accentSoft,
      onPrimaryContainer: c.accent,
      secondary: c.textSecondary,
      onSecondary: Colors.white,
      secondaryContainer: c.cardSubtle,
      onSecondaryContainer: c.textPrimary,
      tertiary: c.warning,
      onTertiary: Colors.white,
      tertiaryContainer: c.warningSoft,
      onTertiaryContainer: c.warning,
      error: c.danger,
      onError: Colors.white,
      errorContainer: c.dangerSoft,
      onErrorContainer: c.danger,
      surface: c.card,
      onSurface: c.textPrimary,
      onSurfaceVariant: c.textSecondary,
      surfaceContainerLowest: c.card,
      surfaceContainerLow: c.scaffold,
      surfaceContainer: c.cardSubtle,
      surfaceContainerHigh: c.cardSubtle,
      surfaceContainerHighest: c.border,
      outline: c.border,
      outlineVariant: c.border,
      surfaceTint: Colors.transparent,
    );

    final baseText = ThemeData(brightness: brightness).textTheme.apply(
          bodyColor: c.textPrimary,
          displayColor: c.textPrimary,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.scaffold,
      canvasColor: c.scaffold,
      textTheme: baseText,
      extensions: [c],
      dividerColor: c.border,
      dividerTheme: DividerThemeData(
        color: c.border,
        thickness: borderWidth,
        space: borderWidth,
      ),
      iconTheme: IconThemeData(color: c.textSecondary, size: 20),
      appBarTheme: AppBarTheme(
        backgroundColor: c.scaffold,
        foregroundColor: c.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: baseText.titleLarge?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: c.textPrimary,
        ),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: c.card,
          systemNavigationBarIconBrightness:
              isDark ? Brightness.light : Brightness.dark,
        ),
      ),
      cardTheme: CardThemeData(
        color: c.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(color: c.border, width: borderWidth),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.card,
        elevation: 0,
        height: 64,
        surfaceTintColor: Colors.transparent,
        indicatorColor: c.accentSoft,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: selected ? c.accent : c.textSecondary,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? c.accent : c.textSecondary,
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.cardSubtle,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        hintStyle: TextStyle(color: c.textMuted, fontSize: 14),
        labelStyle: TextStyle(color: c.textSecondary, fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: c.border, width: borderWidth),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: c.border, width: borderWidth),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: c.accent, width: 1.2),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? c.accentSoft
                : c.card;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? c.accent
                : c.textSecondary;
          }),
          side: WidgetStatePropertyAll(
            BorderSide(color: c.border, width: borderWidth),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          visualDensity: VisualDensity.compact,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return isDark ? const Color(0xFF0A1424) : Colors.white;
          }
          return c.textMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return c.accent;
          return c.cardSubtle;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.transparent;
          }
          return c.border;
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.accent,
          foregroundColor: isDark ? const Color(0xFF0A1424) : Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.textPrimary,
          side: BorderSide(color: c.border, width: borderWidth),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.accent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? c.cardSubtle : c.textPrimary,
        contentTextStyle: TextStyle(
          color: isDark ? c.textPrimary : Colors.white,
          fontSize: 13,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.card,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(color: c.border, width: borderWidth),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.card,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
    );
  }
}
