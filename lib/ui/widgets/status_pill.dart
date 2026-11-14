import 'package:flutter/material.dart';

import '../../theme/falcon_theme.dart';

enum StatusTone { neutral, accent, success, warning, danger }

/// Restraint-first status text label without pill boxes or colored dots.
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
    final (fg, weight) = switch (tone) {
      StatusTone.neutral => (c.textSecondary, FontWeight.w500),
      StatusTone.accent => (c.textPrimary, FontWeight.w600),
      StatusTone.success => (c.textSecondary, FontWeight.w500),
      StatusTone.warning => (c.textSecondary, FontWeight.w500),
      StatusTone.danger => (c.danger, FontWeight.w600),
    };
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: FalconTheme.tabular(
        TextStyle(
          fontSize: 12.5,
          fontWeight: weight,
          color: fg,
        ),
      ),
    );
    if (icon == null) return text;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: fg),
        const SizedBox(width: 4),
        Flexible(child: text),
      ],
    );
  }
}
