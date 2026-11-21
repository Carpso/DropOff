import 'package:flutter/material.dart';

import '../data/dropoff_api.dart';
import '../ui/app_theme.dart';
import '../ui/app_toast.dart';
import '../ui/app_spinner.dart';

/// Customer-facing help desk. Parcel chat was removed — every conversation with
/// DropOff now starts here as a ticket with a subject, a category and a status.
/// The message thread underneath is the same signed-in support thread staff see
/// in the admin Support inbox.
class TicketsScreen extends StatefulWidget {
  /// Optional prefill for "report an issue with this booking" entry points.
  final String? prefill;

  const TicketsScreen({super.key, this.prefill});

  @override
  State<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends State<TicketsScreen> {
  List<Map<String, dynamic>> _tickets = const [];
  String _filter = 'all';
  bool _loading = true;
  String? _error;

  static const _categories = ['delivery', 'payment', 'booking', 'account', 'other'];

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.prefill != null && widget.prefill!.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openNewTicket(prefill: widget.prefill));
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await DropOffApi.tickets();
      if (!mounted) return;
      // Tolerate malformed/cached rows — a strict cast here used to crash the
      // whole screen with "type 'String' is not a subtype of Map".
      final rows = ((data?['tickets'] as List?) ?? const <dynamic>[])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      setState(() {
        _tickets = rows.where((t) => _filter == 'all' || '${t['status'] ?? 'open'}' == _filter).toList();
        _loading = false;
        _error = data == null ? 'Could not load tickets — check your connection.' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _tickets = const [];
        _error = 'Could not open tickets — ${e.toString().split('\n').first.substring(0, e.toString().split('\n').first.length.clamp(0, 160))}';
      });
    }
  }

  Future<void> _openNewTicket({String? prefill}) async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _NewTicketSheet(categories: _categories, prefill: prefill),
    );
    if (created == true) _load();
  }

  Future<void> _openTicket(int id) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
      builder: (_) => TicketDetailScreen(id: id),
    ));
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Support tickets')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openNewTicket(),
        icon: const Icon(Icons.add),
        label: const Text('New ticket'),
      ),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            'Private between you and the DropOff support team. Senders, recipients and riders never see each other\'s tickets.',
            style: AppType.body,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Wrap(spacing: 8, children: [
            for (final f in ['all', 'open', 'pending', 'closed'])
              ChoiceChip(
                label: Text(f == 'all' ? 'All' : f[0].toUpperCase() + f.substring(1)),
                selected: _filter == f,
                onSelected: (_) {
                  setState(() => _filter = f);
                  _load();
                },
              ),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: AppLogoSpinner(size: 26))
              : _error != null
                  ? Center(child: Padding(padding: const EdgeInsets.all(28), child: Text(_error!, textAlign: TextAlign.center, style: AppType.body)))
                  : _tickets.isEmpty
                      ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.support_agent, size: 52, color: AppColors.forestLight),
                          SizedBox(height: 12),
                          Text('No tickets yet', style: AppType.subhead),
                          SizedBox(height: 6),
                          Text('Need help with a delivery or payment? Tap New ticket.', style: AppType.body, textAlign: TextAlign.center),
                        ])))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(12, 6, 12, 90),
                            itemCount: _tickets.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, i) => _ticketCard(_tickets[i]),
                          ),
                        ),
        ),
      ]),
    );
  }

  Widget _ticketCard(Map<String, dynamic> t) {
    final id = '${t['id'] ?? ''}';
    final status = '${t['status'] ?? 'open'}';
    final unread = (t['unread'] is num ? t['unread'] as num : num.tryParse('${t['unread'] ?? 0}') ?? 0).toInt();
    final color = switch (status) {
      'closed' => AppColors.muted,
      'pending' => AppColors.warning,
      _ => AppColors.success,
    };
    return Card(
      child: ListTile(
        onTap: () => _openTicket(int.tryParse(id) ?? 0),
        leading: const CircleAvatar(
          backgroundColor: AppColors.forest,
          foregroundColor: Colors.white,
          child: Icon(Icons.confirmation_number_outlined, size: 20),
        ),
        title: Text('${t['subject'] ?? 'Ticket #$id'}', style: AppType.bodyStrong),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${t['last_message'] ?? 'No messages yet'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.body),
            const SizedBox(height: 4),
            Text('Ticket #$id · ${t['category'] ?? 'other'}', style: AppType.caption),
          ]),
        ),
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
            child: Text(status.toUpperCase(), style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: color)),
          ),
          if (unread > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: CircleAvatar(radius: 10, backgroundColor: AppColors.amber, child: Text('$unread', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.ink))),
            ),
        ]),
      ),
    );
  }
}

/// Create a ticket. Subject + category give staff something to route on, so
/// tickets are not just another anonymous chat thread.
class _NewTicketSheet extends StatefulWidget {
  final List<String> categories;
  final String? prefill;
  const _NewTicketSheet({required this.categories, this.prefill});

  @override
  State<_NewTicketSheet> createState() => _NewTicketSheetState();
}

