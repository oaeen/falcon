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
  const PlaygroundSheet({super.key, this.initialModel});

  final String? initialModel;

  @override
  ConsumerState<PlaygroundSheet> createState() => _PlaygroundSheetState();
}

class _PlaygroundSheetState extends ConsumerState<PlaygroundSheet> {
  final _promptCtrl = TextEditingController();
  final _customModelCtrl = TextEditingController();
  final _customKeyCtrl = TextEditingController();

  final StringBuffer _outputBuffer = StringBuffer();
  final ValueNotifier<String> _outputNotifier = ValueNotifier<String>('');
  final ValueNotifier<({int? ttftMs, int totalMs, int tokens, double tokPerSec})>
      _statsNotifier =
      ValueNotifier((ttftMs: null, totalMs: 0, tokens: 0, tokPerSec: 0));
  final Stopwatch _stopwatch = Stopwatch();

  String? _selectedModel;
  String? _selectedKeyChoice;
  bool _streaming = false;
  String? _error;
  StreamSubscription<PlaygroundChunkEvent>? _sub;
  Timer? _flushTimer;
  int? _ttftMs;
  int? _serverTotalMs;
  int? _serverTokens;
  bool _dirty = false;
  bool _initializedPrompt = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialModel != null && widget.initialModel!.isNotEmpty) {
      _selectedModel = widget.initialModel;
    }
  }

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
    _flushTimer?.cancel();
    _sub?.cancel();
    _outputNotifier.dispose();
    _statsNotifier.dispose();
    _promptCtrl.dispose();
    _customModelCtrl.dispose();
    _customKeyCtrl.dispose();
    super.dispose();
  }

  String? _resolveApiKey({
    required bool requireAccessKey,
    required bool allowLocalKeyless,
    required List<({String id, String label, String secret})> sessionKeys,
  }) {
    if (!requireAccessKey) return null;
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

  void _flushFrame({bool force = false}) {
    if (!mounted) return;
    if (!_dirty && !force && !_streaming) return;
    _dirty = false;
    final text = _outputBuffer.toString();
    if (_outputNotifier.value != text) {
      _outputNotifier.value = text;
    }
    final elapsedMs = _serverTotalMs ?? _stopwatch.elapsedMilliseconds;
    final approxTokens =
        _serverTokens ?? (text.isEmpty ? 0 : (text.length / 4).ceil());
    final rate = elapsedMs > 50 && approxTokens > 0
        ? (approxTokens / (elapsedMs / 1000.0))
        : 0.0;
    _statsNotifier.value = (
      ttftMs: _ttftMs,
      totalMs: elapsedMs,
      tokens: approxTokens,
      tokPerSec: rate,
    );
  }

  Future<void> _stop() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    await _sub?.cancel();
    _sub = null;
    _stopwatch.stop();
    _flushFrame(force: true);
    if (mounted) {
      setState(() => _streaming = false);
    }
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

    _flushTimer?.cancel();
    await _sub?.cancel();

    _outputBuffer.clear();
    _outputNotifier.value = '';
    _ttftMs = null;
    _serverTotalMs = null;
    _serverTokens = null;
    _dirty = false;
    _stopwatch
      ..reset()
      ..start();
    _statsNotifier.value = (ttftMs: null, totalMs: 0, tokens: 0, tokPerSec: 0);

    setState(() {
      _streaming = true;
      _error = null;
    });

    // Coalesce high-frequency token chunks into ~42fps UI updates so fast
    // streams keep scrolling smooth without per-chunk Stateful builds.
    _flushTimer = Timer.periodic(
      const Duration(milliseconds: 24),
      (_) => _flushFrame(),
    );

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
        if (event.deltaText.isNotEmpty) {
          _outputBuffer.write(event.deltaText);
          _dirty = true;
        }
        _ttftMs = event.ttftMs ?? _ttftMs;
        if (event.totalTokens != null) {
          _serverTokens = event.totalTokens;
          _dirty = true;
        }
        if (event.done) {
          _serverTotalMs = event.totalMs ?? _stopwatch.elapsedMilliseconds;
          _stopwatch.stop();
          _flushTimer?.cancel();
          _flushTimer = null;
          _flushFrame(force: true);
          setState(() => _streaming = false);
        }
      },
      onError: (Object err) {
        if (!mounted) return;
        _stopwatch.stop();
        _flushTimer?.cancel();
        _flushTimer = null;
        _flushFrame(force: true);
        setState(() {
          _streaming = false;
          _error = '$err';
        });
      },
      onDone: () {
        if (!mounted) return;
        _stopwatch.stop();
        _flushTimer?.cancel();
        _flushTimer = null;
        _flushFrame(force: true);
        if (_streaming) {
          setState(() => _streaming = false);
        }
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
    final requireAccessKey = snapshot.settings.requireAccessKey;
    final allowLocalKeyless = snapshot.settings.allowLocalKeyless;

    final targets = <String>[
      if (widget.initialModel != null &&
          widget.initialModel!.isNotEmpty &&
          !snapshot.availableTargets.contains(widget.initialModel))
        widget.initialModel!,
      ...snapshot.availableTargets,
    ];
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
      requireAccessKey: requireAccessKey,
      allowLocalKeyless: allowLocalKeyless,
      sessionKeys: sessionKeys,
    );

    return FalconSheetFrame(
      title: l10n.playgroundTitle,
      footer: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              key: const ValueKey('playground-send-btn'),
              onPressed: _streaming ? null : () => _send(resolvedApiKey),
              icon: Icon(
                _streaming
                    ? Icons.hourglass_top_rounded
                    : Icons.play_arrow_rounded,
                size: 18,
              ),
              label:
                  Text(_streaming ? l10n.playgroundSending : l10n.playgroundSend),
            ),
          ),
          if (_streaming) ...[
            const SizedBox(width: 10),
            OutlinedButton.icon(
              key: const ValueKey('playground-stop-btn'),
              onPressed: _stop,
              icon: Icon(Icons.stop_rounded, size: 18, color: c.danger),
              label: Text(
                l10n.playgroundStop,
                style: TextStyle(color: c.danger),
              ),
            ),
          ],
        ],
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
          if (!requireAccessKey)
            Align(
              alignment: Alignment.centerLeft,
              child: StatusPill(
                label: l10n.playgroundKeyNotRequired,
                icon: Icons.lock_open_outlined,
                tone: StatusTone.neutral,
              ),
            )
          else ...[
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
          ValueListenableBuilder<String>(
            valueListenable: _outputNotifier,
            builder: (context, output, _) {
              if (output.isEmpty && !_streaming) {
                return const SizedBox.shrink();
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 14),
                  ValueListenableBuilder(
                    valueListenable: _statsNotifier,
                    builder: (context, stats, _) {
                      return Wrap(
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
                          if (stats.ttftMs != null || stats.totalMs > 0)
                            StatusPill(
                              label: _streaming && stats.tokPerSec > 0
                                  ? l10n.playgroundStreamRate(
                                      stats.tokPerSec.toStringAsFixed(1),
                                      (stats.totalMs / 1000).toStringAsFixed(1),
                                    )
                                  : l10n.playgroundMetrics(
                                      stats.ttftMs ?? 0,
                                      stats.totalMs,
                                      stats.tokens,
                                    ),
                              tone: _streaming
                                  ? StatusTone.accent
                                  : StatusTone.success,
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: c.cardSubtle,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: c.border,
                        width: FalconTheme.borderWidth,
                      ),
                    ),
                    child: SelectableText(
                      output,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: c.textPrimary,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
