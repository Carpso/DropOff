import 'package:flutter/material.dart';

import '../data/dropoff_api.dart';
import '../ui/app_theme.dart';
import 'chat_screen.dart';

/// All my conversations (job threads + support), with unread badges.
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  List<Map<String, dynamic>> _threads = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await DropOffApi.chatThreads();
    if (!mounted) return;
    setState(() {
      _threads = ((data?['threads'] as List?) ?? const []).cast<Map<String, dynamic>>();
      _loading = false;
    });
  }

  void _open(Map<String, dynamic> t) async {
    if (t['kind'] == 'support') {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ChatScreen.supportThread()));
    } else if (t['job_ref'] != null) {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChatScreen.job('${t['job_ref']}')));
    }
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final totalUnread = _threads.fold<int>(0, (sum, t) => sum + ((t['unread'] as num?)?.toInt() ?? 0));
    return Scaffold(
      appBar: AppBar(title: Text(totalUnread > 0 ? 'Inbox ($totalUnread unread)' : 'Inbox', style: const TextStyle(fontWeight: FontWeight.w900))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _threads.isEmpty
              ? const Center(child: Text('No conversations yet.\nOpen a booking and tap Chat.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                    itemCount: _threads.length,
                    itemBuilder: (context, i) => _row(_threads[i]),
                  ),
                ),
    );
  }

  Widget _row(Map<String, dynamic> t) {
    final unread = (t['unread'] as num?)?.toInt() ?? 0;
    final title = t['kind'] == 'support' ? 'DropOff support' : '${t['job_ref'] ?? 'Parcel'} · ${t['dest_city'] ?? ''}';
    final lastAt = '${t['last_at'] ?? ''}'.split(' ').last;
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _open(t),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Icon(t['kind'] == 'support' ? Icons.support_agent : Icons.inventory_2_outlined, color: AppColors.forest),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              const SizedBox(height: 3),
              Text(
                '${t['last_message'] ?? 'No messages yet'}',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.ink, fontSize: 12.5, fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w400),
              ),
            ])),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(lastAt, style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
              const SizedBox(height: 4),
              if (unread > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.forest, borderRadius: BorderRadius.circular(12)),
                  child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
                ),
            ]),
          ]),
        ),
      ),
    );
  }
}
