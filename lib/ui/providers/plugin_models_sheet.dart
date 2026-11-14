import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/admin_models.dart';
import '../../l10n/l10n.dart';
import '../../state/gateway_state.dart';
import '../../theme/falcon_theme.dart';
import '../widgets/falcon_card.dart';
import '../widgets/falcon_row.dart';
import '../widgets/sheet_frame.dart';

enum _ModelFilter { all, selected, free }

class PluginModelsSheet extends ConsumerStatefulWidget {
  const PluginModelsSheet({
    super.key,
    required this.plugin,
    required this.detail,
    required this.displayTitle,
  });

  final InstalledPlugin plugin;
  final PluginProviderDetail detail;
  final String displayTitle;

  @override
  ConsumerState<PluginModelsSheet> createState() => _PluginModelsSheetState();
}

class _PluginModelsSheetState extends ConsumerState<PluginModelsSheet> {
  final _searchCtrl = TextEditingController();
  late Set<String> _selectedIds;
  late List<PluginModelInfo> _models;
  _ModelFilter _filter = _ModelFilter.all;
  String _query = '';
  bool _saving = false;
  bool _refreshing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedIds = widget.detail.selectedModels.toSet();
    _models = widget.detail.models;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _formatTokens(int count) {
    if (count >= 1000000) {
      final m = count / 1000000;
      return '${m.toStringAsFixed(m == m.roundToDouble() ? 0 : 1)}M';
    }
    if (count >= 1000) {
      return '${(count / 1000).round()}K';
    }
    return '$count';
  }

  Future<void> _refreshCatalog() async {
    final client = ref.read(adminApiClientProvider);
    if (client == null) return;
    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      await client.refreshPlugins(pluginId: widget.plugin.id);
      await ref.read(gatewayAdminStateProvider.notifier).reload();
      if (!mounted) return;
      final snapshot = ref.read(gatewayAdminStateProvider).value;
      if (snapshot != null) {
        for (final pl in snapshot.plugins) {
          if (pl.id == widget.plugin.id ||
              isSamePluginPackage(pl.package, widget.plugin.package)) {
            final details = pl.resolvedProviderDetails(
              snapshot.settings.pluginSelectedModels,
            );
            for (final d in details) {
              if (d.id == widget.detail.id) {
                setState(() => _models = d.models);
                break;
              }
            }
          }
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _save() async {
    final client = ref.read(adminApiClientProvider);
    if (client == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final ordered = _models
          .map((m) => m.id)
          .where(_selectedIds.contains)
          .toList(growable: false);
      await client.setPluginSelectedModels(
        pluginId: widget.plugin.id,
        providerId: widget.detail.id,
        selectedModels: ordered,
      );
      await ref.read(gatewayAdminStateProvider.notifier).reload();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$e';
        });
      }
    }
  }

