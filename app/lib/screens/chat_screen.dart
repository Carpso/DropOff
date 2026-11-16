import '../ui/app_toast.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../data/dropoff_api.dart';
import '../ui/app_theme.dart';
import '../main.dart';
import 'track_screen.dart';

/// One chat, three doors:
///  - job thread   (seller, rider, depot partner, ops — via job ref)
///  - token thread (signed-in recipient addressed to the parcel — via the SMS tracking token)
///  - support      (anyone signed in <-> ops)
/// Realtime via a per-thread Durable Object WebSocket; the 4 s poll stays as a
/// safety net until the socket is confirmed open (then relaxes to 15 s), and
/// REST send remains the fallback if the socket drops.
class ChatScreen extends StatefulWidget {
  const ChatScreen.job(this.jobRef, {super.key})
      : token = null,
        prefill = null,
        support = false;
  const ChatScreen.token(this.token, {super.key})
      : jobRef = null,
        prefill = null,
        support = false;
  const ChatScreen.supportThread({super.key, this.prefill})
      : jobRef = null,
        token = null,
        support = true;

  /// Optional message prefilled into the input (used by "request booking
  /// deletion" — the customer taps it, the message is typed, they hit send).
  final String? prefill;
  final String? jobRef;
  final String? token;
  final bool support;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _messages = const [];
  String? _myRole;
  int? _threadId;
  String? _closedAt;
  bool _joinRequired = false;
  bool _joinBusy = false;
  bool _loading = true;
  bool _needsVerify = false;
  bool _sending = false;
  Timer? _poll;
  WebSocketChannel? _ws;
  bool _wsOpen = false;
  int _wsBackoff = 0; // seconds; doubles on each failure, capped at 60
  Timer? _reconnect;
  /// Phones this viewer has blocked that sent messages in this thread —
  /// the server already hides their messages; we show an unblock banner.
  List<String> _blockedSenders = const [];

