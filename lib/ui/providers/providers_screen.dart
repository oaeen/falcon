import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/admin_models.dart';
import '../../l10n/l10n.dart';
import '../../state/gateway_state.dart';
import '../../theme/falcon_theme.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/falcon_card.dart';
import '../widgets/falcon_row.dart';
import '../widgets/gateway_offline_banner.dart';
import '../widgets/responsive_body.dart';
import '../widgets/sheet_frame.dart';
import '../widgets/status_pill.dart';
import 'plugin_market_sheet.dart';
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
  final Set<String> _testingIds = {};

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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = FalconColors.of(context);
    final runtimeRunning =
        ref.watch(gatewayRuntimeProvider).value?.running ?? false;
    final snapshot =
        ref.watch(gatewayAdminStateProvider).value ?? const AdminStateSnapshot();

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
          SegmentedButton<_ProvidersSegment>(
            segments: [
              ButtonSegment(
                value: _ProvidersSegment.api,
                label: Text(l10n.providersSegmentApi),
              ),
              ButtonSegment(
                value: _ProvidersSegment.plugins,
                label: Text(l10n.providersSegmentPlugins),
              ),
            ],
            selected: {_segment},
            onSelectionChanged: (s) => setState(() => _segment = s.first),
          ),
          const SizedBox(height: 14),
          if (_segment == _ProvidersSegment.api) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('add-preset-provider-btn'),
                    onPressed: runtimeRunning
                        ? () => showPresetPickerSheet(context, ref)
                        : null,
                    icon: const Icon(Icons.apps_rounded, size: 17),
                    label: Text(l10n.providersAddFromPreset),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('add-custom-provider-btn'),
                    onPressed: runtimeRunning
                        ? () => showFalconSheet<bool>(
                              context: context,
                              builder: (_) => const ProviderEditorSheet(),
                            )
                        : null,
                    icon: const Icon(Icons.add_rounded, size: 17),
                    label: Text(l10n.providersAddCustom),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (snapshot.providers.isEmpty)
              FalconCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.providersApiEmpty,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.providersApiEmptyHint,
                      style: TextStyle(fontSize: 12.5, color: c.textSecondary),
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
                        testing: _testingIds.contains(snapshot.providers[i].id),
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
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('open-plugin-market-btn'),
                    onPressed: runtimeRunning
                        ? () => showFalconSheet<void>(
                              context: context,
                              builder: (_) => const PluginMarketSheet(),
                            )
                        : null,
                    icon: const Icon(Icons.extension_outlined, size: 17),
                    label: Text(l10n.pluginsDirectoryAction),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: runtimeRunning
                        ? () async {
                            final client = ref.read(adminApiClientProvider);
                            if (client == null) return;
                            await client.refreshPluginQuotas();
                            await ref
                                .read(gatewayAdminStateProvider.notifier)
                                .reload();
                          }
                        : null,
                    icon: const Icon(Icons.refresh_rounded, size: 17),
                    label: Text(l10n.pluginsRefreshQuotas),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (snapshot.plugins.isEmpty)
              FalconCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.pluginsEmpty,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.pluginsEmptyHint,
                      style: TextStyle(fontSize: 12.5, color: c.textSecondary),
                    ),
                  ],
                ),
              )
            else
              for (var i = 0; i < snapshot.plugins.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                _PluginCard(
                  plugin: snapshot.plugins[i],
                  onToggle: (enabled) async {
                    final client = ref.read(adminApiClientProvider);
                    if (client == null) return;
                    await client.togglePlugin(
                      snapshot.plugins[i].package,
                      enabled,
                    );
                    await ref.read(gatewayAdminStateProvider.notifier).reload();
                  },
                  onSignIn: () => showFalconSheet<bool>(
                    context: context,
                    builder: (_) =>
                        PluginSignInSheet(plugin: snapshot.plugins[i]),
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
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            provider.name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: c.textPrimary,
                            ),
                          ),
                          StatusPill(
                            label: provider.protocol,
                            tone: StatusTone.neutral,
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        provider.baseUrl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FalconTheme.mono(
                          context,
                          fontSize: 11.5,
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(value: provider.enabled, onChanged: onToggle),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${provider.keys.length} keys · $activeModels models',
                        style: FalconTheme.tabular(
                          TextStyle(fontSize: 12, color: c.textSecondary),
                        ),
                      ),
                      if (lastTest != null)
                        StatusPill(
                          label: lastTest.ok
                              ? l10n.providersTestPass(lastTest.latencyMs)
                              : l10n.providersTestFail(lastTest.statusCode),
                          tone: lastTest.ok
                              ? StatusTone.success
                              : StatusTone.danger,
                        ),
                    ],
                  ),
                ),
                OutlinedButton(
                  onPressed: testing ? null : onTest,
                  child: Text(testing ? l10n.providersTesting : l10n.actionTest),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PluginCard extends StatelessWidget {
  const _PluginCard({
    required this.plugin,
    required this.onToggle,
    required this.onSignIn,
    required this.onCheckin,
    required this.onSignOut,
  });

  final InstalledPlugin plugin;
  final ValueChanged<bool> onToggle;
  final VoidCallback onSignIn;
  final ValueChanged<PluginAccount> onCheckin;
  final ValueChanged<PluginAccount> onSignOut;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = FalconColors.of(context);

    return FalconCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plugin.name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${plugin.package} · ${l10n.pluginsAccountsCount(plugin.accounts.length)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FalconTheme.tabular(
                          TextStyle(fontSize: 12, color: c.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(value: plugin.enabled, onChanged: onToggle),
              ],
            ),
          ),
          for (final acct in plugin.accounts) ...[
            const FalconDivider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          acct.label.isNotEmpty ? acct.label : acct.id,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => onCheckin(acct),
                        child: Text(l10n.pluginsCheckin),
                      ),
                      TextButton(
                        onPressed: () => onSignOut(acct),
                        child: Text(
                          l10n.pluginsSignOut,
                          style: TextStyle(color: c.danger),
                        ),
                      ),
                    ],
                  ),
                  if (acct.quotas.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: acct.quotas.map((q) {
                        final ratio = q.limit > 0
                            ? '${q.used.toInt()}/${q.limit.toInt()}'
                            : (q.remainingPct != null
                                ? '${q.remainingPct!.toStringAsFixed(0)}%'
                                : '--');
                        return StatusPill(
                          label: '${q.label}: $ratio',
                          tone: StatusTone.neutral,
                        );
                      }).toList(growable: false),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const FalconDivider(),
          FalconRow(
            icon: Icons.login_rounded,
            title: l10n.pluginsSignIn,
            onTap: onSignIn,
          ),
        ],
      ),
    );
  }
}
