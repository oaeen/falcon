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
                width: 34,
                height: 4,
                decoration: BoxDecoration(
                  color: c.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w600,
                            color: c.textPrimary,
                          ),
                        ),
                        if (subtitle != null && subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
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
            Divider(height: FalconTheme.borderWidth, color: c.border),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                child: child,
              ),
            ),
            if (footer != null) ...[
              Divider(height: FalconTheme.borderWidth, color: c.border),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
                child: footer!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
