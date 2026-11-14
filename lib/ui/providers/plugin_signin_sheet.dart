import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/admin_models.dart';
import '../../l10n/l10n.dart';
import '../../state/gateway_state.dart';
import '../../theme/falcon_theme.dart';
import '../widgets/falcon_card.dart';
import '../widgets/falcon_row.dart';
import '../widgets/sheet_frame.dart';
import 'plugin_provider_labels.dart';

class PluginSignInSheet extends ConsumerStatefulWidget {
  const PluginSignInSheet({
    super.key,
    required this.plugin,
    this.providerId,
  });

  final InstalledPlugin plugin;
  final String? providerId;

  @override
  ConsumerState<PluginSignInSheet> createState() => _PluginSignInSheetState();
}

class _PluginSignInSheetState extends ConsumerState<PluginSignInSheet> {
  final _callbackCtrl = TextEditingController();
  final _apiKeyCtrl = TextEditingController();
  final Set<String> _autoOpenedUrls = {};

  late final List<PluginProviderDetail> _providers;
  late String _selectedProviderId;
  late int _selectedMethodIndex;
  bool _started = false;

  PluginSignInSession? _session;
  Timer? _pollTimer;
  String? _error;
  bool _submitting = false;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    final selectedMap = ref
            .read(gatewayAdminStateProvider)
            .value
            ?.settings
            .pluginSelectedModels ??
        const {};
    _providers = sortPluginProviderDetails(
      widget.plugin.resolvedProviderDetails(selectedMap),
    );
    _selectedProviderId = _resolveInitialProviderId();
    final initialMethods = _mobileMethodsFor(_currentDetail);
    _selectedMethodIndex = initialMethods.isNotEmpty ? initialMethods.first.index : 0;

