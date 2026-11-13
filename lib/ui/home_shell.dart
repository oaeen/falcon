import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../state/gateway_state.dart';
import '../theme/falcon_theme.dart';
import 'gateway/gateway_screen.dart';
import 'monitor/monitor_screen.dart';
import 'monitor/playground_sheet.dart';
import 'providers/providers_screen.dart';
import 'routing/routing_screen.dart';
import 'settings/settings_screen.dart';
import 'widgets/sheet_frame.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = FalconColors.of(context);
    final running =
        ref.watch(gatewayRuntimeProvider).value?.running ?? false;

    final titles = [
      l10n.gatewayTitle,
      l10n.providersTitle,
      l10n.routingTitle,
      l10n.monitorTitle,
    ];

    final pages = const [
      GatewayScreen(),
      ProvidersScreen(),
      RoutingScreen(),
      MonitorScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(titles[_tabIndex]),
            const SizedBox(width: 8),
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: running ? c.success : c.textMuted,
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            key: const ValueKey('appbar-test-btn'),
            onPressed: () => showFalconSheet<void>(
              context: context,
              builder: (_) => const PlaygroundSheet(),
            ),
            icon: const Icon(Icons.terminal_rounded, size: 18),
            label: Text(l10n.actionTestConsole),
          ),
          IconButton(
            key: const ValueKey('appbar-settings-btn'),
            tooltip: l10n.actionSettings,
            icon: const Icon(Icons.tune_rounded, size: 20),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SettingsScreen(),
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tabIndex,
        children: pages,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: c.border, width: FalconTheme.borderWidth),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _tabIndex,
          onDestinationSelected: (idx) => setState(() => _tabIndex = idx),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.router_outlined),
              selectedIcon: const Icon(Icons.router_rounded),
              label: l10n.tabGateway,
            ),
            NavigationDestination(
              icon: const Icon(Icons.hub_outlined),
              selectedIcon: const Icon(Icons.hub_rounded),
              label: l10n.tabProviders,
            ),
            NavigationDestination(
              icon: const Icon(Icons.alt_route_rounded),
              selectedIcon: const Icon(Icons.alt_route_rounded),
              label: l10n.tabRouting,
            ),
            NavigationDestination(
              icon: const Icon(Icons.analytics_outlined),
              selectedIcon: const Icon(Icons.analytics_rounded),
              label: l10n.tabMonitor,
            ),
          ],
        ),
      ),
    );
  }
}
