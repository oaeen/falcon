import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/admin_models.dart';
import '../../l10n/l10n.dart';
import '../../state/gateway_state.dart';
import '../../theme/falcon_theme.dart';
import '../widgets/sheet_frame.dart';

class RedactRuleSheet extends ConsumerStatefulWidget {
  const RedactRuleSheet({
    super.key,
    required this.existingRules,
  });

  final List<RedactRule> existingRules;

  @override
  ConsumerState<RedactRuleSheet> createState() => _RedactRuleSheetState();
}

class _RedactRuleSheetState extends ConsumerState<RedactRuleSheet> {
  final _nameCtrl = TextEditingController();
  final _patternCtrl = TextEditingController();
  final _replacementCtrl = TextEditingController(text: '[REDACTED_CUSTOM]');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _patternCtrl.dispose();
    _replacementCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final pattern = _patternCtrl.text.trim();
    final replacement = _replacementCtrl.text.trim();
    if (name.isEmpty || pattern.isEmpty) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    final next = [
      ...widget.existingRules,
      RedactRule(
        id: 'rule-${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        pattern: pattern,
        replacement: replacement.isEmpty ? '[REDACTED]' : replacement,
      ),
    ];

    try {
      await ref.read(gatewayAdminStateProvider.notifier).updateSettings({
        'redactRules': next.map((r) => r.toJson()).toList(growable: false),
      });
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
    return FalconSheetFrame(
      title: l10n.routingRedactRuleAdd,
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
            controller: _nameCtrl,
            decoration: InputDecoration(labelText: l10n.routingRedactRuleName),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _patternCtrl,
            style: FalconTheme.mono(context, fontSize: 13),
            decoration:
                InputDecoration(labelText: l10n.routingRedactRulePattern),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _replacementCtrl,
            style: FalconTheme.mono(context, fontSize: 13),
            decoration:
                InputDecoration(labelText: l10n.routingRedactRuleReplacement),
          ),
        ],
      ),
    );
  }
}
