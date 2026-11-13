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
class RedactRule {
  const RedactRule({
    required this.id,
    required this.name,
    required this.pattern,
    this.replacement = '[REDACTED]',
    this.enabled = true,
  });

  final String id;
  final String name;
  final String pattern;
  final String replacement;
  final bool enabled;

  factory RedactRule.fromJson(Map<String, dynamic> json) {
    return RedactRule(
      id: _asString(json['id']),
      name: _asString(json['name']),
      pattern: _asString(json['pattern']),
      replacement: _asString(json['replacement'], fallback: '[REDACTED]'),
      enabled: _asBool(json['enabled'], fallback: true),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'pattern': pattern,
        'replacement': replacement,
        'enabled': enabled,
      };
}

@immutable
class GatewaySettings {
  const GatewaySettings({
    this.port = 18787,
    this.lanEnabled = false,
    this.allowLocalKeyless = true,
    this.allowIps = const [],
    this.corsOrigins = const [],
    this.redactEnabled = false,
    this.redactRestore = true,
    this.redactRules = const [],
    this.redactAllow = const [],
    this.chinaMirror = true,
  });

  final int port;
  final bool lanEnabled;
  final bool allowLocalKeyless;
  final List<String> allowIps;
  final List<String> corsOrigins;
  final bool redactEnabled;
  final bool redactRestore;
  final List<RedactRule> redactRules;
  final List<String> redactAllow;
  final bool chinaMirror;

  factory GatewaySettings.fromJson(Map<String, dynamic> json) {
    return GatewaySettings(
      port: _asInt(json['port'], fallback: 18787),
      lanEnabled: _asBool(json['lanEnabled']),
      allowLocalKeyless: _asBool(json['allowLocalKeyless'], fallback: true),
      allowIps: _asStringList(json['allowIps']),
      corsOrigins: _asStringList(json['corsOrigins']),
      redactEnabled: _asBool(json['redactEnabled']),
      redactRestore: _asBool(json['redactRestore'], fallback: true),
      redactRules: _asList(json['redactRules'])
          .map((e) => RedactRule.fromJson(_asMap(e)))
          .toList(growable: false),
      redactAllow: _asStringList(json['redactAllow']),
      chinaMirror: _asBool(json['chinaMirror'], fallback: true),
    );
  }

  GatewaySettings copyWith({
    int? port,
    bool? lanEnabled,
    bool? allowLocalKeyless,
    List<String>? allowIps,
    List<String>? corsOrigins,
    bool? redactEnabled,
    bool? redactRestore,
    List<RedactRule>? redactRules,
    List<String>? redactAllow,
    bool? chinaMirror,
  }) {
    return GatewaySettings(
      port: port ?? this.port,
      lanEnabled: lanEnabled ?? this.lanEnabled,
      allowLocalKeyless: allowLocalKeyless ?? this.allowLocalKeyless,
      allowIps: allowIps ?? this.allowIps,
      corsOrigins: corsOrigins ?? this.corsOrigins,
      redactEnabled: redactEnabled ?? this.redactEnabled,
      redactRestore: redactRestore ?? this.redactRestore,
      redactRules: redactRules ?? this.redactRules,
      redactAllow: redactAllow ?? this.redactAllow,
      chinaMirror: chinaMirror ?? this.chinaMirror,
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
class InstalledPlugin {
  const InstalledPlugin({
    required this.package,
    required this.id,
    required this.name,
    this.installed = true,
    this.enabled = true,
    this.version = '',
    this.providers = const [],
    this.models = const [],
    this.options = const {},
    this.accounts = const [],
  });

  final String package;
  final String id;
  final String name;
  final bool installed;
  final bool enabled;
  final String version;
  final List<String> providers;
  final List<String> models;
  final Map<String, dynamic> options;
  final List<PluginAccount> accounts;

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
      providers: _asStringList(json['providers']),
      models: _asStringList(json['models']),
      options: _asMap(json['options']),
      accounts: _asList(json['accounts'])
          .map((e) => PluginAccount.fromJson(_asMap(e)))
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
    this.url,
    this.userCode,
    this.promptLabel,
    this.error,
    this.account,
  });

  /// Phases: `starting`, `open`, `device`, `prompt`, `done`, `failed`
  final String sessionId;
  final String phase;
  final String? url;
  final String? userCode;
  final String? promptLabel;
  final String? error;
  final PluginAccount? account;

  factory PluginSignInSession.fromJson(Map<String, dynamic> json) {
    final acct = json['account'];
    return PluginSignInSession(
      sessionId: _asString(json['sessionId']),
      phase: _asString(json['phase'], fallback: _asString(json['status'], fallback: 'starting')),
      url: json['url'] as String?,
      userCode: json['userCode'] as String?,
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
class RedactSummary {
  const RedactSummary({
    this.enabled = false,
    this.restore = true,
    this.totalHits = 0,
    this.builtinRules = 0,
    this.customRules = 0,
  });

  final bool enabled;
  final bool restore;
  final int totalHits;
  final int builtinRules;
  final int customRules;

  factory RedactSummary.fromJson(Map<String, dynamic> json) {
    return RedactSummary(
      enabled: _asBool(json['enabled']),
      restore: _asBool(json['restore'], fallback: true),
      totalHits: _asInt(json['totalHits'] ?? json['hits']),
      builtinRules: _asInt(json['builtinRules']),
      customRules: _asInt(json['customRules']),
    );
  }
}

@immutable
class RedactHit {
  const RedactHit({
    required this.ruleName,
    required this.placeholder,
    this.category = '',
    this.match = '',
    this.count = 1,
  });

  final String ruleName;
  final String placeholder;
  final String category;
  final String match;
  final int count;

  factory RedactHit.fromJson(Map<String, dynamic> json) {
    return RedactHit(
      ruleName: _asString(json['ruleName'] ?? json['rule'], fallback: 'Rule'),
      placeholder: _asString(json['placeholder']),
      category: _asString(json['category']),
      match: _asString(json['match']),
      count: _asInt(json['count'], fallback: 1),
    );
  }
}

@immutable
class RedactPreviewResult {
  const RedactPreviewResult({
    required this.maskedText,
    this.hits = const [],
  });

  final String maskedText;
  final List<RedactHit> hits;

  factory RedactPreviewResult.fromJson(Map<String, dynamic> json) {
    return RedactPreviewResult(
      maskedText: _asString(json['maskedText']),
      hits: _asList(json['hits'])
          .map((e) => RedactHit.fromJson(_asMap(e)))
          .toList(growable: false),
    );
  }
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
    this.redactionCount = 0,
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
  final int redactionCount;
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
      redactionCount: _asInt(json['redactionCount']),
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
    this.redactSummary = const RedactSummary(),
    this.usageSummary = const UsageSummary(),
  });

  final CoreStatus status;
  final GatewaySettings settings;
  final List<GatewayAccessKey> keys;
  final List<UpstreamProvider> providers;
  final List<InstalledPlugin> plugins;
  final List<RoutingGroup> groups;
  final List<ModelAlias> aliases;
  final RedactSummary redactSummary;
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
      for (final m in pl.models) {
        result.add(m);
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
      redactSummary: RedactSummary.fromJson(_asMap(json['redactSummary'])),
      usageSummary: UsageSummary.fromJson(_asMap(json['usageSummary'])),
    );
  }
}
