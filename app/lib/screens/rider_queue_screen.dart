// ─────────────────────────────────────────────────────────────────────
// DROPOFF — ownership stamp (do not remove)
// :Godfrey Moses Kalambo:Carpso Solutions:0968551110.
// © 2026 Godfrey Moses Kalambo · Carpso Solutions · Lusaka, Zambia.
// All rights reserved — unauthorised copying, resale or rebranding of
// this source code is prohibited.
// ─────────────────────────────────────────────────────────────────────
import 'dart:async';

import '../ui/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/dropoff_api.dart';
import '../data/analytics_service.dart';
import '../l10n/app_localizations.dart';
import '../main.dart';
import '../ui/app_theme.dart';
import '../ui/in_app_browser.dart';

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

class _RiderQueueScreenState extends State<RiderQueueScreen> with WidgetsBindingObserver {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _busyRef;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AnalyticsService.instance.trackScreenView('rider_queue');
    _load();
    // Keep the queue synced with new assignments without a manual refresh.
    _pollTimer = Timer.periodic(const Duration(seconds: 20), (_) => _load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) _load();
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

  /// One-tap navigation to the stop's pickup. Pinned bookings (sender tapped
  /// "use my location") navigate by exact coordinates; typed addresses
  /// navigate by the address text as a fallback — never leave the rider
  /// guessing how to find the sender.
  void _navigateToStop(Map<String, dynamic> s, String app) {
    final lat = (s['lat'] as num?)?.toDouble();
    final lng = (s['lng'] as num?)?.toDouble();
    if (lat != null && lng != null) {
      if (app == 'waze') {
        openInApp('https://waze.com/ul?ll=$lat,$lng&navigate=yes&follow_deep=1');
      } else {
        openInApp('https://maps.google.com/?q=$lat,$lng');
      }
      return;
    }
    // No pin on the booking — fall back to the typed address text.
    final city = '${s['from_city'] ?? ''}'.trim();
    final addr = '${s['address'] ?? ''}'.trim();
    final query = addr.isEmpty ? '' : '$addr${city.isNotEmpty ? ', $city' : ''}';
    if (query.isEmpty) {
      _snack('This stop has no pin or address yet — refresh, or ask ops.');
      return;
    }
    if (app == 'waze') {
      openInApp('https://waze.com/ul?q=${Uri.encodeComponent(query)}&navigate=yes');
    } else {
      openInApp('https://maps.google.com/?q=${Uri.encodeComponent(query)}');
    }
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
          // DEPOT COUNTER FLOW (owner directive 2026-11-12): the drop needs
          // TWO camera photos (parcel + depot receipt) and the EXACT amount
          // transcribed off the depot's written receipt. The rider never
          // QUOTES a fare — the depot's own receipt is the source, the photo
          // is the proof. The sender pays that amount + processing through
          // DropOff and the rider is reimbursed fee-free. No fare entry, no
          // cash from senders, ever.
          ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: Text(l10n.riderDepotDrop),
            subtitle: Text(l10n.riderDepotDropSub),
            onTap: () => _depotDropWithReceipt(ctx, ref),
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

  /// Depot drop with the counter-receipt kit (owner directive 2026-11-12):
  /// photograph EVERY parcel in the batch, and file EVERY depot receipt the
  /// depot wrote — each photographed, each with the EXACT amount written on
  /// it. A submitted receipt is a single, exact, photographed document, never
  /// a rider-computed sum; the SERVER totals the receipts. The rider fronts
  /// the fare with their own money; DropOff reimburses it fee-free the moment
  /// the sender pays.
  Future<void> _depotDropWithReceipt(BuildContext sheetCtx, String ref) async {
    Navigator.pop(sheetCtx); // close the "how did it move on" sheet
    if (!mounted) return;
    final parcelPhotos = <String>[]; // batch: one or more parcel photos
    final branchCtrl = TextEditingController();
    // Each depot receipt: its own amount field + its own photo. A batch may
    // be split across receipts by the depot — file them all, one by one.
    final receipts = <_ReceiptEntry>[];
    final res = await showDialog<ApiResponse>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text('Depot drop — $ref', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Photograph EVERY parcel in the batch, then file EVERY depot receipt the depot wrote — each receipt photographed with the EXACT amount written on it. Never add receipts up yourself: DropOff totals the photographed documents.',
                  style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.muted)),
              const SizedBox(height: 12),
              // ── Parcel photos (one or more) ──
              Text('PARCEL PHOTOS (${parcelPhotos.length})', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: AppColors.muted)),
              const SizedBox(height: 4),
              for (var i = 0; i < parcelPhotos.length; i++)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.check_circle, size: 18, color: AppColors.forest),
                  title: Text('Parcel photo ${i + 1} attached', style: const TextStyle(fontSize: 12.5)),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    tooltip: 'Remove',
                    onPressed: () => setDialog(() => parcelPhotos.removeAt(i)),
                  ),
                ),
              TextButton.icon(
                icon: const Icon(Icons.camera_alt_outlined, size: 18),
                label: Text(parcelPhotos.isEmpty ? 'Add parcel photo (required)' : 'Add another parcel photo',
                    style: const TextStyle(fontSize: 12.5)),
                onPressed: () async {
                  final url = await _pickPodPhoto();
                  if (url != null) setDialog(() => parcelPhotos.add(url));
                },
              ),
              const SizedBox(height: 12),
              const Text('DEPOT BRANCH', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: AppColors.muted)),
              const SizedBox(height: 4),
              TextField(
                controller: branchCtrl,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  hintText: 'e.g. Platinum — Kabwata',
                  prefixIcon: Icon(Icons.storefront_outlined),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 4),
              const Text('Optional — the exact branch you handed the parcel to. Until now the route reads "to Platinum"; this is where it lands on the books.',
                  style: TextStyle(fontSize: 10.5, color: AppColors.muted, height: 1.35)),
              const Divider(height: 20),
              // ── Depot receipts (one or more, each exact) ──
              Text('DEPOT RECEIPTS (${receipts.length})', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: AppColors.muted)),
              const SizedBox(height: 4),
              for (var i = 0; i < receipts.length; i++) _receiptEntryTile(setDialog, receipts, i),
              TextButton.icon(
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                label: Text(receipts.isEmpty ? 'Add depot receipt (required)' : 'Add another depot receipt (if the depot split the batch)',
                    style: const TextStyle(fontSize: 12.5)),
                onPressed: () => setDialog(() => receipts.add(_ReceiptEntry())),
              ),
              const Text('The receipt photos stay locked for the sender until they pay — then they are revealed and your money comes back.',
                  style: TextStyle(fontSize: 11, height: 1.35, color: AppColors.muted)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (parcelPhotos.isEmpty) {
                  _snack('At least one parcel photo is required.');
                  return;
                }
                if (receipts.isEmpty) {
                  _snack('Add the depot receipt — photo + the exact amount written on it.');
                  return;
                }
                for (var i = 0; i < receipts.length; i++) {
                  final r = receipts[i];
                  if (r.url == null) {
                    _snack('Receipt ${i + 1} needs its photo.');
                    return;
                  }
                  final amt = double.tryParse(r.amountCtrl.text.replaceAll(RegExp(r'[^0-9.]'), ''));
                  if (amt == null || amt <= 0) {
                    _snack('Receipt ${i + 1}: type the exact amount written on it.');
                    return;
                  }
                }
                final branch = branchCtrl.text.trim();
                final r = await DropOffApi.jobEvent(
                  jobRef: ref, status: 'delivered',
                  photoUrl: parcelPhotos.first, stage: 'delivery',
                  parcelPhotos: parcelPhotos,
                  branch: branch.isEmpty ? null : branch,
                  receipts: [
                    for (final e in receipts)
                      {
                        'amount_zmw': double.parse(e.amountCtrl.text.replaceAll(RegExp(r'[^0-9.]'), '')),
                        'url': e.url,
                      }
                  ],
                );
                if (!ctx.mounted) return;
                Navigator.pop(ctx, r);
              },
              child: const Text('Submit drop'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (res == null) return; // cancelled
    final l10n = AppLocalizations.of(context);
    if (res.ok) {
      setState(() => _busyRef = null);
      await _snack('$ref ✓ ${l10n.riderDepotDrop}');
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
      } else {
        // AI check is best-effort; a slow/unavailable vision model must not
        // confuse a rider who just filed the drop correctly.
        await _snack('$ref drop filed. Parcel check skipped (${chk.error ?? 'unavailable'}) — ops will eyeball the photos.');
      }
      _load();
      return;
    }
    // Server-side receipt errors map to rider-readable guidance.
    final err = res.error ?? '';
    final detail = (res.body['detail'] as String?) ?? '';
    setState(() => _busyRef = null);
    await _snack(switch (err) {
      'receipt_required' => detail.isEmpty ? 'Every depot receipt needs its photo and exact amount.' : detail,
      'photo_required' => detail.isEmpty ? 'A parcel photo is required.' : detail,
      'two_photos_required' => detail.isEmpty ? 'Parcel photos and receipt photos must be separate images.' : detail,
      _ => 'Could not submit the drop ($err).',
    });
  }

  /// One filed depot receipt inside the drop dialog: its own photo + its own
  /// exact amount (never summed by the rider).
  Widget _receiptEntryTile(void Function(void Function()) setDialog, List<_ReceiptEntry> receipts, int i) {
    final e = receipts[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Receipt ${i + 1}${e.url != null ? ' — photo attached ✓' : ''}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            tooltip: 'Remove receipt',
            onPressed: () => setDialog(() => receipts.removeAt(i)),
          ),
        ]),
        TextField(
          controller: e.amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Exact amount written on THIS receipt (K)',
            prefixText: 'K ',
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 6),
        TextButton.icon(
          icon: Icon(e.url == null ? Icons.camera_alt_outlined : Icons.check_circle, size: 16,
              color: e.url == null ? null : AppColors.forest),
          label: Text(e.url == null ? 'Photo of THIS receipt (required)' : 'Receipt photo attached ✓',
              style: const TextStyle(fontSize: 12)),
          onPressed: () async {
            final url = await _pickPodPhoto();
            if (url != null) setDialog(() => e.url = url);
          },
        ),
      ]),
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
                      tooltip: 'Navigate to pickup (Waze)',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.navigation_rounded, color: AppColors.forest),
                      onPressed: () => _navigateToStop(s, 'waze'),
                    ),
                    IconButton(
                      tooltip: 'Open in Google Maps',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.map_outlined, color: AppColors.forest),
                      onPressed: () => _navigateToStop(s, 'gmaps'),
                    ),
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

/// One depot receipt filed by the rider in the drop dialog: its own photo and
/// its own exact amount - receipts are never summed by the rider; the server
/// totals the photographed documents.
class _ReceiptEntry {
  final TextEditingController amountCtrl = TextEditingController();
  String? url;
}
