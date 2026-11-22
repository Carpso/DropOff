import 'package:flutter/material.dart';

import 'app_theme.dart';

Future<T?> showAppSheet<T>(
  BuildContext context, {
  required Widget child,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: child,
      ),
    ),
  );
}

Future<bool> showConfirmSheet(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  IconData icon = Icons.help_outline_rounded,
  Color accent = AppColors.forest,
  bool danger = false,
}) async {
  final result = await showAppSheet<bool>(
    context,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(4)))),
        const SizedBox(height: 16),
        Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: (danger ? AppColors.danger : accent).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: danger ? AppColors.danger : accent),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.2))),
        ]),
        const SizedBox(height: 14),
        Text(message, style: const TextStyle(fontSize: 14, height: 1.45, color: AppColors.ink)),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: () => Navigator.of(context).pop(false), child: Text(cancelLabel))),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              style: danger ? FilledButton.styleFrom(backgroundColor: AppColors.danger) : null,
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(confirmLabel),
            ),
          ),
        ]),
      ],
    ),
  );
  return result == true;
}

Future<void> showInfoSheet(
  BuildContext context, {
  required String title,
  required String message,
  String buttonLabel = 'Got it',
  IconData icon = Icons.info_outline_rounded,
  Color accent = AppColors.forest,
  Widget? extra,
}) {
  return showAppSheet<void>(
    context,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(4)))),
        const SizedBox(height: 16),
        Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.2))),
        ]),
        const SizedBox(height: 14),
        Text(message, style: const TextStyle(fontSize: 14, height: 1.45, color: AppColors.muted)),
        if (extra != null) ...[const SizedBox(height: 14), extra],
        const SizedBox(height: 20),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(buttonLabel))),
      ],
    ),
  );
}
