import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../data/map_services.dart';
import '../ui/app_theme.dart';
import '../widgets/rider_map.dart';

/// In-app navigator — our own map, our own route. Opens the DropOff map,
/// drops your live GPS as the moving pin, resolves a ROAD-FOLLOWING route
/// (OSRM, turn-by-turn cue sheet in the app) and flies/orbits it fully
/// in-app. When the routing engine is unreachable the line falls back to a
/// labelled straight line — never a fake road.
class InAppNavigatorScreen extends StatefulWidget {
  final double destLat;
  final double destLng;
  final String label;

  /// True when the destination is a DEPOT (rider navigating post-collection):
  /// the pin renders the warehouse badge, not the storefront one.
  final bool destIsDepot;

  /// The other half of the job (sender's stop when heading to the depot, depot
  /// when heading to the sender) — drawn as a context pin so the rider sees
  /// the whole job on one map, like the sender's tracking view does.
  final double? otherLat;
  final double? otherLng;
  final bool otherIsDepot;
  final String? otherLabel;

  const InAppNavigatorScreen({
    super.key,
    required this.destLat,
    required this.destLng,
    required this.label,
    this.destIsDepot = false,
    this.otherLat,
    this.otherLng,
    this.otherIsDepot = false,
    this.otherLabel,
  });

  @override
  State<InAppNavigatorScreen> createState() => _InAppNavigatorScreenState();
}

class _InAppNavigatorScreenState extends State<InAppNavigatorScreen> {
  LatLng? _me;
  LatLng _destPos = const LatLng(0, 0);
  String _destLabel = '';
  RouteResult? _route;
  bool _routeLoading = false;
  bool _engineDown = false;
  String _error = '';
  Timer? _timer;
  Timer? _searchDebounce;
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  bool _searchBusy = false;
  List<MapSearchResult> _results = const [];

  @override
  void initState() {
    super.initState();
    _destPos = LatLng(widget.destLat, widget.destLng);
    _destLabel = widget.label;
    _fix();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _fix());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _searchDebounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  LatLng get _dest => _destPos;

