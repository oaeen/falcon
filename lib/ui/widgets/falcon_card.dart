import 'package:flutter/material.dart';

import '../../theme/falcon_theme.dart';

/// Material 3 Expressive grouped card with tonal depth, 24dp radius,
/// crisp 1dp border, and zero heavy drop shadows.
class FalconCard extends StatelessWidget {
  const FalconCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.backgroundColor,
    this.borderColor,
    this.radius,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final Color? borderColor;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final c = FalconColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor ?? c.card,
        borderRadius: BorderRadius.circular(radius ?? FalconTheme.cardRadius),
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

/// Expressive section header placed above a [FalconCard].
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
      padding: const EdgeInsets.fromLTRB(6, 0, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.15,
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
