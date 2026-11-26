import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/dropoff_api.dart';
import 'app_sheet.dart';
import 'app_spinner.dart';
import 'app_theme.dart';
import 'app_toast.dart';
import '../widgets/rider_map.dart';

/// Admin map console (owner 2026-11-26): manage every account's saved places
/// on our own map, and watch live pins for every online rider. Both maps can be
/// captured as a PNG snapshot and shared.
class AdminPlacesCard extends StatefulWidget {
  const AdminPlacesCard({super.key});

  @override
  State<AdminPlacesCard> createState() => _AdminPlacesCardState();
}

class _AdminPlacesCardState extends State<AdminPlacesCard> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _places = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await DropOffApi.adminPlaces(q: _search.text.trim());
      if (!mounted) return;
      if (data == null) {
        setState(() { _loading = false; _error = 'Could not load saved places.'; });
        return;
      }
      setState(() {
        _places = (data['places'] as List?)?.whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m)).toList() ?? const [];
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'Could not load saved places.'; });
    }
  }

  static List<LatLng> _pins(List<Map<String, dynamic>> places) => places
      .where((p) => p['lat'] is num && p['lng'] is num)
      .map((p) => LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()))
      .toList();

  Future<void> _edit(Map<String, dynamic>? place) async {
    final phone = TextEditingController(text: '${place?['phone'] ?? ''}');
    final label = TextEditingController(text: '${place?['label'] ?? ''}');
    final latCtl = TextEditingController(text: place?['lat']?.toString() ?? '');
    final lngCtl = TextEditingController(text: place?['lng']?.toString() ?? '');
    final result = await showAppSheet<bool>(
      context,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(4)))),
        const SizedBox(height: 16),
        Text(place == null ? 'Add a saved place' : 'Edit saved place',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 19)),
        const SizedBox(height: 4),
        const Text('Enter the phone number and the pin that belongs to it. '
            'The pin appears on the map below immediately after saving.',
            style: TextStyle(fontSize: 12, color: AppColors.muted)),
        const SizedBox(height: 12),
        TextField(controller: phone, keyboardType: TextInputType.phone,
            enabled: place == null,
            decoration: const InputDecoration(labelText: 'Account phone', hintText: '2609XXXXXXXX', border: OutlineInputBorder(), isDense: true)),
        const SizedBox(height: 10),
        TextField(controller: label,
            decoration: const InputDecoration(labelText: 'Place name', border: OutlineInputBorder(), isDense: true)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(controller: latCtl, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: const InputDecoration(labelText: 'Latitude', border: OutlineInputBorder(), isDense: true))),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: lngCtl, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: const InputDecoration(labelText: 'Longitude', border: OutlineInputBorder(), isDense: true))),
        ]),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: FilledButton.icon(
          onPressed: () {
            if (label.text.trim().isEmpty || double.tryParse(latCtl.text) == null || double.tryParse(lngCtl.text) == null) return;
            Navigator.of(context).pop(true);
          },
          icon: const Icon(Icons.save_outlined, size: 17),
          label: Text(place == null ? 'Add place' : 'Save changes'),
        )),
      ]),
    );
    if (result != true) return;
    final lat = double.parse(latCtl.text);
    final lng = double.parse(lngCtl.text);
    final res = place == null
        ? await DropOffApi.adminAddPlace(phone.text.trim(), label.text.trim(), lat, lng)
        : await DropOffApi.adminUpdatePlace((place['id'] as num?)?.toInt() ?? 0, label.text.trim(), lat, lng);
    if (!mounted) return;
    AppToast.show(context, res.ok
        ? (place == null ? 'Place added to the map.' : 'Place updated.')
        : 'Could not save — ${res.error ?? 'check the pin and try again'}.');
    if (res.ok) _load();
  }

  Future<void> _delete(Map<String, dynamic> place) async {
    final go = await showConfirmSheet(
      context,
      title: 'Remove this saved place?',
      message: '${place['label'] ?? 'This place'} disappears from the owner’s saved places. Jobs already booked are not affected.',
      confirmLabel: 'Remove',
      danger: true,
      icon: Icons.delete_outline_rounded,
    );
    if (go != true) return;
    final res = await DropOffApi.adminDeletePlace((place['id'] as num?)?.toInt() ?? 0);
    if (!mounted) return;
    AppToast.show(context, res.ok ? 'Place removed.' : 'Could not remove that place.');
    if (res.ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    final pins = _pins(_places);
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line),
          boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 3))]),
      child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 40, height: 40,
              decoration: BoxDecoration(color: AppColors.forest.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.bookmark_added_outlined, color: AppColors.forest, size: 21)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Saved places on the map', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            Text('${_places.length} pins across all accounts', style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
          ])),
          IconButton(tooltip: 'Refresh', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh, size: 18, color: AppColors.forest)),
          IconButton(tooltip: 'Add a place', onPressed: () => _edit(null), icon: const Icon(Icons.add_location_alt_outlined, color: AppColors.forest)),
        ]),
        const SizedBox(height: 10),
        TextField(controller: _search, onChanged: (_) => _load(),
          decoration: InputDecoration(hintText: 'Search a place or phone number', prefixIcon: const Icon(Icons.search, size: 19),
            isDense: true, filled: true, fillColor: AppColors.canvas,
            border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10)), borderSide: BorderSide(color: AppColors.line)))),
        const SizedBox(height: 10),
        if (pins.isNotEmpty)
          ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(height: 190, child: RiderMap(
            pickup: pins.first, rider: null,
            stops: [for (final p in _places)
              if (p['lat'] is num && p['lng'] is num)
                {'lat': p['lat'], 'lng': p['lng'], 'kind': 'saved', 'label': '${p['label'] ?? 'Place'}'}],
            selectedSavedLabel: '${_places.isNotEmpty ? _places.first['label'] : ''}',
            city: 'Lusaka',
          ))),
        const SizedBox(height: 10),
        if (_loading)
          const Padding(padding: EdgeInsets.all(16), child: Center(child: AppLogoSpinner(size: 24)))
        else if (_error != null)
          Text(_error!, style: const TextStyle(fontSize: 12.5, color: AppColors.danger))
        else if (_places.isEmpty)
          const Padding(padding: EdgeInsets.all(14), child: Text('No saved places yet.', style: TextStyle(fontSize: 12.5, color: AppColors.muted)))
        else
          for (final p in _places.take(12))
            ListTile(contentPadding: EdgeInsets.zero, dense: true,
              leading: const Icon(Icons.place_outlined, color: AppColors.forest, size: 19),
              title: Text('${p['label'] ?? 'Place'}', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              subtitle: Text('${p['phone'] ?? ''} · ${p['used_at'] ?? ''}', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _edit(p)),
                IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.danger), onPressed: () => _delete(p)),
              ])),
      ])),
    );
  }
}

