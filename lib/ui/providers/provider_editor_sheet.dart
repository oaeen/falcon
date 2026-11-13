import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/admin_models.dart';
import '../../l10n/l10n.dart';
import '../../state/gateway_state.dart';
import '../../theme/falcon_theme.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/falcon_card.dart';
import '../widgets/falcon_row.dart';
import '../widgets/sheet_frame.dart';
import '../widgets/status_pill.dart';

class ProviderEditorSheet extends ConsumerStatefulWidget {
  const ProviderEditorSheet({
    super.key,
    this.existing,
    this.preset,
  });

  final UpstreamProvider? existing;
  final ProviderPreset? preset;

  @override
  ConsumerState<ProviderEditorSheet> createState() =>
      _ProviderEditorSheetState();
}

class _ProviderEditorSheetState extends ConsumerState<ProviderEditorSheet> {
  final _nameCtrl = TextEditingController();
  final _baseUrlCtrl = TextEditingController();
  final _manualModelsCtrl = TextEditingController();

  late String _presetId;
  late String _protocol;
  late bool _enabled;
  late List<_EditableKey> _keys;
  late List<String> _models;
  late Set<String> _selectedModels;

  bool _saving = false;
  bool _fetching = false;
  bool _testing = false;
  ProviderTestResult? _testResult;
  String? _error;

  static const _protocols = [
    'openai',
    'responses',
    'anthropic',
    'gemini',
    'ollama',
  ];

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final preset = widget.preset;
    if (existing != null) {
      _presetId = existing.preset;
      final normalized = existing.protocol == 'openai_responses'
          ? 'responses'
          : existing.protocol;
      _protocol = _protocols.contains(normalized) ? normalized : 'openai';
      _enabled = existing.enabled;
      _nameCtrl.text = existing.name;
      _baseUrlCtrl.text = existing.baseUrl;
      _keys = existing.keys
          .map(
            (k) => _EditableKey(
              id: k.id,
              labelCtrl: TextEditingController(text: k.label),
              secretCtrl: TextEditingController(),
              maskedSecret: k.maskedSecret,
              weight: k.weight,
              enabled: k.enabled,
            ),
          )
          .toList();
      _models = existing.models.toList();
      _selectedModels = existing.selectedModels.toSet();
      _testResult = existing.lastTest;
    } else if (preset != null) {
      _presetId = preset.id;
      final normalized = preset.protocol == 'openai_responses'
          ? 'responses'
          : preset.protocol;
      _protocol = _protocols.contains(normalized) ? normalized : 'openai';
      _enabled = true;
      _nameCtrl.text = preset.name;
      _baseUrlCtrl.text = preset.baseUrl;
      _keys = [
        if (preset.requiresKey)
          _EditableKey(
            id: '',
            labelCtrl: TextEditingController(text: 'Default'),
            secretCtrl: TextEditingController(),
            maskedSecret: '',
            weight: 1,
            enabled: true,
          ),
      ];
      _models = preset.defaultModels.toList();
      _selectedModels = preset.defaultModels.toSet();
    } else {
      _presetId = 'custom';
      _protocol = 'openai';
      _enabled = true;
      _keys = [
        _EditableKey(
          id: '',
          labelCtrl: TextEditingController(text: 'Default'),
          secretCtrl: TextEditingController(),
          maskedSecret: '',
          weight: 1,
          enabled: true,
        ),
      ];
      _models = [];
      _selectedModels = {};
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _baseUrlCtrl.dispose();
    _manualModelsCtrl.dispose();
    for (final k in _keys) {
      k.dispose();
    }
    super.dispose();
  }

  void _addKeyRow() {
    setState(() {
      _keys.add(
        _EditableKey(
          id: '',
          labelCtrl: TextEditingController(text: 'Key ${_keys.length + 1}'),
          secretCtrl: TextEditingController(),
          maskedSecret: '',
          weight: 1,
          enabled: true,
        ),
      );
    });
  }

  void _addManualModels() {
    final extra = _manualModelsCtrl.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (extra.isEmpty) return;
    setState(() {
      for (final m in extra) {
        if (!_models.contains(m)) _models.add(m);
        _selectedModels.add(m);
      }
      _manualModelsCtrl.clear();
    });
  }

