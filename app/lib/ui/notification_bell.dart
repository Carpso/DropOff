import 'package:flutter/material.dart';

import '../data/notification_inbox.dart';
import '../screens/notifications_screen.dart';
import 'app_theme.dart';

/// The bell every role can use — riders, senders, recipients, partners and
/// staff. Shows the unread count and opens the in-app notification centre,
/// which holds every push and local alert for the signed-in user.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: NotificationInbox.unread,
      builder: (context, count, _) => IconButton(
        tooltip: count > 0 ? 'Notifications ($count unread)' : 'Notifications',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
        ),
        icon: Badge(
          isLabelVisible: count > 0,
          label: Text(count > 99 ? '99+' : '$count'),
          backgroundColor: AppColors.amber,
          textColor: AppColors.ink,
          child: Icon(Icons.notifications_outlined, color: color),
        ),
      ),
    );
  }
}
