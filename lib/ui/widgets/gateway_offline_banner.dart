import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/gateway_state.dart';
import '../../theme/falcon_theme.dart';
import 'falcon_card.dart';

class GatewayOfflineCard extends ConsumerWidget {
  const GatewayOfflineCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = FalconColors.of(context);
    return FalconCard(
      backgroundColor: c.warningSoft,
      borderColor: c.warning.withValues(alpha: 0.35),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(Icons.power_settings_new_rounded, size: 20, color: c.warning),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.errorGatewayNotRunning,
              style: TextStyle(
                fontSize: 13.5,
                color: c.textPrimary,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () =>
                ref.read(gatewayRuntimeProvider.notifier).toggleGateway(true),
            child: Text(l10n.gatewayServiceToggle),
          ),
        ],
      ),
    );
  }
}
