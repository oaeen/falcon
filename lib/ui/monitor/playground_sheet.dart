import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/admin_api_client.dart';
import '../../data/admin_models.dart';
import '../../l10n/l10n.dart';
import '../../state/gateway_state.dart';
import '../../theme/falcon_theme.dart';
import '../widgets/sheet_frame.dart';
import '../widgets/status_pill.dart';

const String _kCustomKeyChoice = '__custom__';

class PlaygroundSheet extends ConsumerStatefulWidget {
  const PlaygroundSheet({super.key});

  @override
  ConsumerState<PlaygroundSheet> createState() => _PlaygroundSheetState();
}

class _PlaygroundSheetState extends ConsumerState<PlaygroundSheet> {
  final _promptCtrl = TextEditingController();
  final _customModelCtrl = TextEditingController();
  final _customKeyCtrl = TextEditingController();
  String? _selectedModel;
  String? _selectedKeyChoice;
  String _output = '';
  int? _ttftMs;
  int? _totalMs;
  int? _totalTokens;
  bool _streaming = false;
  String? _error;
  StreamSubscription<PlaygroundChunkEvent>? _sub;
  bool _initializedPrompt = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initializedPrompt) {
      _initializedPrompt = true;
      _promptCtrl.text = context.l10n.playgroundPromptDefault;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _promptCtrl.dispose();
    _customModelCtrl.dispose();
    _customKeyCtrl.dispose();
    super.dispose();
  }

  String? _resolveApiKey({
    required bool allowLocalKeyless,
    required List<({String id, String label, String secret})> sessionKeys,
  }) {
    final choice = _selectedKeyChoice ??
        (allowLocalKeyless
            ? null
            : (sessionKeys.isNotEmpty
                ? sessionKeys.first.secret
                : _kCustomKeyChoice));
    if (choice == null) return null;
    if (choice == _kCustomKeyChoice) {
      final raw = _customKeyCtrl.text.trim();
      return raw.isEmpty ? null : raw;
    }
    return choice;
  }

  Future<void> _send(String? apiKey) async {
    final snapshot =
        ref.read(gatewayAdminStateProvider).value ?? const AdminStateSnapshot();
    final runtimeRunning =
        ref.read(gatewayRuntimeProvider).value?.running ?? false;
    if (!runtimeRunning) {
      setState(() => _error = context.l10n.errorGatewayNotRunning);
      return;
    }
    final model = _customModelCtrl.text.trim().isNotEmpty
        ? _customModelCtrl.text.trim()
        : (_selectedModel ??
            (snapshot.availableTargets.isNotEmpty
                ? snapshot.availableTargets.first
                : 'gpt-4o'));
    final prompt = _promptCtrl.text.trim();
    if (prompt.isEmpty) return;

    await _sub?.cancel();
    setState(() {
      _streaming = true;
      _output = '';
      _error = null;
      _ttftMs = null;
      _totalMs = null;
      _totalTokens = null;
    });

    final port = snapshot.settings.port;
    final endpoint = snapshot.status.loopbackUrl.isNotEmpty
        ? snapshot.status.loopbackUrl
        : 'http://127.0.0.1:$port';

    final client = ref.read(playgroundClientProvider);
    _sub = client
        .streamChat(
          endpointBaseUrl: endpoint,
          model: model,
          prompt: prompt,
          apiKey: apiKey,
        )
        .listen(
      (event) {
        if (!mounted) return;
        setState(() {
          if (event.deltaText.isNotEmpty) {
            _output += event.deltaText;
          }
          _ttftMs = event.ttftMs ?? _ttftMs;
          _totalMs = event.totalMs ?? _totalMs;
          _totalTokens = event.totalTokens ?? _totalTokens;
          if (event.done) _streaming = false;
        });
      },
      onError: (Object err) {
        if (!mounted) return;
        setState(() {
          _streaming = false;
          _error = '$err';
        });
      },
      onDone: () {
        if (!mounted) return;
        setState(() => _streaming = false);
        ref.invalidate(requestLogsProvider);
        ref.invalidate(usageSummaryProvider);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = FalconColors.of(context);
    final snapshot =
        ref.watch(gatewayAdminStateProvider).value ?? const AdminStateSnapshot();
    final sessionSecrets = ref.watch(sessionKeySecretsProvider);
    final allowLocalKeyless = snapshot.settings.allowLocalKeyless;
    final targets = snapshot.availableTargets;
    final activeModel = (_selectedModel != null && targets.contains(_selectedModel))
        ? _selectedModel
        : (targets.isNotEmpty ? targets.first : null);

    final sessionKeys = <({String id, String label, String secret})>[];
    for (final k in snapshot.keys) {
      if (!k.enabled) continue;
      final secret = k.secret ?? sessionSecrets[k.id];
      if (secret != null && secret.isNotEmpty) {
        sessionKeys.add((
          id: k.id,
          label: '${k.name} (${k.prefix})',
          secret: secret,
        ));
      }
    }

    final validChoices = <String?>{
      if (allowLocalKeyless) null,
      ...sessionKeys.map((k) => k.secret),
      _kCustomKeyChoice,
    };
    final effectiveKeyChoice = validChoices.contains(_selectedKeyChoice)
        ? _selectedKeyChoice
        : (allowLocalKeyless
            ? null
            : (sessionKeys.isNotEmpty
                ? sessionKeys.first.secret
                : _kCustomKeyChoice));
    final resolvedApiKey = _resolveApiKey(
      allowLocalKeyless: allowLocalKeyless,
      sessionKeys: sessionKeys,
    );

    return FalconSheetFrame(
      title: l10n.playgroundTitle,
      footer: FilledButton.icon(
        key: const ValueKey('playground-send-btn'),
        onPressed: _streaming ? null : () => _send(resolvedApiKey),
        icon: Icon(
          _streaming ? Icons.hourglass_top_rounded : Icons.play_arrow_rounded,
          size: 18,
        ),
        label: Text(_streaming ? l10n.playgroundSending : l10n.playgroundSend),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (targets.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: activeModel,
              isExpanded: true,
              decoration: InputDecoration(labelText: l10n.playgroundModelLabel),
              items: targets
                  .map(
                    (m) => DropdownMenuItem(
                      value: m,
                      child: Text(
                        m,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FalconTheme.mono(context, fontSize: 13),
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (v) => setState(() => _selectedModel = v),
            )
          else
            TextField(
              controller: _customModelCtrl,
              style: FalconTheme.mono(context, fontSize: 13),
              decoration: InputDecoration(
                labelText: l10n.playgroundModelLabel,
                hintText: 'gpt-4o',
              ),
            ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            key: const ValueKey('playground-key-dropdown'),
            initialValue: effectiveKeyChoice,
            isExpanded: true,
            decoration: InputDecoration(labelText: l10n.playgroundKeyLabel),
            items: [
              if (allowLocalKeyless)
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(
                    l10n.playgroundKeyNone,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ...sessionKeys.map(
                (k) => DropdownMenuItem<String?>(
                  value: k.secret,
                  child: Text(
                    k.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              DropdownMenuItem<String?>(
                value: _kCustomKeyChoice,
                child: Text(
                  l10n.playgroundKeyCustom,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            onChanged: (v) => setState(() => _selectedKeyChoice = v),
          ),
          if (effectiveKeyChoice == _kCustomKeyChoice) ...[
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('playground-custom-key-field'),
              controller: _customKeyCtrl,
              obscureText: true,
              style: FalconTheme.mono(context, fontSize: 13),
              decoration: InputDecoration(
                hintText: l10n.playgroundKeyCustomHint,
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _promptCtrl,
            maxLines: 3,
            decoration: InputDecoration(labelText: l10n.playgroundPromptLabel),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: c.danger, fontSize: 12.5)),
          ],
          if (_output.isNotEmpty || _streaming) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  l10n.playgroundOutputLabel,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: c.textSecondary,
                  ),
                ),
                if (_ttftMs != null || _totalMs != null)
                  StatusPill(
                    label: l10n.playgroundMetrics(
                      _ttftMs ?? 0,
                      _totalMs ?? 0,
                      _totalTokens ?? 0,
                    ),
                    tone: _streaming ? StatusTone.accent : StatusTone.success,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.cardSubtle,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: c.border,
                  width: FalconTheme.borderWidth,
                ),
              ),
              child: SelectableText(
                _output,
                style: TextStyle(
                  fontSize: 13.5,
                  color: c.textPrimary,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