  List<PluginModelInfo> get _filteredModels {
    final q = _query.trim().toLowerCase();
    return _models.where((m) {
      if (_filter == _ModelFilter.selected && !_selectedIds.contains(m.id)) {
        return false;
      }
      if (_filter == _ModelFilter.free && !m.free) {
        return false;
      }
      if (q.isEmpty) return true;
      return m.id.toLowerCase().contains(q) ||
          m.displayName.toLowerCase().contains(q);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = FalconColors.of(context);
    final filtered = _filteredModels;
    final shortTitle = widget.displayTitle.split(' (').first;
    final subtitle = _selectedIds.isEmpty
        ? l10n.pluginsAutoAllModels(_models.length)
        : l10n.pluginsSelectedModelsSummary(
            _selectedIds.length,
            _models.length,
          );

    return FalconSheetFrame(
      title: l10n.pluginsModelsTitle,
      subtitle: '$shortTitle · $subtitle',
      headerTrailing: IconButton(
        key: const ValueKey('plugin-models-refresh-btn'),
        tooltip: l10n.actionRefresh,
        onPressed: _refreshing ? null : _refreshCatalog,
        icon: _refreshing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.refresh_rounded, size: 20),
      ),
      footer: FilledButton(
        key: const ValueKey('plugin-models-save-btn'),
        onPressed: _saving ? null : _save,
        child: Text(l10n.actionSave),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('plugin-models-search'),
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: l10n.pluginsModelsSearchHint,
              prefixIcon: const Icon(Icons.search_rounded, size: 19),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                    )
                  : null,
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: Text(l10n.pluginsModelsFilterAll),
                        selected: _filter == _ModelFilter.all,
                        onSelected: (_) =>
                            setState(() => _filter = _ModelFilter.all),
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: Text(l10n.pluginsModelsFilterSelected),
                        selected: _filter == _ModelFilter.selected,
                        onSelected: (_) =>
                            setState(() => _filter = _ModelFilter.selected),
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: Text(l10n.pluginsModelsFilterFree),
                        selected: _filter == _ModelFilter.free,
                        onSelected: (_) =>
                            setState(() => _filter = _ModelFilter.free),
                      ),
                    ],
                  ),
                ),
              ),
              TextButton(
                key: const ValueKey('plugin-models-select-all-btn'),
                onPressed: _models.isEmpty
                    ? null
                    : () => setState(
                          () => _selectedIds =
                              _models.map((m) => m.id).toSet(),
                        ),
                child: Text(l10n.pluginsModelsSelectAll),
              ),
              TextButton(
                key: const ValueKey('plugin-models-clear-auto-btn'),
                onPressed: _selectedIds.isEmpty
                    ? null
                    : () => setState(() => _selectedIds.clear()),
                child: Text(l10n.actionClear),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(fontSize: 12.5, color: c.danger),
            ),
          ],
          const SizedBox(height: 10),
          if (filtered.isEmpty)
            FalconCard(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.pluginsModelsEmpty,
                style: TextStyle(fontSize: 13, color: c.textSecondary),
              ),
            )
          else
            FalconCard(
              child: Column(
                children: [
                  for (var i = 0; i < filtered.length; i++) ...[
                    if (i > 0) const FalconDivider.icon(),
                    _PluginModelRow(
                      model: filtered[i],
                      selected: _selectedIds.contains(filtered[i].id),
                      contextBadge: filtered[i].context > 0
                          ? _formatTokens(filtered[i].context)
                          : null,
                      onChanged: (checked) {
                        setState(() {
                          if (checked) {
                            _selectedIds.add(filtered[i].id);
                          } else {
                            _selectedIds.remove(filtered[i].id);
                          }
                        });
                      },
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PluginModelRow extends StatelessWidget {
  const _PluginModelRow({
    required this.model,
    required this.selected,
    required this.contextBadge,
    required this.onChanged,
  });

  final PluginModelInfo model;
  final bool selected;
  final String? contextBadge;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = FalconColors.of(context);
    final hasSecondary = model.displayName != model.id ||
        model.free ||
        model.reasoning ||
        model.toolCall;

    return InkWell(
      onTap: () => onChanged(!selected),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
        child: Row(
          children: [
            Checkbox(
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              value: selected,
              onChanged: (v) => onChanged(v ?? false),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          model.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                      if (contextBadge != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          contextBadge!,
                          style: FalconTheme.tabular(
                            TextStyle(
                              fontSize: 12,
                              color: c.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (hasSecondary) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (model.displayName != model.id) ...[
                          Flexible(
                            child: Text(
                              model.id,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: FalconTheme.mono(
                                context,
                                fontSize: 11.5,
                                color: c.textMuted,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (model.reasoning) ...[
                          Text(
                            l10n.pluginsModelsCapReasoning,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: c.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (model.toolCall) ...[
                          Text(
                            l10n.pluginsModelsCapTools,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: c.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (model.free)
                          Text(
                            l10n.pluginsModelsCapFree,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: c.accent,
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
