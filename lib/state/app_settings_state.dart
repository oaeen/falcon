import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kThemeModeKey = 'falcon.ui.theme_mode';
const String _kLocaleKey = 'falcon.ui.locale';

@immutable
class AppPreferences {
  const AppPreferences({
    this.themeMode = ThemeMode.system,
    this.locale = const Locale('zh'),
  });

  final ThemeMode themeMode;
  final Locale locale;

  AppPreferences copyWith({
    ThemeMode? themeMode,
    Locale? locale,
  }) {
    return AppPreferences(
      themeMode: themeMode ?? this.themeMode,
      locale: locale ?? this.locale,
    );
  }
}

class AppPreferencesNotifier extends Notifier<AppPreferences> {
  @override
  AppPreferences build() {
    _load();
    return const AppPreferences();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final themeRaw = prefs.getString(_kThemeModeKey);
      final localeRaw = prefs.getString(_kLocaleKey);
      final themeMode = switch (themeRaw) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
      final locale = switch (localeRaw) {
        'en' => const Locale('en'),
        _ => const Locale('zh'),
      };
      state = AppPreferences(themeMode: themeMode, locale: locale);
    } catch (_) {
      // Ignore SharedPreferences errors in isolated test harnesses.
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };
      await prefs.setString(_kThemeModeKey, raw);
    } catch (_) {}
  }

  Future<void> setLocale(Locale locale) async {
    state = state.copyWith(locale: locale);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLocaleKey, locale.languageCode);
    } catch (_) {}
  }
}

final appPreferencesProvider =
    NotifierProvider<AppPreferencesNotifier, AppPreferences>(
  AppPreferencesNotifier.new,
);
