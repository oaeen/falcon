import 'package:falcon/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_fakes.dart';

void main() {
  testWidgets(
    'Gateway screen handles LAN toggle, Client Examples sheet, and Access Key creation',
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

      // Verify loopback URL and MacBook Pro key
      expect(find.text('http://127.0.0.1:18787'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('MacBook Pro'), 150);
      expect(find.text('MacBook Pro'), findsOneWidget);

      // Scroll back up to toggle LAN Access switch
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('lan-access-switch')),
        -150,
      );
      await tester.tap(find.byKey(const ValueKey('lan-access-switch')));
      await tester.pumpAndSettle();
      expect(backend.lanEnabled, isTrue);
      expect(bridge.lastLanSummary, isTrue);
      expect(find.text('http://192.168.1.42:18787'), findsOneWidget);

      // Open Client Examples sheet
      await tester.scrollUntilVisible(find.text('客户端接入示例'), 150);
      await tester.tap(find.text('客户端接入示例'));
      await tester.pumpAndSettle();
      expect(find.text('OpenAI 兼容接口'), findsOneWidget);
      expect(find.text('Gemini 兼容接口'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      // Open Access Key creation sheet and create a key showing full secret once
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('create-access-key-btn')),
        150,
      );
      await tester.tap(find.byKey(const ValueKey('create-access-key-btn')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, '密钥名称'),
        'CI Runner',
      );
      await tester.tap(find.widgetWithText(FilledButton, '创建'));
      await tester.pumpAndSettle();

      expect(find.text('sk-flc-new1secretvalue9999'), findsOneWidget);
    },
  );
}
