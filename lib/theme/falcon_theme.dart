import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Material 3 Expressive semantic and surface color tokens for Falcon.
///
/// Tactile depth via clean tonal surface steps and crisp 1dp structural
/// outlines, deep cobalt primary + warm falcon amber accent, never pure black.
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
    required this.warm,
    required this.warmSoft,
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
  final Color warm;
  final Color warmSoft;
  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;

  static const light = FalconColors(
    scaffold: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    cardSubtle: Color(0xFFF5F6F8),
    border: Color(0xFFE5E7EB),
    textPrimary: Color(0xFF131824),
    textSecondary: Color(0xFF525D73),
    textMuted: Color(0xFF7D889E),
    accent: Color(0xFF2457C5),
    accentSoft: Color(0xFFD6E2FA),
    warm: Color(0xFFE28A1A),
    warmSoft: Color(0xFFFFF3DC),
    success: Color(0xFF15803D),
    successSoft: Color(0xFFDCFCE7),
    warning: Color(0xFFD97706),
    warningSoft: Color(0xFFFEF3C7),
    danger: Color(0xFFDC2626),
    dangerSoft: Color(0xFFFEE2E2),
  );

  static const dark = FalconColors(
    scaffold: Color(0xFF0E131D),
    card: Color(0xFF161D2B),
    cardSubtle: Color(0xFF1E2738),
    border: Color(0xFF283247),
    textPrimary: Color(0xFFEAF0FA),
    textSecondary: Color(0xFF9BA6BD),
    textMuted: Color(0xFF6E7B94),
    accent: Color(0xFF9BBCFF),
    accentSoft: Color(0xFF1B2D52),
    warm: Color(0xFFFFBA63),
    warmSoft: Color(0xFF352612),
    success: Color(0xFF4ADE80),
    successSoft: Color(0xFF132D20),
    warning: Color(0xFFFBBF24),
    warningSoft: Color(0xFF2F2310),
    danger: Color(0xFFF87171),
    dangerSoft: Color(0xFF35181C),
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
    Color? warm,
    Color? warmSoft,
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
      warm: warm ?? this.warm,
      warmSoft: warmSoft ?? this.warmSoft,
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
      warm: Color.lerp(warm, other.warm, t)!,
      warmSoft: Color.lerp(warmSoft, other.warmSoft, t)!,
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
  static const double cardRadius = 16.0;
  static const double heroRadius = 16.0;
  static const double sheetRadius = 24.0;
  static const double inputRadius = 12.0;
  static const double pillRadius = 10.0;
  static const double borderWidth = 1.0;

  static TextStyle tabular(TextStyle? base) => (base ?? const TextStyle())
      .copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  static TextStyle mono(
    BuildContext context, {
    double fontSize = 13,
    Color? color,
  }) {
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
    final onPrimary = isDark ? const Color(0xFF0A1B3D) : Colors.white;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.accent,
      onPrimary: onPrimary,
      primaryContainer: c.accentSoft,
      onPrimaryContainer: isDark ? const Color(0xFFD6E2FA) : c.accent,
      secondary: c.textSecondary,
      onSecondary: isDark ? c.scaffold : Colors.white,
      secondaryContainer: c.accentSoft,
      onSecondaryContainer: isDark ? const Color(0xFFD6E2FA) : c.accent,
      tertiary: c.warm,
      onTertiary: isDark ? const Color(0xFF281800) : Colors.white,
      tertiaryContainer: c.warmSoft,
      onTertiaryContainer: c.warm,
      error: c.danger,
      onError: isDark ? const Color(0xFF2F0808) : Colors.white,
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
    final expressiveText = baseText.copyWith(
      headlineSmall: baseText.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: c.textPrimary,
      ),
      titleLarge: baseText.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: c.textPrimary,
      ),
      titleMedium: baseText.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: c.textPrimary,
      ),
      bodyMedium: baseText.bodyMedium?.copyWith(
        height: 1.4,
        color: c.textPrimary,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.scaffold,
      canvasColor: c.scaffold,
      textTheme: expressiveText,
      extensions: [c],
      dividerColor: c.border,
      dividerTheme: DividerThemeData(
        color: c.border,
        thickness: borderWidth,
        space: borderWidth,
      ),
      iconTheme: IconThemeData(color: c.textSecondary, size: 20),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          minimumSize: const Size(36, 36),
          padding: const EdgeInsets.all(8),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.scaffold,
        foregroundColor: c.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: expressiveText.titleLarge,
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
        height: 62,
        surfaceTintColor: Colors.transparent,
        indicatorColor: c.accentSoft,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: selected
                ? (isDark ? c.textPrimary : c.accent)
                : c.textSecondary,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected
                ? (isDark ? c.textPrimary : c.accent)
                : c.textSecondary,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: c.card,
        elevation: 0,
        indicatorColor: c.accentSoft,
        indicatorShape: const StadiumBorder(),
        selectedIconTheme: IconThemeData(
          size: 22,
          color: isDark ? c.textPrimary : c.accent,
        ),
        unselectedIconTheme: IconThemeData(size: 22, color: c.textSecondary),
        selectedLabelTextStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: isDark ? c.textPrimary : c.accent,
        ),
        unselectedLabelTextStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: c.textSecondary,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.cardSubtle,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 11,
        ),
        hintStyle: TextStyle(color: c.textMuted, fontSize: 13.5),
        labelStyle: TextStyle(color: c.textSecondary, fontSize: 13),
        floatingLabelStyle: TextStyle(color: c.textSecondary, fontSize: 12),
        border: UnderlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: UnderlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide.none,
        ),
        disabledBorder: UnderlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide.none,
        ),
        focusedBorder: UnderlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide.none,
        ),
        errorBorder: UnderlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide(color: c.danger, width: 1.2),
        ),
        focusedErrorBorder: UnderlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide(color: c.danger, width: 1.2),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? c.cardSubtle
                : c.card;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? c.textPrimary
                : c.textSecondary;
          }),
          textStyle: WidgetStateProperty.resolveWith((states) {
            return TextStyle(
              fontSize: 13,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w600
                  : FontWeight.w500,
            );
          }),
          side: WidgetStatePropertyAll(
            BorderSide(color: c.border, width: borderWidth),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(pillRadius),
            ),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        thumbIcon: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Icon(Icons.check_rounded, size: 14, color: c.accent);
          }
          return Icon(Icons.close_rounded, size: 12, color: c.card);
        }),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return isDark ? c.scaffold : Colors.white;
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
          elevation: 0,
          minimumSize: const Size(0, 40),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(pillRadius),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13.5,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.textPrimary,
          minimumSize: const Size(0, 38),
          side: BorderSide(color: c.border, width: borderWidth),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(pillRadius),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.accent,
          minimumSize: const Size(0, 34),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        side: BorderSide.none,
        backgroundColor: c.cardSubtle,
        selectedColor: c.accentSoft,
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        labelPadding: const EdgeInsets.symmetric(horizontal: 2),
        labelStyle: TextStyle(fontSize: 12.5, color: c.textPrimary),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? c.cardSubtle : c.textPrimary,
        contentTextStyle: TextStyle(
          color: isDark ? c.textPrimary : Colors.white,
          fontSize: 13,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(sheetRadius)),
        ),
      ),
    );
  }
}
