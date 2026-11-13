import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/admin_models.dart';
import '../../l10n/l10n.dart';
import '../../state/gateway_state.dart';
import '../../theme/falcon_theme.dart';
import '../widgets/sheet_frame.dart';
import '../widgets/status_pill.dart';

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
  PluginSignInSession? _session;
  Timer? _pollTimer;
  String? _error;
  bool _submitting = false;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _startSession();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _callbackCtrl.dispose();
    super.dispose();
  }

  Future<void> _startSession() async {
    final client = ref.read(adminApiClientProvider);
    if (client == null) return;
    try {
      final session = await client.startPluginSignIn(
        packageName: widget.plugin.package,
        providerId: widget.providerId ??
            (widget.plugin.providers.isNotEmpty
                ? widget.plugin.providers.first
                : null),
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
    if (session.phase == 'done') {
      _pollTimer?.cancel();
      await ref.read(gatewayAdminStateProvider.notifier).reload();
      return;
    }
    if (session.phase == 'failed') {
      _pollTimer?.cancel();
      setState(() => _error = session.error);
      return;
    }
    if (session.phase == 'starting' ||
        session.phase == 'open' ||
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
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
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

    return FalconSheetFrame(
      title: '${widget.plugin.name} · ${l10n.pluginsSignInTitle}',
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
            StatusPill(label: l10n.pluginsSignInFailed, tone: StatusTone.danger),
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: c.danger, fontSize: 13)),
          ] else if (phase == 'done') ...[
            StatusPill(label: l10n.pluginsSignInSuccess, tone: StatusTone.success),
            if (_session?.account != null) ...[
              const SizedBox(height: 10),
              Text(
                _session!.account!.label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
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
                borderRadius: BorderRadius.circular(10),
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
              l10n.pluginsSignInDeviceCodeHint,
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
              l10n.pluginsSignInOpenBrowserHint,
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
