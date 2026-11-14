import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/admin_models.dart';
import '../../data/platform_bridge.dart';
import '../../l10n/l10n.dart';
import '../../state/app_settings_state.dart';
import '../../state/gateway_state.dart';
import '../../theme/falcon_theme.dart';
import '../widgets/falcon_card.dart';
import '../widgets/falcon_row.dart';
import '../widgets/responsive_body.dart';
import '../widgets/sheet_frame.dart';
import 'backup_sheet.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _portCtrl = TextEditingController();
  final _allowIpsCtrl = TextEditingController();
  final _corsCtrl = TextEditingController();
  bool _networkDirty = false;
  bool _includeSecretsInExport = false;

  @override
  void dispose() {
    _portCtrl.dispose();
    _allowIpsCtrl.dispose();
    _corsCtrl.dispose();
    super.dispose();
  }

  List<String> _splitCsv(String raw) {
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> _saveNetworkSettings() async {
    final port = int.tryParse(_portCtrl.text.trim()) ?? 18787;
    final clampedPort = port.clamp(1024, 65535);
    await ref.read(gatewayAdminStateProvider.notifier).updateSettings({
      'port': clampedPort,
      'allowIps': _splitCsv(_allowIpsCtrl.text),
      'corsOrigins': _splitCsv(_corsCtrl.text),
    });
    if (mounted) setState(() => _networkDirty = false);
  }

  Future<void> _exportBackup() async {
    final client = ref.read(adminApiClientProvider);
    if (client == null) return;
    final data =
        await client.exportBackup(includeSecrets: _includeSecretsInExport);
    final pretty = const JsonEncoder.withIndent('  ').convert(data);
    if (!mounted) return;
    await showFalconSheet<void>(
      context: context,
      builder: (_) => BackupSheet(isImport: false, initialJson: pretty),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = FalconColors.of(context);
    final runtime = ref.watch(gatewayRuntimeProvider).value ??
        const GatewayRuntimeStatus();
    final snapshot =
        ref.watch(gatewayAdminStateProvider).value ?? const AdminStateSnapshot();
    final prefs = ref.watch(appPreferencesProvider);

    if (!_networkDirty) {
      final portStr = '${snapshot.settings.port}';
      final ipsStr = snapshot.settings.allowIps.join(', ');
      final corsStr = snapshot.settings.corsOrigins.join(', ');
      if (_portCtrl.text != portStr) _portCtrl.text = portStr;
      if (_allowIpsCtrl.text != ipsStr) _allowIpsCtrl.text = ipsStr;
      if (_corsCtrl.text != corsStr) _corsCtrl.text = corsStr;
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ResponsiveBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            SectionHeader(title: l10n.settingsKeepAliveSection),
            if (runtime.isAndroid)
              FalconCard(
                key: const ValueKey('keepalive-android-card'),
                child: Column(
                  children: [
                    FalconRow(
                      icon: Icons.battery_saver_outlined,
                      title: l10n.settingsBatteryExemption,
                      value: runtime.batteryOptimizationIgnored
                          ? l10n.settingsBatteryGranted
                          : l10n.settingsBatteryNotGranted,
                      onTap: () => ref
                          .read(gatewayRuntimeProvider.notifier)
                          .requestBatteryExemption(),
                    ),
                    const FalconDivider(),
                    FalconRow(
                      icon: Icons.tune_rounded,
                      title: l10n.settingsAppBatterySettings,
                      onTap: () => ref
                          .read(gatewayRuntimeProvider.notifier)
                          .openAppBatterySettings(),
                    ),
                    const FalconDivider(),
                    FalconRow(
                      icon: Icons.notifications_none_rounded,
                      title: l10n.settingsNotificationPermission,
                      value: runtime.notificationPermissionGranted
                          ? l10n.settingsBatteryGranted
                          : l10n.settingsBatteryNotGranted,
                      onTap: () => ref
                          .read(gatewayRuntimeProvider.notifier)
                          .requestNotificationPermission(),
                    ),
                    const FalconDivider(),
                    FalconRow(
                      icon: Icons.power_settings_new_rounded,
                      title: l10n.settingsBootAutoStart,
                      trailing: Switch(
                        value: runtime.startOnBoot,
                        onChanged: (v) => ref
                            .read(gatewayRuntimeProvider.notifier)
                            .setStartOnBoot(v),
                      ),
                    ),
                    const FalconDivider(),
                    FalconRow(
                      icon: Icons.memory_rounded,
                      title: l10n.settingsWakeLock,
                      value: runtime.wakeLockHeld
                          ? l10n.statusEnabled
                          : l10n.statusDisabled,
                    ),
                    const FalconDivider(),
                    FalconRow(
                      icon: Icons.wifi_rounded,
                      title: l10n.settingsWifiLock,
                      value: runtime.wifiLockHeld
                          ? l10n.statusEnabled
                          : l10n.statusDisabled,
                    ),
                    const FalconDivider(),
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        l10n.settingsOemGuidance,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: c.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else if (runtime.isIos)
              FalconCard(
                key: const ValueKey('keepalive-ios-card'),
                child: Column(
                  children: [
                    FalconRow(
                      icon: Icons.volume_off_outlined,
                      title: l10n.settingsIosBackgroundAudio,
                      subtitle: l10n.settingsIosBackgroundAudioHint,
                      trailing: Switch(
                        key: const ValueKey('ios-audio-keepalive-switch'),
                        value: runtime.backgroundAudioKeepAlive,
                        onChanged: (v) => ref
                            .read(gatewayRuntimeProvider.notifier)
                            .setIosBackgroundAudioKeepAlive(v),
                      ),
                    ),
                    const FalconDivider(),
                    FalconRow(
                      icon: Icons.brightness_high_outlined,
                      title: l10n.settingsIosKeepScreenAwake,
                      subtitle: l10n.settingsIosKeepScreenAwakeHint,
                      trailing: Switch(
                        key: const ValueKey('ios-screen-awake-switch'),
                        value: runtime.keepScreenAwake,
                        onChanged: (v) => ref
                            .read(gatewayRuntimeProvider.notifier)
                            .setKeepScreenAwake(v),
                      ),
                    ),
                    const FalconDivider(),
                    FalconRow(
                      icon: Icons.notifications_none_rounded,
                      title: l10n.settingsNotificationPermission,
                      value: runtime.notificationPermissionGranted
                          ? l10n.settingsBatteryGranted
                          : l10n.settingsBatteryNotGranted,
                      onTap: () => ref
                          .read(gatewayRuntimeProvider.notifier)
                          .requestNotificationPermission(),
                    ),
                    const FalconDivider(),
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        l10n.settingsIosLocalNetworkGuidance,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: c.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              FalconCard(
                key: const ValueKey('keepalive-desktop-card'),
                child: Column(
                  children: [
                    FalconRow(
                      icon: Icons.dns_outlined,
                      title: l10n.gatewayCorePid,
                      value: runtime.corePid > 0 ? '${runtime.corePid}' : '--',
                      monoValue: true,
                    ),
                    if (snapshot.status.pluginRuntimeMode != null) ...[
                      const FalconDivider(),
                      FalconRow(
                        icon: Icons.extension_outlined,
                        title: l10n.settingsPluginRuntimeMode,
                        value: snapshot.status.pluginRuntimeMode,
                        monoValue: true,
                      ),
                    ],
                    const FalconDivider(),
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        l10n.settingsDesktopProcessGuidance,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: c.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            SectionHeader(title: l10n.settingsNetworkSection),
            FalconCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FalconRow(
                    icon: Icons.wifi_tethering_outlined,
                    title: l10n.gatewayLanAccess,
                    trailing: Switch(
                      value: snapshot.settings.lanEnabled,
                      onChanged: runtime.running
                          ? (v) => ref
                              .read(gatewayAdminStateProvider.notifier)
                              .updateSettings({'lanEnabled': v})
                          : null,
                    ),
                  ),
                  const FalconDivider(),
                  FalconRow(
                    icon: Icons.lock_open_outlined,
                    title: l10n.gatewayLocalKeyless,
                    trailing: Switch(
                      value: snapshot.settings.allowLocalKeyless,
                      onChanged: runtime.running
                          ? (v) => ref
                              .read(gatewayAdminStateProvider.notifier)
                              .updateSettings({'allowLocalKeyless': v})
                          : null,
                    ),
                  ),
                  const FalconDivider(),
                  FalconRow(
                    icon: Icons.public_outlined,
                    title: l10n.settingsChinaMirror,
                    trailing: Switch(
                      value: snapshot.settings.chinaMirror,
                      onChanged: runtime.running
                          ? (v) => ref
                              .read(gatewayAdminStateProvider.notifier)
                              .updateSettings({'chinaMirror': v})
                          : null,
                    ),
                  ),
                  const FalconDivider(),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _portCtrl,
                          keyboardType: TextInputType.number,
                          style: FalconTheme.tabular(null),
                          decoration: InputDecoration(
                            labelText: l10n.settingsPort,
                            hintText: l10n.settingsPortHint,
                          ),
                          onChanged: (_) =>
                              setState(() => _networkDirty = true),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _allowIpsCtrl,
                          style: FalconTheme.mono(context, fontSize: 13),
                          decoration: InputDecoration(
                            labelText: l10n.settingsAllowIps,
                            hintText: l10n.settingsAllowIpsHint,
                          ),
                          onChanged: (_) =>
                              setState(() => _networkDirty = true),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _corsCtrl,
                          style: FalconTheme.mono(context, fontSize: 13),
                          decoration: InputDecoration(
                            labelText: l10n.settingsCorsOrigins,
                            hintText: l10n.settingsCorsOriginsHint,
                          ),
                          onChanged: (_) =>
                              setState(() => _networkDirty = true),
                        ),
                        if (_networkDirty) ...[
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton(
                              onPressed: runtime.running
                                  ? _saveNetworkSettings
                                  : null,
                              child: Text(l10n.actionSave),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SectionHeader(title: l10n.settingsBackupSection),
            FalconCard(
              child: Column(
                children: [
                  FalconRow(
                    icon: Icons.key_outlined,
                    title: l10n.settingsBackupExportIncludeSecrets,
                    trailing: Switch(
                      value: _includeSecretsInExport,
                      onChanged: (v) =>
                          setState(() => _includeSecretsInExport = v),
                    ),
                  ),
                  const FalconDivider(),
                  FalconRow(
                    icon: Icons.upload_file_outlined,
                    title: l10n.settingsBackupExport,
                    onTap: runtime.running ? _exportBackup : null,
                  ),
                  const FalconDivider(),
                  FalconRow(
                    icon: Icons.download_outlined,
                    title: l10n.settingsBackupImport,
                    onTap: runtime.running
                        ? () => showFalconSheet<bool>(
                              context: context,
                              builder: (_) => const BackupSheet(isImport: true),
                            )
                        : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SectionHeader(title: l10n.settingsAppearanceSection),
            FalconCard(
              child: Column(
                children: [
                  FalconRow(
                    icon: Icons.palette_outlined,
                    title: l10n.settingsThemeMode,
                    trailing: DropdownButton<ThemeMode>(
                      value: prefs.themeMode,
                      underline: const SizedBox.shrink(),
                      items: [
                        DropdownMenuItem(
                          value: ThemeMode.system,
                          child: Text(l10n.settingsThemeSystem),
                        ),
                        DropdownMenuItem(
                          value: ThemeMode.light,
                          child: Text(l10n.settingsThemeLight),
                        ),
                        DropdownMenuItem(
                          value: ThemeMode.dark,
                          child: Text(l10n.settingsThemeDark),
                        ),
                      ],
                      onChanged: (m) {
                        if (m != null) {
                          ref
                              .read(appPreferencesProvider.notifier)
                              .setThemeMode(m);
                        }
                      },
                    ),
                  ),
                  const FalconDivider(),
                  FalconRow(
                    icon: Icons.translate_rounded,
                    title: l10n.settingsLanguage,
                    trailing: DropdownButton<String>(
                      value: prefs.locale.languageCode,
                      underline: const SizedBox.shrink(),
                      items: [
                        DropdownMenuItem(
                          value: 'zh',
                          child: Text(l10n.settingsLanguageZh),
                        ),
                        DropdownMenuItem(
                          value: 'en',
                          child: Text(l10n.settingsLanguageEn),
                        ),
                      ],
                      onChanged: (code) {
                        if (code != null) {
                          ref
                              .read(appPreferencesProvider.notifier)
                              .setLocale(Locale(code));
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
