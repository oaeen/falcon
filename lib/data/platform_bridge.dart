import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const String _kDefaultDevAdminUrl =
    String.fromEnvironment('FALCON_DEV_ADMIN_URL', defaultValue: '');
const String _kDefaultDevAdminToken =
    String.fromEnvironment('FALCON_DEV_ADMIN_TOKEN', defaultValue: '');

String detectHostPlatform() {
  if (kIsWeb) return 'unknown';
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return 'android';
    case TargetPlatform.iOS:
      return 'ios';
    case TargetPlatform.macOS:
      return 'macos';
    case TargetPlatform.linux:
      return 'linux';
    case TargetPlatform.windows:
      return 'windows';
    case TargetPlatform.fuchsia:
      return 'unknown';
  }
}

bool isDesktopPlatformName(String platform) =>
    platform == 'macos' || platform == 'linux' || platform == 'windows';

@immutable
class GatewayRuntimeStatus {
  const GatewayRuntimeStatus({
    this.running = false,
    this.adminBaseUrl = 'http://127.0.0.1:18788',
    this.adminToken = '',
    this.lanIpv4s = const [],
    this.platform = 'android',
    this.keepScreenAwake = false,
    this.backgroundAudioKeepAlive = false,
    this.pluginRuntimeMode,
    this.batteryOptimizationIgnored = false,
    this.notificationPermissionGranted = false,
    this.wakeLockHeld = false,
    this.wifiLockHeld = false,
    this.startOnBoot = false,
    this.uptimeMs = 0,
    this.corePid = 0,
    this.lastLogs = const [],
  });

  final bool running;
  final String adminBaseUrl;
  final String adminToken;
  final List<String> lanIpv4s;

  /// `'android'`, `'ios'`, `'macos'`, `'linux'`, `'windows'`, `'unknown'`
  final String platform;
  final bool keepScreenAwake;
  final bool backgroundAudioKeepAlive;
  final String? pluginRuntimeMode;
  final bool batteryOptimizationIgnored;
  final bool notificationPermissionGranted;
  final bool wakeLockHeld;
  final bool wifiLockHeld;
  final bool startOnBoot;
  final int uptimeMs;
  final int corePid;
  final List<String> lastLogs;

  bool get isAndroid => platform == 'android';
  bool get isIos => platform == 'ios';
  bool get isDesktop => isDesktopPlatformName(platform);

  factory GatewayRuntimeStatus.fromMap(
    Map<Object?, Object?> map, {
    String? platformFallback,
  }) {
    List<String> stringList(Object? value) {
      if (value is List) {
        return value.map((e) => '$e').where((e) => e.isNotEmpty).toList();
      }
      return const [];
    }

    int asInt(Object? value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    final baseUrl = (map['adminBaseUrl'] as String?)?.trim();
    final rawPlatform = (map['platform'] as String?)?.trim();
    final resolvedPlatform = (rawPlatform != null &&
            rawPlatform.isNotEmpty &&
            rawPlatform != 'unknown')
        ? rawPlatform
        : (platformFallback ?? detectHostPlatform());

    return GatewayRuntimeStatus(
      running: map['running'] == true,
      adminBaseUrl: (baseUrl != null && baseUrl.isNotEmpty)
          ? baseUrl
          : (_kDefaultDevAdminUrl.isNotEmpty
              ? _kDefaultDevAdminUrl
              : 'http://127.0.0.1:18788'),
      adminToken: (map['adminToken'] as String?) ?? _kDefaultDevAdminToken,
      lanIpv4s: stringList(map['lanIpv4s']),
      platform: resolvedPlatform,
      keepScreenAwake: map['keepScreenAwake'] == true,
      backgroundAudioKeepAlive: map['backgroundAudioKeepAlive'] == true,
      pluginRuntimeMode: map['pluginRuntimeMode'] as String?,
      batteryOptimizationIgnored: map['batteryOptimizationIgnored'] == true,
      notificationPermissionGranted:
          map['notificationPermissionGranted'] == true,
      wakeLockHeld: map['wakeLockHeld'] == true,
      wifiLockHeld: map['wifiLockHeld'] == true,
      startOnBoot: map['startOnBoot'] == true,
      uptimeMs: asInt(map['uptimeMs']),
      corePid: asInt(map['corePid']),
      lastLogs: stringList(map['lastLogs']),
    );
  }

  GatewayRuntimeStatus copyWith({
    bool? running,
    String? adminBaseUrl,
    String? adminToken,
    List<String>? lanIpv4s,
    String? platform,
    bool? keepScreenAwake,
    bool? backgroundAudioKeepAlive,
    String? pluginRuntimeMode,
    bool? batteryOptimizationIgnored,
    bool? notificationPermissionGranted,
    bool? wakeLockHeld,
    bool? wifiLockHeld,
    bool? startOnBoot,
    int? uptimeMs,
    int? corePid,
    List<String>? lastLogs,
  }) {
    return GatewayRuntimeStatus(
      running: running ?? this.running,
      adminBaseUrl: adminBaseUrl ?? this.adminBaseUrl,
      adminToken: adminToken ?? this.adminToken,
      lanIpv4s: lanIpv4s ?? this.lanIpv4s,
      platform: platform ?? this.platform,
      keepScreenAwake: keepScreenAwake ?? this.keepScreenAwake,
      backgroundAudioKeepAlive:
          backgroundAudioKeepAlive ?? this.backgroundAudioKeepAlive,
      pluginRuntimeMode: pluginRuntimeMode ?? this.pluginRuntimeMode,
      batteryOptimizationIgnored:
          batteryOptimizationIgnored ?? this.batteryOptimizationIgnored,
      notificationPermissionGranted:
          notificationPermissionGranted ?? this.notificationPermissionGranted,
      wakeLockHeld: wakeLockHeld ?? this.wakeLockHeld,
      wifiLockHeld: wifiLockHeld ?? this.wifiLockHeld,
      startOnBoot: startOnBoot ?? this.startOnBoot,
      uptimeMs: uptimeMs ?? this.uptimeMs,
      corePid: corePid ?? this.corePid,
      lastLogs: lastLogs ?? this.lastLogs,
    );
  }
}

abstract interface class PlatformBridge {
  Future<GatewayRuntimeStatus> startGateway();
  Future<GatewayRuntimeStatus> stopGateway();
  Future<GatewayRuntimeStatus> getRuntimeStatus();
  Future<bool> requestBatteryOptimizationExemption();
  Future<void> openAppBatterySettings();
  Future<bool> requestNotificationPermission();
  Future<bool> setStartOnBoot(bool enabled);
  Future<bool> setKeepScreenAwake(bool enabled);
  Future<bool> setIosBackgroundAudioKeepAlive(bool enabled);
  Future<void> updateNotificationSummary({
    required bool lanEnabled,
    required int port,
  });
  Stream<GatewayRuntimeStatus> runtimeEvents();
}

class MethodChannelPlatformBridge implements PlatformBridge {
  MethodChannelPlatformBridge({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
    this.platformOverride,
    this.devAdminUrl = _kDefaultDevAdminUrl,
    this.devAdminToken = _kDefaultDevAdminToken,
  })  : _methodChannel = methodChannel ?? const MethodChannel('falcon/platform'),
        _eventChannel =
            eventChannel ?? const EventChannel('falcon/runtime_events');

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  final String? platformOverride;
  final String devAdminUrl;
  final String devAdminToken;

