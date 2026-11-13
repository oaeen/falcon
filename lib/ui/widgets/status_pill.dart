import 'package:flutter/material.dart';

import '../../theme/falcon_theme.dart';

enum StatusTone { neutral, accent, success, warning, danger }

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    this.tone = StatusTone.neutral,
    this.icon,
  });

  final String label;
  final StatusTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = FalconColors.of(context);
    final (fg, bg) = switch (tone) {
      StatusTone.neutral => (c.textSecondary, c.cardSubtle),
      StatusTone.accent => (c.accent, c.accentSoft),
      StatusTone.success => (c.success, c.successSoft),
      StatusTone.warning => (c.warning, c.warningSoft),
      StatusTone.danger => (c.danger, c.dangerSoft),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FalconTheme.tabular(
                TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
