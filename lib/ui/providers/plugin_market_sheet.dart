import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/admin_models.dart';
import '../../l10n/l10n.dart';
import '../../state/gateway_state.dart';
import '../../theme/falcon_theme.dart';
import '../widgets/falcon_card.dart';
import '../widgets/falcon_row.dart';
import '../widgets/sheet_frame.dart';
import '../widgets/status_pill.dart';

class PluginMarketSheet extends ConsumerStatefulWidget {
  const PluginMarketSheet({super.key});

  @override
  ConsumerState<PluginMarketSheet> createState() => _PluginMarketSheetState();
}

class _PluginMarketSheetState extends ConsumerState<PluginMarketSheet> {
  final _searchCtrl = TextEditingController();
  final _customSpecCtrl = TextEditingController();
  String _query = '';
  String _category = 'all';
  final Set<String> _busyPackages = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    _customSpecCtrl.dispose();
    super.dispose();
  }

  Future<void> _install(String spec) async {
    final trimmed = spec.trim();
    if (trimmed.isEmpty) return;
    final client = ref.read(adminApiClientProvider);
    if (client == null) return;
    setState(() => _busyPackages.add(trimmed));
    try {
      await client.installPlugin(trimmed);
      _customSpecCtrl.clear();
      ref.invalidate(pluginMarketProvider);
      await ref.read(gatewayAdminStateProvider.notifier).reload();
    } finally {
      if (mounted) setState(() => _busyPackages.remove(trimmed));
    }
  }

  Future<void> _remove(String spec) async {
    final client = ref.read(adminApiClientProvider);
    if (client == null) return;
    setState(() => _busyPackages.add(spec));
    try {
      await client.removePlugin(spec);
      ref.invalidate(pluginMarketProvider);
      await ref.read(gatewayAdminStateProvider.notifier).reload();
    } finally {
      if (mounted) setState(() => _busyPackages.remove(spec));
    }
  }

  bool _matches(MarketPlugin p) {
    if (_category == 'auth' && p.category == 'middleware') return false;
    if (_category == 'middleware' && p.category != 'middleware') return false;
    if (_query.trim().isEmpty) return true;
    final q = _query.trim().toLowerCase();
    return p.name.toLowerCase().contains(q) ||
        p.package.toLowerCase().contains(q) ||
        p.summaryZh.toLowerCase().contains(q) ||
        p.summaryEn.toLowerCase().contains(q) ||
        p.providers.any((e) => e.toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = FalconColors.of(context);
    final langCode = Localizations.localeOf(context).languageCode;
    final marketAsync = ref.watch(pluginMarketProvider);
    final settings =
        ref.watch(gatewayAdminStateProvider).value?.settings ??
            const GatewaySettings();

    return FalconSheetFrame(
      title: l10n.pluginsMarketTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: l10n.pluginsMarketSearchHint,
              prefixIcon: const Icon(Icons.search_rounded, size: 19),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      label: Text(l10n.pluginsMarketCategoryAll),
                      selected: _category == 'all',
                      onSelected: (_) => setState(() => _category = 'all'),
                    ),
                    ChoiceChip(
                      label: Text(l10n.pluginsMarketCategoryAuth),
                      selected: _category == 'auth',
                      onSelected: (_) => setState(() => _category = 'auth'),
                    ),
                    ChoiceChip(
                      label: Text(l10n.pluginsMarketCategoryMiddleware),
                      selected: _category == 'middleware',
                      onSelected: (_) =>
                          setState(() => _category = 'middleware'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FalconCard(
            child: FalconRow(
              icon: Icons.public_outlined,
              title: l10n.pluginsMarketChinaMirror,
              trailing: Switch(
                value: settings.chinaMirror,
                onChanged: (v) => ref
                    .read(gatewayAdminStateProvider.notifier)
                    .updateSettings({'chinaMirror': v}),
              ),
            ),
          ),
          const SizedBox(height: 12),
          marketAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text(
              l10n.errorRequestFailed('$e'),
              style: TextStyle(color: c.danger, fontSize: 13),
            ),
            data: (plugins) {
              final filtered = plugins.where(_matches).toList(growable: false);
              return FalconCard(
                child: Column(
                  children: [
                    for (var i = 0; i < filtered.length; i++) ...[
                      if (i > 0) const FalconDivider(indent: 0),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        filtered[i].name,
                                        style: TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w600,
                                          color: c.textPrimary,
                                        ),
                                      ),
                                      if (filtered[i].installed)
                                        StatusPill(
                                          label: l10n.pluginsMarketInstalled,
                                          tone: StatusTone.success,
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    filtered[i].package,
                                    style: FalconTheme.mono(
                                      context,
                                      fontSize: 11.5,
                                      color: c.textMuted,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    filtered[i].localizedSummary(langCode),
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: c.textSecondary,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (_busyPackages.contains(filtered[i].package))
                              const SizedBox(
                                width: 22,
                                height: 22,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            else if (filtered[i].installed)
                              OutlinedButton(
                                onPressed: () =>
                                    _remove(filtered[i].package),
                                child: Text(l10n.pluginsMarketRemove),
                              )
                            else
                              FilledButton(
                                onPressed: () =>
                                    _install(filtered[i].package),
                                child: Text(l10n.pluginsMarketInstall),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customSpecCtrl,
                  decoration: InputDecoration(
                    hintText: l10n.pluginsMarketCustomSpecHint,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => _install(_customSpecCtrl.text),
                child: Text(l10n.pluginsMarketInstall),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