  @override
  void initState() {
    super.initState();
    if (widget.prefill != null && widget.prefill!.isNotEmpty) {
      _input.text = widget.prefill!;
    }
    _refresh();
    _schedulePoll();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _reconnect?.cancel();
    _ws?.sink.close();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Safety-net refresh: 4 s while the socket isn't confirmed, 15 s after.
  void _schedulePoll() {
    _poll?.cancel();
    _poll = Timer(Duration(seconds: _wsOpen ? 15 : 4), () async {
      await _refresh();
      if (mounted) _schedulePoll();
    });
  }

  bool get _isRecipient => widget.token != null;

  Uri _wsUri(int threadId) {
    final base = Uri.parse(DropOffApi.baseUrl);
    final query = _isRecipient ? {'tracking_token': widget.token!} : null;
    return Uri(scheme: 'wss', host: base.host, path: '/ws/chat/$threadId', queryParameters: query);
  }

  Map<String, String> get _wsHeaders {
    final base = _isRecipient
        ? <String, String>{}
        : (DropOffApi.apiKey.isNotEmpty
            ? {'X-Api-Key': DropOffApi.apiKey}
            : {'Authorization': 'Bearer ${DropOffApi.token ?? ''}'});
    final d = DropOffApi.deviceId;
    if (d.isNotEmpty) base['X-Device-Id'] = d;
    return base;
  }

  void _connectWs(int threadId) {
    if (_ws != null) return;
    try {
      final channel = IOWebSocketChannel.connect(_wsUri(threadId), headers: _wsHeaders);
      _ws = channel;
      channel.stream.listen(
        (data) {
          _wsBackoff = 0; // healthy again
          try {
            final msg = jsonDecode(data as String) as Map<String, dynamic>;
            if (msg['type'] == 'message') _append(Map<String, dynamic>.from(msg));
            if (msg['type'] == 'error') _showModerationError(msg['error'] as String?, '${msg['until'] ?? ''}');
          } catch (_) {}
        },
        onDone: () => _onWsDown(),
        onError: (_) => _onWsDown(),
        cancelOnError: true,
      );
      // Treat the socket as live; if auth fails the server closes it and the
      // exponential backoff reconnect keeps trying without hammering.
      _wsOpen = true;
    } catch (_) {
      _ws = null;
      _onWsDown();
    }
  }

  void _onWsDown() {
    _wsOpen = false;
    _ws = null;
    if (!mounted || _threadId == null) return;
    _reconnect?.cancel();
    _reconnect = Timer(Duration(seconds: _wsBackoff == 0 ? 2 : _wsBackoff), () {
      if (!mounted || _threadId == null) return;
      _wsBackoff = _wsBackoff == 0 ? 4 : (_wsBackoff * 2).clamp(4, 60);
      _connectWs(_threadId!);
    });
  }

  void _append(Map<String, dynamic> m) {
    final id = (m['id'] as num?)?.toInt();
    if (_messages.any((e) => (e['id'] as num?)?.toInt() == id)) return;
    setState(() => _messages = [..._messages, m]);
    _scrollToEnd();
  }

  Future<void> _scrollToEnd() async {
    await Future<void>.delayed(const Duration(milliseconds: 30));
    if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  Future<void> _refresh() async {
    try {
      // Linked partner (courier depot): the thread 404s until they opt in —
      // probe the door predicate first and render the Join button.
      final store = AppScope.of(context);
      if (!widget.support && widget.jobRef != null && store.role == 'partner') {
        final js = await DropOffApi.jobChatJoinStatus(widget.jobRef!);
        final state = js?['state'] as String?;
        if (state == 'join_required') {
          if (!mounted) return;
          setState(() {
            _loading = false;
            _joinRequired = true;
          });
          _poll?.cancel();
          return;
        }
        if (state == 'joined' && _joinRequired && mounted) {
          setState(() => _joinRequired = false);
        }
      }
      final Map<String, dynamic>? data;
      if (widget.support) {
        data = await DropOffApi.supportChat();
      } else if (widget.jobRef != null) {
        data = await DropOffApi.jobChat(widget.jobRef!);
      } else {
        data = await DropOffApi.trackChat(widget.token!);
      }
      if (!mounted) return;
      if (data == null && !_isRecipient) return;
      if (data == null) {
        // Token chat without a signed-in account (401): the account gate in
        // TrackScreen handles it — route there.
        setState(() { _loading = false; _needsVerify = true; });
        _poll?.cancel();
        return;
      }
      final Map<String, dynamic> live = data; // null already excluded above
      final incoming = ((live['messages'] as List?) ?? const []).cast<Map<String, dynamic>>();
      setState(() {
        _messages = incoming;
        _myRole = live['role'] as String?;
        _threadId = (live['thread_id'] as num?)?.toInt();
        _closedAt = live['closed_at'] as String?;
        _blockedSenders = ((live['blocked_senders'] as List?) ?? const [])
            .map((p) => '$p')
            .where((p) => p.isNotEmpty)
            .toList();
        _loading = false;
      });
      _scrollToEnd();
      final tid = _threadId;
      if (tid != null) _connectWs(tid);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    if (_closedAt != null) return;
    final body = _input.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    _input.clear();

    final viaSocket = _ws != null && _wsOpen;
    if (viaSocket) {
      _ws!.sink.add(jsonEncode({'type': 'send', 'body': body}));
    } else {
      ApiResponse res;
      if (widget.support) {
        res = await DropOffApi.supportChatSend(body);
      } else if (widget.jobRef != null) {
        res = await DropOffApi.sendJobChat(widget.jobRef!, body);
      } else {
        res = await DropOffApi.sendTrackChat(widget.token!, body);
      }
      if (!mounted) return;
      if (!res.ok) {
        _showModerationError(res.error, '${res.body['until'] ?? ''}');
      }
    }
    if (!mounted) return;
    setState(() => _sending = false);
    await _refresh();
  }

  String _roleLabel(Object? role) => switch ('$role') {
        'seller' => 'Seller',
        'recipient' => 'Recipient',
        'rider' => 'Rider',
        'courier' => 'Courier',
        'ops' => 'DropOff',
        'admin' => 'DropOff',
        'cfo' => 'Finance',
        _ => 'User',
      };

  /// Report/block actions need a real account (JWT) — ops-key and token-only
  /// sessions can't prove their identity to the moderation endpoints.
  bool get _canModerate => DropOffApi.token != null;

  void _showModerationError(String? error, String until) {
    if (!mounted) return;
    if (error == 'chat_closed') {
      setState(() => _closedAt = until.isNotEmpty ? until : DateTime.now().toIso8601String());
      AppToast.show(context, 'This conversation is archived — history is read-only.');
      return;
    }
    final text = switch (error) {
      'message_blocked' => 'Keep messages respectful.',
      'chat_suspended' => until.isNotEmpty
          ? 'Messaging paused by moderation until ${until.split(' ').first}.'
          : 'Messaging is paused by moderation.',
      'too_many_requests' => 'Sending too fast — wait a moment.',
      _ => 'Message not sent — check your connection.',
    };
    AppToast.show(context, text);
  }

  String _maskPhone(String phone) =>
      phone.length >= 4 ? '••• ${phone.substring(phone.length - 4)}' : phone;

  /// Partner opts in to the delivery chat (linked courier required server-side).
  Future<void> _join() async {
    if (widget.jobRef == null || _joinBusy) return;
    setState(() => _joinBusy = true);
    final res = await DropOffApi.jobChatJoin(widget.jobRef!);
    if (!mounted) return;
    setState(() => _joinBusy = false);
    if (res.ok) {
      setState(() => _joinRequired = false);
      _refresh();
    } else {
      AppToast.show(context, res.error == 'not found'
          ? 'This chat is not for your depot.'
          : 'Could not join (${res.error ?? 'network'}) — try again.');
    }
  }

  Future<void> _close() async {
    if (_threadId == null) return;
    final threadId = _threadId!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Close this chat?'),
        content: const Text('The conversation will become read-only for everyone. All history — every message, every photo, every system note — stays available to you and the other participants.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Close & archive')),
        ],
      ),
    );
    if (ok != true) return;
    final res = await DropOffApi.closeChatThread(threadId);
    if (!mounted) return;
    if (!res.ok) {
      AppToast.show(context, 'Could not close (${res.error ?? 'try again'})');
      return;
    }
    AppToast.show(context, 'Chat closed & archived — you can still read history.');
    setState(() => _closedAt = DateTime.now().toUtc().toIso8601String());
    await _refresh();
  }

  Future<void> _openMessageActions(Map<String, dynamic> m) async {
    if (!_canModerate) return;
    final phone = '${m['sender_phone'] ?? ''}';
    final id = (m['id'] as num?)?.toInt() ?? 0;
    // System messages (ops) can't be reported or blocked.
    if (id <= 0 || phone.isEmpty || phone == 'ops') return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.flag_outlined, color: Colors.redAccent),
            title: const Text('Report message', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: const Text('Goes to DropOff moderation — kept private.', style: TextStyle(fontSize: 11.5)),
            onTap: () => Navigator.pop(ctx, 'report'),
          ),
          ListTile(
            leading: const Icon(Icons.person_off_outlined, color: Colors.redAccent),
            title: Text('Block ${_roleLabel(m['sender_role'])} (${_maskPhone(phone)})',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: const Text('Hide all their messages in this chat, for you only.',
                style: TextStyle(fontSize: 11.5)),
            onTap: () => Navigator.pop(ctx, 'block'),
          ),
        ]),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'report') {
      await _reportMessage(id);
    } else if (action == 'block') {
      await _confirmBlock(phone, _roleLabel(m['sender_role']));
    }
  }

  Future<void> _reportMessage(int id) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(alignment: Alignment.centerLeft,
                child: Text('Why are you reporting this message?',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900))),
          ),
          ListTile(title: const Text('Harassment or abuse'), onTap: () => Navigator.pop(ctx, 'harassment')),
          ListTile(title: const Text('Spam or scam'), onTap: () => Navigator.pop(ctx, 'spam')),
          ListTile(title: const Text('Other'), onTap: () => Navigator.pop(ctx, 'other')),
        ]),
      ),
    );
    if (reason == null) return;
    final res = await DropOffApi.reportChatMessage(id, reason);
    if (!mounted) return;
    final already = res.body['already_reported'] == true;
    AppToast.show(context, res.ok ? (already ? 'Already reported — DropOff has it.' : 'Thanks — reported to DropOff.')
             : 'Could not report right now. Try again later.',);
  }

  Future<void> _confirmBlock(String phone, String label) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Block $label ($_maskPhone(phone))?'),
        content: const Text(
            'Their messages will disappear from this chat for you. You can unblock any time. '
            'Delivery coordination for open parcels is unaffected for everyone else.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Block')),
        ],
      ),
    );
    if (yes != true) return;
    final res = await DropOffApi.blockUser(phone);
    if (!mounted) return;
    AppToast.show(context, res.ok ? 'User blocked in your chats.' : 'Could not block right now (${res.error}).',);
    if (res.ok) {
      setState(() => _blockedSenders = [..._blockedSenders, phone]);
      await _refresh();
    }
  }

  Future<void> _unblock(String phone) async {
    final res = await DropOffApi.unblockUser(phone);
    if (!mounted) return;
    if (res.ok) {
      setState(() => _blockedSenders = _blockedSenders.where((p) => p != phone).toList());
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.support
        ? 'DropOff support'
        : widget.jobRef != null
            ? 'Chat — ${widget.jobRef}'
            : 'Parcel chat';
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          if (widget.jobRef != null && !widget.support && _closedAt == null && (_myRole == 'seller' || _myRole == 'recipient' || _myRole == 'rider' || _myRole == 'partner'))
            IconButton(
              tooltip: 'Close this chat (archive for everyone)',
              icon: const Icon(Icons.lock_outline),
              onPressed: _threadId == null ? null : () => _close(),
            ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: _joinRequired
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.apartment_outlined, size: 48, color: AppColors.forest),
                      const SizedBox(height: 16),
                      const Text('Join this delivery\u2019s chat', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900), textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      const Text('Your depot is linked to this courier. Join to follow the parcel with the sender, recipient and rider — every message, every milestone. You can leave or close it any time; history stays available either way.',
                          textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, height: 1.5)),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _joinBusy ? null : _join,
                        icon: _joinBusy
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.forum_outlined),
                        label: Text(_joinBusy ? 'Joining…' : 'Join chat'),
                      ),
                    ]),
                  ),
                )
              : _needsVerify
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.lock_outline, size: 48, color: AppColors.muted),
                      const SizedBox(height: 16),
                      const Text('An account is needed', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900), textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      const Text('Only the parcel’s sender or recipient — signed in to DropOff with the phone it was addressed to — can open this chat.',
                          textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, height: 1.5)),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
                          builder: (_) => TrackScreen(initialToken: widget.token),
                        )),
                        icon: const Icon(Icons.person),
                        label: const Text('Go to tracking'),
                      ),
                    ]),
                  ),
                )
              : _loading
              ? const Center(child: CircularProgressIndicator())
              : _messages.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('No messages yet.\nSay hello — everyone on this delivery sees this chat.',
                            textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, height: 1.5)),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      itemCount: _messages.length,
                      itemBuilder: (context, i) => _bubble(_messages[i]),
                    ),
        ),
        SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Block notice: server already hides this person's messages for you.
            for (final phone in _blockedSenders)
              Material(
                color: Colors.amber.shade50,
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.person_off_outlined, color: Colors.black87),
                  title: Text('Messages from ${_maskPhone(phone)} are hidden',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                  trailing: TextButton(
                    onPressed: () => _unblock(phone),
                    child: const Text('Unblock', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
            if (_closedAt != null && !_joinRequired)
              // Read-only archive ribbon — everyone can still scroll history.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                color: AppColors.forest.withValues(alpha: 0.08),
                child: Row(children: const [
                  Icon(Icons.lock_outline, size: 16, color: AppColors.forest),
                  SizedBox(width: 8),
                  Expanded(child: Text('This conversation is archived — history stays available to everyone.',
                      style: TextStyle(color: AppColors.forest, fontWeight: FontWeight.w700, fontSize: 11.5))),
                ]),
              ),
            if (!_joinRequired)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
              child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  enabled: _closedAt == null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  maxLength: 500,
                  decoration: InputDecoration(
                    hintText: _closedAt == null ? 'Message…' : 'Archived — read only',
                    counterText: '',
                    prefixIcon: Icon(
                      Icons.chat_bubble_outline,
                      color: _closedAt != null ? AppColors.muted : (_wsOpen ? AppColors.forest : AppColors.muted),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filled(
                onPressed: _closedAt == null && !_sending ? _send : null,
                icon: _sending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(_closedAt == null ? Icons.send_rounded : Icons.lock_outline),
              ),
            ]),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _bubble(Map<String, dynamic> m) {
    final alignRight = _myRole != null && m['sender_role'] == _myRole;
    final time = '${m['created_at'] ?? ''}'.split(' ').last;
    final avatar = _ChatAvatar(photoUrl: m['sender_photo_url'] as String?, label: _roleLabel(m['sender_role']));
    final bubble = Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        decoration: BoxDecoration(
          color: alignRight ? AppColors.forest : Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: alignRight ? null : Border.all(color: AppColors.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            _roleLabel(m['sender_role']),
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5, color: alignRight ? AppColors.amber : AppColors.forest),
          ),
          const SizedBox(height: 3),
          Text('${m['body'] ?? ''}', style: TextStyle(fontSize: 13.5, height: 1.35, color: alignRight ? Colors.white : AppColors.ink)),
          const SizedBox(height: 3),
          Text(time, style: TextStyle(fontSize: 9.5, color: alignRight ? Colors.white70 : AppColors.muted)),
        ]),
    );
    return Align(
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        // UGC safety: long-press someone else's message → report / block.
        onLongPress: alignRight ? null : () => _openMessageActions(m),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: alignRight ? [bubble, const SizedBox(width: 7), avatar] : [avatar, const SizedBox(width: 7), bubble],
        ),
      ),
    );
  }
}

/// Sender avatar in the chat bubble (the account photo, or initials).
class _ChatAvatar extends StatelessWidget {
  const _ChatAvatar({this.photoUrl, required this.label});

  final String? photoUrl;
  final String label;

  String get _initials => label
      .trim()
      .split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty)
      .take(2)
      .map((s) => s[0].toUpperCase())
      .join();

  @override
  Widget build(BuildContext context) {
    const radius = 15.0;
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.line.withValues(alpha: 0.55),
      child: photoUrl == null || photoUrl!.isEmpty
          ? Text(_initials.isEmpty ? '?' : _initials,
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: AppColors.forest))
          : ClipOval(
              child: Image.network(
                '${DropOffApi.baseUrl}$photoUrl',
                headers: DropOffApi.authHeaders,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Text(_initials.isEmpty ? '?' : _initials,
                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: AppColors.forest)),
              ),
            ),
    );
  }
}
