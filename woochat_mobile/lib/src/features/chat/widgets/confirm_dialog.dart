import 'package:flutter/material.dart';

import '../../../theme/wa_colors.dart';

/// Asks before something that cannot be undone. True only on confirm —
/// dismissing counts as no.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
  String cancelLabel = 'Cancel',
  bool destructive = true,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Wa.sheet,
      title: Text(
        title,
        style: const TextStyle(color: Wa.title, fontSize: 17),
      ),
      content: Text(
        message,
        style: const TextStyle(color: Wa.secondaryText, fontSize: 14),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            cancelLabel,
            style: const TextStyle(color: Wa.secondaryText),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: destructive ? Wa.error : Wa.accent,
            foregroundColor: destructive ? Colors.black : Wa.onAccent,
          ),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
