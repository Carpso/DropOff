import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'keys.dart';

/// Severity used to pick the colour + icon. [inferLog] is also used when the
/// caller doesn't pass a type — it guesses from the message text.
enum AppToastType { success, info, warning, error }

/// DropOff toast ("snack bar") with icon + rounded pill + behaviour floats.
///
/// SUCCESS/INFO/WARNING float 22 px above the bottom edge. ERRORS are pinned
/// under the top app bar instead (owner bug 2026-11-23): on the delivery
/// details screen the bottom toast covered "Pay K5.00 to unlock" and
/// "Download courier receipt" in Help & actions, so a sender could not see or
/// tap the very action the message was about.
class AppToast {
  const AppToast._();

  static const _dur = Duration(seconds: 3);
  static const _durLong = Duration(seconds: 5);

  /// Only one top error is ever visible; a newer one replaces the old one.
  static OverlayEntry? _topEntry;

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

  static (Color, IconData) _style(AppToastType type) => switch (type) {
        AppToastType.success => (AppColors.forest, Icons.check_circle_rounded),
        AppToastType.info => (const Color(0xFF2B5A86), Icons.info_rounded),
        AppToastType.warning => (AppColors.warning, Icons.warning_amber_rounded),
        AppToastType.error => (AppColors.danger, Icons.error_rounded),
      };

  static Widget _content(IconData icon, String message) => Row(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          // Flexible — never Expanded inside a min-size Row: intrinsic sizing
          // collapsed the text to a 0-width column, which rendered long
          // messages as VERTICAL text (owner bug 2026-11-20).
          Flexible(
            child: Text(message,
                softWrap: true,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13, height: 1.32)),
          ),
        ],
      );

  static void _show(BuildContext context, String message, AppToastType type, Duration duration) {
    // Errors go to the TOP so they never sit on top of the action they are
    // complaining about. Root overlay keeps them above sheets and dialogs.
    if (type == AppToastType.error) {
      // Prefer the CALLER's context: it is inside a route and therefore has an
      // Overlay ancestor. The root ScaffoldMessenger context can sit above the
      // Navigator in MaterialApp, where `Overlay.maybeOf` finds nothing.
      final overlay = Overlay.maybeOf(context, rootOverlay: true) ??
          Overlay.maybeOf(context) ??
          (scaffoldMessengerKey.currentContext == null
              ? null
              : Overlay.maybeOf(scaffoldMessengerKey.currentContext!, rootOverlay: true));
      if (overlay != null) {
        _showTop(overlay, message, type, duration);
        return;
      }
    }
    final (bg, icon) = _style(type);
    // Root-scope messenger: renders above sheets, dialogs and route transitions
    // (a nearest-ScaffoldMessenger would be BELOW them).
    final messenger = scaffoldMessengerKey.currentState ?? ScaffoldMessenger.of(context);
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
      content: _content(icon, message),
    ));
  }

  static void _showTop(OverlayState overlay, String message, AppToastType type, Duration duration) {
    _topEntry?.remove();
    final (bg, icon) = _style(type);
    late final OverlayEntry entry;
    entry = OverlayEntry(builder: (ctx) {
      return Positioned(
        top: MediaQuery.of(ctx).padding.top + 10,
        left: 14,
        right: 14,
        child: GestureDetector(
          onTap: () {
            if (entry.mounted) entry.remove();
            if (identical(_topEntry, entry)) _topEntry = null;
          },
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20), boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 12, offset: const Offset(0, 4)),
              ]),
              child: _content(icon, message),
            ),
          ),
        ),
      );
    });
    _topEntry = entry;
    overlay.insert(entry);
    Future<void>.delayed(duration, () {
      if (!entry.mounted) return;
      entry.remove();
      if (identical(_topEntry, entry)) _topEntry = null;
    });
  }
}
