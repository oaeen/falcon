import 'package:flutter/widgets.dart';

import 'gen/app_localizations.dart';

export 'gen/app_localizations.dart';

extension FalconL10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;
}
