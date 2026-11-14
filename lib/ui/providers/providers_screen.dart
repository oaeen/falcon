import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/admin_models.dart';
import '../../l10n/l10n.dart';
import '../../state/gateway_state.dart';
import '../../theme/falcon_theme.dart';
import '../monitor/playground_sheet.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/falcon_card.dart';
import '../widgets/falcon_row.dart';
import '../widgets/gateway_offline_banner.dart';
import '../widgets/responsive_body.dart';
import '../widgets/segmented_track.dart';
import '../widgets/sheet_frame.dart';
import 'plugin_market_sheet.dart';
import 'plugin_models_sheet.dart';
import 'plugin_provider_labels.dart';
import 'plugin_signin_sheet.dart';
import 'provider_editor_sheet.dart';

enum _ProvidersSegment { api, plugins }

class ProvidersScreen extends ConsumerStatefulWidget {
  const ProvidersScreen({super.key});

  @override
  ConsumerState<ProvidersScreen> createState() => _ProvidersScreenState();
}

class _ProvidersScreenState extends ConsumerState<ProvidersScreen> {
  _ProvidersSegment _segment = _ProvidersSegment.api;
  bool _userSwitchedSegment = false;
  final Set<String> _testingIds = {};
  final Set<String> _refreshingPlugins = {};

  Future<void> _testProvider(UpstreamProvider provider) async {
    final client = ref.read(adminApiClientProvider);
    if (client == null) return;
    setState(() => _testingIds.add(provider.id));
    try {
      await client.testProvider(provider.id);
      await ref.read(gatewayAdminStateProvider.notifier).reload();
    } finally {
      if (mounted) setState(() => _testingIds.remove(provider.id));
    }
  }

  Future<void> _refreshPlugin(InstalledPlugin plugin) async {
    final client = ref.read(adminApiClientProvider);
    if (client == null) return;
    setState(() => _refreshingPlugins.add(plugin.id));
    try {
      await client.refreshPlugins(pluginId: plugin.id);
      await ref.read(gatewayAdminStateProvider.notifier).reload();
    } finally {
      if (mounted) setState(() => _refreshingPlugins.remove(plugin.id));
    }
  }

