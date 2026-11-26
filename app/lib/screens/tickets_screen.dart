import 'dart:async';

import 'package:flutter/material.dart';

import '../data/dropoff_api.dart';
import '../ui/app_sheet.dart';
import '../ui/app_theme.dart';
import '../ui/app_toast.dart';
import '../ui/app_spinner.dart';
import '../widgets/common.dart';

/// Plain-language errors: no raw codes or provider details in a support chat.
String _ticketError(String code, String fallback) => switch (code) {
      'message_too_short' => 'Write a little more so support can understand.',
      'subject_and_description_required' => 'Add a subject and a short description.',
      'ticket_closed' => 'This ticket is closed — reopen it to reply.',
      'too_many_requests' => 'Too many messages at once — wait a moment and try again.',
      'network_error' => "Can't reach DropOff right now — your message was not sent.",
      _ => fallback,
    };

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
                  ? StateMessage(icon: Icons.cloud_off_outlined, title: 'Could not load tickets', message: _error!, actionLabel: 'Try again', onAction: _load)
                  : _tickets.isEmpty
                      ? StateMessage(icon: Icons.support_agent, title: 'No tickets yet', message: 'Need help with a delivery or payment? Tap New ticket.', actionLabel: 'New ticket', onAction: () => _openNewTicket())
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
    if (!res.ok) {
      return AppToast.error(context,
        _ticketError(res.error ?? '', 'Could not open the ticket. Please try again.'));
    }
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
          TextField(controller: _subject, maxLength: 90, textCapitalization: TextCapitalization.sentences,
            enabled: !_saving,
            decoration: const InputDecoration(labelText: 'Subject', hintText: 'e.g. Item not delivered', counterText: '')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Category', prefixIcon: Icon(Icons.category_outlined)),
            items: [for (final c in widget.categories) DropdownMenuItem(value: c, child: Text(c[0].toUpperCase() + c.substring(1)))],
            onChanged: (v) => setState(() => _category = v ?? 'other'),
          ),
          const SizedBox(height: 12),
          TextField(controller: _body, maxLines: 5, maxLength: 2000, enabled: !_saving,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'What happened?', hintText: 'Include the booking reference if you have it.', alignLabelWithHint: true)),
          const SizedBox(height: 6),
          const Text('Support replies in this ticket. Only you and the DropOff team can read it.',
              style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
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
  final _scroll = ScrollController();
  Timer? _poll;
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    // A support thread is a live conversation: pick up staff replies without
    // making the customer leave or pull manually.
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _scroll.dispose();
    _reply.dispose();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _loading = true);
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
        _error = data == null ? 'Could not load this conversation.' : null;
      });
      _scrollToLatest();
    } catch (e) {
      if (!mounted || quiet) return;
      setState(() {
        _loading = false;
        _ticket = null;
        _messages = const [];
        _error = 'Could not open this ticket — please try again.';
      });
    }
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    final body = _reply.text.trim();
    if (body.length < 3) return AppToast.error(context, 'Write a little more before sending.');
    setState(() => _sending = true);
    final res = await DropOffApi.ticketReply(widget.id, body);
    if (!mounted) return;
    setState(() => _sending = false);
    if (!res.ok) {
      return AppToast.error(context,
          _ticketError(res.error ?? '', 'Could not send your message. Please try again.'));
    }
    _reply.clear();
    _load();
  }

  Future<void> _setStatus(String status) async {
    final go = await showConfirmSheet(
      context,
      title: status == 'closed' ? 'Close this ticket?' : 'Reopen this ticket?',
      message: status == 'closed'
          ? 'You can still reply later by reopening it.'
          : 'Support will be able to reply here again.',
      confirmLabel: status == 'closed' ? 'Close ticket' : 'Reopen ticket',
      icon: status == 'closed' ? Icons.check_circle_outline : Icons.restore,
    );
    if (go != true) return;
    final res = await DropOffApi.ticketStatus(widget.id, status);
    if (!mounted) return;
    if (!res.ok) {
      return AppToast.error(context,
          _ticketError(res.error ?? '', 'Could not update the ticket. Please try again.'));
    }
    AppToast.show(context, status == 'closed' ? 'Ticket closed.' : 'Ticket reopened.');
    _load();
  }

  static String _timeOf(Object? raw) {
    final s = '${raw ?? ''}';
    if (s.isEmpty) return '';
    final dt = DateTime.tryParse(s.replaceFirst(' ', 'T'));
    if (dt == null) return '';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
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
              // Long identifiers must own their width: a bare Text in a Row
              // collapses to one character per line on narrow phones.
              Expanded(child: Text('Ticket #${ticket['id'] ?? widget.id} · ${ticket['category'] ?? 'other'}',
                  maxLines: 2, softWrap: true, style: AppType.caption)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (status == 'closed' ? AppColors.muted : AppColors.success).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(status.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: AppType.bodyStrong.copyWith(
                      fontSize: 9.5, letterSpacing: 0.6,
                      color: status == 'closed' ? AppColors.muted : AppColors.success)),
              ),
            ]),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
            child: Row(children: [
              Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12.5))),
              TextButton(onPressed: () => _load(), child: const Text('Retry')),
            ]),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _load(quiet: true),
            child: _loading
                ? const Center(child: AppLogoSpinner(size: 26))
                : _messages.isEmpty
                    ? const Center(child: Text('No messages yet.', style: AppType.body))
                    : ListView.separated(
                        controller: _scroll,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        itemCount: _messages.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final m = _messages[i];
                          final fromOps = '${m['sender_role']}' == 'ops';
                          return Row(
                            mainAxisAlignment: fromOps ? MainAxisAlignment.start : MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Container(
                                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.80),
                                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                                decoration: BoxDecoration(
                                  color: fromOps ? Colors.white : AppColors.forest,
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(14), topRight: const Radius.circular(14),
                                    bottomLeft: Radius.circular(fromOps ? 3 : 14), bottomRight: Radius.circular(fromOps ? 14 : 3),
                                  ),
                                  border: fromOps ? Border.all(color: AppColors.line) : null,
                                  boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 6, offset: Offset(0, 2))],
                                ),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  if (fromOps) const Padding(padding: EdgeInsets.only(bottom: 4), child: Text('DropOff support', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.forestLight))),
                                  SelectableText('${m['body'] ?? ''}',
                                      style: TextStyle(fontSize: 13, height: 1.4, color: fromOps ? AppColors.ink : Colors.white)),
                                  const SizedBox(height: 4),
                                  Text(_timeOf(m['created_at']),
                                      style: TextStyle(fontSize: 9.5, color: fromOps ? AppColors.muted : Colors.white70)),
                                ]),
                              ),
                            ],
                          );
                        },
                      ),
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
