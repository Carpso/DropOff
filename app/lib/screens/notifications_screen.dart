import 'package:flutter/material.dart';

import '../data/notification_inbox.dart';
import '../ui/app_theme.dart';

/// Bell-icon notification center (owner 2026-11-25).
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    NotificationInbox.markAllRead();
  }

  String _time(String? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    final now = DateTime.now();
    if (d.day == now.day && d.month == now.month && d.year == now.year) {
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    return '${d.day} ${_months[d.month - 1]} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  IconData _icon(String kind) {
    if (kind.contains('sos')) return Icons.sos_rounded;
    if (kind.contains('assign') || kind.contains('new_order')) return Icons.delivery_dining_rounded;
    if (kind.contains('payment') || kind.contains('deposit') || kind.contains('plan')) return Icons.payments_rounded;
    if (kind.contains('chat') || kind.contains('support')) return Icons.chat_bubble_rounded;
    if (kind.contains('counter_fare')) return Icons.receipt_long_rounded;
    return Icons.notifications_rounded;
  }

  Color _color(String kind) {
    if (kind.contains('sos')) return AppColors.danger;
    if (kind.contains('assign') || kind.contains('new_order')) return AppColors.forest;
    if (kind.contains('payment')) return AppColors.amber;
    return AppColors.muted;
  }

  @override
  Widget build(BuildContext context) {
    final items = NotificationInbox.items;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          if (items.isNotEmpty)
            IconButton(
              tooltip: 'Clear all',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () async {
                await NotificationInbox.clear();
                if (mounted) setState(() {});
              },
            ),
        ],
      ),
      body: items.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.notifications_none_rounded, size: 56, color: AppColors.muted),
                  SizedBox(height: 12),
                  Text('No notifications yet', style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700)),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) {
                final n = items[i];
                final kind = '${n['kind'] ?? ''}'.toLowerCase();
                final title = (n['title'] ?? 'DropOff').toString();
                final body = (n['body'] ?? '').toString();
                final read = n['read'] == true;
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: read ? Colors.white : AppColors.canvas,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: read ? AppColors.line : AppColors.forest.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: _color(kind).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(_icon(kind), color: _color(kind), size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: TextStyle(fontWeight: read ? FontWeight.w700 : FontWeight.w900, fontSize: 13.5)),
                            if (body.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(body, style: const TextStyle(fontSize: 12.5, height: 1.35, color: Color(0xFF3A4A42))),
                            ],
                            const SizedBox(height: 4),
                            Text(_time(n['received_at']?.toString()), style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
