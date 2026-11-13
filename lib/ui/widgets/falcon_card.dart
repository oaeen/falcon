import 'package:flutter/material.dart';

import '../../theme/falcon_theme.dart';

/// Restrained grouped card with 12px radius, 0.5px border, and zero shadows.
class FalconCard extends StatelessWidget {
  const FalconCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.backgroundColor,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final c = FalconColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor ?? c.card,
        borderRadius: BorderRadius.circular(FalconTheme.cardRadius),
        border: Border.all(
          color: borderColor ?? c.border,
          width: FalconTheme.borderWidth,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: padding == EdgeInsets.zero
          ? child
          : Padding(padding: padding, child: child),
    );
  }
}

/// Section header placed directly above a [FalconCard].
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
  });

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = FalconColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
                color: c.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
