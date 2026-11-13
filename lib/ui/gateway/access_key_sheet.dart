import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/admin_models.dart';
import '../../l10n/l10n.dart';
import '../../state/gateway_state.dart';
import '../../theme/falcon_theme.dart';
import '../widgets/sheet_frame.dart';

class AccessKeySheet extends ConsumerStatefulWidget {
  const AccessKeySheet({
    super.key,
    this.existingKey,
    this.availableModels = const [],
  });

  final GatewayAccessKey? existingKey;
  final List<String> availableModels;

  @override
  ConsumerState<AccessKeySheet> createState() => _AccessKeySheetState();
}

class _AccessKeySheetState extends ConsumerState<AccessKeySheet> {
  final _nameController = TextEditingController();
  final _modelsController = TextEditingController();
  final _dailyUsdController = TextEditingController(text: '0');
  final _monthlyUsdController = TextEditingController(text: '0');
  final _dailyReqsController = TextEditingController(text: '0');

  bool _saving = false;
  String? _error;
  GatewayAccessKey? _createdWithSecret;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingKey;
    if (existing != null) {
      _nameController.text = existing.name;
      _modelsController.text = existing.allowedModels.join(', ');
      _dailyUsdController.text = existing.dailyLimitUsd > 0
          ? existing.dailyLimitUsd.toString()
          : '0';
      _monthlyUsdController.text = existing.monthlyLimitUsd > 0
          ? existing.monthlyLimitUsd.toString()
          : '0';
      _dailyReqsController.text = existing.dailyLimitReqs.toString();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _modelsController.dispose();
    _dailyUsdController.dispose();
    _monthlyUsdController.dispose();
    _dailyReqsController.dispose();
    super.dispose();
  }

  List<String> _parseModels() {
    return _modelsController.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  void _toggleModelChip(String model) {
    final current = _parseModels().toList();
    if (current.contains(model)) {
      current.remove(model);
    } else {
      current.add(model);
    }
    setState(() {
      _modelsController.text = current.join(', ');
    });
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final client = ref.read(adminApiClientProvider);
    if (client == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final result = await client.upsertKey(
        id: widget.existingKey?.id,
        name: name,
        enabled: widget.existingKey?.enabled ?? true,
        allowedModels: _parseModels(),
        dailyLimitUsd: double.tryParse(_dailyUsdController.text.trim()) ?? 0,
        monthlyLimitUsd: double.tryParse(_monthlyUsdController.text.trim()) ?? 0,
        dailyLimitReqs: int.tryParse(_dailyReqsController.text.trim()) ?? 0,
      );
      await ref.read(gatewayAdminStateProvider.notifier).reload();
      if (!mounted) return;
      if (result.secret != null && result.secret!.isNotEmpty) {
        ref
            .read(sessionKeySecretsProvider.notifier)
            .record(result.id, result.secret!);
        setState(() {
          _createdWithSecret = result;
          _saving = false;
        });
      } else {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$e';
      });
    }
  }

  Future<void> _copySecret(String secret) async {
    await Clipboard.setData(ClipboardData(text: secret));
    if (!mounted) return;
    setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = FalconColors.of(context);

    if (_createdWithSecret != null) {
      final secret = _createdWithSecret!.secret!;
      return FalconSheetFrame(
        title: _createdWithSecret!.name,
        subtitle: l10n.gatewayKeyCreatedNotice,
        footer: FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.actionClose),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
              child: SelectableText(
                secret,
                style: FalconTheme.mono(context, fontSize: 13.5),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _copySecret(secret),
              icon: Icon(
                _copied ? Icons.check_rounded : Icons.copy_outlined,
                size: 18,
              ),
              label: Text(_copied ? l10n.actionCopied : l10n.actionCopy),
            ),
          ],
        ),
      );
    }

    final selectedModels = _parseModels().toSet();
    final isEdit = widget.existingKey != null;

    return FalconSheetFrame(
      title: isEdit ? l10n.actionEdit : l10n.gatewayKeyCreateTitle,
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
              onPressed: _saving ? null : _submit,
              child: Text(isEdit ? l10n.actionSave : l10n.actionCreate),
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            Text(
              _error!,
              style: TextStyle(color: c.danger, fontSize: 13),
            ),
            const SizedBox(height: 10),
          ],
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: l10n.gatewayKeyNameLabel,
              hintText: l10n.gatewayKeyNameHint,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _modelsController,
            decoration: InputDecoration(
              labelText: l10n.gatewayKeyModelsLabel,
              hintText: l10n.gatewayKeyModelsHint,
            ),
          ),
          if (widget.availableModels.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: widget.availableModels
                  .take(12)
                  .map(
                    (m) => FilterChip(
                      label: Text(
                        m,
                        style: FalconTheme.mono(context, fontSize: 11.5),
                      ),
                      selected: selectedModels.contains(m),
                      onSelected: (_) => _toggleModelChip(m),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _dailyUsdController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: FalconTheme.tabular(null),
                  decoration: InputDecoration(
                    labelText: l10n.gatewayKeyDailyUsdLabel,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _monthlyUsdController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: FalconTheme.tabular(null),
                  decoration: InputDecoration(
                    labelText: l10n.gatewayKeyMonthlyUsdLabel,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _dailyReqsController,
            keyboardType: TextInputType.number,
            style: FalconTheme.tabular(null),
            decoration: InputDecoration(
              labelText: l10n.gatewayKeyDailyReqsLabel,
            ),
          ),
        ],
      ),
    );
  }
}
