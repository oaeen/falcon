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
    final (fg, bg, borderColor, dotColor, weight) = switch (tone) {
      StatusTone.neutral => (
          c.textSecondary,
          c.cardSubtle,
          null,
          null,
          FontWeight.w500,
        ),
      StatusTone.accent => (
          c.textPrimary,
          c.card,
          c.border,
          null,
          FontWeight.w600,
        ),
      StatusTone.success => (
          c.textPrimary,
          c.card,
          c.border,
          c.success,
          FontWeight.w600,
        ),
      StatusTone.warning => (
          c.textSecondary,
          c.card,
          c.border,
          null,
          FontWeight.w500,
        ),
      StatusTone.danger => (
          c.danger,
          c.card,
          c.border,
          c.danger,
          FontWeight.w600,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: borderColor != null
            ? Border.all(color: borderColor, width: FalconTheme.borderWidth)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4.5),
          ] else if (dotColor != null) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5.5),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FalconTheme.tabular(
                TextStyle(
                  fontSize: 11.5,
                  fontWeight: weight,
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
