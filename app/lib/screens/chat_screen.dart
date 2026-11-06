import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../data/dropoff_api.dart';
import '../ui/app_theme.dart';
import 'track_screen.dart';

/// One chat, three doors:
///  - job thread   (seller, rider, depot partner, ops — via job ref)
///  - token thread (recipient — via the SMS tracking token, no account)
///  - support      (anyone signed in <-> ops)
/// Realtime via a per-thread Durable Object WebSocket; the 4 s poll stays as a
/// safety net until the socket is confirmed open (then relaxes to 15 s), and
/// REST send remains the fallback if the socket drops.
class ChatScreen extends StatefulWidget {
  const ChatScreen.job(this.jobRef, {super.key})
      : token = null,
        support = false;
  const ChatScreen.token(this.token, {super.key})
      : jobRef = null,
        support = false;
  const ChatScreen.supportThread({super.key})
      : jobRef = null,
        token = null,
        support = true;

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
  bool _loading = true;
  bool _needsVerify = false;
  bool _sending = false;
  Timer? _poll;
  WebSocketChannel? _ws;
  bool _wsOpen = false;
  int _wsBackoff = 0; // seconds; doubles on each failure, capped at 60
  Timer? _reconnect;

  @override
  void initState() {
    super.initState();
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

  Map<String, String> get _wsHeaders => _isRecipient
      ? {}
      : DropOffApi.apiKey.isNotEmpty
          ? {'X-Api-Key': DropOffApi.apiKey}
          : {'Authorization': 'Bearer ${DropOffApi.token ?? ''}'};

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
        // Token chat without a phone-verification grant (fresh app run): the
        // TrackScreen verify flow mints the X-Track-Grant — route the user there.
        setState(() { _loading = false; _needsVerify = true; });
        _poll?.cancel();
        return;
      }
      final incoming = ((data['messages'] as List?) ?? const []).cast<Map<String, dynamic>>();
      setState(() {
        _messages = incoming;
        _myRole = data!['role'] as String?;
        _threadId = (data['thread_id'] as num?)?.toInt();
        _loading = false;
      });
      _scrollToEnd();
      if (_threadId != null) _connectWs(_threadId!);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
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
        await DropOffApi.supportChat(body: body);
        res = const ApiResponse(ok: true);
      } else if (widget.jobRef != null) {
        res = await DropOffApi.sendJobChat(widget.jobRef!, body);
      } else {
        res = await DropOffApi.sendTrackChat(widget.token!, body);
      }
      if (!mounted) return;
      if (!res.ok) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.error == 'message_blocked'
            ? 'Keep messages respectful.'
            : 'Message not sent — check your connection.')));
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
        _ => 'User',
      };

  @override
  Widget build(BuildContext context) {
    final title = widget.support
        ? 'DropOff support'
        : widget.jobRef != null
            ? 'Chat — ${widget.jobRef}'
            : 'Parcel chat';
    return Scaffold(
      appBar: AppBar(title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900))),
      body: Column(children: [
        Expanded(
          child: _needsVerify
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.phonelink_lock, size: 44, color: AppColors.muted),
                      const SizedBox(height: 16),
                      const Text('Verify your number first', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900), textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      const Text('Only the parcel\u2019s sender or recipient can open this chat. Verify the phone it was addressed to, then come back.',
                          textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, height: 1.5)),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
                          builder: (_) => TrackScreen(initialToken: widget.token),
                        )),
                        icon: const Icon(Icons.verified_user),
                        label: const Text('Verify & track'),
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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  maxLength: 500,
                  decoration: InputDecoration(
                    hintText: 'Message…',
                    counterText: '',
                    prefixIcon: Icon(
                      Icons.chat_bubble_outline,
                      color: _wsOpen ? AppColors.forest : AppColors.muted,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filled(
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_rounded),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _bubble(Map<String, dynamic> m) {
    final alignRight = _myRole != null && m['sender_role'] == _myRole;
    final time = '${m['created_at'] ?? ''}'.split(' ').last;
    return Align(
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
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
      ),
    );
  }
}
