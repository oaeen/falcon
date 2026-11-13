import 'package:falcon/app.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_fakes.dart';

void main() {
  testWidgets('FalconApp boots into Gateway tab without errors', (tester) async {
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

    expect(find.text('网关'), findsWidgets);
    expect(find.text('运行中'), findsOneWidget);
  });
}
