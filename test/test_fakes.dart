import 'dart:async';
import 'dart:convert';

import 'package:falcon/data/platform_bridge.dart';
import 'package:falcon/state/gateway_state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakePlatformBridge implements PlatformBridge {
  FakePlatformBridge({
    GatewayRuntimeStatus? initialStatus,
  }) : status = initialStatus ??
            const GatewayRuntimeStatus(
              running: true,
              adminBaseUrl: 'http://127.0.0.1:18788',
              adminToken: 'test-admin-token',
              lanIpv4s: ['192.168.1.42'],
              platform: 'android',
              batteryOptimizationIgnored: false,
              notificationPermissionGranted: false,
              wakeLockHeld: true,
              wifiLockHeld: true,
              startOnBoot: false,
              uptimeMs: 125000,
              corePid: 4321,
            );

  GatewayRuntimeStatus status;
  final _events = StreamController<GatewayRuntimeStatus>.broadcast();
  bool lastLanSummary = false;
  int lastPortSummary = 18787;

  void emit(GatewayRuntimeStatus next) {
    status = next;
    _events.add(next);
  }

  @override
  Future<GatewayRuntimeStatus> getRuntimeStatus() async => status;

  @override
  Future<GatewayRuntimeStatus> startGateway() async {
    status = status.copyWith(
      running: true,
      wakeLockHeld: status.isAndroid,
      wifiLockHeld: status.isAndroid,
      uptimeMs: 1000,
      corePid: 4321,
    );
    return status;
  }

  @override
  Future<GatewayRuntimeStatus> stopGateway() async {
    status = status.copyWith(
      running: false,
      wakeLockHeld: false,
      wifiLockHeld: false,
      uptimeMs: 0,
      corePid: 0,
    );
    return status;
  }

  @override
  Future<bool> requestBatteryOptimizationExemption() async {
    status = status.copyWith(batteryOptimizationIgnored: true);
    return true;
  }

  @override
  Future<void> openAppBatterySettings() async {}

  @override
  Future<bool> requestNotificationPermission() async {
    status = status.copyWith(notificationPermissionGranted: true);
    return true;
  }

  @override
  Future<bool> setStartOnBoot(bool enabled) async {
    status = status.copyWith(startOnBoot: enabled);
    return enabled;
  }

  @override
  Future<bool> setKeepScreenAwake(bool enabled) async {
    status = status.copyWith(keepScreenAwake: enabled);
    return enabled;
  }

  @override
  Future<bool> setIosBackgroundAudioKeepAlive(bool enabled) async {
    status = status.copyWith(backgroundAudioKeepAlive: enabled);
    return enabled;
  }

  @override
  Future<void> updateNotificationSummary({
    required bool lanEnabled,
    required int port,
  }) async {
    lastLanSummary = lanEnabled;
    lastPortSummary = port;
  }

  @override
  Stream<GatewayRuntimeStatus> runtimeEvents() => _events.stream;
}

class MockAdminBackend {
  bool lanEnabled = false;
  bool allowLocalKeyless = true;
  String? lastChatAuthorizationHeader;
  bool redactEnabled = true;
  bool redactRestore = true;
  bool chinaMirror = true;
  int port = 18787;
  List<String> allowIps = [];
  List<String> corsOrigins = [];
  List<Map<String, dynamic>> redactRules = [];
  List<String> redactAllow = ['127.0.0.1'];

  final List<Map<String, dynamic>> keys = [
    {
      'id': 'key-1',
      'name': 'MacBook Pro',
      'prefix': 'sk-flc-ab12...89ef',
      'enabled': true,
      'allowedModels': ['gpt-4o'],
      'dailyLimitUsd': 5.0,
      'monthlyLimitUsd': 50.0,
      'dailyLimitReqs': 500,
      'todayUsd': 0.42,
      'monthUsd': 4.18,
      'todayReqs': 18,
    },
  ];

