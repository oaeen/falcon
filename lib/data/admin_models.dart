import 'package:flutter/foundation.dart';

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((k, v) => MapEntry('$k', v));
  }
  return const {};
}

List<dynamic> _asList(Object? value) {
  if (value is List) return value;
  return const [];
}

List<String> _asStringList(Object? value) {
  if (value is List) {
    return value.map((e) => '$e').where((e) => e.isNotEmpty).toList();
  }
  return const [];
}

Map<String, List<String>> _asStringListMap(Object? value) {
  if (value is! Map) return const {};
  final out = <String, List<String>>{};
  for (final entry in value.entries) {
    final k = '${entry.key}'.trim();
    if (k.isEmpty) continue;
    out[k] = _asStringList(entry.value);
  }
  return out;
}

/// Canonicalizes npm plugin package names so `@magpie-community/*` and bare
/// `opencode-*` entries map cleanly without duplicates in market/installed lists.
String canonicalPluginPackage(String raw) {
  var s = raw.trim().toLowerCase();
  if (s.startsWith('@magpie-community/')) {
    s = s.substring('@magpie-community/'.length);
  }
  final slash = s.indexOf('/');
  final at = s.lastIndexOf('@');
  if (at > 0 && at > slash) {
    s = s.substring(0, at);
  }
  return s;
}

bool isSamePluginPackage(String a, String b) =>
    canonicalPluginPackage(a) == canonicalPluginPackage(b);

bool _asBool(Object? value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is String) {
    if (value == 'true') return true;
    if (value == 'false') return false;
  }
  return fallback;
}