class _NewTicketSheetState extends State<_NewTicketSheet> {
  final _subject = TextEditingController();
  final _body = TextEditingController();
  String _category = 'delivery';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.prefill != null) _body.text = widget.prefill!;
  }

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final subject = _subject.text.trim();
    final body = _body.text.trim();
    if (subject.length < 3) return AppToast.error(context, 'Add a short subject (at least 3 characters).');
    if (body.length < 3) return AppToast.error(context, 'Describe what you need help with.');
    setState(() => _saving = true);
    final res = await DropOffApi.createTicket(subject: subject, category: _category, body: body);
    if (!mounted) return;
    setState(() => _saving = false);
    if (!res.ok) return AppToast.error(context, 'Could not open the ticket (${res.error}). Try again.');
    Navigator.of(context).pop(true);
    AppToast.show(context, 'Ticket opened — we will reply here.');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Container(width: 42, height: 4, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(3))),
          const SizedBox(height: 16),
          const Text('New support ticket', style: AppType.title),
          const SizedBox(height: 14),
          TextField(controller: _subject, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Subject', hintText: 'e.g. Item not delivered')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Category', prefixIcon: Icon(Icons.category_outlined)),
            items: [for (final c in widget.categories) DropdownMenuItem(value: c, child: Text(c[0].toUpperCase() + c.substring(1)))],
            onChanged: (v) => setState(() => _category = v ?? 'other'),
          ),
          const SizedBox(height: 12),
          TextField(controller: _body, maxLines: 5, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'What happened?', hintText: 'Include the booking reference if you have it.', alignLabelWithHint: true)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving ? null : _submit,
            icon: _saving ? const AppLogoSpinner(size: 16) : const Icon(Icons.send),
            label: Text(_saving ? 'Opening ticket…' : 'Open ticket'),
          ),
        ]),
      ),
    );
  }
}

/// One ticket's conversation. Customers can reply and close/reopen; staff
/// replies arrive in the admin Support inbox of the same ticket.
class TicketDetailScreen extends StatefulWidget {
  final int id;
  const TicketDetailScreen({required this.id, super.key});

  @override
  State<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends State<TicketDetailScreen> {
  Map<String, dynamic>? _ticket;
  List<Map<String, dynamic>> _messages = const [];
  final _reply = TextEditingController();
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await DropOffApi.ticket(widget.id);
      if (!mounted) return;
      setState(() {
        _ticket = (data?['ticket'] as Map?)?.cast<String, dynamic>() ?? data;
        _messages = ((data?['messages'] as List?) ?? const <dynamic>[])
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _ticket = null;
        _messages = const [];
        _error = 'Could not open this ticket — ${e.toString().split('\n').first.substring(0, e.toString().split('\n').first.length.clamp(0, 160))}';
      });
    }
  }

  Future<void> _send() async {
    final body = _reply.text.trim();
    if (body.isEmpty) return;
    setState(() => _sending = true);
    final res = await DropOffApi.ticketReply(widget.id, body);
    if (!mounted) return;
    setState(() => _sending = false);
    if (!res.ok) return AppToast.error(context, 'Could not send (${res.error}).');
    _reply.clear();
    _load();
  }

  Future<void> _setStatus(String status) async {
    final res = await DropOffApi.ticketStatus(widget.id, status);
    if (!mounted) return;
    if (!res.ok) return AppToast.error(context, 'Could not update the ticket (${res.error}).');
    AppToast.show(context, status == 'closed' ? 'Ticket closed.' : 'Ticket reopened.');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final ticket = _ticket;
    final status = '${ticket?['status'] ?? 'open'}';
    return Scaffold(
      appBar: AppBar(
        title: Text(ticket?['subject'] ?? 'Ticket #${widget.id}'),
        actions: [
          if (status == 'closed')
            IconButton(tooltip: 'Reopen ticket', icon: const Icon(Icons.restore), onPressed: () => _setStatus('open'))
          else
            IconButton(tooltip: 'Close ticket', icon: const Icon(Icons.check_circle_outline), onPressed: () => _setStatus('closed')),
        ],
      ),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (ticket != null)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            color: AppColors.canvas,
            child: Row(children: [
              Text('Ticket #${ticket['id'] ?? widget.id} · ${ticket['category'] ?? 'other'}', style: AppType.caption),
              const Spacer(),
              Text(status.toUpperCase(), style: AppType.bodyStrong.copyWith(color: status == 'closed' ? AppColors.muted : AppColors.success)),
            ]),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
          ),
        Expanded(
          child: _loading
              ? const Center(child: AppLogoSpinner(size: 26))
              : _messages.isEmpty
                  ? const Center(child: Text('No messages yet.', style: AppType.body))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      itemCount: _messages.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final m = _messages[i];
                        final fromOps = '${m['sender_role']}' == 'ops';
                        return Row(
                          mainAxisAlignment: fromOps ? MainAxisAlignment.start : MainAxisAlignment.end,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                              decoration: BoxDecoration(
                                color: fromOps ? Colors.white : AppColors.forest,
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(14), topRight: const Radius.circular(14),
                                  bottomLeft: Radius.circular(fromOps ? 3 : 14), bottomRight: Radius.circular(fromOps ? 14 : 3),
                                ),
                                border: fromOps ? Border.all(color: AppColors.line) : null,
                              ),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                if (fromOps) const Padding(padding: EdgeInsets.only(bottom: 4), child: Text('DropOff support', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.forestLight))),
                                Text('${m['body'] ?? ''}', style: TextStyle(fontSize: 13, color: fromOps ? AppColors.ink : Colors.white)),
                              ]),
                            ),
                          ],
                        );
                      },
                    ),
        ),
        if (status != 'closed')
          Container(
            decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.line))),
            padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.of(context).viewInsets.bottom + 8),
            child: Row(children: [
              Expanded(child: TextField(controller: _reply, maxLines: 3, decoration: const InputDecoration(hintText: 'Reply to support…', border: InputBorder.none))),
              IconButton.filled(onPressed: _sending ? null : _send, icon: _sending ? const AppLogoSpinner(size: 18, color: Colors.white) : const Icon(Icons.send)),
            ]),
          ),
      ]),
    );
  }
}