  final List<Map<String, dynamic>> providers = [
    {
      'id': 'deepseek-1',
      'name': 'DeepSeek',
      'preset': 'deepseek',
      'protocol': 'openai',
      'baseUrl': 'https://api.deepseek.com/v1',
      'enabled': true,
      'keys': [
        {
          'id': 'pk-1',
          'label': 'Primary',
          'maskedSecret': 'sk-...9876',
          'enabled': true,
          'weight': 1,
        },
      ],
      'models': ['deepseek-chat', 'deepseek-reasoner'],
      'selectedModels': ['deepseek-chat'],
      'lastTest': {
        'ok': true,
        'statusCode': 200,
        'latencyMs': 185,
        'model': 'deepseek-chat',
        'replyPreview': 'OK',
      },
    },
  ];

  final List<Map<String, dynamic>> plugins = [
    {
      'package': '@magpie-community/opencode-zen-free-auth',
      'id': 'opencode-zen-free',
      'name': 'OpenCode Zen Free',
      'installed': true,
      'enabled': true,
      'version': '1.0.2',
      'providers': ['opencode-zen-free'],
      'models': ['opencode-zen-free/qwen-coder'],
      'accounts': [
        {
          'id': 'acc-pub',
          'providerId': 'opencode-zen-free',
          'label': 'Public Credential',
          'status': 'active',
          'enabled': true,
          'quotas': [
            {'label': '5h', 'used': 12, 'limit': 100},
          ],
        },
      ],
    },
  ];

  final List<Map<String, dynamic>> marketPlugins = [
    {
      'package': '@magpie-community/opencode-zen-free-auth',
      'name': 'OpenCode Zen Free',
      'category': 'auth',
      'summaryZh': '使用 public 凭证接入 OpenCode Zen 免费模型。',
      'summaryEn': 'Access OpenCode Zen free models with public credential.',
      'providers': ['opencode-zen-free'],
      'installed': true,
    },
    {
      'package': '@magpie-community/opencode-kimi-auth',
      'name': 'Kimi',
      'category': 'auth',
      'summaryZh': '接入 Kimi 订阅账号模型与额度同步。',
      'summaryEn': 'Connect Kimi subscription account and quota sync.',
      'providers': ['kimi'],
      'installed': false,
    },
    {
      'package': '@magpie-community/middleware-word-guard',
      'name': 'Word Guard',
      'category': 'middleware',
      'summaryZh': '出站与响应敏感词过滤中间件。',
      'summaryEn': 'Sensitive-word filter middleware for requests and replies.',
      'providers': <String>[],
      'installed': false,
    },
  ];

  final List<Map<String, dynamic>> groups = [
    {
      'id': 'grp-1',
      'name': 'default-chat',
      'strategy': 'order',
      'pinnedMember': '',
      'enabled': true,
      'members': ['deepseek-1/deepseek-chat'],
    },
  ];

  List<Map<String, dynamic>> aliases = [
    {'alias': 'gpt-4o', 'target': 'default-chat'},
  ];

  List<Map<String, dynamic>> logs = [
    {
      'id': 'req-1',
      'timestamp': '2026-11-13T20:45:10Z',
      'clientIp': '192.168.1.15',
      'isLocal': false,
      'keyName': 'MacBook Pro',
      'requestedModel': 'gpt-4o',
      'upstreamProvider': 'deepseek-1',
      'upstreamModel': 'deepseek-chat',
      'protocol': 'openai',
      'statusCode': 200,
      'ttftMs': 240,
      'latencyMs': 980,
      'inputTokens': 120,
      'outputTokens': 340,
      'estimatedUsd': 0.002,
      'failoverAttempts': 0,
      'redactionCount': 1,
      'error': '',
    },
  ];