int _asInt(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

double _asDouble(Object? value, {double fallback = 0.0}) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

String _asString(Object? value, {String fallback = ''}) {
  if (value == null) return fallback;
  return '$value';
}

@immutable
class CoreStatus {
  const CoreStatus({
    this.running = false,
    this.listenAddr = '127.0.0.1:18787',
    this.port = 18787,
    this.lanEnabled = false,
    this.requireAccessKey = false,
    this.allowLocalKeyless = true,
    this.lanUrls = const [],
    this.loopbackUrl = 'http://127.0.0.1:18787',
    this.uptimeSec = 0,
    this.modelCount = 0,
    this.activeProviderCount = 0,
    this.pluginRuntimeMode,
  });

  final bool running;
  final String listenAddr;
  final int port;
  final bool lanEnabled;
  final bool requireAccessKey;
  final bool allowLocalKeyless;
  final List<String> lanUrls;
  final String loopbackUrl;
  final int uptimeSec;
  final int modelCount;
  final int activeProviderCount;
  final String? pluginRuntimeMode;

  factory CoreStatus.fromJson(Map<String, dynamic> json) {
    final port = _asInt(json['port'], fallback: 18787);
    final loopback = _asString(json['loopbackUrl']);
    final runtimeMode = json['pluginRuntimeMode'] as String?;
    return CoreStatus(
      running: _asBool(json['running']),
      listenAddr: _asString(json['listenAddr'], fallback: '127.0.0.1:$port'),
      port: port,
      lanEnabled: _asBool(json['lanEnabled']),
      requireAccessKey: _asBool(json['requireAccessKey']),
      allowLocalKeyless: _asBool(json['allowLocalKeyless'], fallback: true),
      lanUrls: _asStringList(json['lanUrls']),
      loopbackUrl: loopback.isNotEmpty ? loopback : 'http://127.0.0.1:$port',
      uptimeSec: _asInt(json['uptimeSec']),
      modelCount: _asInt(json['modelCount']),
      activeProviderCount: _asInt(json['activeProviderCount']),
      pluginRuntimeMode:
          (runtimeMode != null && runtimeMode.isNotEmpty) ? runtimeMode : null,
    );
  }
}

@immutable
class GatewaySettings {
  const GatewaySettings({
    this.port = 18787,
    this.lanEnabled = false,
    this.requireAccessKey = false,
    this.allowLocalKeyless = true,
    this.allowIps = const [],
    this.corsOrigins = const [],
    this.chinaMirror = true,
    this.pluginSelectedModels = const {},
  });

  final int port;
  final bool lanEnabled;
  final bool requireAccessKey;
  final bool allowLocalKeyless;
  final List<String> allowIps;
  final List<String> corsOrigins;
  final bool chinaMirror;
  final Map<String, List<String>> pluginSelectedModels;

  factory GatewaySettings.fromJson(Map<String, dynamic> json) {
    return GatewaySettings(
      port: _asInt(json['port'], fallback: 18787),
      lanEnabled: _asBool(json['lanEnabled']),
      requireAccessKey: _asBool(json['requireAccessKey']),
      allowLocalKeyless: _asBool(json['allowLocalKeyless'], fallback: true),
      allowIps: _asStringList(json['allowIps']),
      corsOrigins: _asStringList(json['corsOrigins']),
      chinaMirror: _asBool(json['chinaMirror'], fallback: true),
      pluginSelectedModels: _asStringListMap(json['pluginSelectedModels']),
    );
  }

  GatewaySettings copyWith({
    int? port,
    bool? lanEnabled,
    bool? requireAccessKey,
    bool? allowLocalKeyless,
    List<String>? allowIps,
    List<String>? corsOrigins,
    bool? chinaMirror,
    Map<String, List<String>>? pluginSelectedModels,
  }) {
    return GatewaySettings(
      port: port ?? this.port,
      lanEnabled: lanEnabled ?? this.lanEnabled,
      requireAccessKey: requireAccessKey ?? this.requireAccessKey,
      allowLocalKeyless: allowLocalKeyless ?? this.allowLocalKeyless,
      allowIps: allowIps ?? this.allowIps,
      corsOrigins: corsOrigins ?? this.corsOrigins,
      chinaMirror: chinaMirror ?? this.chinaMirror,
      pluginSelectedModels: pluginSelectedModels ?? this.pluginSelectedModels,
    );
  }
}

@immutable
class GatewayAccessKey {
  const GatewayAccessKey({
    required this.id,
    required this.name,
    this.prefix = 'sk-flc-...',
    this.secret,
    this.enabled = true,
    this.allowedModels = const [],
    this.dailyLimitUsd = 0,
    this.monthlyLimitUsd = 0,
    this.dailyLimitReqs = 0,
    this.todayUsd = 0,
    this.monthUsd = 0,
    this.todayReqs = 0,
    this.lastUsedAt,
    this.createdAt,
  });

  final String id;
  final String name;
  final String prefix;
  final String? secret;
  final bool enabled;
  final List<String> allowedModels;
  final double dailyLimitUsd;
  final double monthlyLimitUsd;
  final int dailyLimitReqs;
  final double todayUsd;
  final double monthUsd;
  final int todayReqs;
  final String? lastUsedAt;
  final String? createdAt;

  factory GatewayAccessKey.fromJson(Map<String, dynamic> json) {
    final secretRaw = json['secret'];
    final secret = (secretRaw is String && secretRaw.isNotEmpty)
        ? secretRaw
        : null;
    final prefix = _asString(
      json['prefix'] ?? json['maskedSecret'] ?? json['preview'],
      fallback: 'sk-flc-...',
    );
    return GatewayAccessKey(
      id: _asString(json['id']),
      name: _asString(json['name'], fallback: 'Unnamed Key'),
      prefix: prefix,
      secret: secret,
      enabled: _asBool(json['enabled'], fallback: true),
      allowedModels: _asStringList(json['allowedModels']),
      dailyLimitUsd: _asDouble(json['dailyLimitUsd']),
      monthlyLimitUsd: _asDouble(json['monthlyLimitUsd']),
      dailyLimitReqs: _asInt(json['dailyLimitReqs']),
      todayUsd: _asDouble(json['todayUsd']),
      monthUsd: _asDouble(json['monthUsd']),
      todayReqs: _asInt(json['todayReqs']),
      lastUsedAt: json['lastUsedAt'] as String?,
      createdAt: json['createdAt'] as String?,
    );
  }
}

@immutable
class ProviderKeyEntry {
  const ProviderKeyEntry({
    required this.id,
    this.label = '',
    this.maskedSecret = '',
    this.secret,
    this.enabled = true,
    this.weight = 1,
  });

  final String id;
  final String label;
  final String maskedSecret;
  final String? secret;
  final bool enabled;
  final int weight;

  factory ProviderKeyEntry.fromJson(Map<String, dynamic> json) {
    return ProviderKeyEntry(
      id: _asString(json['id']),
      label: _asString(json['label']),
      maskedSecret: _asString(
        json['maskedSecret'] ?? json['secretMasked'] ?? json['prefix'],
        fallback: '***',
      ),
      enabled: _asBool(json['enabled'], fallback: true),
      weight: _asInt(json['weight'], fallback: 1),
    );
  }

  Map<String, dynamic> toUpsertJson() => {
        if (id.isNotEmpty) 'id': id,
        'label': label,
        if (secret != null && secret!.isNotEmpty) 'secret': secret,
        'enabled': enabled,
        'weight': weight,
      };
}

@immutable
class ProviderTestResult {
  const ProviderTestResult({
    required this.ok,
    this.statusCode = 0,
    this.latencyMs = 0,
    this.model = '',
    this.replyPreview = '',
    this.error = '',
  });

  final bool ok;
  final int statusCode;
  final int latencyMs;
  final String model;
  final String replyPreview;
  final String error;

  factory ProviderTestResult.fromJson(Map<String, dynamic> json) {
    return ProviderTestResult(
      ok: _asBool(json['ok']),
      statusCode: _asInt(json['statusCode']),
      latencyMs: _asInt(json['latencyMs']),
      model: _asString(json['model']),
      replyPreview: _asString(json['replyPreview']),
      error: _asString(json['error']),
    );
  }
}

@immutable
class UpstreamProvider {
  const UpstreamProvider({
    required this.id,
    required this.name,
    this.preset = 'custom',
    this.protocol = 'openai',
    required this.baseUrl,
    this.enabled = true,
    this.keys = const [],
    this.models = const [],
    this.selectedModels = const [],
    this.lastTest,
  });

  final String id;
  final String name;
  final String preset;
  final String protocol;
  final String baseUrl;
  final bool enabled;
  final List<ProviderKeyEntry> keys;
  final List<String> models;
  final List<String> selectedModels;
  final ProviderTestResult? lastTest;

  factory UpstreamProvider.fromJson(Map<String, dynamic> json) {
    final testRaw = json['lastTest'];
    return UpstreamProvider(
      id: _asString(json['id']),
      name: _asString(json['name']),
      preset: _asString(json['preset'], fallback: 'custom'),
      protocol: _asString(json['protocol'], fallback: 'openai'),
      baseUrl: _asString(json['baseUrl']),
      enabled: _asBool(json['enabled'], fallback: true),
      keys: _asList(json['keys'])
          .map((e) => ProviderKeyEntry.fromJson(_asMap(e)))
          .toList(growable: false),
      models: _asStringList(json['models']),
      selectedModels: _asStringList(json['selectedModels']),
      lastTest: testRaw is Map
          ? ProviderTestResult.fromJson(_asMap(testRaw))
          : null,
    );
  }
}

@immutable
class ProviderPreset {
  const ProviderPreset({
    required this.id,
    required this.name,
    this.protocol = 'openai',
    required this.baseUrl,
    this.defaultModels = const [],
    this.requiresKey = true,
  });

  final String id;
  final String name;
  final String protocol;
  final String baseUrl;
  final List<String> defaultModels;
  final bool requiresKey;

  factory ProviderPreset.fromJson(Map<String, dynamic> json) {
    return ProviderPreset(
      id: _asString(json['id']),
      name: _asString(json['name']),
      protocol: _asString(json['protocol'], fallback: 'openai'),
      baseUrl: _asString(json['baseUrl']),
      defaultModels: _asStringList(json['defaultModels'] ?? json['models']),
      requiresKey: _asBool(json['requiresKey'], fallback: true),
    );
  }
}

@immutable
class QuotaWindow {
  const QuotaWindow({
    required this.label,
    this.used = 0,
    this.limit = 0,
    this.remainingPct,
    this.resetAt,
  });

  final String label;
  final double used;
  final double limit;
  final double? remainingPct;
  final String? resetAt;

  factory QuotaWindow.fromJson(Map<String, dynamic> json) {
    return QuotaWindow(
      label: _asString(json['label'], fallback: 'Quota'),
      used: _asDouble(json['used']),
      limit: _asDouble(json['limit']),
      remainingPct: json['remainingPct'] != null
          ? _asDouble(json['remainingPct'])
          : null,
      resetAt: json['resetAt'] as String?,
    );
  }
}

@immutable
class PluginAccount {
  const PluginAccount({
    required this.id,
    required this.providerId,
    required this.label,
    this.email = '',
    this.status = 'active',
    this.enabled = true,
    this.quotas = const [],
  });

  final String id;
  final String providerId;
  final String label;
  final String email;
  final String status;
  final bool enabled;
  final List<QuotaWindow> quotas;

  factory PluginAccount.fromJson(Map<String, dynamic> json) {
    return PluginAccount(
      id: _asString(json['id']),
      providerId: _asString(json['providerId']),
      label: _asString(json['label'], fallback: _asString(json['email'])),
      email: _asString(json['email']),
      status: _asString(json['status'], fallback: 'active'),
      enabled: _asBool(json['enabled'], fallback: true),
      quotas: _asList(json['quotas'])
          .map((e) => QuotaWindow.fromJson(_asMap(e)))
          .toList(growable: false),
    );
  }
}

@immutable
class PluginModelInfo {
  const PluginModelInfo({
    required this.id,
    this.name = '',
    this.protocol = 'openai',
    this.context = 0,
    this.output = 0,
    this.free = false,
    this.reasoning = false,
    this.toolCall = false,
  });

  final String id;
  final String name;
  final String protocol;
  final int context;
  final int output;
  final bool free;
  final bool reasoning;
  final bool toolCall;

  String get displayName => name.isNotEmpty ? name : id;

  factory PluginModelInfo.fromJson(Map<String, dynamic> json) {
    final limit = _asMap(json['limit']);
    final caps = _asMap(json['capabilities']);
    final id = _asString(json['id']);
    return PluginModelInfo(
      id: id,
      name: _asString(json['name'], fallback: id),
      protocol: _asString(json['protocol'], fallback: 'openai'),
      context: _asInt(
        json['context'],
        fallback: _asInt(limit['context']),
      ),
      output: _asInt(
        json['output'],
        fallback: _asInt(limit['output']),
      ),
      free: _asBool(json['free']),
      reasoning: _asBool(
        json['reasoning'],
        fallback: _asBool(caps['reasoning']),
      ),
      toolCall: _asBool(
        json['toolCall'],
        fallback: _asBool(
          json['tool_call'],
          fallback: _asBool(
            caps['toolcall'],
            fallback: _asBool(caps['toolCall']),
          ),
        ),
      ),
    );
  }
}

@immutable
class PluginAuthMethod {
  const PluginAuthMethod({
    required this.index,
    this.type = 'oauth',
    required this.label,
    this.keyless = false,
    this.placeholder = '',
  });

  final int index;

  /// `'api'` | `'oauth'`
  final String type;
  final String label;
  final bool keyless;
  final String placeholder;

  bool get isDesktopOnly {
    final lower = label.toLowerCase();
    return lower.contains('local app') ||
        lower.contains('desktop') ||
        lower.contains('read local') ||
        lower.contains('本地客户端') ||
        lower.contains('本地登录态');
  }

  factory PluginAuthMethod.fromJson(Map<String, dynamic> json, {int fallbackIndex = 0}) {
    return PluginAuthMethod(
      index: _asInt(json['index'], fallback: fallbackIndex),
      type: _asString(json['type'], fallback: 'oauth'),
      label: _asString(json['label']),
      keyless: _asBool(json['keyless']),
      placeholder: _asString(json['placeholder']),
    );
  }
}

@immutable
class PluginProviderDetail {
  const PluginProviderDetail({
    required this.id,
    required this.name,
    this.protocol = 'openai',
    this.authenticated = false,
    this.accountCount = 0,
    this.accounts = const [],
    this.models = const [],
    this.selectedModels = const [],
    this.methods = const [],
    this.supportsUsage = false,
    this.supportsCheckin = false,
    this.supportsModels = true,
    this.lastError = '',
  });

  final String id;
  final String name;
  final String protocol;
  final bool authenticated;
  final int accountCount;
  final List<PluginAccount> accounts;
  final List<PluginModelInfo> models;
  final List<String> selectedModels;
  final List<PluginAuthMethod> methods;
  final bool supportsUsage;
  final bool supportsCheckin;
  final bool supportsModels;
  final String lastError;

  List<String> get effectiveModelIds => selectedModels.isNotEmpty
      ? selectedModels
      : models.map((m) => m.id).where((id) => id.isNotEmpty).toList();

  factory PluginProviderDetail.fromJson(Map<String, dynamic> json) {
    final accts = _asList(json['accounts'])
        .map((e) => PluginAccount.fromJson(_asMap(e)))
        .toList(growable: false);
    final rawMethods = _asList(json['methods']);
    final parsedMethods = <PluginAuthMethod>[];
    for (var i = 0; i < rawMethods.length; i++) {
      parsedMethods.add(
        PluginAuthMethod.fromJson(_asMap(rawMethods[i]), fallbackIndex: i),
      );
    }
    final models = _asList(json['models'])
        .map((e) => e is String
            ? PluginModelInfo(id: e, name: e)
            : PluginModelInfo.fromJson(_asMap(e)))
        .where((m) => m.id.isNotEmpty)
        .toList(growable: false);
    final id = _asString(json['id']);
    final authRaw = json['authenticated'];
    final authenticated =
        authRaw is bool ? authRaw : accts.any((a) => a.enabled);
    final err = _asString(json['lastError'], fallback: _asString(json['listError']));
    return PluginProviderDetail(
      id: id,
      name: _asString(json['name'], fallback: id),
      protocol: _asString(json['protocol'], fallback: 'openai'),
      authenticated: authenticated,
      accountCount: _asInt(json['accountCount'], fallback: accts.length),
      accounts: accts,
      models: models,
      selectedModels: _asStringList(json['selectedModels']),
      methods: parsedMethods,
      supportsUsage: _asBool(json['supportsUsage']),
      supportsCheckin: _asBool(json['supportsCheckin']),
      supportsModels: _asBool(
        json['supportsModels'],
        fallback: models.isNotEmpty || parsedMethods.isNotEmpty,
      ),
      lastError: err,
    );
  }
}

@immutable
class InstalledPlugin {
  const InstalledPlugin({
    required this.package,
    required this.id,
    required this.name,
    this.installed = true,
    this.enabled = true,
    this.version = '',
    this.error = '',
    this.providers = const [],
    this.models = const [],
    this.options = const {},
    this.accounts = const [],
    this.providerDetails = const [],
  });

  final String package;
  final String id;
  final String name;
  final bool installed;
  final bool enabled;
  final String version;
  final String error;
  final List<String> providers;
  final List<String> models;
  final Map<String, dynamic> options;
  final List<PluginAccount> accounts;
  final List<PluginProviderDetail> providerDetails;

  /// Resolves per-provider rich details, synthesizing clean fallbacks from
  /// `providers` + `accounts` + `models` when a fixture omits `providerDetails`.
  List<PluginProviderDetail> resolvedProviderDetails(
    Map<String, List<String>> settingsSelectedModels,
  ) {
    if (providerDetails.isNotEmpty) {
      return providerDetails
          .map((d) {
            final override = settingsSelectedModels[d.id];
            if (d.selectedModels.isEmpty &&
                override != null &&
                override.isNotEmpty) {
              return PluginProviderDetail(
                id: d.id,
                name: d.name,
                protocol: d.protocol,
                authenticated: d.authenticated,
                accountCount: d.accountCount,
                accounts: d.accounts,
                models: d.models,
                selectedModels: override,
                methods: d.methods,
                supportsUsage: d.supportsUsage,
                supportsCheckin: d.supportsCheckin,
                supportsModels: d.supportsModels,
                lastError: d.lastError,
              );
            }
            return d;
          })
          .toList(growable: false);
    }

    final pids = providers.isNotEmpty
        ? providers
        : accounts
            .map((a) => a.providerId)
            .where((p) => p.isNotEmpty)
            .toSet()
            .toList(growable: false);
    if (pids.isEmpty) {
      return [
        PluginProviderDetail(
          id: id,
          name: name,
          authenticated: accounts.any((a) => a.enabled),
          accountCount: accounts.length,
          accounts: accounts,
          models: models
              .map((m) => PluginModelInfo(id: m, name: m))
              .toList(growable: false),
          selectedModels: settingsSelectedModels[id] ?? const [],
          supportsUsage: accounts.any((a) => a.quotas.isNotEmpty),
        ),
      ];
    }
    return pids.map((pid) {
      final accts = accounts
          .where((a) => a.providerId == pid || a.providerId.isEmpty)
          .toList(growable: false);
      return PluginProviderDetail(
        id: pid,
        name: pid,
        authenticated: accts.any((a) => a.enabled),
        accountCount: accts.length,
        accounts: accts,
        models: models
            .map((m) => PluginModelInfo(id: m, name: m))
            .toList(growable: false),
        selectedModels: settingsSelectedModels[pid] ?? const [],
        supportsUsage: accts.any((a) => a.quotas.isNotEmpty),
      );
    }).toList(growable: false);
  }

  factory InstalledPlugin.fromJson(Map<String, dynamic> json) {
    final pkg = _asString(json['package']);
    final id = _asString(json['id'], fallback: pkg);
    return InstalledPlugin(
      package: pkg.isNotEmpty ? pkg : id,
      id: id,
      name: _asString(json['name'], fallback: id),
      installed: _asBool(json['installed'], fallback: true),
      enabled: _asBool(json['enabled'], fallback: true),
      version: _asString(json['version']),
      error: _asString(json['error']),
      providers: _asStringList(json['providers']),
      models: _asStringList(json['models']),
      options: _asMap(json['options']),
      accounts: _asList(json['accounts'])
          .map((e) => PluginAccount.fromJson(_asMap(e)))
          .toList(growable: false),
      providerDetails: _asList(json['providerDetails'])
          .map((e) => PluginProviderDetail.fromJson(_asMap(e)))
          .toList(growable: false),
    );
  }
}

@immutable
class MarketPlugin {
  const MarketPlugin({
    required this.package,
    required this.name,
    this.category = 'auth',
    this.summaryZh = '',
    this.summaryEn = '',
    this.providers = const [],
    this.installed = false,
    this.version = '',
    this.community = true,
  });

  final String package;
  final String name;
  final String category;
  final String summaryZh;
  final String summaryEn;
  final List<String> providers;
  final bool installed;
  final String version;
  final bool community;

  String localizedSummary(String languageCode) {
    if (languageCode == 'en') {
      return summaryEn.isNotEmpty ? summaryEn : summaryZh;
    }
    return summaryZh.isNotEmpty ? summaryZh : summaryEn;
  }

  factory MarketPlugin.fromJson(Map<String, dynamic> json) {
    final summaryRaw = json['summary'];
    var zh = _asString(json['summaryZh']);
    var en = _asString(json['summaryEn']);
    if (summaryRaw is Map) {
      zh = zh.isNotEmpty ? zh : _asString(summaryRaw['zh']);
      en = en.isNotEmpty ? en : _asString(summaryRaw['en']);
    } else if (summaryRaw is String && zh.isEmpty && en.isEmpty) {
      zh = summaryRaw;
      en = summaryRaw;
    }
    final kind = _asString(json['category'], fallback: _asString(json['kind']));
    return MarketPlugin(
      package: _asString(json['package']),
      name: _asString(json['name'], fallback: _asString(json['package'])),
      category: kind.isNotEmpty ? kind : 'auth',
      summaryZh: zh,
      summaryEn: en,
      providers: _asStringList(json['providers']),
      installed: _asBool(json['installed']),
      version: _asString(json['version']),
      community: _asBool(json['community'], fallback: true),
    );
  }
}

@immutable
class PluginSignInSession {
  const PluginSignInSession({
    required this.sessionId,
    required this.phase,
    this.providerId = '',
    this.method = '',
    this.url,
    this.instructions,
    this.userCode,
    this.promptLabel,
    this.error,
    this.account,
  });

  /// Phases: `starting`, `open`, `open_auto`, `device`, `prompt`, `done`, `failed`
  final String sessionId;
  final String phase;
  final String providerId;
  final String method;
  final String? url;
  final String? instructions;
  final String? userCode;
  final String? promptLabel;
  final String? error;
  final PluginAccount? account;

  factory PluginSignInSession.fromJson(Map<String, dynamic> json) {
    final acct = json['account'];
    return PluginSignInSession(
      sessionId: _asString(json['sessionId']),
      phase: _asString(
        json['phase'],
        fallback: _asString(json['status'], fallback: 'starting'),
      ),
      providerId: _asString(json['providerId']),
      method: _asString(json['method']),
      url: json['url'] as String?,
      instructions: json['instructions'] as String?,
      userCode: _asString(
        json['userCode'],
        fallback: _asString(json['deviceCode']),
      ).isEmpty
          ? null
          : _asString(json['userCode'], fallback: _asString(json['deviceCode'])),
      promptLabel: json['promptLabel'] as String?,
      error: json['error'] as String?,
      account: acct is Map ? PluginAccount.fromJson(_asMap(acct)) : null,
    );
  }
}

@immutable
class RoutingGroup {
  const RoutingGroup({
    required this.id,
    required this.name,
    this.strategy = 'order',
    this.pinnedMember = '',
    this.enabled = true,
    this.members = const [],
  });

  final String id;
  final String name;

  /// `order` | `round_robin` | `fastest` | `manual`
  final String strategy;
  final String pinnedMember;
  final bool enabled;
  final List<String> members;

  factory RoutingGroup.fromJson(Map<String, dynamic> json) {
    final rawMembers = _asList(json['members']);
    final parsedMembers = <String>[];
    for (final m in rawMembers) {
      if (m is String && m.isNotEmpty) {
        parsedMembers.add(m);
      } else if (m is Map) {
        final map = _asMap(m);
        final target = _asString(map['target']);
        if (target.isNotEmpty) {
          parsedMembers.add(target);
        } else {
          final prov = _asString(map['providerId']);
          final model = _asString(map['model']);
          if (prov.isNotEmpty && model.isNotEmpty) {
            parsedMembers.add('$prov/$model');
          }
        }
      }
    }
    return RoutingGroup(
      id: _asString(json['id']),
      name: _asString(json['name']),
      strategy: _asString(json['strategy'], fallback: 'order'),
      pinnedMember: _asString(json['pinnedMember']),
      enabled: _asBool(json['enabled'], fallback: true),
      members: parsedMembers,
    );
  }

  Map<String, dynamic> toJson() => {
        if (id.isNotEmpty) 'id': id,
        'name': name,
        'strategy': strategy,
        'pinnedMember': pinnedMember,
        'enabled': enabled,
        'members': members,
      };
}

@immutable
class ModelAlias {
  const ModelAlias({
    required this.alias,
    required this.target,
  });

  final String alias;
  final String target;

  static List<ModelAlias> listFromJson(Object? raw) {
    if (raw is List) {
      return raw
          .map((e) => _asMap(e))
          .map(
            (m) => ModelAlias(
              alias: _asString(m['alias']),
              target: _asString(m['target']),
            ),
          )
          .where((a) => a.alias.isNotEmpty)
          .toList(growable: false);
    }
    if (raw is Map) {
      return raw.entries
          .map((e) => ModelAlias(alias: '${e.key}', target: '${e.value}'))
          .where((a) => a.alias.isNotEmpty)
          .toList(growable: false);
    }
    return const [];
  }

  Map<String, dynamic> toJson() => {
        'alias': alias,
        'target': target,
      };
}

@immutable
class UsageSummary {
  const UsageSummary({
    this.range = 'today',
    this.requests = 0,
    this.successRequests = 0,
    this.errorRequests = 0,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.totalTokens = 0,
    this.estimatedUsd = 0,
    this.avgTtftMs = 0,
  });

  final String range;
  final int requests;
  final int successRequests;
  final int errorRequests;
  final int inputTokens;
  final int outputTokens;
  final int totalTokens;
  final double estimatedUsd;
  final int avgTtftMs;

  factory UsageSummary.fromJson(Map<String, dynamic> json) {
    final inTok = _asInt(json['inputTokens']);
    final outTok = _asInt(json['outputTokens']);
    final totalTok = _asInt(json['totalTokens']);
    return UsageSummary(
      range: _asString(json['range'], fallback: 'today'),
      requests: _asInt(json['requests']),
      successRequests: _asInt(json['successRequests']),
      errorRequests: _asInt(json['errorRequests']),
      inputTokens: inTok,
      outputTokens: outTok,
      totalTokens: totalTok > 0 ? totalTok : (inTok + outTok),
      estimatedUsd: _asDouble(json['estimatedUsd']),
      avgTtftMs: _asInt(json['avgTtftMs']),
    );
  }
}

@immutable
class RequestLogEntry {
  const RequestLogEntry({
    required this.id,
    required this.timestamp,
    this.clientIp = '127.0.0.1',
    this.isLocal = true,
    this.keyName = '',
    this.requestedModel = '',
    this.upstreamProvider = '',
    this.upstreamModel = '',
    this.protocol = 'openai',
    this.statusCode = 200,
    this.ttftMs = 0,
    this.latencyMs = 0,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.estimatedUsd = 0,
    this.failoverAttempts = 0,
    this.error = '',
  });

  final String id;
  final String timestamp;
  final String clientIp;
  final bool isLocal;
  final String keyName;
  final String requestedModel;
  final String upstreamProvider;
  final String upstreamModel;
  final String protocol;
  final int statusCode;
  final int ttftMs;
  final int latencyMs;
  final int inputTokens;
  final int outputTokens;
  final double estimatedUsd;
  final int failoverAttempts;
  final String error;

  factory RequestLogEntry.fromJson(Map<String, dynamic> json) {
    final ip = _asString(json['clientIp'], fallback: '127.0.0.1');
    final isLocalRaw = json['isLocal'];
    final isLocal = isLocalRaw is bool
        ? isLocalRaw
        : (ip == '127.0.0.1' || ip == '::1' || ip.isEmpty);
    return RequestLogEntry(
      id: _asString(json['id']),
      timestamp: _asString(json['timestamp']),
      clientIp: ip,
      isLocal: isLocal,
      keyName: _asString(json['keyName']),
      requestedModel: _asString(json['requestedModel']),
      upstreamProvider: _asString(json['upstreamProvider']),
      upstreamModel: _asString(json['upstreamModel']),
      protocol: _asString(json['protocol'], fallback: 'openai'),
      statusCode: _asInt(json['statusCode'], fallback: 200),
      ttftMs: _asInt(json['ttftMs']),
      latencyMs: _asInt(json['latencyMs']),
      inputTokens: _asInt(json['inputTokens']),
      outputTokens: _asInt(json['outputTokens']),
      estimatedUsd: _asDouble(json['estimatedUsd']),
      failoverAttempts: _asInt(json['failoverAttempts']),
      error: _asString(json['error']),
    );
  }
}

@immutable
class AdminStateSnapshot {
  const AdminStateSnapshot({
    this.status = const CoreStatus(),
    this.settings = const GatewaySettings(),
    this.keys = const [],
    this.providers = const [],
    this.plugins = const [],
    this.groups = const [],
    this.aliases = const [],
    this.usageSummary = const UsageSummary(),
  });

  final CoreStatus status;
  final GatewaySettings settings;
  final List<GatewayAccessKey> keys;
  final List<UpstreamProvider> providers;
  final List<InstalledPlugin> plugins;
  final List<RoutingGroup> groups;
  final List<ModelAlias> aliases;
  final UsageSummary usageSummary;

  List<String> get availableTargets {
    final result = <String>[];
    for (final g in groups) {
      if (g.enabled && g.name.isNotEmpty) result.add(g.name);
    }
    for (final p in providers) {
      if (!p.enabled) continue;
      final list = p.selectedModels.isNotEmpty ? p.selectedModels : p.models;
      for (final m in list) {
        result.add('${p.id}/$m');
      }
    }
    for (final pl in plugins) {
      if (!pl.enabled) continue;
      if (pl.providerDetails.isNotEmpty) {
        for (final detail in pl.providerDetails) {
          final modelIds = detail.effectiveModelIds;
          for (final m in modelIds) {
            result.add(m.contains('/') ? m : '${detail.id}/$m');
          }
        }
      } else {
        for (final m in pl.models) {
          result.add(m);
        }
      }
    }
    return result.toSet().toList(growable: false);
  }

  factory AdminStateSnapshot.fromJson(Map<String, dynamic> json) {
    return AdminStateSnapshot(
      status: CoreStatus.fromJson(_asMap(json['status'])),
      settings: GatewaySettings.fromJson(_asMap(json['settings'])),
      keys: _asList(json['keys'])
          .map((e) => GatewayAccessKey.fromJson(_asMap(e)))
          .toList(growable: false),
      providers: _asList(json['providers'])
          .map((e) => UpstreamProvider.fromJson(_asMap(e)))
          .toList(growable: false),
      plugins: _asList(json['plugins'])
          .map((e) => InstalledPlugin.fromJson(_asMap(e)))
          .toList(growable: false),
      groups: _asList(json['groups'])
          .map((e) => RoutingGroup.fromJson(_asMap(e)))
          .toList(growable: false),
      aliases: ModelAlias.listFromJson(json['aliases']),
      usageSummary: UsageSummary.fromJson(_asMap(json['usageSummary'])),
    );
  }
}
