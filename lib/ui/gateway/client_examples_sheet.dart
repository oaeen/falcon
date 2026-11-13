import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../../theme/falcon_theme.dart';
import '../widgets/sheet_frame.dart';

class ClientExamplesSheet extends StatefulWidget {
  const ClientExamplesSheet({
    super.key,
    required this.loopbackUrl,
    required this.lanUrls,
  });

  final String loopbackUrl;
  final List<String> lanUrls;

  @override
  State<ClientExamplesSheet> createState() => _ClientExamplesSheetState();
}

class _ClientExamplesSheetState extends State<ClientExamplesSheet> {
  String _selectedEndpoint = '';
  String? _copiedId;

  @override
  void initState() {
    super.initState();
    _selectedEndpoint =
        widget.lanUrls.isNotEmpty ? widget.lanUrls.first : widget.loopbackUrl;
  }

  Future<void> _copy(String id, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() => _copiedId = id);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _copiedId == id) setState(() => _copiedId = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = FalconColors.of(context);
    final endpoints = <String>[widget.loopbackUrl, ...widget.lanUrls];

    final openAiSnippet = 'OPENAI_BASE_URL=$_selectedEndpoint/v1\n'
        'OPENAI_API_KEY=sk-flc-your-key';
    final anthropicSnippet = 'ANTHROPIC_BASE_URL=$_selectedEndpoint\n'
        'ANTHROPIC_API_KEY=sk-flc-your-key';
    final geminiSnippet = 'GEMINI_API_BASE=$_selectedEndpoint/v1beta\n'
        'GEMINI_API_KEY=sk-flc-your-key';
    final curlSnippet = 'curl $_selectedEndpoint/v1/chat/completions \\\n'
        '  -H "Authorization: Bearer sk-flc-your-key" \\\n'
        '  -H "Content-Type: application/json" \\\n'
        '  -d \'{"model":"gpt-4o","messages":[{"role":"user","content":"ping"}]}\'';

    return FalconSheetFrame(
      title: l10n.gatewayClientExamplesTitle,
      subtitle: l10n.gatewayClientAuthNote,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (endpoints.length > 1) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: endpoints
                  .map(
                    (url) => ChoiceChip(
                      label: Text(
                        url,
                        style: FalconTheme.mono(context, fontSize: 12),
                      ),
                      selected: _selectedEndpoint == url,
                      onSelected: (_) => setState(() => _selectedEndpoint = url),
                    ),
                  )
                  .toList(growable: false),
            ),
            const SizedBox(height: 14),
          ],
          _SnippetBlock(
            title: l10n.gatewayClientOpenAi,
            code: openAiSnippet,
            copied: _copiedId == 'openai',
            copyLabel: _copiedId == 'openai' ? l10n.actionCopied : l10n.actionCopy,
            onCopy: () => _copy('openai', openAiSnippet),
            colors: c,
          ),
          const SizedBox(height: 12),
          _SnippetBlock(
            title: l10n.gatewayClientAnthropic,
            code: anthropicSnippet,
            copied: _copiedId == 'anthropic',
            copyLabel:
                _copiedId == 'anthropic' ? l10n.actionCopied : l10n.actionCopy,
            onCopy: () => _copy('anthropic', anthropicSnippet),
            colors: c,
          ),
          const SizedBox(height: 12),
          _SnippetBlock(
            title: l10n.gatewayClientGemini,
            code: geminiSnippet,
            copied: _copiedId == 'gemini',
            copyLabel: _copiedId == 'gemini' ? l10n.actionCopied : l10n.actionCopy,
            onCopy: () => _copy('gemini', geminiSnippet),
            colors: c,
          ),
          const SizedBox(height: 12),
          _SnippetBlock(
            title: l10n.gatewayClientCurl,
            code: curlSnippet,
            copied: _copiedId == 'curl',
            copyLabel: _copiedId == 'curl' ? l10n.actionCopied : l10n.actionCopy,
            onCopy: () => _copy('curl', curlSnippet),
            colors: c,
          ),
        ],
      ),
    );
  }
}

class _SnippetBlock extends StatelessWidget {
  const _SnippetBlock({
    required this.title,
    required this.code,
    required this.copied,
    required this.copyLabel,
    required this.onCopy,
    required this.colors,
  });

  final String title;
  final String code;
  final bool copied;
  final String copyLabel;
  final VoidCallback onCopy;
  final FalconColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: onCopy,
              icon: Icon(
                copied ? Icons.check_rounded : Icons.copy_outlined,
                size: 16,
              ),
              label: Text(copyLabel),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.cardSubtle,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.border, width: FalconTheme.borderWidth),
          ),
          child: SelectableText(
            code,
            style: FalconTheme.mono(context, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
