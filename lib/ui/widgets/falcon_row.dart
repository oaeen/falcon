import 'package:flutter/material.dart';

import '../../theme/falcon_theme.dart';

class FalconDivider extends StatelessWidget {
  const FalconDivider({super.key, this.indent = 16});

  final double indent;

  @override
  Widget build(BuildContext context) {
    final c = FalconColors.of(context);
    return Divider(
      height: FalconTheme.borderWidth,
      thickness: FalconTheme.borderWidth,
      indent: indent,
      color: c.border,
    );
  }
}

/// Clean list/settings row inspired by iOS Settings and Tailscale.
///
/// Uses a bare 20px linear icon (no colored background disc).
class FalconRow extends StatelessWidget {
  const FalconRow({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
    this.danger = false,
    this.monoTitle = false,
    this.monoValue = false,
    this.showChevron,
  });

  final IconData? icon;
  final String title;
  final String? subtitle;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;
  final bool monoTitle;
  final bool monoValue;
  final bool? showChevron;

  @override
  Widget build(BuildContext context) {
    final c = FalconColors.of(context);
    final hasSubtitle = subtitle != null && subtitle!.isNotEmpty;
    final chevron = showChevron ?? (onTap != null && trailing == null);

    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: hasSubtitle ? 60 : 50),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              if (icon != null) ...[
                SizedBox(
                  width: 24,
                  child: Icon(
                    icon,
                    size: 20,
                    color: danger ? c.danger : c.textSecondary,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: monoTitle
                          ? FalconTheme.mono(
                              context,
                              fontSize: 13.5,
                              color: danger ? c.danger : c.textPrimary,
                            )
                          : TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w500,
                              color: danger ? c.danger : c.textPrimary,
                            ),
                    ),
                    if (hasSubtitle) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: FalconTheme.tabular(
                          TextStyle(
                            fontSize: 12.5,
                            color: c.textSecondary,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (value != null && value!.isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  flex: 0,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: Text(
                      value!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: monoValue
                          ? FalconTheme.mono(
                              context,
                              fontSize: 13,
                              color: c.textSecondary,
                            )
                          : FalconTheme.tabular(
                              TextStyle(
                                fontSize: 13.5,
                                color: c.textSecondary,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ] else if (chevron) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: c.textMuted,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
