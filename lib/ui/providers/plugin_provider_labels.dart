import '../../data/admin_models.dart';
import '../../l10n/gen/app_localizations.dart';

/// Orders provider entries within multi-edition plugins (e.g., keeping
/// WorkBuddy domestic `workbuddy` before international `workbuddy-ai`).
List<PluginProviderDetail> sortPluginProviderDetails(
  List<PluginProviderDetail> details,
) {
  final list = [...details];
  int rank(String id) {
    switch (id) {
      case 'workbuddy':
        return 0;
      case 'workbuddy-ai':
        return 1;
      default:
        return 2;
    }
  }

  list.sort((a, b) => rank(a.id).compareTo(rank(b.id)));
  return list;
}

/// Returns crisp localized edition labels for known multi-region plugin
/// providers while preserving unknown provider names verbatim.
String localizedPluginProviderTitle(
  AppLocalizations l10n,
  PluginProviderDetail detail,
) {
  switch (detail.id) {
    case 'workbuddy':
      return l10n.pluginsEditionWorkbuddyCn;
    case 'workbuddy-ai':
      return l10n.pluginsEditionWorkbuddyIntl;
    default:
      return detail.name.isNotEmpty ? detail.name : detail.id;
  }
}

/// Maps verbose or raw English plugin auth method labels into concise
/// localized strings while preserving unknown plugin labels intact.
String localizedPluginAuthMethodLabel(
  AppLocalizations l10n,
  PluginAuthMethod method,
) {
  final raw = method.label.trim();
  final lower = raw.toLowerCase();
  if (lower.contains('api key') || lower.contains('api_key')) {
    return l10n.pluginsAuthMethodApiKey;
  }
  if (lower.contains('browser') ||
      lower.contains('workbuddy account') ||
      lower.contains('oauth')) {
    return l10n.pluginsAuthMethodBrowser;
  }
  return raw;
}