  Future<UpstreamProvider?> _saveInternal({bool closeAfter = true}) async {
    final client = ref.read(adminApiClientProvider);
    if (client == null) return null;
    final name = _nameCtrl.text.trim();
    final baseUrl = _baseUrlCtrl.text.trim();
    if (name.isEmpty || baseUrl.isEmpty) return null;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final saved = await client.upsertProvider(
        id: widget.existing?.id,
        name: name,
        preset: _presetId,
        protocol: _protocol,
        baseUrl: baseUrl,
        enabled: _enabled,
        keys: _keys
            .map(
              (k) => ProviderKeyEntry(
                id: k.id,
                label: k.labelCtrl.text.trim(),
                secret: k.secretCtrl.text.trim().isEmpty
                    ? null
                    : k.secretCtrl.text.trim(),
                enabled: k.enabled,
                weight: k.weight,
              ),
            )
            .toList(growable: false),
        models: _models,
        selectedModels: _selectedModels.toList(growable: false),
      );
      await ref.read(gatewayAdminStateProvider.notifier).reload();
      if (!mounted) return saved;
      setState(() => _saving = false);
      if (closeAfter) {
        Navigator.of(context).pop(true);
      }
      return saved;
    } catch (e) {
      if (!mounted) return null;
      setState(() {
        _saving = false;
        _error = '$e';
      });
      return null;
    }
  }

  Future<void> _fetchModels() async {
    final client = ref.read(adminApiClientProvider);
    if (client == null) return;
    var providerId = widget.existing?.id ?? '';
    if (providerId.isEmpty) {
      final saved = await _saveInternal(closeAfter: false);
      if (saved == null) return;
      providerId = saved.id;
    }
    setState(() {
      _fetching = true;
      _error = null;
    });
    try {
      final fetched = await client.fetchProviderModels(providerId);
      if (!mounted) return;
      setState(() {
        for (final m in fetched) {
          if (!_models.contains(m)) _models.add(m);
        }
        if (_selectedModels.isEmpty) {
          _selectedModels.addAll(fetched.take(5));
        }
        _fetching = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.providersModelsFetched(fetched.length)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fetching = false;
        _error = '$e';
      });
    }
  }

  Future<void> _testProvider() async {
    final client = ref.read(adminApiClientProvider);
    if (client == null) return;
    final saved = await _saveInternal(closeAfter: false);
    final providerId = saved?.id ?? widget.existing?.id ?? '';
    if (providerId.isEmpty) return;

    setState(() {
      _testing = true;
      _error = null;
    });
    try {
      final res = await client.testProvider(
        providerId,
        model: _selectedModels.isNotEmpty ? _selectedModels.first : null,
      );
      await ref.read(gatewayAdminStateProvider.notifier).reload();
      if (!mounted) return;
      setState(() {
        _testResult = res;
        _testing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _error = '$e';
      });
    }
  }

  Future<void> _deleteProvider() async {
    final existing = widget.existing;
    if (existing == null) return;
    final confirmed = await showFalconConfirmDialog(
      context: context,
      title: context.l10n.actionDelete,
      message: context.l10n.providersDeleteConfirm(existing.name),
      destructive: true,
    );
    if (!confirmed) return;
    final client = ref.read(adminApiClientProvider);
    if (client == null) return;
    await client.deleteProvider(existing.id);
    await ref.read(gatewayAdminStateProvider.notifier).reload();
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = FalconColors.of(context);
    final isEdit = widget.existing != null;

    return FalconSheetFrame(
      title: isEdit
          ? l10n.providersEditorEditTitle
          : l10n.providersEditorAddTitle,
      headerTrailing: isEdit
          ? IconButton(
              icon: Icon(Icons.delete_outline_rounded, color: c.danger, size: 20),
              tooltip: l10n.actionDelete,
              onPressed: _deleteProvider,
            )
          : null,
      footer: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              child: Text(l10n.actionCancel),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: _saving ? null : () => _saveInternal(closeAfter: true),
              child: Text(l10n.actionSave),
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            Text(_error!, style: TextStyle(color: c.danger, fontSize: 12.5)),
            const SizedBox(height: 10),
          ],
          TextField(
            controller: _nameCtrl,
            decoration: InputDecoration(labelText: l10n.providersNameLabel),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _protocol,
            isExpanded: true,
            decoration: InputDecoration(labelText: l10n.providersProtocolLabel),
            items: _protocols
                .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                .toList(growable: false),
            onChanged: (v) {
              if (v != null) setState(() => _protocol = v);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _baseUrlCtrl,
            style: FalconTheme.mono(context, fontSize: 13),
            decoration: InputDecoration(labelText: l10n.providersBaseUrlLabel),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.providersKeysLabel,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: c.textSecondary,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _addKeyRow,
                icon: const Icon(Icons.add_rounded, size: 17),
                label: Text(l10n.providersAddKey),
              ),
            ],
          ),
          for (var i = 0; i < _keys.length; i++) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: c.cardSubtle,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: c.border,
                  width: FalconTheme.borderWidth,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _keys[i].labelCtrl,
                          decoration: InputDecoration(
                            hintText: l10n.providersKeyLabelHint,
                            fillColor: c.card,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Switch(
                        value: _keys[i].enabled,
                        onChanged: (v) =>
                            setState(() => _keys[i].enabled = v),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: c.textMuted,
                        ),
                        onPressed: () {
                          setState(() {
                            final removed = _keys.removeAt(i);
                            removed.dispose();
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _keys[i].secretCtrl,
                    obscureText: true,
                    style: FalconTheme.mono(context, fontSize: 12.5),
                    decoration: InputDecoration(
                      hintText: _keys[i].maskedSecret.isNotEmpty
                          ? '${_keys[i].maskedSecret} · ${l10n.providersKeySecretHint}'
                          : l10n.providersKeySecretHint,
                      fillColor: c.card,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _fetching ? null : _fetchModels,
                  icon: const Icon(Icons.sync_rounded, size: 17),
                  label: Text(
                    _fetching
                        ? l10n.providersFetchingModels
                        : l10n.providersFetchModels,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _testing ? null : _testProvider,
                  icon: const Icon(Icons.bolt_outlined, size: 17),
                  label: Text(
                    _testing
                        ? l10n.providersTesting
                        : l10n.providersTestConnectivity,
                  ),
                ),
              ),
            ],
          ),
          if (_testResult != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                StatusPill(
                  label: _testResult!.ok
                      ? l10n.providersTestPass(_testResult!.latencyMs)
                      : l10n.providersTestFail(_testResult!.statusCode),
                  tone: _testResult!.ok ? StatusTone.success : StatusTone.danger,
                ),
                if (_testResult!.error.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _testResult!.error,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: c.danger),
                    ),
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _manualModelsCtrl,
                  decoration: InputDecoration(
                    hintText: l10n.providersManualModelHint,
                  ),
                  onSubmitted: (_) => _addManualModels(),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _addManualModels,
                child: Text(l10n.actionAdd),
              ),
            ],
          ),
          if (_models.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              l10n.providersSelectedModels(_selectedModels.length),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: c.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _models
                  .map(
                    (m) => FilterChip(
                      label: Text(
                        m,
                        style: FalconTheme.mono(context, fontSize: 11.5),
                      ),
                      selected: _selectedModels.contains(m),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedModels.add(m);
                          } else {
                            _selectedModels.remove(m);
                          }
                        });
                      },
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ],
      ),
    );
  }
}