  Future<void> _checkin(PluginAccount account) async {
    final client = ref.read(adminApiClientProvider);
    if (client == null) return;
    final res = await client.checkinPluginAccount(account.providerId, account.id);
    await ref.read(gatewayAdminStateProvider.notifier).reload();
    if (!mounted) return;
    final outcome = '${res['outcome'] ?? res['message'] ?? 'ok'}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.pluginsCheckinResult(outcome))),
    );
  }

  Future<void> _signOut(PluginAccount account) async {
    final confirmed = await showFalconConfirmDialog(
      context: context,
      title: context.l10n.pluginsSignOut,
      message: context.l10n.pluginsSignOutConfirm(account.label),
      destructive: true,
    );
    if (!confirmed) return;
    final client = ref.read(adminApiClientProvider);
    if (client == null) return;
    await client.deletePluginAccount(account.providerId, account.id);
    await ref.read(gatewayAdminStateProvider.notifier).reload();
  }

  List<InstalledPlugin> _dedupeInstalled(List<InstalledPlugin> raw) {
    final byCanonical = <String, InstalledPlugin>{};
    for (final pl in raw) {
      final key = canonicalPluginPackage(pl.package);
      final existing = byCanonical[key];
      if (existing == null ||
          (pl.accounts.length > existing.accounts.length) ||
          (pl.providerDetails.length > existing.providerDetails.length)) {
        byCanonical[key] = pl;
      }
    }
    return byCanonical.values.toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = FalconColors.of(context);
    final runtimeRunning =
        ref.watch(gatewayRuntimeProvider).value?.running ?? false;
    final snapshot =
        ref.watch(gatewayAdminStateProvider).value ?? const AdminStateSnapshot();
    final plugins = _dedupeInstalled(snapshot.plugins);

    final activeSegment = _userSwitchedSegment
        ? _segment
        : (plugins.isNotEmpty && snapshot.providers.isEmpty
            ? _ProvidersSegment.plugins
            : _segment);

    return ResponsiveBody(
      child: RefreshIndicator(
        onRefresh: () => ref.read(gatewayAdminStateProvider.notifier).reload(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            if (!runtimeRunning) ...[
              const GatewayOfflineCard(),
              const SizedBox(height: 14),
            ],
            Row(
              children: [
                FalconSegmentedTrack<_ProvidersSegment>(
                  segments: [
                    (
                      value: _ProvidersSegment.api,
                      label: l10n.providersSegmentApi,
                    ),
                    (
                      value: _ProvidersSegment.plugins,
                      label: l10n.providersSegmentPlugins,
                    ),
                  ],
                  selected: activeSegment,
                  onChanged: (s) => setState(() {
                    _segment = s;
                    _userSwitchedSegment = true;
                  }),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: activeSegment == _ProvidersSegment.api
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton(
                                  key: const ValueKey(
                                    'add-preset-provider-btn',
                                  ),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                    minimumSize: const Size(0, 34),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: runtimeRunning
                                      ? () =>
                                            showPresetPickerSheet(context, ref)
                                      : null,
                                  child: Text(l10n.providersAddFromPreset),
                                ),
                                const SizedBox(width: 4),
                                FilledButton.tonalIcon(
                                  key: const ValueKey(
                                    'add-custom-provider-btn',
                                  ),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    minimumSize: const Size(0, 34),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: runtimeRunning
                                      ? () => showFalconSheet<bool>(
                                            context: context,
                                            builder: (_) =>
                                                const ProviderEditorSheet(),
                                          )
                                      : null,
                                  icon: const Icon(Icons.add_rounded, size: 17),
                                  label: Text(l10n.actionAdd),
                                ),
                              ],
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: l10n.pluginsRefreshQuotas,
                                  icon: const Icon(
                                    Icons.refresh_rounded,
                                    size: 19,
                                  ),
                                  onPressed: runtimeRunning
                                      ? () async {
                                          final client = ref.read(
                                            adminApiClientProvider,
                                          );
                                          if (client == null) return;
                                          await client.refreshPluginQuotas();
                                          await ref
                                              .read(
                                                gatewayAdminStateProvider
                                                    .notifier,
                                              )
                                              .reload();
                                        }
                                      : null,
                                ),
                                TextButton.icon(
                                  key: const ValueKey(
                                    'open-plugin-market-btn',
                                  ),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                    minimumSize: const Size(0, 34),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: runtimeRunning
                                      ? () => showFalconSheet<void>(
                                            context: context,
                                            builder: (_) =>
                                                const PluginMarketSheet(),
                                          )
                                      : null,
                                  icon: const Icon(Icons.add_rounded, size: 17),
                                  label: Text(l10n.pluginsDirectoryAction),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (activeSegment == _ProvidersSegment.api) ...[
              if (snapshot.providers.isEmpty)
                FalconCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.providersApiEmpty,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.providersApiEmptyHint,
                        style:
                            TextStyle(fontSize: 12.5, color: c.textSecondary),
                      ),
                    ],
                  ),
                )
              else
                FalconCard(
                  child: Column(
                    children: [
                      for (var i = 0; i < snapshot.providers.length; i++) ...[
                        if (i > 0) const FalconDivider(),
                        _ProviderRow(
                          provider: snapshot.providers[i],
                          testing:
                              _testingIds.contains(snapshot.providers[i].id),
                          onTap: () => showFalconSheet<bool>(
                            context: context,
                            builder: (_) => ProviderEditorSheet(
                              existing: snapshot.providers[i],
                            ),
                          ),
                          onTest: () => _testProvider(snapshot.providers[i]),
                          onToggle: (enabled) async {
                            final client = ref.read(adminApiClientProvider);
                            if (client == null) return;
                            final p = snapshot.providers[i];
                            await client.upsertProvider(
                              id: p.id,
                              name: p.name,
                              preset: p.preset,
                              protocol: p.protocol,
                              baseUrl: p.baseUrl,
                              enabled: enabled,
                              keys: p.keys,
                              models: p.models,
                              selectedModels: p.selectedModels,
                            );
                            await ref
                                .read(gatewayAdminStateProvider.notifier)
                                .reload();
                          },
                        ),
                      ],
                    ],
                  ),
                ),
            ] else ...[
              if (plugins.isEmpty)
                FalconCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.pluginsEmpty,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.pluginsEmptyHint,
                        style:
                            TextStyle(fontSize: 12.5, color: c.textSecondary),
                      ),
                    ],
                  ),
                )
              else
                for (var i = 0; i < plugins.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  _PluginCard(
                    plugin: plugins[i],
                    settingsSelectedModels:
                        snapshot.settings.pluginSelectedModels,
                    refreshing: _refreshingPlugins.contains(plugins[i].id),
                    onRefresh: () => _refreshPlugin(plugins[i]),
                    onToggle: (enabled) async {
                      final client = ref.read(adminApiClientProvider);
                      if (client == null) return;
                      await client.togglePlugin(
                        plugins[i].package,
                        enabled,
                      );
                      await ref
                          .read(gatewayAdminStateProvider.notifier)
                          .reload();
                    },
                    onSignIn: (providerId) => showFalconSheet<bool>(
                      context: context,
                      builder: (_) => PluginSignInSheet(
                        plugin: plugins[i],
                        providerId: providerId,
                      ),
                    ),
                    onSelectModels: (detail, displayTitle) =>
                        showFalconSheet<bool>(
                      context: context,
                      builder: (_) => PluginModelsSheet(
                        plugin: plugins[i],
                        detail: detail,
                        displayTitle: displayTitle,
                      ),
                    ),
                    onTestModel: (modelTarget) => showFalconSheet<void>(
                      context: context,
                      builder: (_) => PlaygroundSheet(initialModel: modelTarget),
                    ),
                    onCheckin: _checkin,
                    onSignOut: _signOut,
                  ),
                ],
            ],
          ],
        ),
      ),
    );
  }
}

