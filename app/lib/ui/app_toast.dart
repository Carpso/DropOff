import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Severity used to pick the colour + icon. [inferLog] is also used when the
/// caller doesn't pass a type — it guesses from the message text.
enum AppToastType { success, info, warning, error }

/// DropOff toast ("snack bar") with icon + rounded pill + behaviour floats.
/// Every user-facing ephemeral message should be an AppToast: white-on-forest,
/// 15% bottom inset, swipe-up to dismiss, with an auto-selected severity.
class AppToast {
  const AppToast._();

  static const _dur = Duration(seconds: 3);
  static const _durLong = Duration(seconds: 5);

  static void success(BuildContext context, String message, {Duration? duration}) =>
      _show(context, message, AppToastType.success, duration ?? _dur);

  static void info(BuildContext context, String message, {Duration? duration}) =>
      _show(context, message, AppToastType.info, duration ?? _dur);

  static void warning(BuildContext context, String message, {Duration? duration}) =>
      _show(context, message, AppToastType.warning, duration ?? _durLong);

  static void error(BuildContext context, String message, {Duration? duration}) =>
      _show(context, message, AppToastType.error, duration ?? _durLong);

  /// Smart entry point: infers severity from the wording of [message] so the
  /// 80 existing call sites convert without hand-classification.
  static void show(BuildContext context, String message, {AppToastType? type, Duration? duration}) {
    final t = type ?? _infer(message);
    _show(context, message, t, duration ?? (t == AppToastType.success ? _dur : _durLong));
  }

  static AppToastType _infer(String message) {
    final m = ' ${message.toLowerCase()} ';
    const success = [
      'copied', 'saved', 'sent', 'done', 'success', 'verified', 'approved', 'accepted',
      'activated', 'renewed', 'upgraded', 'linked', 'generated', 'created', 'shared',
      'applied', 'signed in', 'signed out', 'deactivated', 'removed', 'paid', 'received',
      'on its way', 'complete', 'updated', 'marked', 'taller', 'renewed', 'prompted',
    ];
    const failure = [
      'failed', 'could not', 'cannot', "couldn't", 'invalid', 'denied', 'rejected',
      'expired', 'unavailable', 'error', 'not authenticated', 'permission', 'unverified',
      'refused', 'blocked', 'low', 'insufficient', 'cancelled', 'empty',
    ];
    const warning = [
      'could not be', 'check', 'try again', 'required', 'first', 'no ', 'unknown',
      'keep', 'not ', 'caution', 'warning', 'share', 'please', 'do not',
    ];
    bool hit(List<String> needles) => needles.any((n) => m.contains(' $n') || m.startsWith('$n ') || m.contains('$n '));
    if (hit(success)) return AppToastType.success;
    if (hit(failure)) return AppToastType.error;
    if (hit(warning)) return AppToastType.warning;
    return AppToastType.info;
  }

  static void _show(BuildContext context, String message, AppToastType type, Duration duration) {
    final (bg, icon) = switch (type) {
      AppToastType.success => (AppColors.forest, Icons.check_circle_rounded),
      AppToastType.info => (const Color(0xFF2B5A86), Icons.info_rounded),
      AppToastType.warning => (const Color(0xFF8A5A00), Icons.warning_amber_rounded),
      AppToastType.error => (const Color(0xFFB3261E), Icons.error_rounded),
    };
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      elevation: 8,
      duration: duration,
      dismissDirection: DismissDirection.up,
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 22),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.22),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(message,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13, height: 1.32)),
        ),
      ]),
    ));
  }
}
