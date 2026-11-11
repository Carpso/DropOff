import '../ui/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/dropoff_api.dart';
import '../data/analytics_service.dart';
import '../l10n/app_localizations.dart';
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
    AnalyticsService.instance.trackScreenView('rider_queue');
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
      AppToast.show(context, 'Proof photo upload failed (${res.error ?? 'network'}) — moving on without it.');
      return null;
    }
    return '${res.body['url'] ?? ''}';
  }

  Future<void> _snack(String msg) async {
    if (!mounted) return;
    AppToast.show(context, msg);
  }

  Future<void> _advanceStop(Map<String, dynamic> s) async {
    final String ref = '${s['ref']}';
    if (_busyRef != null) return;
    final l10n = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.all(14), child: Text(l10n.riderStopTitle,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
          ListTile(
            leading: const Icon(Icons.local_shipping_outlined),
            title: Text(l10n.riderPickedUp),
            subtitle: Text(l10n.riderPickedUpSub),
            trailing: _busyRef == ref ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : null,
            onTap: () async {
              final photo = await _pickPodPhoto();
              setState(() => _busyRef = ref);
              final res = await DropOffApi.jobEvent(
                jobRef: ref, status: 'picked_up', photoUrl: photo, stage: photo == null ? null : 'pickup');
              if (!mounted) return;
              setState(() => _busyRef = null);
              Navigator.pop(ctx);
              await _snack(res.ok ? '$ref ✓ ${l10n.riderPickedUp}' : 'Could not update (${res.error})');
              if (res.ok) {
                AnalyticsService.instance.track(feature: 'rider', action: 'picked_up', context: 'depot_stop');
                _load();
              }
            },
          ),
          // NO-QUOTING POLICY (owner directive): there is NO fare entry here —
          // not optional, not "recorded", not ever. The depot fare is heard at
          // the counter and stays the depot's business. A parcel is marked
          // delivered by CAMERA CAPTURE only: no photo, no delivery.
          ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: Text(l10n.riderDepotDrop),
            subtitle: Text(l10n.riderDepotDropSub),
            onTap: () async {
              final photo = await _pickPodPhoto();
              if (!mounted) return;
              if (photo == null) {
                await _snack(l10n.riderPhotoRequired);
                return;
              }
              setState(() => _busyRef = ref);
              final res = await DropOffApi.jobEvent(
                jobRef: ref, status: 'delivered', photoUrl: photo, stage: 'delivery');
              if (!mounted) return;
              setState(() => _busyRef = null);
              Navigator.pop(ctx);
              await _snack(res.ok ? '$ref ✓ ${l10n.riderDepotDrop}' : 'Could not update (${res.error})');
              if (res.ok) {
                AnalyticsService.instance.track(feature: 'rider', action: 'delivered', context: 'depot_stop');
                // Best-effort: compare seller's booking photo vs this drop photo.
                final chk = await DropOffApi.parcelCheck(ref);
                if (!mounted) return;
                if (chk.ok) {
                  final verdict = chk.body['same_parcel'] ?? 'uncertain';
                  final flagged = chk.body['flagged'] == true;
                  await _snack(flagged
                      ? '$ref parcel check: possible mismatch — ops flagged for review'
                      : '$ref parcel check: $verdict');
                } else if (chk.status == 409) {
                  await _snack('$ref parcel check skipped: ${chk.body['detail'] ?? chk.body['error'] ?? 'photo missing'}');
                }
                _load();
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.home_outlined),
            title: Text(l10n.riderDoorDrop),
            subtitle: Text(l10n.riderDoorDropSub),
            onTap: () => _deliverToDoor(ctx, ref),
          ),
          ListTile(
            leading: const Icon(Icons.close),
            title: Text(l10n.riderNotYet),
            onTap: () => Navigator.pop(ctx),
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
            Text(AppLocalizations.of(context).handoverCodeWarning,
              style: const TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.muted)),
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
            // CAMERA-CAPTURE POLICY: the photo is required, not recommended —
            // a door delivery is marked by camera capture like a depot drop.
            TextButton.icon(
              icon: Icon(podUrl == null ? Icons.camera_alt_outlined : Icons.check_circle, size: 18),
              label: Text(podUrl == null ? AppLocalizations.of(context).riderDoorPhotoAdd : AppLocalizations.of(context).riderDoorPhotoAttached,
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
                if (podUrl == null) {
                  _snack(AppLocalizations.of(context).riderDoorPhotoRequired);
                  return;
                }
                final r = await DropOffApi.jobEvent(
                  jobRef: ref, status: 'delivered', otp: code,
                  photoUrl: podUrl, stage: 'delivery');
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
