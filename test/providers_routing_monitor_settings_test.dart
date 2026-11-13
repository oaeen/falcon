import 'package:falcon/app.dart';
import 'package:falcon/data/platform_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_fakes.dart';

void main() {
  testWidgets(
    'Providers, Plugin Market, Routing Redaction Preview, Monitor Playground, and Request Detail',
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

      // Providers -> Subscription Plugins -> Plugin Market
      await tester.tap(find.text('渠道'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('订阅插件'));
      await tester.pumpAndSettle();
      expect(find.text('OpenCode Zen Free'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('open-plugin-market-btn')));
      await tester.pumpAndSettle();
      expect(find.text('插件目录'), findsWidgets);
      expect(find.text('Kimi'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      // Routing -> Redaction -> Redaction Preview sheet
      await tester.tap(find.text('路由'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('请求脱敏'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-redact-preview-btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('run-redact-preview-btn')));
      await tester.pumpAndSettle();
      expect(find.textContaining('[REDACTED_KEY_1]'), findsWidgets);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      // Monitor -> Request Detail + Playground SSE streaming
      await tester.tap(find.text('观测'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('gpt-4o → deepseek-chat'));
      await tester.pumpAndSettle();
      expect(find.text('请求详情'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('open-playground-btn')));
      await tester.pumpAndSettle();
      // Masked key prefix must never be offered/sent as a bearer secret.
      expect(find.textContaining('sk-flc-ab12...89ef'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('playground-send-btn')));
      await tester.pumpAndSettle();
      expect(backend.lastChatAuthorizationHeader, isNull);
      expect(find.text('Falcon gateway OK'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      // Providers -> Add Custom -> Protocol list contains 'responses' (not 'openai_responses')
      await tester.tap(find.text('渠道'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('接口渠道'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add-custom-provider-btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('openai').last);
      await tester.pumpAndSettle();
      expect(find.text('responses'), findsOneWidget);
      expect(find.text('openai_responses'), findsNothing);
    },
  );

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
