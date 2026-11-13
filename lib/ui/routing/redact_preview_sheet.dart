import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/admin_models.dart';
import '../../l10n/l10n.dart';
import '../../state/gateway_state.dart';
import '../../theme/falcon_theme.dart';
import '../widgets/falcon_card.dart';
import '../widgets/falcon_row.dart';
import '../widgets/sheet_frame.dart';
import '../widgets/status_pill.dart';

class RedactPreviewSheet extends ConsumerStatefulWidget {
  const RedactPreviewSheet({super.key});

  @override
  ConsumerState<RedactPreviewSheet> createState() => _RedactPreviewSheetState();
}

class _RedactPreviewSheetState extends ConsumerState<RedactPreviewSheet> {
  final _inputCtrl = TextEditingController(
    text: 'Authorization: Bearer sk-test-1234567890abcdef, '
        'contact dev@example.com or 13800138000 at 192.168.1.42',
  );
  RedactPreviewResult? _result;
  bool _running = false;
  String? _error;

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<void> _runPreview() async {
    final text = _inputCtrl.text;
    if (text.trim().isEmpty) return;
    final client = ref.read(adminApiClientProvider);
    if (client == null) return;
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final res = await client.previewRedact(text);
      if (!mounted) return;
      setState(() {
        _result = res;
        _running = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = FalconColors.of(context);
    return FalconSheetFrame(
      title: l10n.routingRedactPreviewTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _inputCtrl,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: l10n.routingRedactPreviewInput,
              hintText: l10n.routingRedactPreviewInputHint,
            ),
          ),
          const SizedBox(height: 10),
          FilledButton(
            key: const ValueKey('run-redact-preview-btn'),
            onPressed: _running ? null : _runPreview,
            child: Text(l10n.routingRedactPreviewRun),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: c.danger, fontSize: 12.5)),
          ],
          if (_result != null) ...[
            const SizedBox(height: 16),
            Text(
              l10n.routingRedactPreviewOutput,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: c.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
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
                _result!.maskedText,
                style: FalconTheme.mono(context, fontSize: 12.5),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              l10n.routingRedactPreviewHits(_result!.hits.length),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: c.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            if (_result!.hits.isNotEmpty)
              FalconCard(
                child: Column(
                  children: [
                    for (var i = 0; i < _result!.hits.length; i++) ...[
                      if (i > 0) const FalconDivider(indent: 0),
                      FalconRow(
                        title: _result!.hits[i].ruleName,
                        subtitle: _result!.hits[i].placeholder,
                        monoTitle: false,
                        trailing: StatusPill(
                          label: '${_result!.hits[i].count}',
                          tone: StatusTone.accent,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
