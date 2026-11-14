import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'admin_models.dart';

class AdminApiException implements Exception {
  AdminApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'AdminApiException($statusCode): $message';
}

class AdminApiClient {
  AdminApiClient({
    required String baseUrl,
    required this.adminToken,
    http.Client? httpClient,
  })  : baseUrl = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl,
        _http = httpClient ?? http.Client();

  final String baseUrl;
  final String adminToken;
  final http.Client _http;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (adminToken.isNotEmpty) 'Authorization': 'Bearer $adminToken',
      };

  Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse('$baseUrl$path').replace(queryParameters: query);
  }

  Future<Map<String, dynamic>> _requestJson(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
  }) async {
    final uri = _uri(path, query);
    late http.Response resp;
    final encoded = body == null ? null : jsonEncode(body);
    switch (method) {
      case 'GET':
        resp = await _http.get(uri, headers: _headers);
      case 'POST':
        resp = await _http.post(uri, headers: _headers, body: encoded);
      case 'DELETE':
        resp = await _http.delete(uri, headers: _headers, body: encoded);
      default:
        throw ArgumentError('Unsupported HTTP method: $method');
    }

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      var msg = resp.body;
      try {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map && decoded['error'] != null) {
          msg = '${decoded['error']}';
        }
      } catch (_) {}
      throw AdminApiException(resp.statusCode, msg);
    }

    if (resp.body.trim().isEmpty) return const {};
    final decoded = jsonDecode(resp.body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) {
      return decoded.map((k, v) => MapEntry('$k', v));
    }
    return {'data': decoded};
  }

  Future<AdminStateSnapshot> getState() async {
    final json = await _requestJson('GET', '/admin/v1/state');
    return AdminStateSnapshot.fromJson(json);
  }

  Future<({GatewaySettings settings, CoreStatus status})> updateSettings(
    Map<String, dynamic> patch,
  ) async {
    final json = await _requestJson('POST', '/admin/v1/settings', body: patch);
    return (
      settings: GatewaySettings.fromJson(
        (json['settings'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      status: CoreStatus.fromJson(
        (json['status'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
    );
  }

  Future<List<ProviderPreset>> getPresets() async {
    final json = await _requestJson('GET', '/admin/v1/presets');
    final list = (json['presets'] as List?) ?? const [];
    return list
        .whereType<Map>()
        .map((e) => ProviderPreset.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<GatewayAccessKey> upsertKey({
    String? id,
    required String name,
    bool enabled = true,
    List<String> allowedModels = const [],
    double dailyLimitUsd = 0,
    double monthlyLimitUsd = 0,
    int dailyLimitReqs = 0,
  }) async {
    final json = await _requestJson(
      'POST',
      '/admin/v1/keys',
      body: {
        if (id != null && id.isNotEmpty) 'id': id,
        'name': name,
        'enabled': enabled,
        'allowedModels': allowedModels,
        'dailyLimitUsd': dailyLimitUsd,
        'monthlyLimitUsd': monthlyLimitUsd,
        'dailyLimitReqs': dailyLimitReqs,
      },
    );
    final rawKey = (json['key'] as Map?)?.cast<String, dynamic>() ?? json;
    return GatewayAccessKey.fromJson(rawKey);
  }

  Future<void> deleteKey(String id) async {
    await _requestJson('DELETE', '/admin/v1/keys/$id');
  }

  Future<GatewayAccessKey> rotateKey(String id) async {
    final json = await _requestJson('POST', '/admin/v1/keys/$id/rotate');
    final rawKey = (json['key'] as Map?)?.cast<String, dynamic>() ?? json;
    return GatewayAccessKey.fromJson(rawKey);
  }

  Future<UpstreamProvider> upsertProvider({
    String? id,
    required String name,
    required String preset,
    required String protocol,
    required String baseUrl,
    required bool enabled,
    required List<ProviderKeyEntry> keys,
    required List<String> models,
    required List<String> selectedModels,
  }) async {
    final json = await _requestJson(
      'POST',
      '/admin/v1/providers',
      body: {
        if (id != null && id.isNotEmpty) 'id': id,
        'name': name,
        'preset': preset,
        'protocol': protocol,
        'baseUrl': baseUrl,
        'enabled': enabled,
        'keys': keys.map((k) => k.toUpsertJson()).toList(growable: false),
        'models': models,
        'selectedModels': selectedModels,
      },
    );
    final raw = (json['provider'] as Map?)?.cast<String, dynamic>() ?? json;
    return UpstreamProvider.fromJson(raw);
  }

  Future<void> deleteProvider(String id) async {
    await _requestJson('DELETE', '/admin/v1/providers/$id');
  }

  Future<List<String>> fetchProviderModels(String id) async {
    final json = await _requestJson(
      'POST',
      '/admin/v1/providers/$id/fetch-models',
    );
    final list = (json['models'] as List?) ?? const [];
    return list.map((e) => '$e').where((e) => e.isNotEmpty).toList();
  }

  Future<ProviderTestResult> testProvider(String id, {String? model}) async {
    final json = await _requestJson(
      'POST',
      '/admin/v1/providers/$id/test',
      body: model == null ? const {} : {'model': model},
    );
    return ProviderTestResult.fromJson(json);
  }

  Future<List<MarketPlugin>> getPluginMarket() async {
    final json = await _requestJson('GET', '/admin/v1/plugins/market');
    final list = (json['plugins'] as List?) ?? const [];
    return list
        .whereType<Map>()
        .map((e) => MarketPlugin.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<void> installPlugin(String spec) async {
    await _requestJson(
      'POST',
      '/admin/v1/plugins/install',
      body: {'spec': spec, 'package': spec},
    );
  }

  Future<void> removePlugin(String spec) async {
    await _requestJson(
      'POST',
      '/admin/v1/plugins/remove',
      body: {'spec': spec, 'package': spec},
    );
  }

  Future<void> togglePlugin(String packageName, bool enabled) async {
    await _requestJson(
      'POST',
      '/admin/v1/plugins/toggle',
      body: {'package': packageName, 'enabled': enabled},
    );
  }

  Future<void> setPluginOptions(
    String packageName,
    Map<String, dynamic> options,
  ) async {
    await _requestJson(
      'POST',
      '/admin/v1/plugins/options',
      body: {'package': packageName, 'options': options},
    );
  }

  Future<PluginSignInSession> startPluginSignIn({
    required String packageName,
    String? providerId,
    int methodIndex = 0,
    String? apiKey,
  }) async {
    final json = await _requestJson(
      'POST',
      '/admin/v1/plugins/signin/start',
      body: {
        'package': packageName,
        if (providerId != null && providerId.isNotEmpty)
          'providerId': providerId,
        'methodIndex': methodIndex,
        if (apiKey != null && apiKey.isNotEmpty) 'apiKey': apiKey,
      },
    );
    return PluginSignInSession.fromJson(json);
  }

  Future<List<String>> setPluginSelectedModels({
    String? pluginId,
    required String providerId,
    required List<String> selectedModels,
  }) async {
    final json = await _requestJson(
      'POST',
      '/admin/v1/plugins/models',
      body: {
        if (pluginId != null && pluginId.isNotEmpty) 'pluginId': pluginId,
        'providerId': providerId,
        'selectedModels': selectedModels,
      },
    );
    return (json['selectedModels'] as List?)
            ?.map((e) => '$e')
            .where((e) => e.isNotEmpty)
            .toList(growable: false) ??
        selectedModels;
  }

  Future<void> refreshPlugins({String? pluginId}) async {
    await _requestJson(
      'POST',
      '/admin/v1/plugins/refresh',
      body: pluginId == null || pluginId.isEmpty ? const {} : {'pluginId': pluginId},
    );
  }

  Future<PluginSignInSession> pollPluginSignIn(String sessionId) async {
    final json = await _requestJson('GET', '/admin/v1/plugins/signin/$sessionId');
    return PluginSignInSession.fromJson(json);
  }

  Future<PluginSignInSession> submitPluginSignInCallback(
    String sessionId,
    String input,
  ) async {
    final json = await _requestJson(
      'POST',
      '/admin/v1/plugins/signin/$sessionId/callback',
      body: {'input': input, 'value': input},
    );
    return PluginSignInSession.fromJson(json);
  }

  Future<void> deletePluginAccount(String providerId, String accountId) async {
    await _requestJson(
      'DELETE',
      '/admin/v1/plugins/accounts/$providerId/$accountId',
    );
  }

  Future<Map<String, dynamic>> checkinPluginAccount(
    String providerId,
    String accountId,
  ) async {
    return _requestJson(
      'POST',
      '/admin/v1/plugins/accounts/$providerId/$accountId/checkin',
    );
  }

  Future<void> refreshPluginQuotas() async {
    await _requestJson('POST', '/admin/v1/plugins/quotas/refresh');
  }

  Future<RoutingGroup> upsertGroup(RoutingGroup group) async {
    final json = await _requestJson(
      'POST',
      '/admin/v1/groups',
      body: group.toJson(),
    );
    final raw = (json['group'] as Map?)?.cast<String, dynamic>() ?? json;
    return RoutingGroup.fromJson(raw);
  }

  Future<void> deleteGroup(String id) async {
    await _requestJson('DELETE', '/admin/v1/groups/$id');
  }

  Future<void> saveAliases(List<ModelAlias> aliases) async {
    await _requestJson(
      'POST',
      '/admin/v1/aliases',
      body: {
        'aliases': aliases.map((a) => a.toJson()).toList(growable: false),
      },
    );
  }

  Future<UsageSummary> getUsage(String range) async {
    final json = await _requestJson(
      'GET',
      '/admin/v1/usage',
      query: {'range': range},
    );
    return UsageSummary.fromJson(json);
  }

  Future<List<RequestLogEntry>> getLogs({int limit = 100}) async {
    final json = await _requestJson(
      'GET',
      '/admin/v1/logs',
      query: {'limit': '$limit'},
    );
    final list = (json['logs'] as List?) ?? const [];
    return list
        .whereType<Map>()
        .map((e) => RequestLogEntry.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<void> clearLogs() async {
    await _requestJson('POST', '/admin/v1/logs/clear');
  }

  Future<Map<String, dynamic>> exportBackup({
    bool includeSecrets = false,
  }) async {
    return _requestJson(
      'GET',
      '/admin/v1/backup/export',
      query: {'includeSecrets': '$includeSecrets'},
    );
  }

  Future<void> importBackup(Map<String, dynamic> data) async {
    await _requestJson('POST', '/admin/v1/backup/import', body: data);
  }

  void dispose() {
    _http.close();
  }
}

class PlaygroundChunkEvent {
  const PlaygroundChunkEvent({
    this.deltaText = '',
    this.ttftMs,
    this.totalMs,
    this.totalTokens,
    this.done = false,
  });

  final String deltaText;
  final int? ttftMs;
  final int? totalMs;
  final int? totalTokens;
  final bool done;
}

class StreamingPlaygroundClient {
  StreamingPlaygroundClient({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final http.Client _http;

  Stream<PlaygroundChunkEvent> streamChat({
    required String endpointBaseUrl,
    required String model,
    required String prompt,
    String? apiKey,
  }) async* {
    final cleanBase = endpointBaseUrl.endsWith('/')
        ? endpointBaseUrl.substring(0, endpointBaseUrl.length - 1)
        : endpointBaseUrl;
    final req = http.Request(
      'POST',
      Uri.parse('$cleanBase/v1/chat/completions'),
    );
    req.headers['Content-Type'] = 'application/json';
    req.headers['Accept'] = 'text/event-stream';
    if (apiKey != null && apiKey.isNotEmpty) {
      req.headers['Authorization'] = 'Bearer $apiKey';
    }
    req.body = jsonEncode({
      'model': model,
      'stream': true,
      'stream_options': {'include_usage': true},
      'messages': [
        {'role': 'user', 'content': prompt},
      ],
    });

    final stopwatch = Stopwatch()..start();
    int? ttftMs;
    int? totalTokens;

    final streamed = await _http.send(req);
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      final errBody = await streamed.stream.bytesToString();
      throw AdminApiException(
        streamed.statusCode,
        errBody.isNotEmpty ? errBody : 'HTTP ${streamed.statusCode}',
      );
    }

    final lines = streamed.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in lines) {
      if (!line.startsWith('data:')) continue;
      final payload = line.substring(5).trim();
      if (payload.isEmpty) continue;
      if (payload == '[DONE]') {
        yield PlaygroundChunkEvent(
          ttftMs: ttftMs ?? stopwatch.elapsedMilliseconds,
          totalMs: stopwatch.elapsedMilliseconds,
          totalTokens: totalTokens,
          done: true,
        );
        return;
      }
      try {
        final decoded = jsonDecode(payload);
        if (decoded is! Map) continue;
        final usage = decoded['usage'];
        if (usage is Map && usage['total_tokens'] != null) {
          final rawTok = usage['total_tokens'];
          totalTokens = rawTok is num
              ? rawTok.toInt()
              : int.tryParse('$rawTok');
        }
        final choices = decoded['choices'];
        if (choices is List && choices.isNotEmpty) {
          final first = choices.first;
          if (first is Map) {
            final delta = first['delta'];
            if (delta is Map) {
              final content = delta['content'];
              final reasoning = delta['reasoning_content'];
              final chunkText = '${content ?? reasoning ?? ''}';
              if (chunkText.isNotEmpty) {
                ttftMs ??= stopwatch.elapsedMilliseconds;
                yield PlaygroundChunkEvent(
                  deltaText: chunkText,
                  ttftMs: ttftMs,
                  totalMs: stopwatch.elapsedMilliseconds,
                  totalTokens: totalTokens,
                );
              }
            }
          }
        }
      } catch (_) {
        // Ignore malformed partial SSE keepalive comments.
      }
    }

    yield PlaygroundChunkEvent(
      ttftMs: ttftMs ?? stopwatch.elapsedMilliseconds,
      totalMs: stopwatch.elapsedMilliseconds,
      totalTokens: totalTokens,
      done: true,
    );
  }
}
