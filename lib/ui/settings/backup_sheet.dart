import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/l10n.dart';
import '../../state/gateway_state.dart';
import '../../theme/falcon_theme.dart';
import '../widgets/sheet_frame.dart';

class BackupSheet extends ConsumerStatefulWidget {
  const BackupSheet({
    super.key,
    required this.isImport,
    this.initialJson = '',
  });

  final bool isImport;
  final String initialJson;

  @override
  ConsumerState<BackupSheet> createState() => _BackupSheetState();
}

class _BackupSheetState extends ConsumerState<BackupSheet> {
  late final TextEditingController _jsonCtrl;
  bool _busy = false;
  bool _copied = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _jsonCtrl = TextEditingController(text: widget.initialJson);
  }

  @override
  void dispose() {
    _jsonCtrl.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final text = _jsonCtrl.text.trim();
    if (text.isEmpty) return;
    final client = ref.read(adminApiClientProvider);
    if (client == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('JSON object expected');
      }
      await client.importBackup(decoded);
      await ref.read(gatewayAdminStateProvider.notifier).reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.settingsBackupImportSuccess)),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _jsonCtrl.text));
    if (mounted) setState(() => _copied = true);
  }

  Future<void> _share() async {
    await SharePlus.instance.share(
      ShareParams(text: _jsonCtrl.text, subject: 'falcon-backup.json'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = FalconColors.of(context);
    return FalconSheetFrame(
      title: l10n.settingsBackupSheetTitle,
      footer: widget.isImport
          ? Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: Text(l10n.actionCancel),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : _import,
                    child: Text(l10n.actionImport),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _copy,
                    icon: Icon(
                      _copied ? Icons.check_rounded : Icons.copy_outlined,
                      size: 17,
                    ),
                    label: Text(_copied ? l10n.actionCopied : l10n.actionCopy),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _share,
                    icon: const Icon(Icons.share_outlined, size: 17),
                    label: Text(l10n.actionExport),
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
            controller: _jsonCtrl,
            readOnly: !widget.isImport,
            maxLines: 12,
            style: FalconTheme.mono(context, fontSize: 12),
            decoration: InputDecoration(
              hintText: widget.isImport ? l10n.settingsBackupPasteHint : null,
            ),
          ),
        ],
      ),
    );
  }
}
