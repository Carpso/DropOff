import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/dropoff_api.dart';
import '../main.dart';
import '../ui/app_theme.dart';

/// The rider's day as slot-batched task queues:
///   BATCH: 10:00 AM SLOT · TOTAL PARCELS: 6 · DESTINATION: Mercury — Kabulonga
///   1. 10:05 · 14 Reedbuck Rd (Beauty Hub) — 2 parcels ...
/// plus the target branch drop-off time. Stop order is a nearest-neighbour
/// chain from the rider's last known position; ETAs assume 22 km/h + 4 min
/// per stop. Refresh pulls the latest assignments.
class RiderQueueScreen extends StatefulWidget {
  const RiderQueueScreen({super.key, this.phone});

  final String? phone;

  @override
  State<RiderQueueScreen> createState() => _RiderQueueScreenState();
}

class _RiderQueueScreenState extends State<RiderQueueScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _busyRef;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await DropOffApi.riderQueue(widget.phone);
    if (!mounted) return;
    setState(() { _data = data; _loading = false; });
  }

  /* ------------------------ stop advancement (proof kit) -------------------- */
  // Anti-false-parcel handover: door deliveries require the recipient's
  // 4-digit DropOff code (sent in their booking SMS), and any leg can carry a
  // proof photo filed to that job's evidence columns. Depot drops need no
  // code — the AI-checked depot photo already covers them.

  Future<String?> _pickPodPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera), title: const Text('Take photo with camera'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library), title: const Text('Pick from gallery'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
        ]),
      ),
    );
    if (source == null) return null;
    final picked = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 82);
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    final res = await DropOffApi.uploadImage(bytes, picked.name.isNotEmpty ? picked.name : 'proof.jpg', kind: 'kyc');
    if (!mounted) return null;
    if (!res.ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Proof photo upload failed (${res.error ?? 'network'}) — moving on without it.')));
      return null;
    }
    return '${res.body['url'] ?? ''}';
  }

  Future<void> _snack(String msg) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _advanceStop(Map<String, dynamic> s) async {
    final String ref = '${s['ref']}';
    if (_busyRef != null) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(padding: EdgeInsets.all(14), child: Text('How did the parcel move on?',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
          ListTile(
            leading: const Icon(Icons.local_shipping_outlined),
            title: const Text('Picked up from the seller'),
            subtitle: const Text('File it before leaving the stop'),
            trailing: _busyRef == ref ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : null,
            onTap: () async {
              final photo = await _pickPodPhoto();
              setState(() => _busyRef = ref);
              final res = await DropOffApi.jobEvent(
                jobRef: ref, status: 'picked_up', photoUrl: photo, stage: photo == null ? null : 'pickup');
              if (!mounted) return;
              setState(() => _busyRef = null);
              Navigator.pop(ctx);
              await _snack(res.ok ? '$ref — picked up ✓' : 'Could not update (${res.error})');
              if (res.ok) _load();
            },
          ),
          ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: const Text('Dropped at the depot branch'),
            subtitle: const Text('First-mile drop signed in'),
            onTap: () async {
              final photo = await _pickPodPhoto();
              setState(() => _busyRef = ref);
              final res = await DropOffApi.jobEvent(
                jobRef: ref, status: 'delivered', photoUrl: photo, stage: photo == null ? null : 'delivery');
              if (!mounted) return;
              setState(() => _busyRef = null);
              Navigator.pop(ctx);
              await _snack(res.ok ? '$ref — depot drop ✓' : 'Could not update (${res.error})');
              if (res.ok) _load();
            },
          ),
          ListTile(
            leading: const Icon(Icons.home_outlined),
            title: const Text('Handed to the recipient (door)'),
            subtitle: const Text('Requires their 4-digit DropOff code'),
            onTap: () => _deliverToDoor(ctx, ref),
          ),
        ]),
      ),
    );
  }

  /// Door delivery: the server enforces the recipient's 4-digit handover code.
  Future<void> _deliverToDoor(BuildContext sheetCtx, String ref) async {
    Navigator.pop(sheetCtx); // close the "how did it move on" sheet
    if (!mounted) return;
    final otpCtrl = TextEditingController();
    String? podUrl;
    final res = await showDialog<ApiResponse>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text('Handover — $ref', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Ask the recipient for the 4-digit DropOff code from their booking SMS. Never type a code the parcel-owner hasn\'t shown you.',
              style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.muted)),
            const SizedBox(height: 12),
            TextField(
              controller: otpCtrl,
              keyboardType: TextInputType.number,
              maxLength: 4,
              autofocus: true,
              decoration: const InputDecoration(
                counterText: '',
                labelText: '4-digit DropOff code',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: Icon(podUrl == null ? Icons.camera_alt_outlined : Icons.check_circle, size: 18),
              label: Text(podUrl == null ? 'Add proof photo (recommended)' : 'Proof photo attached ✓',
                style: const TextStyle(fontSize: 12.5)),
              onPressed: () async {
                setDialog(() => podUrl = null); // visual pending state
                final url = await _pickPodPhoto();
                setDialog(() => podUrl = url);
              },
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final code = otpCtrl.text.trim();
                if (code.length < 4) {
                  _snack('Enter the recipient\'s 4-digit code.');
                  return;
                }
                final r = await DropOffApi.jobEvent(
                  jobRef: ref, status: 'delivered', otp: code,
                  photoUrl: podUrl, stage: podUrl == null ? null : 'delivery');
                if (!ctx.mounted) return;
                Navigator.pop(ctx, r);
              },
              child: const Text('Confirm handover'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (res == null) return; // cancelled
    if (res.ok) {
      await _snack('$ref — delivered and code-verified ✓');
      _load();
      return;
    }
    // Server-side OTP errors map to rider-readable guidance.
    final err = res.error ?? '';
    final detail = (res.body['detail'] as String?) ?? '';
    await _snack(switch (err) {
      'otp_required' => 'Code rejected. ${detail.isEmpty ? 'Ask the recipient to re-check their SMS.' : detail}',
      'otp_locked' => 'Too many wrong codes — support has been notified.',
      _ => 'Could not mark delivered ($err).',
    });
  }

  @override
  Widget build(BuildContext context) {
    // Fleet view is staff-only (Team tab + this gate). The server also
    // validates the phone belongs to an active rider — a seller whose phone
    // is not a rider row gets an empty queue, never someone else's stops.
    final store = AppScope.of(context);
    if (!store.linked) {
      return Scaffold(
        appBar: AppBar(title: const Text('Task queue', style: TextStyle(fontWeight: FontWeight.w900))),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.lock_outline, size: 44, color: AppColors.muted),
              SizedBox(height: 16),
              Text('Sign in for the task queue', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900), textAlign: TextAlign.center),
              SizedBox(height: 8),
              Text('Link this device to a rider account to see slot-batched pickup runs.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, height: 1.45)),
            ]),
          ),
        ),
      );
    }
    final batches = ((_data?['batches'] as List?) ?? const []).cast<Map<String, dynamic>>();
    return Scaffold(
      appBar: AppBar(title: const Text('Task queue', style: TextStyle(fontWeight: FontWeight.w900))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _load,
        icon: const Icon(Icons.refresh),
        label: const Text('Refresh'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : batches.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('No pick-ups assigned yet.\nNew bookings drop into your queue automatically.',
                        textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, height: 1.5)),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
                  itemCount: batches.length,
                  itemBuilder: (context, i) => _batchCard(batches[i]),
                ),
    );
  }

  Widget _batchCard(Map<String, dynamic> b) {
    final dest = b['destination'] as Map<String, dynamic>?;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            color: AppColors.forest,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${b['label']}', style: const TextStyle(color: AppColors.amber, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.8)),
              const SizedBox(height: 5),
              Text('TOTAL PARCELS TO PICK UP: ${b['total_parcels']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
              if (dest != null)
                Text('DESTINATION: ${dest['courier']} — ${dest['branch']}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final s in ((b['stops'] as List?) ?? const []).cast<Map<String, dynamic>>())
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${s['n']}.', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: AppColors.forest)),
                    const SizedBox(width: 8),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${s['time']} — ${s['address']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      const SizedBox(height: 2),
                      Text('Seller: ${s['seller']} · ${s['parcels']} parcel${s['parcels'] == 1 ? '' : 's'} · ${s['status']}'.replaceAll('_', ' '),
                          style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                    ])),
                    IconButton(
                      tooltip: 'Update stop',
                      visualDensity: VisualDensity.compact,
                      icon: _busyRef == '${s['ref']}'
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.check_circle_outline, color: AppColors.forest),
                      onPressed: () => _advanceStop(s),
                    ),
                  ]),
                ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.line.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  const Icon(Icons.flag_outlined, size: 16, color: AppColors.forest),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    'Target branch drop-off: before ${b['target_dropoff']} · ~${b['minutes_on_road']} min on the road',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.forest),
                  )),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
