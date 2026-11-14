import 'package:falcon/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_fakes.dart';

void main() {
  testWidgets(
    '4-tab NavigationBar and Settings render cleanly on compact 360x780 viewport',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 780));
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

      // Tab 1: Gateway Hero Mascot Card + Access Endpoints + bottom NavigationBar
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(
        find.byKey(const ValueKey('gateway-service-toggle-btn')),
        findsOneWidget,
      );
      expect(find.text('访问端点'), findsOneWidget);

      // Tab 2: Providers (API + Plugins)
      await tester.tap(find.text('渠道'));
      await tester.pumpAndSettle();
      expect(find.text('DeepSeek'), findsOneWidget);

      // Tab 3: Routing (2-segment Groups + Aliases, no Redaction)
      await tester.tap(find.text('路由'));
      await tester.pumpAndSettle();
      expect(find.text('default-chat'), findsOneWidget);
      expect(find.text('请求脱敏'), findsNothing);

      // Tab 4: Monitor
      await tester.tap(find.text('观测'));
      await tester.pumpAndSettle();
      expect(find.text('请求日志'), findsOneWidget);

      // Settings screen
      await tester.tap(find.byKey(const ValueKey('appbar-settings-btn')));
      await tester.pumpAndSettle();
      expect(find.text('后台保活'), findsOneWidget);
    },
  );

  testWidgets('Wide tablet/desktop 1024x768 layout uses NavigationRail cleanly',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 768));
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

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('访问端点'), findsOneWidget);
  });
}
