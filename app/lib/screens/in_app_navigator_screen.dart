import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../data/map_services.dart';
import '../data/saved_places.dart';
import '../ui/app_theme.dart';
import '../widgets/rider_map.dart';
import '../ui/app_spinner.dart';
import '../services/step_sounds.dart';

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

  /// Server-decided vehicle class so the rider navigator shows the same
  /// branded bike/car the sender sees on the tracking map.
  final String vehicleClass;

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
    this.vehicleClass = 'motorcycle',
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
  final FlutterTts _tts = FlutterTts();
  bool _voiceOn = true; // one-tap mute, persisted via StepSounds

  // GPS-DRIVEN VOICE: one cue at a time, triggered by the rider's distance to
  // the NEXT maneuver point — never a timed read of the whole step list.
  int _cueIndex = 0;
  final Set<int> _spokenDistanceBands = {};
  DateTime? _lastSpokeAt;
  String? _spokenSignature; // maneuver identity — survives a re-route
  double _cueDistance = 0; // drives the live visual cue banner
  final _searchFocus = FocusNode();
  bool _searchBusy = false;
  List<MapSearchResult> _results = const [];
  List<SavedPlace> _saved = const [];

  StreamSubscription<Position>? _guidanceSub;
  @override
  void initState() {
    super.initState();
    unawaited(_setupTts());
    _destPos = LatLng(widget.destLat, widget.destLng);
    _destLabel = widget.label;
    _fix();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) { if (_me == null) _fix(); });
    _startGuidance();
    StepSounds.load().then((_) {
      if (mounted) setState(() => _voiceOn = StepSounds.voiceGuidance);
    });
    SavedPlaces.load().then((list) { if (mounted) setState(() => _saved = list); });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _guidanceSub?.cancel();
    _searchDebounce?.cancel();
    unawaited(_tts.stop());
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _setupTts() async {
    try {
      final languages = await _tts.getLanguages;
      final voice = languages.contains('en-GB') ? 'en-GB' : 'en-US';
      await _tts.setLanguage(voice);
      await _tts.setSpeechRate(1.0);
      await _tts.setVolume(1.0);
      await _tts.awaitSpeakCompletion(true);
    } catch (_) {/* guidance still works visually */}
  }

  /// 1-second GPS stream — the old 10 s one-shot fix skipped the "turn now"
  /// cue entirely at riding speed (a rider covered ~110 m between samples).
  void _startGuidance() {
    _guidanceSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
    ).listen((pos) {
      if (!mounted) return;
      final me = LatLng(pos.latitude, pos.longitude);
      setState(() => _me = me);
      final moved = _lastRouteFix == null ||
          const Distance().as(LengthUnit.Meter, _lastRouteFix!, me) > 150;
      if (_route == null || moved) unawaited(_refreshRoute());
      unawaited(_speakNextCue());
    }, onError: (_) {/* the 10 s watchdog and displayed error handle this */});
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
      // Spoken strictly from where the rider IS now — one instruction, and
      // only when the next turn is close enough to matter.
      await _speakNextCue();
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not get your position — check Location and try again.');
    }
  }

  LatLng? _lastRouteFix;

  /// Re-anchor the spoken cue to the maneuver nearest the rider whenever the
  /// route is (re)built. A re-route every 150 m must not restart the narration.
  void _syncCues(RouteResult? route, LatLng me) {
    final steps = route?.steps ?? const <RouteStep>[];
    final previousSig = _spokenSignature;
    var next = 0;
    var best = double.infinity;
    for (var i = 0; i < steps.length; i++) {
      final loc = steps[i].location;
      if (loc == null) continue;
      final d = const Distance().as(LengthUnit.Meter, me, loc);
      if (d < best) { best = d; next = i; }
    }
    _cueIndex = next;
    final loc = steps.isEmpty ? null : steps[next.clamp(0, steps.length - 1)].location;
    final sig = loc == null ? '' : '${steps[next.clamp(0, steps.length - 1)].instruction}|${loc.latitude}|${loc.longitude}';
    // Only re-arm narration for a genuinely different maneuver; the frequent
    // 150 m re-routes must not re-speak a cue the rider already heard.
    if (sig != previousSig) {
      _spokenDistanceBands.clear();
      _lastSpokeAt = null;
      _spokenSignature = sig;
    }
  }

  /// Speak ONE upcoming turn, driven by live GPS. Steps without a maneuver
  /// point are skipped silently — better quiet than a paragraph read aloud.
  Future<void> _speakNextCue() async {
    if (!_voiceOn) return;
    final me = _me;
    final steps = _route?.steps ?? const <RouteStep>[];
    if (me == null || steps.isEmpty || _cueIndex >= steps.length) return;
    const d = Distance();

    // Skip maneuvers already passed: inside 25 m of the point, or when the
    // following maneuver is now nearer than this one.
    while (_cueIndex < steps.length - 1) {
      final cur = steps[_cueIndex].location;
      final next = steps[_cueIndex + 1].location;
      if (cur == null) { _cueIndex++; _spokenDistanceBands.clear(); continue; }
      final curM = d.as(LengthUnit.Meter, me, cur);
      if (curM <= 25) { _cueIndex++; _spokenDistanceBands.clear(); continue; }
      if (next != null && d.as(LengthUnit.Meter, me, next) < curM) {
        _cueIndex++;
        _spokenDistanceBands.clear();
        continue;
      }
      break;
    }
    if (_cueIndex >= steps.length) return;

    final loc = steps[_cueIndex].location;
    if (loc == null) return;
    final metres = d.as(LengthUnit.Meter, me, loc);
    if (metres > 400) return; // not yet — no long-range "read everything"
    if (mounted) setState(() => _cueDistance = metres);

    // THROTTLE FIRST: a consumed band must never be marked "spoken" when the
    // time guard drops the cue (manual Refresh made cues disappear entirely).
    final now = DateTime.now();
    if (_lastSpokeAt != null && now.difference(_lastSpokeAt!).inSeconds < 6) return;

    final band = metres <= 30 ? 0 : metres <= 100 ? 1 : metres <= 250 ? 2 : 3;
    if (!_spokenDistanceBands.add(band)) return;
    _lastSpokeAt = now;

    final instruction = steps[_cueIndex].instruction.trim();
    final lowering = instruction.isEmpty
        ? instruction
        : '${instruction[0].toLowerCase()}${instruction.substring(1)}';
    final isArrival = lowering.startsWith('arrive') || lowering.contains('destination');
    final say = band == 0
        ? (isArrival ? "You've arrived at $_destLabel." : '$lowering now.')
        : band == 1
            ? '$lowering ahead.'
            : 'In ${(metres / 50).floor() * 50} metres, $lowering';
    await _tts.speak(say).catchError((_) => 0);
  }

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
    _syncCues(route, me);
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    if (value.trim().length < 3) {
      setState(() => _results = const []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 400), () async {
      setState(() => _searchBusy = true);
      // Saved places answer instantly and offline — never an empty box.
      final q = value.trim().toLowerCase();
      final local = _saved.where((p) => p.label.toLowerCase().contains(q)).map((p) =>
          MapSearchResult(p.label, LatLng(p.lat ?? _destPos.latitude, p.lng ?? _destPos.longitude))).toList();
      final hits = await MapServices.search(value, bias: _me);
      if (!mounted) return;
      final seen = <String>{};
      setState(() {
        _results = [...local, ...hits].where((r) => seen.add(r.label.toLowerCase())).toList();
        _searchBusy = false;
      });
    });
  }

  void _pickResult(MapSearchResult r) {
    // Every place used gets remembered automatically — the book grows.
    unawaited(SavedPlaces.remember(r.label, lat: r.point.latitude, lng: r.point.longitude).then((_) => SavedPlaces.load()).then((list) {
      if (mounted) setState(() => _saved = list);
    }));
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
    if (t.contains('roundabout')) return Icons.roundabout_left;
    if (t.contains('u-turn') || t.contains('uturn')) return Icons.u_turn_left;
    if (t.contains('merge') || t.contains('ramp')) return Icons.merge;
    if (t.startsWith('arrive') || t.contains('destination')) return Icons.flag;
    if (t.contains('left')) return Icons.turn_left;
    if (t.contains('right')) return Icons.turn_right;
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
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Navigate', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: () { _fix(); }),
          IconButton(
            tooltip: _voiceOn ? 'Mute voice guidance' : 'Turn on voice guidance',
            icon: Icon(_voiceOn ? Icons.volume_up : Icons.volume_off),
            onPressed: () async {
              await StepSounds.setVoiceGuidance(!_voiceOn);
              if (!mounted) return;
              setState(() => _voiceOn = !_voiceOn);
              await _tts.stop();
              if (_voiceOn && _me != null) {
                _syncCues(_route, _me!);
                _lastSpokeAt = null;
                unawaited(_speakNextCue());
              }
            },
          ),
        ],
      ),
      body: Stack(children: [
        RiderMap(
          pickup: _dest,
          pickupIsDepot: widget.destIsDepot,
          rider: me,
          route: displayLine,
          routeIsStraightLine: isStraight,
          vehicleClass: widget.vehicleClass,
          // The other half of the job as context: depot gets the full
          // warehouse pin, a sender stop gets the small storefront badge.
          depot: (widget.otherLat != null && widget.otherIsDepot)
              ? LatLng(widget.otherLat!, widget.otherLng!)
              : null,
          // Other half of the job + the growing saved-places collection, all
          // as pins on our own map.
          stops: [
            if (widget.otherLat != null && !widget.otherIsDepot)
              {
                'lat': widget.otherLat,
                'lng': widget.otherLng,
                'kind': 'pickup',
                if (widget.otherLabel != null) 'label': widget.otherLabel,
              },
            for (final p in _saved)
              if (p.lat != null && p.lng != null)
                {'lat': p.lat, 'lng': p.lng, 'kind': 'saved', 'label': p.label},
          ],
          selectedSavedLabel: _destLabel,
          frequentSavedLabels: {
            for (final p in _saved.take(6)) p.label,
          },
          onSavedTap: (label) {
            final place = _saved.where((p) => p.label == label).firstOrNull;
            if (place?.lat == null || place?.lng == null) return;
            _pickResult(MapSearchResult(label, LatLng(place!.lat!, place.lng!)));
          },
        ),
        // Floating search — our own geocoder, biased to Lusaka.
        Positioned(
          left: 12,
          right: 64, // leave the top-right compass badge visible/tappable
          top: 10,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.forest.withValues(alpha: 0.35)),
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
                      ? const Padding(padding: EdgeInsets.all(12), child: AppLogoSpinner(size: 18))
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
                  border: Border.all(color: AppColors.forest.withValues(alpha: 0.3)),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: (_saved.isEmpty ? 0 : _saved.length + 1) + _results.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      // Saved places first (growing list), then live results.
                      final savedCount = _saved.isEmpty ? 0 : _saved.length + 1;
                      if (_saved.isNotEmpty && i == 0) {
                        return const ListTile(
                          dense: true,
                          title: Text('SAVED PLACES', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10.5, letterSpacing: 0.7, color: AppColors.forest)),
                        );
                      }
                      if (i < savedCount) {
                        final p = _saved[i - 1];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.bookmark_border, color: AppColors.forest),
                          title: Text(p.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                          onTap: p.lat == null || p.lng == null
                              ? null
                              : () => _pickResult(MapSearchResult(p.label, LatLng(p.lat!, p.lng!))),
                          subtitle: p.lat == null ? const Text('No pin — search-only address', style: TextStyle(fontSize: 10.5, color: AppColors.muted)) : null,
                        );
                      }
                      final r = _results[i - savedCount];
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
          // LIVE CUE BANNER — mirrors the spoken instruction (Waze/Google
          // pattern): riders see the next turn even if audio is missed.
          if (_route != null && _cueIndex < _route!.steps.length)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: IgnorePointer(
                child: Card(
                  color: AppColors.forest,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(children: [
                      Icon(_stepIcon(_route!.steps[_cueIndex].instruction), color: AppColors.amber, size: 26),
                      const SizedBox(width: 12),
                      Expanded(child: Text(
                        _route!.steps[_cueIndex].instruction,
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14, height: 1.3),
                      )),
                      const SizedBox(width: 10),
                      Text(_cueDistance >= 1000
                          ? '${(_cueDistance / 1000).toStringAsFixed(1)} km'
                          : '${(_cueDistance / 10).round() * 10} m',
                          style: const TextStyle(color: AppColors.amber, fontWeight: FontWeight.w900, fontSize: 15)),
                    ]),
                  ),
                ),
              ),
            ),
      ]),
      // Destination bar
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.forest, width: 1, strokeAlign: BorderSide.strokeAlignOutside))),
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
                      : '$distanceLabel · $durationLabel${_engineDown ? ' · direct line' : ''}${_routeLoading ? ' · routing…' : ''}',
                  style: const TextStyle(color: AppColors.ink, fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
              if (_route != null && _route!.steps.isNotEmpty)
                TextButton.icon(
                  onPressed: _openCueSheet,
                  icon: const Icon(Icons.format_list_bulleted, size: 18),
                  label: Text('View steps (${_route!.steps.length})'),
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