class _ProviderRow extends StatelessWidget {
  const _ProviderRow({
    required this.provider,
    required this.testing,
    required this.onTap,
    required this.onTest,
    required this.onToggle,
  });

  final UpstreamProvider provider;
  final bool testing;
  final VoidCallback onTap;
  final VoidCallback onTest;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = FalconColors.of(context);
    final activeModels = provider.selectedModels.isNotEmpty
        ? provider.selectedModels.length
        : provider.models.length;
    final lastTest = provider.lastTest;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    provider.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${provider.protocol} · $activeModels'
                    '${lastTest != null ? ' · ${lastTest.ok ? l10n.providersTestPass(lastTest.latencyMs) : l10n.providersTestFail(lastTest.statusCode)}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FalconTheme.tabular(
                      TextStyle(
                        fontSize: 12,
                        color: (lastTest != null && !lastTest.ok)
                            ? c.danger
                            : c.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: l10n.actionTest,
              onPressed: testing ? null : onTest,
              icon: testing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.bolt_outlined, size: 19),
            ),
            Switch(value: provider.enabled, onChanged: onToggle),
          ],
        ),
      ),
    );
  }
}

class _PluginCard extends StatelessWidget {
  const _PluginCard({
    required this.plugin,
    required this.settingsSelectedModels,
    required this.refreshing,
    required this.onRefresh,
    required this.onToggle,
    required this.onSignIn,
    required this.onSelectModels,
    required this.onTestModel,
    required this.onCheckin,
    required this.onSignOut,
  });

  final InstalledPlugin plugin;
  final Map<String, List<String>> settingsSelectedModels;
  final bool refreshing;
  final VoidCallback onRefresh;
  final ValueChanged<bool> onToggle;
  final ValueChanged<String?> onSignIn;
  final void Function(PluginProviderDetail detail, String displayTitle)
      onSelectModels;
  final ValueChanged<String> onTestModel;
  final ValueChanged<PluginAccount> onCheckin;
  final ValueChanged<PluginAccount> onSignOut;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = FalconColors.of(context);
    final details = sortPluginProviderDetails(
      plugin.resolvedProviderDetails(settingsSelectedModels),
    );