  Future<void> _fix() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _error = 'Location denied — the map still shows the stop, but not you. Enable Location for DropOff.');
        return;
      }
      final service = await Geolocator.isLocationServiceEnabled();
      if (!service) {
        if (mounted) setState(() => _error = 'Location is off on this phone — turn it on to see yourself on the map.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      final moved = _lastRouteFix == null || const Distance().as(LengthUnit.Meter, _lastRouteFix!, LatLng(pos.latitude, pos.longitude)) > 150;
      setState(() {
        _me = LatLng(pos.latitude, pos.longitude);
        _error = '';
      });
      if (_route == null || moved) await _refreshRoute();
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not get your position — check Location and try again.');
    }
  }

  LatLng? _lastRouteFix;

  Future<void> _refreshRoute() async {
    final me = _me;
    if (me == null || _routeLoading) return;
    setState(() => _routeLoading = true);
    final route = await MapServices.route(me, _dest);
    if (!mounted) return;
    setState(() {
      _route = route; // null → fall back to straight line for the pin-line only
      _engineDown = route == null;
      _routeLoading = false;
      _lastRouteFix = me;
    });
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    if (value.trim().length < 3) {
      setState(() => _results = const []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 400), () async {
      setState(() => _searchBusy = true);
      final hits = await MapServices.search(value, bias: _me);
      if (!mounted) return;
      setState(() {
        _results = hits;
        _searchBusy = false;
      });
    });
  }

  void _pickResult(MapSearchResult r) {
    setState(() {
      _destPos = r.point;
      _destLabel = r.label;
      _route = null;
      _results = const [];
      _search.clear();
      _engineDown = false;
    });
    _searchFocus.unfocus();
    _refreshRoute();
  }

  IconData _stepIcon(String instruction) {
    final t = instruction.toLowerCase();
    if (t.contains('u-turn') || t.contains('uturn')) return Icons.u_turn_left;
    if (t.contains('left')) return Icons.turn_left;
    if (t.contains('right')) return Icons.turn_right;
    if (t.contains('roundabout')) return Icons.roundabout_left;
    if (t.contains('merge') || t.contains('ramp')) return Icons.merge;
    if (t.startsWith('arrive')) return Icons.flag;
    if (t.startsWith('head') || t.startsWith('depart')) return Icons.navigation;
    return Icons.straight;
  }

  void _openCueSheet() {
    final steps = _route?.steps ?? const [];
    if (steps.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 0.92,
        builder: (ctx, controller) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
            child: Row(children: [
              const Icon(Icons.format_list_bulleted, color: AppColors.forest),
              const SizedBox(width: 8),
              Expanded(child: Text('Turn-by-turn · $_destLabel', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
              itemCount: steps.length,
              separatorBuilder: (_, __) => const SizedBox(height: 2),
              itemBuilder: (ctx, i) {
                final s = steps[i];
                return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 34, height: 34,
                    decoration: BoxDecoration(color: AppColors.forest.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                    child: Icon(_stepIcon(s.instruction), size: 18, color: AppColors.forest),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(s.instruction, style: const TextStyle(fontSize: 15.5, height: 1.4, fontWeight: FontWeight.w700)),
                  )),
                  if (s.distanceMetres >= 50)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(s.distanceMetres >= 1000 ? '${(s.distanceMetres / 1000).toStringAsFixed(1)} km' : '${s.distanceMetres.round()} m',
                          style: const TextStyle(color: AppColors.muted, fontSize: 12.5, fontWeight: FontWeight.w800)),
                    ),
                ]);
              },
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    final route = _route;
    final routePoints = route?.points;
    final isStraight = routePoints == null || routePoints.length < 3 || _engineDown;
    final displayLine = routePoints ?? (me == null ? null : [me, _dest]);
    final distanceLabel = route?.distanceLabel ?? (me == null ? null : RouteResult.straightLine(me, _dest).distanceLabel);
    final durationLabel = route?.durationLabel ?? (me == null ? null : RouteResult.straightLine(me, _dest).durationLabel);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        elevation: 0,
        title: const Text('Navigate', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: () { _fix(); }),
        ],
      ),
      body: Stack(children: [
        RiderMap(
          pickup: _dest,
          pickupIsDepot: widget.destIsDepot,
          rider: me,
          route: displayLine,
          routeIsStraightLine: isStraight,
          // The other half of the job as context: depot gets the full
          // warehouse pin, a sender stop gets the small storefront badge.
          depot: (widget.otherLat != null && widget.otherIsDepot)
              ? LatLng(widget.otherLat!, widget.otherLng!)
              : null,
          stops: (widget.otherLat != null && !widget.otherIsDepot)
              ? [
                  {
                    'lat': widget.otherLat,
                    'lng': widget.otherLng,
                    'kind': 'pickup',
                    if (widget.otherLabel != null) 'label': widget.otherLabel,
                  },
                ]
              : null,
        ),
        // Floating search — our own geocoder, biased to Lusaka.
        Positioned(
          left: 12,
          right: 12,
          top: 10,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF123C32).withValues(alpha: 0.35)),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2))],
              ),
              child: TextField(
                controller: _search,
                focusNode: _searchFocus,
                onChanged: _onSearchChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search places — e.g. Kabwata market',
                  prefixIcon: const Icon(Icons.search, color: AppColors.forest),
                  suffixIcon: _searchBusy
                      ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                      : (_search.text.isNotEmpty
                          ? IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() { _search.clear(); _results = const []; }))
                          : null),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                ),
              ),
            ),
            if (_results.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF123C32).withValues(alpha: 0.3)),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: _results.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final r = _results[i];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.place_outlined, color: AppColors.forest),
                        title: Text(r.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        onTap: () => _pickResult(r),
                      );
                    },
                  ),
                ),
              ),
          ]),
        ),
      ]),
      // Destination bar
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFF123C32), width: 1, strokeAlign: BorderSide.strokeAlignOutside))),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(_destLabel, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5)),
            const SizedBox(height: 3),
            Row(children: [
              Icon(_engineDown ? Icons.straight : Icons.route, size: 15, color: AppColors.forest),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  distanceLabel == null
                      ? 'Waiting for GPS…'
                      : '$distanceLabel · $durationLabel${_engineDown ? ' · straight-line' : ''}${_routeLoading ? ' · routing…' : ''}',
                  style: const TextStyle(color: AppColors.ink, fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
              if (_route != null && _route!.steps.isNotEmpty)
                TextButton.icon(
                  onPressed: _openCueSheet,
                  icon: const Icon(Icons.format_list_bulleted, size: 18),
                  label: Text('Steps (${_route!.steps.length})'),
                ),
            ]),
            if (_error.isNotEmpty) Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_error, style: const TextStyle(color: AppColors.muted, fontSize: 11, height: 1.4)),
            ),
          ]),
        ),
      ),
    );
  }
}
