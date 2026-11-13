import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/admin_models.dart';
import '../../l10n/l10n.dart';
import '../../state/gateway_state.dart';
import '../../theme/falcon_theme.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/sheet_frame.dart';

class GroupEditorSheet extends ConsumerStatefulWidget {
  const GroupEditorSheet({
    super.key,
    this.existing,
    this.availableMembers = const [],
  });

  final RoutingGroup? existing;
  final List<String> availableMembers;

  @override
  ConsumerState<GroupEditorSheet> createState() => _GroupEditorSheetState();
}

class _GroupEditorSheetState extends ConsumerState<GroupEditorSheet> {
  final _nameCtrl = TextEditingController();
  final _membersCtrl = TextEditingController();
  String _strategy = 'order';
  String _pinned = '';
  bool _enabled = true;
  bool _saving = false;
  String? _error;

  static const _strategies = ['order', 'round_robin', 'fastest', 'manual'];

  @override
  void initState() {
    super.initState();
    final g = widget.existing;
    if (g != null) {
      _nameCtrl.text = g.name;
      _membersCtrl.text = g.members.join('\n');
      _strategy = _strategies.contains(g.strategy) ? g.strategy : 'order';
      _pinned = g.pinnedMember;
      _enabled = g.enabled;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _membersCtrl.dispose();
    super.dispose();
  }

  List<String> _parseMembers() {
    return _membersCtrl.text
        .split(RegExp(r'[\n,]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  void _toggleMember(String member) {
    final list = _parseMembers().toList();
    if (list.contains(member)) {
      list.remove(member);
    } else {
      list.add(member);
    }
    setState(() {
      _membersCtrl.text = list.join('\n');
    });
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final client = ref.read(adminApiClientProvider);
    if (client == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    final members = _parseMembers();
    try {
      await client.upsertGroup(
        RoutingGroup(
          id: widget.existing?.id ?? '',
          name: name,
          strategy: _strategy,
          pinnedMember: _strategy == 'manual'
              ? (_pinned.isNotEmpty
                  ? _pinned
                  : (members.isNotEmpty ? members.first : ''))
              : '',
          enabled: _enabled,
          members: members,
        ),
      );
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

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final ok = await showFalconConfirmDialog(
      context: context,
      title: context.l10n.actionDelete,
      message: context.l10n.routingGroupDeleteConfirm(existing.name),
      destructive: true,
    );
    if (!ok) return;
    final client = ref.read(adminApiClientProvider);
    if (client == null) return;
    await client.deleteGroup(existing.id);
    await ref.read(gatewayAdminStateProvider.notifier).reload();
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = FalconColors.of(context);
    final isEdit = widget.existing != null;
    final currentMembers = _parseMembers();
    final selectedSet = currentMembers.toSet();

    String strategyLabel(String s) => switch (s) {
          'order' => l10n.routingStrategyOrder,
          'round_robin' => l10n.routingStrategyRoundRobin,
          'fastest' => l10n.routingStrategyFastest,
          'manual' => l10n.routingStrategyManual,
          _ => s,
        };

    return FalconSheetFrame(
      title: isEdit ? l10n.routingGroupEdit : l10n.routingGroupAdd,
      headerTrailing: isEdit
          ? IconButton(
              icon: Icon(Icons.delete_outline_rounded, color: c.danger, size: 20),
              tooltip: l10n.actionDelete,
              onPressed: _delete,
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
            decoration: InputDecoration(labelText: l10n.routingGroupNameLabel),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _strategy,
            isExpanded: true,
            decoration:
                InputDecoration(labelText: l10n.routingGroupStrategyLabel),
            items: _strategies
                .map(
                  (s) => DropdownMenuItem(
                    value: s,
                    child: Text(strategyLabel(s)),
                  ),
                )
                .toList(growable: false),
            onChanged: (v) {
              if (v != null) setState(() => _strategy = v);
            },
          ),
          if (_strategy == 'manual' && currentMembers.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: currentMembers.contains(_pinned)
                  ? _pinned
                  : currentMembers.first,
              isExpanded: true,
              decoration:
                  InputDecoration(labelText: l10n.routingGroupPinnedLabel),
              items: currentMembers
                  .map(
                    (m) => DropdownMenuItem(
                      value: m,
                      child: Text(
                        m,
                        style: FalconTheme.mono(context, fontSize: 12.5),
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (v) {
                if (v != null) setState(() => _pinned = v);
              },
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _membersCtrl,
            maxLines: 4,
            style: FalconTheme.mono(context, fontSize: 12.5),
            decoration: InputDecoration(
              labelText: l10n.routingGroupMembersLabel,
              hintText: l10n.routingGroupMembersHint,
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (widget.availableMembers.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: widget.availableMembers
                  .where((m) => m.contains('/'))
                  .take(15)
                  .map(
                    (m) => FilterChip(
                      label: Text(
                        m,
                        style: FalconTheme.mono(context, fontSize: 11.5),
                      ),
                      selected: selectedSet.contains(m),
                      onSelected: (_) => _toggleMember(m),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.statusEnabled),
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),
        ],
      ),
    );
  }
}
