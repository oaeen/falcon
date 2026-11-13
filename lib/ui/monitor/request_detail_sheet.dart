import 'package:flutter/material.dart';

import '../../data/admin_models.dart';
import '../../l10n/l10n.dart';
import '../../theme/falcon_theme.dart';
import '../widgets/falcon_card.dart';
import '../widgets/falcon_row.dart';
import '../widgets/sheet_frame.dart';

class RequestDetailSheet extends StatelessWidget {
  const RequestDetailSheet({super.key, required this.entry});

  final RequestLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = FalconColors.of(context);
    final routeText = entry.upstreamModel.isNotEmpty
        ? '${entry.requestedModel} → ${entry.upstreamProvider}/${entry.upstreamModel}'
        : entry.requestedModel;

    return FalconSheetFrame(
      title: l10n.monitorDetailTitle,
      subtitle: entry.timestamp,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FalconCard(
            child: Column(
              children: [
                FalconRow(
                  title: l10n.monitorDetailClientIp,
                  value: entry.isLocal
                      ? l10n.monitorSourceLocal
                      : l10n.monitorSourceLan(entry.clientIp),
                  monoValue: true,
                ),
                const FalconDivider(indent: 0),
                FalconRow(
                  title: l10n.monitorDetailKey,
                  value: entry.keyName.isNotEmpty
                      ? entry.keyName
                      : l10n.playgroundKeyNone,
                ),
                const FalconDivider(indent: 0),
                FalconRow(
                  title: l10n.monitorDetailProtocol,
                  value: entry.protocol,
                  monoValue: true,
                ),
                const FalconDivider(indent: 0),
                FalconRow(
                  title: l10n.monitorDetailRoute,
                  subtitle: routeText,
                ),
                const FalconDivider(indent: 0),
                FalconRow(
                  title: l10n.monitorDetailStatus,
                  value: '${entry.statusCode}',
                  monoValue: true,
                ),
                const FalconDivider(indent: 0),
                FalconRow(
                  title: l10n.monitorDetailTiming,
                  value: '${entry.ttftMs} ms / ${entry.latencyMs} ms',
                  monoValue: true,
                ),
                const FalconDivider(indent: 0),
                FalconRow(
                  title: l10n.monitorDetailTokens,
                  value: '${entry.inputTokens} / ${entry.outputTokens}',
                  monoValue: true,
                ),
                const FalconDivider(indent: 0),
                FalconRow(
                  title: l10n.monitorDetailFailovers,
                  value: '${entry.failoverAttempts}',
                  monoValue: true,
                ),
                const FalconDivider(indent: 0),
                FalconRow(
                  title: l10n.monitorDetailRedactions,
                  value: '${entry.redactionCount}',
                  monoValue: true,
                ),
              ],
            ),
          ),
          if (entry.error.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              l10n.monitorDetailError,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: c.danger,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.dangerSoft,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: c.danger.withValues(alpha: 0.3),
                  width: FalconTheme.borderWidth,
                ),
              ),
              child: SelectableText(
                entry.error,
                style: FalconTheme.mono(context, fontSize: 12, color: c.danger),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
