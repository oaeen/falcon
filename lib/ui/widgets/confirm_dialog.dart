import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/falcon_theme.dart';

Future<bool> showFalconConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String? confirmLabel,
  bool destructive = false,
}) async {
  final l10n = context.l10n;
  final c = FalconColors.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: c.textPrimary,
        ),
      ),
      content: Text(
        message,
        style: TextStyle(fontSize: 14, color: c.textSecondary, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: c.danger,
                  foregroundColor: Colors.white,
                )
              : null,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel ?? l10n.actionConfirm),
        ),
      ],
    ),
  );
  return ok ?? false;
}
