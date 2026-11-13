import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/admin_models.dart';
import '../../data/platform_bridge.dart';
import '../../l10n/l10n.dart';
import '../../state/gateway_state.dart';
import '../../theme/falcon_theme.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/falcon_card.dart';
import '../widgets/falcon_row.dart';
import '../widgets/responsive_body.dart';
import '../widgets/sheet_frame.dart';
import '../widgets/status_pill.dart';
import 'access_key_sheet.dart';
import 'client_examples_sheet.dart';

class GatewayScreen extends ConsumerWidget {
  const GatewayScreen({super.key});

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '00:00:00';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(h)}:${two(m)}:${two(s)}';
  }

  Future<void> _copyEndpoint(BuildContext context, String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${context.l10n.actionCopied}: $url')),
    );
  }

  Future<void> _rotateKey(
    BuildContext context,
    WidgetRef ref,
    GatewayAccessKey accessKey,
  ) async {
    final l10n = context.l10n;
    final confirmed = await showFalconConfirmDialog(
      context: context,
      title: l10n.gatewayKeyRotate,
      message: l10n.gatewayKeyRotateConfirm,
    );
    if (!confirmed || !context.mounted) return;
    final client = ref.read(adminApiClientProvider);
    if (client == null) return;
    final rotated = await client.rotateKey(accessKey.id);
    await ref.read(gatewayAdminStateProvider.notifier).reload();
    if (!context.mounted) return;
    if (rotated.secret != null && rotated.secret!.isNotEmpty) {
      ref
          .read(sessionKeySecretsProvider.notifier)
          .record(rotated.id, rotated.secret!);
      await showFalconSheet<void>(
        context: context,
        builder: (_) => FalconSheetFrame(
          title: rotated.name,
          subtitle: l10n.gatewayKeyCreatedNotice,
          footer: FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.actionClose),
          ),
          child: _SecretBox(secret: rotated.secret!),
        ),
      );
    }
  }

  Future<void> _deleteKey(
    BuildContext context,
    WidgetRef ref,
    GatewayAccessKey accessKey,
  ) async {
    final l10n = context.l10n;
    final confirmed = await showFalconConfirmDialog(
      context: context,
      title: l10n.actionDelete,
      message: l10n.gatewayKeyDeleteConfirm(accessKey.name),
      destructive: true,
    );
    if (!confirmed) return;
    final client = ref.read(adminApiClientProvider);
    if (client == null) return;
    await client.deleteKey(accessKey.id);
    await ref.read(gatewayAdminStateProvider.notifier).reload();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = FalconColors.of(context);
    final runtime = ref.watch(gatewayRuntimeProvider).value ??
        const GatewayRuntimeStatus();
    final adminAsync = ref.watch(gatewayAdminStateProvider);
    final snapshot = adminAsync.value ?? const AdminStateSnapshot();
    final running = runtime.running;
    final port = snapshot.settings.port;
    final loopbackUrl = snapshot.status.loopbackUrl.isNotEmpty
        ? snapshot.status.loopbackUrl
        : 'http://127.0.0.1:$port';
    final lanUrls = snapshot.status.lanUrls.isNotEmpty
        ? snapshot.status.lanUrls
        : runtime.lanIpv4s.map((ip) => 'http://$ip:$port').toList();

    final uptimeSec = snapshot.status.uptimeSec > 0
        ? snapshot.status.uptimeSec
        : (runtime.uptimeMs ~/ 1000);

    return ResponsiveBody(
      child: RefreshIndicator(
        onRefresh: () async {
          await ref.read(gatewayRuntimeProvider.notifier).refresh();
          await ref.read(gatewayAdminStateProvider.notifier).reload();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            SectionHeader(title: l10n.gatewayServiceSection),
            FalconCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    l10n.gatewayServiceToggle,
                                    style: TextStyle(
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w600,
                                      color: c.textPrimary,
                                    ),
                                  ),
                                  StatusPill(
                                    label: running
                                        ? l10n.statusRunning
                                        : l10n.statusStopped,
                                    tone: running
                                        ? StatusTone.success
                                        : StatusTone.neutral,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  if (running && runtime.isAndroid)
                                    StatusPill(
                                      label: l10n.gatewayBadgeForeground,
                                      tone: StatusTone.accent,
                                    ),
                                  if (runtime.isAndroid && runtime.wakeLockHeld)
                                    StatusPill(
                                      label: l10n.gatewayBadgeWakeLock,
                                      tone: StatusTone.neutral,
                                    ),
                                  if (runtime.isAndroid && runtime.wifiLockHeld)
                                    StatusPill(
                                      label: l10n.gatewayBadgeWifiLock,
                                      tone: StatusTone.neutral,
                                    ),
                                  if (running &&
                                      runtime.isIos &&
                                      runtime.backgroundAudioKeepAlive)
                                    StatusPill(
                                      label: l10n.gatewayBadgeAudioKeepAlive,
                                      tone: StatusTone.accent,
                                    ),
                                  if (running &&
                                      runtime.isIos &&
                                      runtime.keepScreenAwake)
                                    StatusPill(
                                      label: l10n.gatewayBadgeScreenAwake,
                                      tone: StatusTone.neutral,
                                    ),
                                  if (running && runtime.isDesktop)
                                    StatusPill(
                                      label: l10n.gatewayBadgeDesktopProcess,
                                      tone: StatusTone.accent,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          key: const ValueKey('gateway-service-switch'),
                          value: running,
                          onChanged: (v) => ref
                              .read(gatewayRuntimeProvider.notifier)
                              .toggleGateway(v),
                        ),
                      ],
                    ),
                  ),
                  const FalconDivider(indent: 0),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _StatCell(
                            label: l10n.gatewayUptime,
                            value: _formatDuration(uptimeSec),
                          ),
                        ),
                        Expanded(
                          child: _StatCell(
                            label: l10n.gatewayModelsCount,
                            value: '${snapshot.status.modelCount}',
                          ),
                        ),
                        Expanded(
                          child: _StatCell(
                            label: l10n.gatewayProvidersCount,
                            value: '${snapshot.status.activeProviderCount}',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (runtime.isAndroid && !runtime.batteryOptimizationIgnored) ...[
              const SizedBox(height: 10),
              _PermissionBanner(
                icon: Icons.battery_alert_outlined,
                title: l10n.gatewayBatteryBannerTitle,
                body: l10n.gatewayBatteryBannerBody,
                actionLabel: l10n.gatewayBatteryGrant,
                onAction: () => ref
                    .read(gatewayRuntimeProvider.notifier)
                    .requestBatteryExemption(),
              ),
            ],
            if ((runtime.isAndroid || runtime.isIos) &&
                !runtime.notificationPermissionGranted) ...[
              const SizedBox(height: 10),
              _PermissionBanner(
                icon: Icons.notifications_none_rounded,
                title: l10n.gatewayNotifBannerTitle,
                body: l10n.gatewayNotifBannerBody,
                actionLabel: l10n.gatewayNotifGrant,
                onAction: () => ref
                    .read(gatewayRuntimeProvider.notifier)
                    .requestNotificationPermission(),
              ),
            ],
          const SizedBox(height: 20),
          SectionHeader(title: l10n.gatewayEndpointsSection),
          FalconCard(
            child: Column(
              children: [
                FalconRow(
                  icon: Icons.computer_outlined,
                  title: l10n.gatewayLoopbackLabel,
                  subtitle: loopbackUrl,
                  trailing: IconButton(
                    icon: const Icon(Icons.copy_outlined, size: 18),
                    tooltip: l10n.actionCopy,
                    onPressed: () => _copyEndpoint(context, loopbackUrl),
                  ),
                  onTap: () => _copyEndpoint(context, loopbackUrl),
                ),
                const FalconDivider(),
                FalconRow(
                  icon: Icons.lock_open_outlined,
                  title: l10n.gatewayLocalKeyless,
                  subtitle: l10n.gatewayLocalKeylessHint,
                  trailing: Switch(
                    key: const ValueKey('local-keyless-switch'),
                    value: snapshot.settings.allowLocalKeyless,
                    onChanged: running
                        ? (v) => ref
                            .read(gatewayAdminStateProvider.notifier)
                            .updateSettings({'allowLocalKeyless': v})
                        : null,
                  ),
                ),
                const FalconDivider(),
                FalconRow(
                  icon: Icons.wifi_tethering_outlined,
                  title: l10n.gatewayLanAccess,
                  subtitle: l10n.gatewayLanAccessHint,
                  trailing: Switch(
                    key: const ValueKey('lan-access-switch'),
                    value: snapshot.settings.lanEnabled,
                    onChanged: running
                        ? (v) => ref
                            .read(gatewayAdminStateProvider.notifier)
                            .updateSettings({'lanEnabled': v})
                        : null,
                  ),
                ),
                if (snapshot.settings.lanEnabled) ...[
                  if (lanUrls.isEmpty) ...[
                    const FalconDivider(),
                    FalconRow(
                      icon: Icons.info_outline_rounded,
                      title: l10n.gatewayLanNoIp,
                    ),
                  ] else
                    for (final url in lanUrls) ...[
                      const FalconDivider(),
                      FalconRow(
                        icon: Icons.lan_outlined,
                        title: url,
                        monoTitle: true,
                        trailing: IconButton(
                          icon: const Icon(Icons.copy_outlined, size: 18),
                          tooltip: l10n.actionCopy,
                          onPressed: () => _copyEndpoint(context, url),
                        ),
                        onTap: () => _copyEndpoint(context, url),
                      ),
                    ],
                ],
                const FalconDivider(),
                FalconRow(
                  icon: Icons.code_rounded,
                  title: l10n.gatewayClientExamples,
                  onTap: () => showFalconSheet<void>(
                    context: context,
                    builder: (_) => ClientExamplesSheet(
                      loopbackUrl: loopbackUrl,
                      lanUrls: lanUrls,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SectionHeader(
            title: l10n.gatewayKeysSection,
            trailing: TextButton.icon(
              key: const ValueKey('create-access-key-btn'),
              onPressed: running
                  ? () => showFalconSheet<bool>(
                        context: context,
                        builder: (_) => AccessKeySheet(
                          availableModels: snapshot.availableTargets,
                        ),
                      )
                  : null,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(l10n.actionCreate),
            ),
          ),
          FalconCard(
            child: snapshot.keys.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.gatewayKeysEmpty,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: c.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.gatewayKeysEmptyHint,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      for (var i = 0; i < snapshot.keys.length; i++) ...[
                        if (i > 0) const FalconDivider(),
                        _AccessKeyRow(
                          accessKey: snapshot.keys[i],
                          onToggle: (enabled) async {
                            final client = ref.read(adminApiClientProvider);
                            if (client == null) return;
                            final k = snapshot.keys[i];
                            await client.upsertKey(
                              id: k.id,
                              name: k.name,
                              enabled: enabled,
                              allowedModels: k.allowedModels,
                              dailyLimitUsd: k.dailyLimitUsd,
                              monthlyLimitUsd: k.monthlyLimitUsd,
                              dailyLimitReqs: k.dailyLimitReqs,
                            );
                            await ref
                                .read(gatewayAdminStateProvider.notifier)
                                .reload();
                          },
                          onEdit: () => showFalconSheet<bool>(
                            context: context,
                            builder: (_) => AccessKeySheet(
                              existingKey: snapshot.keys[i],
                              availableModels: snapshot.availableTargets,
                            ),
                          ),
                          onRotate: () =>
                              _rotateKey(context, ref, snapshot.keys[i]),
                          onDelete: () =>
                              _deleteKey(context, ref, snapshot.keys[i]),
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

class _StatCell extends StatelessWidget {
  const _StatCell({required this.label, required this.value});

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
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
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

class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final c = FalconColors.of(context);
    return FalconCard(
      backgroundColor: c.warningSoft,
      borderColor: c.warning.withValues(alpha: 0.35),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: c.warning),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
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
          OutlinedButton(
            onPressed: onAction,
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

class _AccessKeyRow extends StatelessWidget {
  const _AccessKeyRow({
    required this.accessKey,
    required this.onToggle,
    required this.onEdit,
    required this.onRotate,
    required this.onDelete,
  });

  final GatewayAccessKey accessKey;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onRotate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = FalconColors.of(context);
    final usage = l10n.gatewayKeyUsageSummary(
      accessKey.todayReqs,
      accessKey.todayUsd.toStringAsFixed(2),
    );
    return InkWell(
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    accessKey.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${accessKey.prefix} · $usage',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FalconTheme.tabular(
                      TextStyle(fontSize: 12, color: c.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: accessKey.enabled,
              onChanged: onToggle,
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded, size: 20, color: c.textMuted),
              onSelected: (value) {
                switch (value) {
                  case 'edit':
                    onEdit();
                  case 'rotate':
                    onRotate();
                  case 'delete':
                    onDelete();
                }
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(value: 'edit', child: Text(l10n.actionEdit)),
                PopupMenuItem(
                  value: 'rotate',
                  child: Text(l10n.gatewayKeyRotate),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    l10n.actionDelete,
                    style: TextStyle(color: c.danger),
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

class _SecretBox extends StatefulWidget {
  const _SecretBox({required this.secret});

  final String secret;

  @override
  State<_SecretBox> createState() => _SecretBoxState();
}

class _SecretBoxState extends State<_SecretBox> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = FalconColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.cardSubtle,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: c.border,
              width: FalconTheme.borderWidth,
            ),
          ),
          child: SelectableText(
            widget.secret,
            style: FalconTheme.mono(context, fontSize: 13.5),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: widget.secret));
            if (mounted) setState(() => _copied = true);
          },
          icon: Icon(_copied ? Icons.check_rounded : Icons.copy_outlined, size: 18),
          label: Text(_copied ? l10n.actionCopied : l10n.actionCopy),
        ),
      ],
    );
  }
}
