import 'package:flutter/material.dart';

import '../../theme/falcon_theme.dart';

/// Opens a modal bottom sheet that safely respects keyboard insets and SafeArea.
Future<T?> showFalconSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: isDismissible,
    useSafeArea: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: builder(ctx),
    ),
  );
}

class FalconSheetFrame extends StatelessWidget {
  const FalconSheetFrame({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.headerTrailing,
    this.footer,
  });

  final String title;
  final String? subtitle;
  final Widget? headerTrailing;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final c = FalconColors.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.88;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: c.textMuted.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 17.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                            color: c.textPrimary,
                          ),
                        ),
                        if (subtitle != null && subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: c.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  ?headerTrailing,
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    tooltip: MaterialLocalizations.of(context).closeButtonLabel,
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: child,
              ),
            ),
            if (footer != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
                child: footer!,
              ),
          ],
        ),
      ),
    );
  }
}