  Process? _desktopProcess;
  DateTime? _desktopStartedAt;
  bool _keepScreenAwake = false;
  bool _backgroundAudioKeepAlive = false;
  bool _startOnBoot = false;
  bool _batteryIgnored = true;
  bool _notifGranted = true;

  String get _effectivePlatform => platformOverride ?? detectHostPlatform();

  Future<List<String>> _enumerateLanIpv4s() async {
    if (kIsWeb) return const [];
    try {
      final ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      final ips = <String>[];
      for (final iface in ifaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && !addr.address.startsWith('169.254.')) {
            ips.add(addr.address);
          }
        }
      }
      return ips;
    } catch (_) {
      return const [];
    }
  }

  String? _findDesktopCoreBinary() {
    if (kIsWeb || !isDesktopPlatformName(_effectivePlatform)) return null;
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final ext = Platform.isWindows ? '.exe' : '';
      final candidates = [
        '$exeDir${Platform.pathSeparator}falcon-core$ext',
        '${Directory.current.path}${Platform.pathSeparator}tooling${Platform.pathSeparator}.cache${Platform.pathSeparator}falcon-core-host$ext',
        '${Directory.current.path}${Platform.pathSeparator}core${Platform.pathSeparator}falcon-core$ext',
      ];
      for (final path in candidates) {
        if (File(path).existsSync()) return path;
      }
    } catch (_) {}
    return null;
  }

  Future<GatewayRuntimeStatus> _buildFallbackStatus({bool? running}) async {
    final plat = _effectivePlatform;
    final lanIps = await _enumerateLanIpv4s();
    final procRunning = _desktopProcess != null;
    final isRunning = running ?? (devAdminUrl.isNotEmpty || procRunning);
    final uptime = _desktopStartedAt != null && procRunning
        ? DateTime.now().difference(_desktopStartedAt!).inMilliseconds
        : 0;

    return GatewayRuntimeStatus(
      running: isRunning,
      adminBaseUrl:
          devAdminUrl.isNotEmpty ? devAdminUrl : 'http://127.0.0.1:18788',
      adminToken: devAdminToken,
      lanIpv4s: lanIps,
      platform: plat,
      keepScreenAwake: _keepScreenAwake,
      backgroundAudioKeepAlive: _backgroundAudioKeepAlive,
      batteryOptimizationIgnored: _batteryIgnored,
      notificationPermissionGranted: _notifGranted,
      wakeLockHeld: isRunning && plat == 'android',
      wifiLockHeld: isRunning && plat == 'android',
      startOnBoot: _startOnBoot,
      uptimeMs: uptime,
      corePid: _desktopProcess?.pid ?? 0,
    );
  }

  @override
  Future<GatewayRuntimeStatus> startGateway() async {
    try {
      final result =
          await _methodChannel.invokeMapMethod<Object?, Object?>('startGateway');
      if (result != null) {
        return GatewayRuntimeStatus.fromMap(
          result,
          platformFallback: _effectivePlatform,
        );
      }
      return await _buildFallbackStatus(running: true);
    } on MissingPluginException {
      if (devAdminUrl.isEmpty && isDesktopPlatformName(_effectivePlatform)) {
        final binary = _findDesktopCoreBinary();
        if (binary != null && _desktopProcess == null) {
          try {
            _desktopProcess = await Process.start(
              binary,
              ['--admin-addr=127.0.0.1:18788'],
            );
            _desktopStartedAt = DateTime.now();
            unawaited(_desktopProcess!.exitCode.then((_) {
              _desktopProcess = null;
              _desktopStartedAt = null;
            }));
          } catch (_) {}
        }
      }
      return await _buildFallbackStatus(
        running: devAdminUrl.isNotEmpty || _desktopProcess != null,
      );
    }
  }

  @override
  Future<GatewayRuntimeStatus> stopGateway() async {
    try {
      final result =
          await _methodChannel.invokeMapMethod<Object?, Object?>('stopGateway');
      if (result != null) {
        return GatewayRuntimeStatus.fromMap(
          result,
          platformFallback: _effectivePlatform,
        );
      }
      return await _buildFallbackStatus(running: false);
    } on MissingPluginException {
      _desktopProcess?.kill();
      _desktopProcess = null;
      _desktopStartedAt = null;
      return await _buildFallbackStatus(running: false);
    }
  }

  @override
  Future<GatewayRuntimeStatus> getRuntimeStatus() async {
    try {
      final result = await _methodChannel
          .invokeMapMethod<Object?, Object?>('getRuntimeStatus');
      if (result != null) {
        return GatewayRuntimeStatus.fromMap(
          result,
          platformFallback: _effectivePlatform,
        );
      }
      return await _buildFallbackStatus();
    } on MissingPluginException {
      return await _buildFallbackStatus();
    }
  }

  @override
  Future<bool> requestBatteryOptimizationExemption() async {
    try {
      final granted = await _methodChannel
          .invokeMethod<bool>('requestBatteryOptimizationExemption');
      return granted ?? false;
    } on MissingPluginException {
      _batteryIgnored = true;
      return true;
    }
  }

  @override
  Future<void> openAppBatterySettings() async {
    try {
      await _methodChannel.invokeMethod<void>('openAppBatterySettings');
    } on MissingPluginException {
      // No-op on desktop/tests.
    }
  }

  @override
  Future<bool> requestNotificationPermission() async {
    try {
      final granted = await _methodChannel
          .invokeMethod<bool>('requestNotificationPermission');
      return granted ?? false;
    } on MissingPluginException {
      _notifGranted = true;
      return true;
    }
  }

  @override
  Future<bool> setStartOnBoot(bool enabled) async {
    try {
      final res = await _methodChannel.invokeMethod<bool>(
        'setStartOnBoot',
        {'enabled': enabled},
      );
      return res ?? enabled;
    } on MissingPluginException {
      _startOnBoot = enabled;
      return enabled;
    }
  }

  @override
  Future<bool> setKeepScreenAwake(bool enabled) async {
    try {
      final res = await _methodChannel.invokeMethod<bool>(
        'setKeepScreenAwake',
        {'enabled': enabled},
      );
      return res ?? enabled;
    } on MissingPluginException {
      _keepScreenAwake = enabled;
      return enabled;
    }
  }

  @override
  Future<bool> setIosBackgroundAudioKeepAlive(bool enabled) async {
    try {
      final res = await _methodChannel.invokeMethod<bool>(
        'setIosBackgroundAudioKeepAlive',
        {'enabled': enabled},
      );
      return res ?? enabled;
    } on MissingPluginException {
      _backgroundAudioKeepAlive = enabled;
      return enabled;
    }
  }

  @override
  Future<void> updateNotificationSummary({
    required bool lanEnabled,
    required int port,
  }) async {
    try {
      await _methodChannel.invokeMethod<void>(
        'updateNotificationSummary',
        {'lanEnabled': lanEnabled, 'port': port},
      );
    } on MissingPluginException {
      // No-op on desktop/tests.
    }
  }

  @override
  Stream<GatewayRuntimeStatus> runtimeEvents() {
    if (kIsWeb) return const Stream.empty();
    return _eventChannel
        .receiveBroadcastStream()
        .where((event) => event is Map)
        .map(
          (event) => GatewayRuntimeStatus.fromMap(
            event as Map,
            platformFallback: _effectivePlatform,
          ),
        )
        .handleError((Object _) {}, test: (e) => e is MissingPluginException);
  }
}

final platformBridgeProvider = Provider<PlatformBridge>((ref) {
  return MethodChannelPlatformBridge();
});
