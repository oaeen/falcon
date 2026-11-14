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
import '../widgets/segmented_track.dart';
import '../widgets/sheet_frame.dart';
import 'alias_editor_sheet.dart';
import 'group_editor_sheet.dart';

enum _RoutingSegment { groups, aliases }

class RoutingScreen extends ConsumerStatefulWidget {
  const RoutingScreen({super.key});

  @override
  ConsumerState<RoutingScreen> createState() => _RoutingScreenState();
}

class _RoutingScreenState extends ConsumerState<RoutingScreen> {
  _RoutingSegment _segment = _RoutingSegment.groups;

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
            Row(
              children: [
                FalconSegmentedTrack<_RoutingSegment>(
                  segments: [
                    (
                      value: _RoutingSegment.groups,
                      label: l10n.routingSegmentGroups,
                    ),
                    (
                      value: _RoutingSegment.aliases,
                      label: l10n.routingSegmentAliases,
                    ),
                  ],
                  selected: _segment,
                  onChanged: (s) => setState(() => _segment = s),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: _segment == _RoutingSegment.groups
                          ? TextButton.icon(
                              key: const ValueKey('add-group-btn'),
                              style: TextButton.styleFrom(
                                minimumSize: const Size(0, 34),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: runtimeRunning
                                  ? () => showFalconSheet<bool>(
                                        context: context,
                                        builder: (_) => GroupEditorSheet(
                                          availableMembers:
                                              snapshot.availableTargets,
                                        ),
                                      )
                                  : null,
                              icon: const Icon(Icons.add_rounded, size: 17),
                              label: Text(l10n.routingGroupAdd),
                            )
                          : TextButton.icon(
                              key: const ValueKey('add-alias-btn'),
                              style: TextButton.styleFrom(
                                minimumSize: const Size(0, 34),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: runtimeRunning
                                  ? () => showFalconSheet<bool>(
                                        context: context,
                                        builder: (_) => AliasEditorSheet(
                                          existingAliases: snapshot.aliases,
                                          availableTargets:
                                              snapshot.availableTargets,
                                        ),
                                      )
                                  : null,
                              icon: const Icon(Icons.add_rounded, size: 17),
                              label: Text(l10n.routingAliasAdd),
                            ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_segment == _RoutingSegment.groups) ...[
              if (snapshot.groups.isEmpty)
                FalconCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.routingGroupsEmpty,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
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
            ] else ...[
              if (snapshot.aliases.isEmpty)
                FalconCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.routingAliasesEmpty,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
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
    final l10n = context.l10n;
    final c = FalconColors.of(context);
    final summary = l10n.routingMembersSummary(
      group.members.length,
      group.strategy,
    );
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FalconTheme.mono(context, fontSize: 14),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$summary${group.pinnedMember.isNotEmpty ? ' · ${group.pinnedMember}' : ''}',
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