/// Live fleet map: every rider with a fresh GPS fix, with a snapshot action.
class AdminLiveMapCard extends StatefulWidget {
  const AdminLiveMapCard({super.key});

  @override
  State<AdminLiveMapCard> createState() => _AdminLiveMapCardState();
}

class _AdminLiveMapCardState extends State<AdminLiveMapCard> {
  final _mapKey = GlobalKey();
  List<Map<String, dynamic>> _riders = const [];
  bool _loading = true;
  bool _snapshotting = false;
  int _minutes = 60;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await DropOffApi.adminLiveRiders(minutes: _minutes);
      if (!mounted) return;
      if (data == null) {
        setState(() { _loading = false; _error = 'Could not load rider positions.'; });
        return;
      }
      setState(() {
        _riders = (data['riders'] as List?)?.whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m)).toList() ?? const [];
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'Could not load rider positions.'; });
    }
  }

  Future<void> _snapshot() async {
    final boundary = _mapKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    setState(() => _snapshotting = true);
    try {
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/dropoff-fleet-${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(data.buffer.asUint8List());
      await Share.shareXFiles([XFile(file.path)], subject: 'DropOff live rider map');
    } catch (_) {
      if (mounted) AppToast.show(context, 'Could not capture the map right now.');
    } finally {
      if (mounted) setState(() => _snapshotting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pins = _riders.where((r) => r['last_lat'] is num && r['last_lng'] is num).toList();
    final center = pins.isNotEmpty
        ? LatLng((pins.first['last_lat'] as num).toDouble(), (pins.first['last_lng'] as num).toDouble())
        : RiderMap.chibolya;
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line),
          boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 3))]),
      child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 40, height: 40,
              decoration: BoxDecoration(color: AppColors.forest.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.hail_outlined, color: AppColors.forest, size: 21)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Live rider map', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            Text('${pins.length} riders with a fresh pin', style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
          ])),
          IconButton(tooltip: 'Refresh', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh, size: 18, color: AppColors.forest)),
          IconButton(tooltip: 'Snapshot & share', onPressed: _snapshotting ? null : _snapshot, icon: const Icon(Icons.camera_alt_outlined, color: AppColors.forest)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          const Expanded(child: Text('Show pins from the last', style: TextStyle(fontSize: 12, color: AppColors.muted))),
          for (final m in [30, 60, 180])
            Padding(padding: const EdgeInsets.only(left: 6), child: ChoiceChip(
              label: Text('${m}m', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
              selected: _minutes == m, onSelected: (_) { if (_minutes != m) setState(() => _minutes = m); _load(); },
            )),
        ]),
        const SizedBox(height: 10),
        if (_error != null)
          Text(_error!, style: const TextStyle(fontSize: 12.5, color: AppColors.danger))
        else if (_loading)
          const Padding(padding: EdgeInsets.all(18), child: Center(child: AppLogoSpinner(size: 24)))
        else
          ClipRRect(borderRadius: BorderRadius.circular(12), child: RepaintBoundary(key: _mapKey,
            child: SizedBox(height: 240, child: RiderMap(
              pickup: center, rider: null,
              stops: [for (final r in pins)
                {'lat': r['last_lat'], 'lng': r['last_lng'], 'kind': 'saved',
                 'label': '${r['full_name'] ?? r['phone'] ?? 'Rider'} · ${r['status'] ?? ''}'}],
              city: 'Lusaka',
            )))),
        const SizedBox(height: 8),
        const Text('Pins fade out when a rider stops sharing. Snapshot saves a PNG to your phone.',
            style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
      ])),
    );
  }
}