  http.Client createHttpClient() {
    return MockClient.streaming((request, bodyStream) async {
      final path = request.url.path;
      if (path == '/v1/chat/completions') {
        lastChatAuthorizationHeader = request.headers['Authorization'];
        final sse = [
          'data: {"choices":[{"delta":{"content":"Falcon "}}]}\n\n',
          'data: {"choices":[{"delta":{"content":"gateway OK"}}],"usage":{"total_tokens":28}}\n\n',
          'data: [DONE]\n\n',
        ].join();
        return http.StreamedResponse(
          Stream.value(utf8.encode(sse)),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      }

      final bodyBytes = await bodyStream.toBytes();
      final bodyStr = bodyBytes.isEmpty ? '' : utf8.decode(bodyBytes);
      final Map<String, dynamic> reqBody =
          bodyStr.isNotEmpty ? (jsonDecode(bodyStr) as Map<String, dynamic>) : {};

      final responseJson = _handleAdmin(request.method, path, request.url.queryParameters, reqBody);
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(responseJson))),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
  }

  Map<String, dynamic> _settingsMap() => {
        'port': port,
        'lanEnabled': lanEnabled,
        'allowLocalKeyless': allowLocalKeyless,
        'allowIps': allowIps,
        'corsOrigins': corsOrigins,
        'redactEnabled': redactEnabled,
        'redactRestore': redactRestore,
        'redactRules': redactRules,
        'redactAllow': redactAllow,
        'chinaMirror': chinaMirror,
      };

  Map<String, dynamic> _statusMap() => {
        'running': true,
        'listenAddr': lanEnabled ? '0.0.0.0:$port' : '127.0.0.1:$port',
        'port': port,
        'lanEnabled': lanEnabled,
        'allowLocalKeyless': allowLocalKeyless,
        'lanUrls': lanEnabled ? ['http://192.168.1.42:$port'] : <String>[],
        'loopbackUrl': 'http://127.0.0.1:$port',
        'uptimeSec': 125,
        'modelCount': 2,
        'activeProviderCount': providers.where((p) => p['enabled'] == true).length,
        'pluginRuntimeMode': 'bun',
      };

  Map<String, dynamic> _handleAdmin(
    String method,
    String path,
    Map<String, String> query,
    Map<String, dynamic> body,
  ) {
    if (path == '/admin/v1/state') {
      return {
        'status': _statusMap(),
        'settings': _settingsMap(),
        'keys': keys,
        'providers': providers,
        'plugins': plugins,
        'groups': groups,
        'aliases': aliases,
        'redactSummary': {
          'enabled': redactEnabled,
          'restore': redactRestore,
          'totalHits': 3,
          'builtinRules': 7,
          'customRules': redactRules.length,
        },
        'usageSummary': {
          'range': 'today',
          'requests': 18,
          'successRequests': 18,
          'errorRequests': 0,
          'inputTokens': 4200,
          'outputTokens': 8400,
          'totalTokens': 12600,
          'estimatedUsd': 0.042,
          'avgTtftMs': 240,
        },
      };
    }

    if (path == '/admin/v1/settings') {
      if (body.containsKey('port')) port = (body['port'] as num).toInt();
      if (body.containsKey('lanEnabled')) lanEnabled = body['lanEnabled'] == true;
      if (body.containsKey('allowLocalKeyless')) {
        allowLocalKeyless = body['allowLocalKeyless'] == true;
      }
      if (body.containsKey('redactEnabled')) {
        redactEnabled = body['redactEnabled'] == true;
      }
      if (body.containsKey('redactRestore')) {
        redactRestore = body['redactRestore'] == true;
      }
      if (body.containsKey('chinaMirror')) {
        chinaMirror = body['chinaMirror'] == true;
      }
      if (body.containsKey('allowIps')) {
        allowIps = (body['allowIps'] as List).cast<String>();
      }
      if (body.containsKey('corsOrigins')) {
        corsOrigins = (body['corsOrigins'] as List).cast<String>();
      }
      if (body.containsKey('redactRules')) {
        redactRules = (body['redactRules'] as List).cast<Map<String, dynamic>>();
      }
      if (body.containsKey('redactAllow')) {
        redactAllow = (body['redactAllow'] as List).cast<String>();
      }
      return {'settings': _settingsMap(), 'status': _statusMap()};
    }

    if (path == '/admin/v1/presets') {
      return {
        'presets': [
          {
            'id': 'openai',
            'name': 'OpenAI',
            'protocol': 'openai',
            'baseUrl': 'https://api.openai.com/v1',
            'defaultModels': ['gpt-4o', 'gpt-4o-mini'],
            'requiresKey': true,
          },
        ],
      };
    }

    if (path == '/admin/v1/keys' && method == 'POST') {
      final created = {
        'id': body['id'] ?? 'key-${keys.length + 1}',
        'name': body['name'] ?? 'New Key',
        'prefix': 'sk-flc-new1...9999',
        if (body['id'] == null) 'secret': 'sk-flc-new1secretvalue9999',
        'enabled': body['enabled'] ?? true,
        'allowedModels': body['allowedModels'] ?? <String>[],
        'dailyLimitUsd': body['dailyLimitUsd'] ?? 0,
        'monthlyLimitUsd': body['monthlyLimitUsd'] ?? 0,
        'dailyLimitReqs': body['dailyLimitReqs'] ?? 0,
        'todayUsd': 0,
        'monthUsd': 0,
        'todayReqs': 0,
      };
      if (body['id'] == null) {
        keys.add(created);
      }
      return {'key': created};
    }

    if (path.startsWith('/admin/v1/keys/') && path.endsWith('/rotate')) {
      return {
        'key': {
          'id': 'key-1',
          'name': 'MacBook Pro',
          'prefix': 'sk-flc-rot1...7777',
          'secret': 'sk-flc-rotatedsecret7777',
          'enabled': true,
        },
      };
    }

    if (path.startsWith('/admin/v1/providers/') && path.endsWith('/test')) {
      return {
        'ok': true,
        'statusCode': 200,
        'latencyMs': 152,
        'model': 'deepseek-chat',
        'replyPreview': 'OK',
      };
    }

    if (path == '/admin/v1/plugins/market') {
      return {'plugins': marketPlugins};
    }

    if (path == '/admin/v1/plugins/install') {
      final spec = body['spec'] as String? ?? '';
      for (final p in marketPlugins) {
        if (p['package'] == spec) {
          p['installed'] = true;
        }
      }
      return {'ok': true};
    }

    if (path == '/admin/v1/plugins/signin/start') {
      return {
        'sessionId': 'sess-1',
        'phase': 'done',
        'account': {
          'id': 'acc-pub',
          'providerId': 'opencode-zen-free',
          'label': 'Public Credential',
          'status': 'active',
        },
      };
    }

    if (path == '/admin/v1/redact/preview') {
      return {
        'maskedText':
            'Authorization: Bearer [REDACTED_KEY_1], contact [REDACTED_EMAIL_1]',
        'hits': [
          {
            'ruleName': 'API Key',
            'placeholder': '[REDACTED_KEY_1]',
            'count': 1,
          },
          {
            'ruleName': 'Email',
            'placeholder': '[REDACTED_EMAIL_1]',
            'count': 1,
          },
        ],
      };
    }

    if (path == '/admin/v1/usage') {
      final range = query['range'] ?? 'today';
      return {
        'range': range,
        'requests': range == 'today' ? 18 : 140,
        'totalTokens': range == 'today' ? 12600 : 98000,
        'estimatedUsd': range == 'today' ? 0.042 : 0.312,
        'avgTtftMs': 240,
      };
    }

    if (path == '/admin/v1/logs') {
      return {'logs': logs};
    }

    if (path == '/admin/v1/logs/clear') {
      logs.clear();
      return {'ok': true};
    }

    if (path == '/admin/v1/backup/export') {
      return {
        'version': 1,
        'settings': _settingsMap(),
      };
    }

    return {'ok': true};
  }
}

Widget createTestScope({
  required FakePlatformBridge bridge,
  required MockAdminBackend backend,
  required Widget child,
}) {
  return ProviderScope(
    overrides: [
      platformBridgeProvider.overrideWithValue(bridge),
      httpClientProvider.overrideWithValue(backend.createHttpClient()),
    ],
    child: child,
  );
}
