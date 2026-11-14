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
import '../widgets/segmented_track.dart';
import '../widgets/sheet_frame.dart';
import 'request_detail_sheet.dart';

class MonitorScreen extends ConsumerWidget {
  const MonitorScreen({super.key});

  String _formatCount(int value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(2)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
    return '$value';
  }

  Future<void> _clearLogs(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final ok = await showFalconConfirmDialog(
      context: context,
      title: l10n.actionClear,
      message: l10n.monitorLogsClearConfirm,
      destructive: true,
    );
    if (!ok) return;
    final client = ref.read(adminApiClientProvider);
    if (client == null) return;
    await client.clearLogs();
    ref.invalidate(requestLogsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = FalconColors.of(context);
    final runtimeRunning =
        ref.watch(gatewayRuntimeProvider).value?.running ?? false;
    final range = ref.watch(usageRangeProvider);
    final usage =
        ref.watch(usageSummaryProvider).value ?? UsageSummary(range: range);
    final logs = ref.watch(requestLogsProvider).value ?? const [];

    return ResponsiveBody(
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(usageSummaryProvider);
          ref.invalidate(requestLogsProvider);
          await ref.read(gatewayAdminStateProvider.notifier).reload();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            if (!runtimeRunning) ...[
              const GatewayOfflineCard(),
              const SizedBox(height: 14),
            ],
            FalconSegmentedTrack<String>(
              expand: true,
              segments: [
                (value: 'today', label: l10n.monitorRangeToday),
                (value: '7d', label: l10n.monitorRange7d),
                (value: '30d', label: l10n.monitorRange30d),
              ],
              selected: range,
              onChanged: (v) =>
                  ref.read(usageRangeProvider.notifier).setRange(v),
            ),
            const SizedBox(height: 12),
            Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _KpiCell(
                        label: l10n.monitorKpiRequests,
                        value: _formatCount(usage.requests),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _KpiCell(
                        label: l10n.monitorKpiTokens,
                        value: _formatCount(usage.totalTokens),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _KpiCell(
                        label: l10n.monitorKpiSpend,
                        value: '\$${usage.estimatedUsd.toStringAsFixed(3)}',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _KpiCell(
                        label: l10n.monitorKpiTtft,
                        value: '${usage.avgTtftMs} ms',
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            SectionHeader(
              title: l10n.monitorLogsSection,
              trailing: logs.isNotEmpty
                  ? TextButton(
                      onPressed: () => _clearLogs(context, ref),
                      child: Text(l10n.actionClear),
                    )
                  : null,
            ),
            if (logs.isEmpty)
              FalconCard(
                padding: const EdgeInsets.all(16),
                child: Text(
                  l10n.monitorLogsEmpty,
                  style: TextStyle(fontSize: 13.5, color: c.textSecondary),
                ),
              )
            else
              FalconCard(
                child: Column(
                  children: [
                    for (var i = 0; i < logs.length; i++) ...[
                      if (i > 0) const FalconDivider(),
                      _LogEntryRow(
                        entry: logs[i],
                        onTap: () => showFalconSheet<void>(
                          context: context,
                          builder: (_) => RequestDetailSheet(entry: logs[i]),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _KpiCell extends StatelessWidget {
  const _KpiCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = FalconColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.cardSubtle,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: c.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: FalconTheme.tabular(
              TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogEntryRow extends StatelessWidget {
  const _LogEntryRow({required this.entry, required this.onTap});

  final RequestLogEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = FalconColors.of(context);
    final ok = entry.statusCode >= 200 && entry.statusCode < 300;
    final source = entry.isLocal
        ? l10n.monitorSourceLocal
        : l10n.monitorSourceLan(entry.clientIp);
    final keyPart =
        entry.keyName.isNotEmpty ? entry.keyName : l10n.playgroundKeyNone;
    final modelRoute = entry.upstreamModel.isNotEmpty &&
            entry.upstreamModel != entry.requestedModel
        ? '${entry.requestedModel} → ${entry.upstreamModel}'
        : entry.requestedModel;
    final tokens = entry.inputTokens + entry.outputTokens;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    modelRoute,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FalconTheme.mono(context, fontSize: 13.5),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$source · $keyPart',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: c.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${entry.statusCode}',
                  style: FalconTheme.tabular(
                    TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: ok ? c.textSecondary : c.danger,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${entry.ttftMs}ms · ${tokens}t',
                  style: FalconTheme.tabular(
                    TextStyle(fontSize: 11.5, color: c.textMuted),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
