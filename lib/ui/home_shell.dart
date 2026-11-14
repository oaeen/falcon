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

    const pages = [
      GatewayScreen(),
      ProvidersScreen(),
      RoutingScreen(),
      MonitorScreen(),
    ];

    final navDestinations = [
      (
        icon: Icons.router_outlined,
        selectedIcon: Icons.router_rounded,
        label: l10n.tabGateway,
      ),
      (
        icon: Icons.hub_outlined,
        selectedIcon: Icons.hub_rounded,
        label: l10n.tabProviders,
      ),
      (
        icon: Icons.alt_route_rounded,
        selectedIcon: Icons.alt_route_rounded,
        label: l10n.tabRouting,
      ),
      (
        icon: Icons.analytics_outlined,
        selectedIcon: Icons.analytics_rounded,
        label: l10n.tabMonitor,
      ),
    ];

    final bodyStack = IndexedStack(
      index: _tabIndex,
      children: pages,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final useRail = constraints.maxWidth >= 720;
        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    titles[_tabIndex],
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: running ? c.success : c.textMuted,
                  ),
                ),
              ],
            ),
            actions: [
              FilledButton.tonalIcon(
                key: const ValueKey('appbar-test-btn'),
                onPressed: () => showFalconSheet<void>(
                  context: context,
                  builder: (_) => const PlaygroundSheet(),
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  minimumSize: const Size(0, 34),
                ),
                icon: const Icon(Icons.terminal_rounded, size: 16),
                label: Text(l10n.actionTestConsole),
              ),
              const SizedBox(width: 4),
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
              const SizedBox(width: 4),
            ],
          ),
          body: useRail
              ? Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(
                            color: c.border,
                            width: FalconTheme.borderWidth,
                          ),
                        ),
                      ),
                      child: NavigationRail(
                        selectedIndex: _tabIndex,
                        labelType: NavigationRailLabelType.all,
                        onDestinationSelected: (idx) =>
                            setState(() => _tabIndex = idx),
                        destinations: [
                          for (final d in navDestinations)
                            NavigationRailDestination(
                              icon: Icon(d.icon),
                              selectedIcon: Icon(d.selectedIcon),
                              label: Text(d.label),
                            ),
                        ],
                      ),
                    ),
                    Expanded(child: bodyStack),
                  ],
                )
              : bodyStack,
          bottomNavigationBar: useRail
              ? null
              : Container(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: c.border,
                        width: FalconTheme.borderWidth,
                      ),
                    ),
                  ),
                  child: NavigationBar(
                    selectedIndex: _tabIndex,
                    onDestinationSelected: (idx) =>
                        setState(() => _tabIndex = idx),
                    destinations: [
                      for (final d in navDestinations)
                        NavigationDestination(
                          icon: Icon(d.icon),
                          selectedIcon: Icon(d.selectedIcon),
                          label: d.label,
                        ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}