class _EditableKey {
  _EditableKey({
    required this.id,
    required this.labelCtrl,
    required this.secretCtrl,
    required this.maskedSecret,
    required this.weight,
    required this.enabled,
  });

  final String id;
  final TextEditingController labelCtrl;
  final TextEditingController secretCtrl;
  final String maskedSecret;
  final int weight;
  bool enabled;

  void dispose() {
    labelCtrl.dispose();
    secretCtrl.dispose();
  }
}

Future<void> showPresetPickerSheet(BuildContext context, WidgetRef ref) async {
  final l10n = context.l10n;
  final presets = await ref.read(providerPresetsProvider.future);
  if (!context.mounted) return;
  final selected = await showFalconSheet<ProviderPreset>(
    context: context,
    builder: (ctx) => FalconSheetFrame(
      title: l10n.providersPresetTitle,
      child: FalconCard(
        child: Column(
          children: [
            for (var i = 0; i < presets.length; i++) ...[
              if (i > 0) const FalconDivider(),
              FalconRow(
                icon: Icons.hub_outlined,
                title: presets[i].name,
                subtitle: presets[i].baseUrl,
                value: presets[i].protocol,
                onTap: () => Navigator.of(ctx).pop(presets[i]),
              ),
            ],
          ],
        ),
      ),
    ),
  );
  if (selected != null && context.mounted) {
    await showFalconSheet<bool>(
      context: context,
      builder: (_) => ProviderEditorSheet(preset: selected),
    );
  }
}
