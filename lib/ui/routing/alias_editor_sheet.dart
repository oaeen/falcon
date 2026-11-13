import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/admin_models.dart';
import '../../l10n/l10n.dart';
import '../../state/gateway_state.dart';
import '../../theme/falcon_theme.dart';
import '../widgets/sheet_frame.dart';

class AliasEditorSheet extends ConsumerStatefulWidget {
  const AliasEditorSheet({
    super.key,
    required this.existingAliases,
    this.editing,
    this.availableTargets = const [],
  });

  final List<ModelAlias> existingAliases;
  final ModelAlias? editing;
  final List<String> availableTargets;

  @override
  ConsumerState<AliasEditorSheet> createState() => _AliasEditorSheetState();
}

class _AliasEditorSheetState extends ConsumerState<AliasEditorSheet> {
  final _aliasCtrl = TextEditingController();
  final _targetCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.editing != null) {
      _aliasCtrl.text = widget.editing!.alias;
      _targetCtrl.text = widget.editing!.target;
    }
  }

  @override
  void dispose() {
    _aliasCtrl.dispose();
    _targetCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final alias = _aliasCtrl.text.trim();
    final target = _targetCtrl.text.trim();
    if (alias.isEmpty || target.isEmpty) return;
    final client = ref.read(adminApiClientProvider);
    if (client == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    final updated = widget.existingAliases
        .where(
          (a) =>
              a.alias != alias &&
              (widget.editing == null || a.alias != widget.editing!.alias),
        )
        .toList();
    updated.add(ModelAlias(alias: alias, target: target));

    try {
      await client.saveAliases(updated);
      await ref.read(gatewayAdminStateProvider.notifier).reload();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = FalconColors.of(context);
    final isEdit = widget.editing != null;

    return FalconSheetFrame(
      title: isEdit ? l10n.routingAliasEdit : l10n.routingAliasAdd,
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
              onPressed: _saving ? null : _save,
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
            controller: _aliasCtrl,
            style: FalconTheme.mono(context, fontSize: 13),
            decoration: InputDecoration(
              labelText: l10n.routingAliasSourceLabel,
              hintText: l10n.routingAliasSourceHint,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _targetCtrl,
            style: FalconTheme.mono(context, fontSize: 13),
            decoration: InputDecoration(
              labelText: l10n.routingAliasTargetLabel,
              hintText: l10n.routingAliasTargetHint,
            ),
          ),
          if (widget.availableTargets.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: widget.availableTargets
                  .take(12)
                  .map(
                    (t) => ActionChip(
                      label: Text(
                        t,
                        style: FalconTheme.mono(context, fontSize: 11.5),
                      ),
                      onPressed: () => setState(() => _targetCtrl.text = t),
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
