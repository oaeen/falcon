import 'package:falcon/app.dart';
import 'package:falcon/theme/falcon_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_fakes.dart';

void main() {
  testWidgets(
    'Gateway Hero card, Access Key Protection gating, LAN sub-toggle, Client Examples, and Key creation',
    (tester) async {
      expect(FalconColors.light.scaffold, const Color(0xFFFFFFFF));
      expect(FalconColors.light.card, const Color(0xFFFFFFFF));
      expect(FalconColors.light.cardSubtle, const Color(0xFFF5F6F8));
      expect(FalconColors.light.border, const Color(0xFFE5E7EB));

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

      // Hero Mascot avatar uses pure white background without blue square
      final avatarBox = tester.widget<Container>(
        find.byKey(const ValueKey('hero-mascot-avatar')),
      );
      expect(
        (avatarBox.decoration as BoxDecoration?)?.color,
        Colors.white,
      );

      // Hero Mascot Card renders loopback endpoint and Stop CTA while running
      expect(find.text('http://127.0.0.1:18787'), findsAtLeastNWidgets(1));
      expect(
        find.byKey(const ValueKey('gateway-service-toggle-btn')),
        findsOneWidget,
      );

      // Access Key Protection defaults OFF -> key management list/create controls stay hidden
      expect(find.byKey(const ValueKey('require-access-key-switch')), findsOneWidget);
      expect(find.text('MacBook Pro'), findsNothing);
      expect(find.byKey(const ValueKey('create-access-key-btn')), findsNothing);

      // Enable Access Key Protection -> reveals Access Keys card
      await tester.ensureVisible(
        find.byKey(const ValueKey('require-access-key-switch')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('require-access-key-switch')));
      await tester.pumpAndSettle();
      expect(backend.requireAccessKey, isTrue);

      await tester.scrollUntilVisible(find.text('MacBook Pro'), 150);
      await tester.ensureVisible(find.text('MacBook Pro'));
      await tester.pumpAndSettle();
      expect(find.text('MacBook Pro'), findsOneWidget);

      // Open Access Key creation sheet and verify one-time full secret display
      await tester.ensureVisible(
        find.byKey(const ValueKey('create-access-key-btn')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('create-access-key-btn')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, '密钥名称'),
        'CI Runner',
      );
      await tester.tap(find.widgetWithText(FilledButton, '创建'));
      await tester.pumpAndSettle();
      expect(find.text('sk-flc-new1secretvalue9999'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '关闭'));
      await tester.pumpAndSettle();

      // Turn Access Key Protection back OFF -> section disappears again
      await tester.ensureVisible(
        find.byKey(const ValueKey('require-access-key-switch')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('require-access-key-switch')));
      await tester.pumpAndSettle();
      expect(backend.requireAccessKey, isFalse);
      expect(find.text('MacBook Pro'), findsNothing);

      // Toggle LAN Access ON -> reveals LAN URL + Require access key on LAN sub-toggle
      await tester.ensureVisible(
        find.byKey(const ValueKey('lan-access-switch')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('lan-access-switch')));
      await tester.pumpAndSettle();
      expect(backend.lanEnabled, isTrue);
      expect(bridge.lastLanSummary, isTrue);
      expect(find.text('http://192.168.1.42:18787'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('lan-require-key-switch')),
        findsOneWidget,
      );

      // Open Client Examples sheet
      await tester.ensureVisible(find.text('客户端接入示例'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('客户端接入示例'));
      await tester.pumpAndSettle();
      expect(find.text('OpenAI 兼容接口'), findsOneWidget);
      expect(find.text('Gemini 兼容接口'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
    },
  );
}
