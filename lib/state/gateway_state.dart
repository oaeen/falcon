import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../data/admin_api_client.dart';
import '../data/admin_models.dart';
import '../data/platform_bridge.dart';

/// Injectable HTTP client so tests can substitute `MockClient`.
final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

class GatewayRuntimeNotifier extends AsyncNotifier<GatewayRuntimeStatus> {
  StreamSubscription<GatewayRuntimeStatus>? _sub;

  @override
  Future<GatewayRuntimeStatus> build() async {
    final bridge = ref.read(platformBridgeProvider);
    _sub?.cancel();
    _sub = bridge.runtimeEvents().listen((status) {
      state = AsyncData(status);
    });
    ref.onDispose(() => _sub?.cancel());
    return bridge.getRuntimeStatus();
  }

  Future<void> refresh() async {
    final bridge = ref.read(platformBridgeProvider);
    state = AsyncData(await bridge.getRuntimeStatus());
  }

  Future<void> toggleGateway(bool start) async {
    final bridge = ref.read(platformBridgeProvider);
    final next = start ? await bridge.startGateway() : await bridge.stopGateway();
    state = AsyncData(next);
    ref.invalidate(gatewayAdminStateProvider);
  }

  Future<bool> requestBatteryExemption() async {
    final bridge = ref.read(platformBridgeProvider);
    final ok = await bridge.requestBatteryOptimizationExemption();
    await refresh();
    return ok;
  }

  Future<void> openAppBatterySettings() async {
    await ref.read(platformBridgeProvider).openAppBatterySettings();
  }

  Future<bool> requestNotificationPermission() async {
    final bridge = ref.read(platformBridgeProvider);
    final ok = await bridge.requestNotificationPermission();
    await refresh();
    return ok;
  }

  Future<void> setStartOnBoot(bool enabled) async {
    await ref.read(platformBridgeProvider).setStartOnBoot(enabled);
    await refresh();
  }

  Future<void> setKeepScreenAwake(bool enabled) async {
    await ref.read(platformBridgeProvider).setKeepScreenAwake(enabled);
    await refresh();
  }

  Future<void> setIosBackgroundAudioKeepAlive(bool enabled) async {
    await ref
        .read(platformBridgeProvider)
        .setIosBackgroundAudioKeepAlive(enabled);
    await refresh();
  }

  Future<void> syncNotificationSummary({
    required bool lanEnabled,
    required int port,
  }) async {
    await ref
        .read(platformBridgeProvider)
        .updateNotificationSummary(lanEnabled: lanEnabled, port: port);
  }
}

final gatewayRuntimeProvider =
    AsyncNotifierProvider<GatewayRuntimeNotifier, GatewayRuntimeStatus>(
  GatewayRuntimeNotifier.new,
);

final adminApiClientProvider = Provider<AdminApiClient?>((ref) {
  final runtime = ref.watch(gatewayRuntimeProvider).value;
  if (runtime == null || !runtime.running || runtime.adminBaseUrl.isEmpty) {
    return null;
  }
  return AdminApiClient(
    baseUrl: runtime.adminBaseUrl,
    adminToken: runtime.adminToken,
    httpClient: ref.watch(httpClientProvider),
  );
});

final playgroundClientProvider = Provider<StreamingPlaygroundClient>((ref) {
  return StreamingPlaygroundClient(httpClient: ref.watch(httpClientProvider));
});

class GatewayAdminStateNotifier extends AsyncNotifier<AdminStateSnapshot> {
  @override
  Future<AdminStateSnapshot> build() async {
    final client = ref.watch(adminApiClientProvider);
    if (client == null) {
      return const AdminStateSnapshot();
    }
    return client.getState();
  }

  Future<void> reload() async {
    final client = ref.read(adminApiClientProvider);
    if (client == null) {
      state = const AsyncData(AdminStateSnapshot());
      return;
    }
    try {
      final snap = await client.getState();
      state = AsyncData(snap);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> updateSettings(Map<String, dynamic> patch) async {
    final client = ref.read(adminApiClientProvider);
    if (client == null) return;
    final res = await client.updateSettings(patch);
    if (patch.containsKey('lanEnabled') || patch.containsKey('port')) {
      await ref.read(gatewayRuntimeProvider.notifier).syncNotificationSummary(
            lanEnabled: res.settings.lanEnabled,
            port: res.settings.port,
          );
    }
    await reload();
  }
}

final gatewayAdminStateProvider =
    AsyncNotifierProvider<GatewayAdminStateNotifier, AdminStateSnapshot>(
  GatewayAdminStateNotifier.new,
);

final providerPresetsProvider = FutureProvider<List<ProviderPreset>>((ref) async {
  final client = ref.watch(adminApiClientProvider);
  if (client == null) return const [];
  return client.getPresets();
});

final pluginMarketProvider = FutureProvider<List<MarketPlugin>>((ref) async {
  final client = ref.watch(adminApiClientProvider);
  if (client == null) return const [];
  return client.getPluginMarket();
});

class UsageRangeNotifier extends Notifier<String> {
  @override
  String build() => 'today';

  void setRange(String range) {
    state = range;
  }
}

final usageRangeProvider = NotifierProvider<UsageRangeNotifier, String>(
  UsageRangeNotifier.new,
);

final usageSummaryProvider = FutureProvider<UsageSummary>((ref) async {
  final client = ref.watch(adminApiClientProvider);
  final range = ref.watch(usageRangeProvider);
  if (client == null) return UsageSummary(range: range);
  return client.getUsage(range);
});

final requestLogsProvider = FutureProvider<List<RequestLogEntry>>((ref) async {
  final client = ref.watch(adminApiClientProvider);
  if (client == null) return const [];
  return client.getLogs(limit: 100);
});

/// Stores plaintext secrets for gateway access keys created or rotated in the
/// current app session (never persisted to disk).
class SessionKeySecretsNotifier extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() => const {};

  void record(String keyId, String secret) {
    if (keyId.isEmpty || secret.isEmpty) return;
    state = {...state, keyId: secret};
  }
}

final sessionKeySecretsProvider =
    NotifierProvider<SessionKeySecretsNotifier, Map<String, String>>(
  SessionKeySecretsNotifier.new,
);
