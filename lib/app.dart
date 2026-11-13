import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'l10n/l10n.dart';
import 'state/app_settings_state.dart';
import 'theme/falcon_theme.dart';
import 'ui/home_shell.dart';

class FalconApp extends ConsumerWidget {
  const FalconApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(appPreferencesProvider);
    return MaterialApp(
      onGenerateTitle: (ctx) => ctx.l10n.appName,
      debugShowCheckedModeBanner: false,
      themeMode: prefs.themeMode,
      theme: FalconTheme.light(),
      darkTheme: FalconTheme.dark(),
      locale: prefs.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: const HomeShell(),
    );
  }
}