    return FalconCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          plugin.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                      if (plugin.version.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          'v${plugin.version}',
                          style: FalconTheme.tabular(
                            TextStyle(fontSize: 12, color: c.textMuted),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: l10n.pluginsRefreshPlugin,
                  onPressed: refreshing ? null : onRefresh,
                  icon: refreshing
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync_rounded, size: 19),
                ),
                Switch(value: plugin.enabled, onChanged: onToggle),
              ],
            ),
          ),
          if (plugin.error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text(
                plugin.error,
                style: TextStyle(fontSize: 12, color: c.danger),
              ),
            ),
          if (details.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < details.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    _PluginProviderSection(
                      detail: details[i],
                      displayTitle: localizedPluginProviderTitle(
                        l10n,
                        details[i],
                      ),
                      onSignIn: () => onSignIn(details[i].id),
                      onSelectModels: () => onSelectModels(
                        details[i],
                        localizedPluginProviderTitle(l10n, details[i]),
                      ),
                      onTestModel: onTestModel,
                      onCheckin: onCheckin,
                      onSignOut: onSignOut,
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PluginProviderSection extends StatelessWidget {
  const _PluginProviderSection({
    required this.detail,
    required this.displayTitle,
    required this.onSignIn,
    required this.onSelectModels,
    required this.onTestModel,
    required this.onCheckin,
    required this.onSignOut,
  });

  final PluginProviderDetail detail;
  final String displayTitle;
  final VoidCallback onSignIn;
  final VoidCallback onSelectModels;
  final ValueChanged<String> onTestModel;
  final ValueChanged<PluginAccount> onCheckin;
  final ValueChanged<PluginAccount> onSignOut;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = FalconColors.of(context);
    final activeIds = detail.effectiveModelIds;
    final modelSummary = detail.selectedModels.isEmpty
        ? l10n.pluginsAutoAllModels(detail.models.length)
        : l10n.pluginsSelectedModelsSummary(
            detail.selectedModels.length,
            detail.models.length,
          );
    final firstTestTarget = activeIds.isEmpty
        ? null
        : (activeIds.first.contains('/')
            ? activeIds.first
            : '${detail.id}/${activeIds.first}');

    if (!detail.authenticated) {
      return Container(
        decoration: BoxDecoration(
          color: c.cardSubtle,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail.lastError.isNotEmpty
                        ? detail.lastError
                        : l10n.pluginsNotAuthenticated,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: detail.lastError.isNotEmpty
                          ? c.danger
                          : c.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              key: ValueKey('plugin-signin-${detail.id}'),
              style: OutlinedButton.styleFrom(
                backgroundColor: c.card,
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onSignIn,
              child: Text(l10n.pluginsActionSignInShort),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: c.cardSubtle,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            displayTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: c.textPrimary,
            ),
          ),
          if (detail.lastError.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              detail.lastError,
              style: TextStyle(fontSize: 12, color: c.danger),
            ),
          ],
          for (final acct in detail.accounts) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        acct.label.isNotEmpty ? acct.label : acct.id,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: c.textSecondary,
                        ),
                      ),
                      if (acct.quotas.isNotEmpty) ...[
                        const SizedBox(height: 1),
                        Text(
                          acct.quotas.map((q) {
                            final ratio = q.limit > 0
                                ? '${q.used.toInt()}/${q.limit.toInt()}'
                                : (q.remainingPct != null
                                    ? '${q.remainingPct!.toStringAsFixed(0)}%'
                                    : '--');
                            return '${q.label} $ratio';
                          }).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: FalconTheme.tabular(
                            TextStyle(fontSize: 11.5, color: c.textMuted),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (detail.supportsCheckin)
                  TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => onCheckin(acct),
                    child: Text(l10n.pluginsCheckin),
                  ),
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => onSignOut(acct),
                  child: Text(
                    l10n.pluginsSignOut,
                    style: TextStyle(color: c.textSecondary),
                  ),
                ),
              ],
            ),
          ],
          if (detail.supportsModels || detail.models.isNotEmpty) ...[
            const SizedBox(height: 10),
            Material(
              color: c.card,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                key: ValueKey('plugin-models-${detail.id}'),
                borderRadius: BorderRadius.circular(10),
                onTap: onSelectModels,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
                  child: Row(
                    children: [
                      Text(
                        l10n.pluginsModelsRowLabel,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: c.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      Flexible(
                        flex: 0,
                        child: Text(
                          modelSummary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: FalconTheme.tabular(
                            TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: c.textPrimary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: c.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                key: ValueKey('plugin-signin-${detail.id}'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: onSignIn,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: Text(l10n.pluginsAddAccount),
              ),
              if (firstTestTarget != null) ...[
                const SizedBox(width: 6),
                TextButton.icon(
                  key: ValueKey('plugin-test-${detail.id}'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => onTestModel(firstTestTarget),
                  icon: const Icon(Icons.terminal_rounded, size: 15),
                  label: Text(l10n.actionTest),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