    if (!_needsPreStartStep(initialMethods)) {
      _started = true;
      _startSession();
    }
  }

  String _resolveInitialProviderId() {
    if (widget.providerId != null && widget.providerId!.isNotEmpty) {
      return widget.providerId!;
    }
    if (_providers.isNotEmpty) {
      return _providers.first.id;
    }
    if (widget.plugin.providers.isNotEmpty) {
      return widget.plugin.providers.first;
    }
    return widget.plugin.id;
  }

  PluginProviderDetail? get _currentDetail {
    for (final p in _providers) {
      if (p.id == _selectedProviderId) return p;
    }
    return _providers.isNotEmpty ? _providers.first : null;
  }

  List<PluginAuthMethod> _mobileMethodsFor(PluginProviderDetail? detail) {
    if (detail == null || detail.methods.isEmpty) return const [];
    final mobile =
        detail.methods.where((m) => !m.isDesktopOnly).toList(growable: false);
    return mobile.isNotEmpty ? mobile : detail.methods;
  }

  PluginAuthMethod? _selectedMethodIn(List<PluginAuthMethod> methods) {
    for (final m in methods) {
      if (m.index == _selectedMethodIndex) return m;
    }
    return methods.isNotEmpty ? methods.first : null;
  }

  bool _needsPreStartStep(List<PluginAuthMethod> methods) {
    final multiProviderChoice =
        widget.providerId == null && _providers.length > 1;
    final multiMethodChoice = methods.length > 1;
    final needsApiInput = methods.any((m) => m.type == 'api' && !m.keyless);
    return multiProviderChoice || multiMethodChoice || needsApiInput;
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _callbackCtrl.dispose();
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _startSession() async {
    final client = ref.read(adminApiClientProvider);
    if (client == null) return;
    setState(() {
      _started = true;
      _error = null;
      _session = null;
    });
    try {
      final session = await client.startPluginSignIn(
        packageName: widget.plugin.package,
        providerId: _selectedProviderId,
        methodIndex: _selectedMethodIndex,
        apiKey: _apiKeyCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() => _session = session);
      await _handlePhase(session);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  Future<void> _handlePhase(PluginSignInSession session) async {
    final client = ref.read(adminApiClientProvider);
    if (session.phase == 'done') {
      _pollTimer?.cancel();
      if (client != null) {
        try {
          await client.refreshPlugins(pluginId: widget.plugin.id);
        } catch (_) {}
      }
      await ref.read(gatewayAdminStateProvider.notifier).reload();
      return;
    }
    if (session.phase == 'failed') {
      _pollTimer?.cancel();
      setState(() => _error = session.error);
      return;
    }
    if (session.phase == 'open_auto' &&
        session.url != null &&
        session.url!.isNotEmpty &&
        !_autoOpenedUrls.contains(session.url)) {
      _autoOpenedUrls.add(session.url!);
      unawaited(_openUrl(session.url!));
    }
    if (session.phase == 'starting' ||
        session.phase == 'open' ||
        session.phase == 'open_auto' ||
        session.phase == 'device') {
      _pollTimer ??= Timer.periodic(
        const Duration(seconds: 2),
        (_) => _pollOnce(),
      );
    }
  }

  Future<void> _pollOnce() async {
    final id = _session?.sessionId;
    if (id == null || id.isEmpty) return;
    final client = ref.read(adminApiClientProvider);
    if (client == null) return;
    try {
      final next = await client.pollPluginSignIn(id);
      if (!mounted) return;
      setState(() => _session = next);
      await _handlePhase(next);
    } catch (_) {
      // Keep polling until session resolves or sheet closes.
    }
  }

  Future<void> _submitCallback() async {
    final id = _session?.sessionId;
    final text = _callbackCtrl.text.trim();
    if (id == null || id.isEmpty || text.isEmpty) return;
    final client = ref.read(adminApiClientProvider);
    if (client == null) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final next = await client.submitPluginSignInCallback(id, text);
      if (!mounted) return;
      setState(() {
        _session = next;
        _submitting = false;
      });
      await _handlePhase(next);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = '$e';
      });
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Ignore launcher failures in headless/widget tests; URL copy remains available.
    }
  }

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = FalconColors.of(context);
    final phase = _session?.phase ?? 'starting';
    final methods = _mobileMethodsFor(_currentDetail);
    final activeMethod = _selectedMethodIn(methods);

    if (!_started) {
      return FalconSheetFrame(
        title: l10n.pluginsSignInTitle,
        subtitle: widget.plugin.name,
        footer: FilledButton(
          key: const ValueKey('signin-start-btn'),
          onPressed: _startSession,
          child: Text(l10n.pluginsSignIn),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_providers.length > 1) ...[
              SectionHeader(title: l10n.pluginsEditionLabel),
              FalconCard(
                child: Column(
                  children: [
                    for (var i = 0; i < _providers.length; i++) ...[
                      if (i > 0) const FalconDivider.icon(),
                      _RadioOptionRow(
                        rowKey: ValueKey('signin-edition-${_providers[i].id}'),
                        label: localizedPluginProviderTitle(
                          l10n,
                          _providers[i],
                        ),
                        selected: _providers[i].id == _selectedProviderId,
                        onTap: () {
                          final detail = _providers[i];
                          final nextMethods = _mobileMethodsFor(detail);
                          setState(() {
                            _selectedProviderId = detail.id;
                            _selectedMethodIndex = nextMethods.isNotEmpty
                                ? nextMethods.first.index
                                : 0;
                          });
                        },
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (methods.isNotEmpty) ...[
              SectionHeader(title: l10n.pluginsAuthMethodLabel),
              FalconCard(
                child: Column(
                  children: [
                    for (var i = 0; i < methods.length; i++) ...[
                      if (i > 0) const FalconDivider.icon(),
                      _RadioOptionRow(
                        rowKey: ValueKey('signin-method-${methods[i].index}'),
                        label: localizedPluginAuthMethodLabel(l10n, methods[i]),
                        selected: methods[i].index == _selectedMethodIndex,
                        onTap: () => setState(
                          () => _selectedMethodIndex = methods[i].index,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            if (activeMethod != null &&
                activeMethod.type == 'api' &&
                !activeMethod.keyless) ...[
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey('signin-apikey-input'),
                controller: _apiKeyCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: localizedPluginAuthMethodLabel(l10n, activeMethod),
                  hintText: activeMethod.placeholder,
                ),
              ),
            ],
          ],
        ),
      );
    }

    return FalconSheetFrame(
      title: l10n.pluginsSignInTitle,
      subtitle: widget.plugin.name,
      footer: phase == 'done' || phase == 'failed' || _error != null
          ? FilledButton(
              onPressed: () => Navigator.of(context).pop(phase == 'done'),
              child: Text(l10n.actionClose),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            Text(
              l10n.pluginsSignInFailed,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: c.danger,
              ),
            ),
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: c.danger, fontSize: 13)),
          ] else if (phase == 'done') ...[
            Row(
              children: [
                Icon(Icons.check_circle_outline_rounded, size: 18, color: c.textPrimary),
                const SizedBox(width: 8),
                Text(
                  l10n.pluginsSignInSuccess,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
              ],
            ),
            if (_session?.account != null) ...[
              const SizedBox(height: 8),
              Text(
                _session!.account!.label,
                style: TextStyle(
                  fontSize: 14,
                  color: c.textSecondary,
                ),
              ),
            ],
          ] else if (phase == 'open_auto') ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Center(child: CircularProgressIndicator()),
            ),
            Text(
              _session?.instructions?.isNotEmpty == true
                  ? _session!.instructions!
                  : l10n.pluginsAuthOpenAutoHint,
              style: TextStyle(fontSize: 13.5, color: c.textSecondary),
            ),
            if ((_session?.url ?? '').isNotEmpty) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _openUrl(_session!.url!),
                      child: Text(l10n.pluginsSignInReopenBrowser),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _copy(_session!.url!),
                      child: Text(
                        _copied ? l10n.actionCopied : l10n.pluginsSignInCopyUrl,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ] else if (phase == 'device') ...[
            Text(
              l10n.pluginsSignInDeviceCode,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: c.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.cardSubtle,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: c.border,
                  width: FalconTheme.borderWidth,
                ),
              ),
              child: Center(
                child: SelectableText(
                  _session?.userCode ?? '',
                  style: FalconTheme.mono(context, fontSize: 20),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _session?.instructions?.isNotEmpty == true
                  ? _session!.instructions!
                  : l10n.pluginsSignInDeviceCodeHint,
              style: TextStyle(fontSize: 12.5, color: c.textSecondary),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if ((_session?.userCode ?? '').isNotEmpty)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _copy(_session!.userCode!),
                      icon: Icon(
                        _copied ? Icons.check_rounded : Icons.copy_outlined,
                        size: 17,
                      ),
                      label: Text(_copied ? l10n.actionCopied : l10n.actionCopy),
                    ),
                  ),
                if ((_session?.url ?? '').isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _openUrl(_session!.url!),
                      child: Text(l10n.pluginsSignInReopenBrowser),
                    ),
                  ),
                ],
              ],
            ),
          ] else if (phase == 'open' || phase == 'prompt') ...[
            Text(
              phase == 'open'
                  ? l10n.pluginsSignInOpenBrowser
                  : (_session?.promptLabel ?? l10n.pluginsSignInPasteCallback),
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _session?.instructions?.isNotEmpty == true
                  ? _session!.instructions!
                  : l10n.pluginsSignInOpenBrowserHint,
              style: TextStyle(fontSize: 12.5, color: c.textSecondary),
            ),
            if ((_session?.url ?? '').isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _openUrl(_session!.url!),
                      child: Text(l10n.pluginsSignInReopenBrowser),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _copy(_session!.url!),
                      child: Text(
                        _copied ? l10n.actionCopied : l10n.pluginsSignInCopyUrl,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _callbackCtrl,
              decoration: InputDecoration(
                labelText: l10n.pluginsSignInPasteCallback,
                hintText: l10n.pluginsSignInPasteHint,
              ),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: _submitting ? null : _submitCallback,
              child: Text(l10n.pluginsSignInSubmit),
            ),
          ] else ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            ),
            Center(
              child: Text(
                l10n.pluginsSignInPreparing,
                style: TextStyle(fontSize: 13.5, color: c.textSecondary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RadioOptionRow extends StatelessWidget {
  const _RadioOptionRow({
    required this.rowKey,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Key rowKey;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = FalconColors.of(context);
    return InkWell(
      key: rowKey,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              size: 19,
              color: selected ? c.accent : c.textMuted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: c.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
