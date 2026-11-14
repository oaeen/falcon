import 'dart:async';

import 'package:falcon/app.dart';
import 'package:falcon/data/admin_api_client.dart';
import 'package:falcon/data/admin_models.dart';
import 'package:falcon/data/platform_bridge.dart';
import 'package:falcon/state/gateway_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_fakes.dart';

class _SlowFakePlaygroundClient extends StreamingPlaygroundClient {
  @override
  Stream<PlaygroundChunkEvent> streamChat({
    required String endpointBaseUrl,
    required String model,
    required String prompt,
    String? apiKey,
  }) async* {
    yield const PlaygroundChunkEvent(deltaText: 'Chunk 1 ', ttftMs: 42);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    yield const PlaygroundChunkEvent(deltaText: 'Chunk 2 ', ttftMs: 42);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    yield const PlaygroundChunkEvent(
      deltaText: 'Done',
      ttftMs: 42,
      totalMs: 250,
      totalTokens: 12,
      done: true,
    );
  }
}

void main() {
  testWidgets(
    'Providers defaults to Plugins when API empty, renders WorkBuddy CN/Intl, deduplicates market, saves models, and tests Playground',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final bridge = FakePlatformBridge();
      final backend = MockAdminBackend(withDefaultProvider: false);

      await tester.pumpWidget(
        createTestScope(
          bridge: bridge,
          backend: backend,
          child: const FalconApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Tab 2: Providers -> automatically defaults to Plugins segment since API providers are empty
      await tester.tap(find.text('渠道'));
      await tester.pumpAndSettle();
      expect(find.text('WorkBuddy Auth'), findsOneWidget);
      expect(find.text('WorkBuddy 国内版 (copilot.tencent.com)'), findsOneWidget);
      expect(find.text('WorkBuddy 国际版 (www.workbuddy.ai)'), findsOneWidget);

      // Market deduplicates @magpie-community/opencode-workbuddy-auth vs opencode-workbuddy-auth
      await tester.tap(find.byKey(const ValueKey('open-plugin-market-btn')));
      await tester.pumpAndSettle();
      expect(find.text('WorkBuddy Auth'), findsWidgets);
      expect(find.text('WorkBuddy Auth Duplicate'), findsNothing);
      expect(find.text('Kimi'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      // PluginModelsSheet: search, capability pills, toggle GLM-4.7, save
      await tester.tap(find.byKey(const ValueKey('plugin-models-workbuddy')));
      await tester.pumpAndSettle();
      expect(find.text('GLM-4.7'), findsOneWidget);
      expect(find.text('DeepSeek V3'), findsOneWidget);
      expect(find.text('200K'), findsOneWidget);
      expect(find.text('免费'), findsWidgets);

      await tester.tap(find.text('GLM-4.7'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('plugin-models-save-btn')));
      await tester.pumpAndSettle();
      expect(backend.lastPluginModelsBody?['providerId'], 'workbuddy');
      expect(backend.lastPluginModelsBody?['selectedModels'], ['glm-4.7']);

      // PluginSignInSheet: filters desktop-only method and preserves original methodIndex=1
      await tester.tap(find.byKey(const ValueKey('plugin-signin-workbuddy')));
      await tester.pumpAndSettle();
      expect(backend.lastSignInStartBody?['providerId'], 'workbuddy');
      expect(backend.lastSignInStartBody?['methodIndex'], 1);
      await tester.tap(find.widgetWithText(FilledButton, '关闭'));
      await tester.pumpAndSettle();

      // Open Playground directly from WorkBuddy provider row with initialModel
      await tester.tap(find.byKey(const ValueKey('plugin-test-workbuddy')));
      await tester.pumpAndSettle();
      expect(find.textContaining('workbuddy/glm-4.7'), findsWidgets);
      // Key dropdown is hidden while Access Key Protection is OFF
      expect(find.byKey(const ValueKey('playground-key-dropdown')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('playground-send-btn')));
      await tester.pumpAndSettle();
      expect(backend.lastChatAuthorizationHeader, isNull);
      expect(find.text('Falcon gateway OK'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Routing hides Redaction tab cleanly; Monitor RequestDetail and Custom Provider protocols',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final bridge = FakePlatformBridge();
      final backend = MockAdminBackend();

      await tester.pumpWidget(
        createTestScope(
          bridge: bridge,
          backend: backend,
          child: const FalconApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Routing has Groups + Aliases and zero Redaction
      await tester.tap(find.text('路由'));
      await tester.pumpAndSettle();
      expect(find.text('路由组'), findsOneWidget);
      expect(find.text('模型映射'), findsOneWidget);
      expect(find.text('请求脱敏'), findsNothing);

      // Monitor -> Request Detail has no Redactions row
      await tester.tap(find.text('观测'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('gpt-4o → deepseek-chat'));
      await tester.pumpAndSettle();
      expect(find.text('请求详情'), findsOneWidget);
      expect(find.text('脱敏替换次数'), findsNothing);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      // Providers -> Add Custom -> Protocol dropdown has 'responses' (not 'openai_responses')
      await tester.tap(find.text('渠道'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add-custom-provider-btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('openai').last);
      await tester.pumpAndSettle();
      expect(find.text('responses'), findsOneWidget);
      expect(find.text('openai_responses'), findsNothing);
    },
  );

  testWidgets('Playground Stop button cancels active stream cleanly',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final bridge = FakePlatformBridge();
    final backend = MockAdminBackend();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          platformBridgeProvider.overrideWithValue(bridge),
          httpClientProvider.overrideWithValue(backend.createHttpClient()),
          playgroundClientProvider.overrideWithValue(_SlowFakePlaygroundClient()),
        ],
        child: const FalconApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('appbar-test-btn')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('playground-send-btn')));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('Chunk 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('playground-stop-btn')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('playground-stop-btn')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('playground-stop-btn')), findsNothing);
    expect(find.textContaining('Done'), findsNothing);

    expect(
      canonicalPluginPackage('@magpie-community/opencode-workbuddy-auth'),
      'opencode-workbuddy-auth',
    );
  });

  testWidgets('Settings renders Android keep-alive controls', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final androidBridge = FakePlatformBridge(
      initialStatus: const GatewayRuntimeStatus(
        running: true,
        platform: 'android',
        wakeLockHeld: true,
        wifiLockHeld: true,
      ),
    );
    await tester.pumpWidget(
      createTestScope(
        bridge: androidBridge,
        backend: MockAdminBackend(),
        child: const FalconApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('appbar-settings-btn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('keepalive-android-card')), findsOneWidget);
    expect(find.text('忽略电池优化'), findsOneWidget);
    expect(find.text('开机自启动'), findsOneWidget);
    expect(find.text('后台静默保活（混音模式）'), findsNothing);
  });

  testWidgets('Settings renders iOS keep-alive controls and hides Android-only rows',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final iosBridge = FakePlatformBridge(
      initialStatus: const GatewayRuntimeStatus(
        running: true,
        platform: 'ios',
        backgroundAudioKeepAlive: true,
        keepScreenAwake: false,
        notificationPermissionGranted: true,
      ),
    );
    await tester.pumpWidget(
      createTestScope(
        bridge: iosBridge,
        backend: MockAdminBackend(),
        child: const FalconApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('appbar-settings-btn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('keepalive-ios-card')), findsOneWidget);
    expect(find.text('后台静默保活（混音模式）'), findsOneWidget);
    expect(find.text('防止锁屏休眠'), findsOneWidget);
    expect(find.text('忽略电池优化'), findsNothing);
    expect(find.text('开机自启动'), findsNothing);
  });
}
