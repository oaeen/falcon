import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/admin_models.dart';
import '../../l10n/l10n.dart';
import '../../state/gateway_state.dart';
import '../../theme/falcon_theme.dart';
import '../widgets/falcon_card.dart';
import '../widgets/falcon_row.dart';
import '../widgets/gateway_offline_banner.dart';
import '../widgets/responsive_body.dart';
import '../widgets/sheet_frame.dart';
import '../widgets/status_pill.dart';
import 'alias_editor_sheet.dart';
import 'group_editor_sheet.dart';
import 'redact_preview_sheet.dart';
import 'redact_rule_sheet.dart';

enum _RoutingSegment { groups, aliases, redaction }

class RoutingScreen extends ConsumerStatefulWidget {
  const RoutingScreen({super.key});

  @override
  ConsumerState<RoutingScreen> createState() => _RoutingScreenState();
}

class _RoutingScreenState extends ConsumerState<RoutingScreen> {
  _RoutingSegment _segment = _RoutingSegment.groups;
  final _allowlistCtrl = TextEditingController();
  bool _allowlistDirty = false;

  @override
  void dispose() {
    _allowlistCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveAllowlist() async {
    final items = _allowlistCtrl.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    await ref
        .read(gatewayAdminStateProvider.notifier)
        .updateSettings({'redactAllow': items});
    if (mounted) setState(() => _allowlistDirty = false);
  }

  Future<void> _deleteAlias(
    List<ModelAlias> all,
    ModelAlias target,
  ) async {
    final client = ref.read(adminApiClientProvider);
    if (client == null) return;
    final next = all.where((a) => a.alias != target.alias).toList();
    await client.saveAliases(next);
    await ref.read(gatewayAdminStateProvider.notifier).reload();
  }

  Future<void> _deleteRedactRule(
    List<RedactRule> all,
    RedactRule rule,
  ) async {
    final next = all
        .where((r) => r.id != rule.id)
        .map((r) => r.toJson())
        .toList(growable: false);
    await ref
        .read(gatewayAdminStateProvider.notifier)
        .updateSettings({'redactRules': next});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = FalconColors.of(context);
    final runtimeRunning =
        ref.watch(gatewayRuntimeProvider).value?.running ?? false;
    final snapshot =
        ref.watch(gatewayAdminStateProvider).value ?? const AdminStateSnapshot();

    if (!_allowlistDirty) {
      final serverAllow = snapshot.settings.redactAllow.join(', ');
      if (_allowlistCtrl.text != serverAllow) {
        _allowlistCtrl.text = serverAllow;
      }
    }

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
            SegmentedButton<_RoutingSegment>(
              segments: [
                ButtonSegment(
                  value: _RoutingSegment.groups,
                  label: Text(l10n.routingSegmentGroups),
                ),
                ButtonSegment(
                  value: _RoutingSegment.aliases,
                  label: Text(l10n.routingSegmentAliases),
                ),
                ButtonSegment(
                  value: _RoutingSegment.redaction,
                  label: Text(l10n.routingSegmentRedaction),
                ),
              ],
              selected: {_segment},
              onSelectionChanged: (s) => setState(() => _segment = s.first),
            ),
            const SizedBox(height: 14),
            if (_segment == _RoutingSegment.groups) ...[
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  key: const ValueKey('add-group-btn'),
                  onPressed: runtimeRunning
                      ? () => showFalconSheet<bool>(
                            context: context,
                            builder: (_) => GroupEditorSheet(
                              availableMembers: snapshot.availableTargets,
                            ),
                          )
                      : null,
                  icon: const Icon(Icons.add_rounded, size: 17),
                  label: Text(l10n.routingGroupAdd),
                ),
              ),
              const SizedBox(height: 12),
              if (snapshot.groups.isEmpty)
                FalconCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.routingGroupsEmpty,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.routingGroupsEmptyHint,
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
                      for (var i = 0; i < snapshot.groups.length; i++) ...[
                        if (i > 0) const FalconDivider(),
                        _GroupRow(
                          group: snapshot.groups[i],
                          onTap: () => showFalconSheet<bool>(
                            context: context,
                            builder: (_) => GroupEditorSheet(
                              existing: snapshot.groups[i],
                              availableMembers: snapshot.availableTargets,
                            ),
                          ),
                          onToggle: (enabled) async {
                            final client = ref.read(adminApiClientProvider);
                            if (client == null) return;
                            final g = snapshot.groups[i];
                            await client.upsertGroup(
                              RoutingGroup(
                                id: g.id,
                                name: g.name,
                                strategy: g.strategy,
                                pinnedMember: g.pinnedMember,
                                enabled: enabled,
                                members: g.members,
                              ),
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
            ] else if (_segment == _RoutingSegment.aliases) ...[
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  key: const ValueKey('add-alias-btn'),
                  onPressed: runtimeRunning
                      ? () => showFalconSheet<bool>(
                            context: context,
                            builder: (_) => AliasEditorSheet(
                              existingAliases: snapshot.aliases,
                              availableTargets: snapshot.availableTargets,
                            ),
                          )
                      : null,
                  icon: const Icon(Icons.add_rounded, size: 17),
                  label: Text(l10n.routingAliasAdd),
                ),
              ),
              const SizedBox(height: 12),
              if (snapshot.aliases.isEmpty)
                FalconCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.routingAliasesEmpty,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.routingAliasesEmptyHint,
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
                      for (var i = 0; i < snapshot.aliases.length; i++) ...[
                        if (i > 0) const FalconDivider(),
                        FalconRow(
                          icon: Icons.compare_arrows_rounded,
                          title: snapshot.aliases[i].alias,
                          subtitle: snapshot.aliases[i].target,
                          monoTitle: true,
                          trailing: IconButton(
                            icon: Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                              color: c.textMuted,
                            ),
                            onPressed: () => _deleteAlias(
                              snapshot.aliases,
                              snapshot.aliases[i],
                            ),
                          ),
                          onTap: () => showFalconSheet<bool>(
                            context: context,
                            builder: (_) => AliasEditorSheet(
                              existingAliases: snapshot.aliases,
                              editing: snapshot.aliases[i],
                              availableTargets: snapshot.availableTargets,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ] else ...[
              FalconCard(
                child: Column(
                  children: [
                    FalconRow(
                      icon: Icons.shield_outlined,
                      title: l10n.routingRedactEnable,
                      subtitle: l10n.routingRedactEnableHint,
                      trailing: Switch(
                        key: const ValueKey('redact-enabled-switch'),
                        value: snapshot.settings.redactEnabled,
                        onChanged: runtimeRunning
                            ? (v) => ref
                                .read(gatewayAdminStateProvider.notifier)
                                .updateSettings({'redactEnabled': v})
                            : null,
                      ),
                    ),
                    const FalconDivider(),
                    FalconRow(
                      icon: Icons.restore_rounded,
                      title: l10n.routingRedactRestore,
                      subtitle: l10n.routingRedactRestoreHint,
                      trailing: Switch(
                        value: snapshot.settings.redactRestore,
                        onChanged: runtimeRunning
                            ? (v) => ref
                                .read(gatewayAdminStateProvider.notifier)
                                .updateSettings({'redactRestore': v})
                            : null,
                      ),
                    ),
                    const FalconDivider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _RedactStat(
                              label: l10n.routingRedactHits,
                              value: '${snapshot.redactSummary.totalHits}',
                            ),
                          ),
                          Expanded(
                            child: _RedactStat(
                              label: l10n.routingRedactBuiltinCount,
                              value: '${snapshot.redactSummary.builtinRules}',
                            ),
                          ),
                          Expanded(
                            child: _RedactStat(
                              label: l10n.routingRedactCustomRules,
                              value: '${snapshot.settings.redactRules.length}',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const ValueKey('open-redact-preview-btn'),
                onPressed: runtimeRunning
                    ? () => showFalconSheet<void>(
                          context: context,
                          builder: (_) => const RedactPreviewSheet(),
                        )
                    : null,
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: Text(l10n.routingRedactPreview),
              ),
              const SizedBox(height: 18),
              SectionHeader(
                title: l10n.routingRedactCustomRules,
                trailing: TextButton.icon(
                  onPressed: runtimeRunning
                      ? () => showFalconSheet<bool>(
                            context: context,
                            builder: (_) => RedactRuleSheet(
                              existingRules: snapshot.settings.redactRules,
                            ),
                          )
                      : null,
                  icon: const Icon(Icons.add_rounded, size: 17),
                  label: Text(l10n.actionAdd),
                ),
              ),
              if (snapshot.settings.redactRules.isNotEmpty)
                FalconCard(
                  child: Column(
                    children: [
                      for (var i = 0;
                          i < snapshot.settings.redactRules.length;
                          i++) ...[
                        if (i > 0) const FalconDivider(),
                        FalconRow(
                          icon: Icons.rule_outlined,
                          title: snapshot.settings.redactRules[i].name,
                          subtitle:
                              '${snapshot.settings.redactRules[i].pattern} → ${snapshot.settings.redactRules[i].replacement}',
                          trailing: IconButton(
                            icon: Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                              color: c.textMuted,
                            ),
                            onPressed: () => _deleteRedactRule(
                              snapshot.settings.redactRules,
                              snapshot.settings.redactRules[i],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              SectionHeader(title: l10n.routingRedactAllowlist),
              FalconCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _allowlistCtrl,
                      decoration: InputDecoration(
                        hintText: l10n.routingRedactAllowlistHint,
                      ),
                      onChanged: (_) => setState(() => _allowlistDirty = true),
                    ),
                    if (_allowlistDirty) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          onPressed: runtimeRunning ? _saveAllowlist : null,
                          child: Text(l10n.actionSave),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.group,
    required this.onTap,
    required this.onToggle,
  });

  final RoutingGroup group;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final c = FalconColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        child: Row(
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
                        group.name,
                        style: FalconTheme.mono(context, fontSize: 14),
                      ),
                      StatusPill(label: group.strategy, tone: StatusTone.accent),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${group.members.length} members'
                    '${group.pinnedMember.isNotEmpty ? ' · pin: ${group.pinnedMember}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FalconTheme.tabular(
                      TextStyle(fontSize: 12, color: c.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            Switch(value: group.enabled, onChanged: onToggle),
          ],
        ),
      ),
    );
  }
}

class _RedactStat extends StatelessWidget {
  const _RedactStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = FalconColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11.5, color: c.textSecondary),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: FalconTheme.tabular(
            TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: c.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
