import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';

import '../data/map_tile_sources.dart';
import '../ui/app_theme.dart';
import '../ui/app_spinner.dart';
import '../ui/saved_place_pin.dart';
import '../ui/map_vehicle_marker.dart';

/// Live in-app map on the DropOff basemap (Protomaps Zambia/Zimbabwe/Malawi/
/// Mozambique archive on our R2 bucket — no Google, no MapTiler, no external
/// navigation app). The map is ours; it grows with the fleet's rider density.
class RiderMap extends StatefulWidget {
  final LatLng? pickup;
  final LatLng? rider;
  final LatLng? depot;

  /// True when [pickup] is actually a DEPOT (rider navigating post-collection):
  /// renders the warehouse badge instead of the storefront one, so the pin
  /// never lies about what the stop is.
  final bool pickupIsDepot;

  /// Optional route to draw as a polyline (e.g. rider → pickup → drop-off).
  /// Road-following when the caller resolved one (OSRM); a straight line is
  /// fine for overview but the caller must label it as such.
  final List<LatLng>? route;

  /// True when [route] is a straight line (routing engine unreachable) —
  /// draws it dashed so it never masquerades as a road route.
  final bool routeIsStraightLine;

  /// Extra labelled pins (e.g. batched pickup stops 1..n).
  final List<Map<String, dynamic>>? stops;

  /// Smart saved-place pins: the selected label gets a name bubble, frequently
  /// used places an amber star. Tapping a pin routes to it.
  final String? selectedSavedLabel;
  final Set<String> frequentSavedLabels;
  final ValueChanged<String>? onSavedTap;

  /// Vehicle class for the rider marker: 'motorcycle' (default) or 'car'.
  /// Server decides this for large/over-cap items; the sender, recipient and
  /// rider all see the SAME branded marker.
  final String vehicleClass;

  const RiderMap({
    super.key,
    required this.pickup,
    required this.rider,
    this.depot,
    this.pickupIsDepot = false,
    this.route,
    this.routeIsStraightLine = false,
    this.stops,
    this.selectedSavedLabel,
    this.frequentSavedLabels = const {},
    this.onSavedTap,
    this.vehicleClass = 'motorcycle',
  });

  static const String tileUrl =
      'https://pub-f3c14b5846eb4de487b036d5a6d6a760.r2.dev/region-zm-zw-mw-mz.pmtiles';
  /// High-detail Lusaka archive from the SAME bucket (z0–16, clipped to the
  /// city). Street-level zoom in Lusaka comes from here; the regional file
  /// still covers the rest of Zambia/Zimbabwe/Malawi/Mozambique.
  static const String lusakaTileUrl =
      'https://pub-f3c14b5846eb4de487b036d5a6d6a760.r2.dev/tiles/lusaka-z0-16.pmtiles';
  /// Lusaka rectangle read from that archive's own PMTiles header
  /// (south, west, north, east).
  static const MapBounds lusakaBounds =
      MapBounds(south: -15.78, west: 27.66, north: -15.02, east: 28.62);
  /// Map label assets (glyphs + sprites) mirrored into OUR R2 bucket. Nothing
  /// on the map reaches protomaps.github.io or any other external host.
  static const String labelAssetBase =
      'https://pub-d23651cb1a9d491f998c73094d54f379.r2.dev';
  static const LatLng chibolya = LatLng(-15.4255, 28.2805);

  /// All map markers currently on screen (for camera fitting).
  List<LatLng> get _points => [
        if (pickup != null) pickup!,
        if (rider != null) rider!,
        if (depot != null) depot!,
        ...?route,
        // Saved places are deliberately NOT in the camera fit: a city-wide
        // address book would zoom the route and rider down to specks.
        ...?stops?.where((s) => s['kind'] != 'saved').map((s) => LatLng((s['lat'] as num).toDouble(), (s['lng'] as num).toDouble())),
      ];

  @override
  State<RiderMap> createState() => _RiderMapState();
}

/// Basemap pieces: the PMTiles provider plus the theme (fonts/sprites/urls)
/// hosted on our own R2 bucket — no external map host at all.
class _MapAssets {
  final VectorTileProvider provider;
  final dynamic theme;
  const _MapAssets(this.provider, this.theme);
}

class _RiderMapState extends State<RiderMap> with SingleTickerProviderStateMixin {
  late final Future<_MapAssets> _assets = () async {
    // Regional archive first (always required), then the Lusaka city archive.
    // The city file is an upgrade, never a dependency: if it cannot be opened
    // the map still draws the regional basemap.
    final regional = await PmTilesVectorTileProvider.fromSource(RiderMap.tileUrl);
    VectorTileProvider provider = regional;
    try {
      final lusaka =
          await PmTilesVectorTileProvider.fromSource(RiderMap.lusakaTileUrl);
      provider = CityFirstTileProvider(
        regional: regional,
        city: lusaka,
        cityBounds: RiderMap.lusakaBounds,
      );
    } catch (_) {
      /* Lusaka archive unavailable — regional basemap still renders. */
    }
    // The theme JSON ships in the app bundle; its glyphs + sprite templates
    // point at OUR R2 bucket, so nothing on the map touches another host.
    final raw = await rootBundle.loadString('assets/map/theme-light-v4.json');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final layers = (decoded['layers'] as List).cast<Map<String, Object>>();
    final theme = ProtomapsThemes(
      glyphs: decoded['glyphs'] as String,
      sprites: decoded['sprite'] as String,
    ).build(layers);
    return _MapAssets(provider, theme);
  }();
  final MapController _mapCtl = MapController();

  // BIKE PULSE (owner 2026-11-18: "make the bike icon more 3d or lively"): a
  // repeating radar ring behind the rider badge — the map reads as live even
  // between the 12 s fixes.
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat();

  // COMPASS (owner directive 2026-11-17: "I kept turning the phone in order
  // to track my north of the route direction"): a live needle badge that
  // always points at true north, tracking both the device heading and any
  // in-app map rotation.
  StreamSubscription<CompassEvent>? _compassSub;
  double _headingDeg = 0; // 0 = north-up until the magnetometer speaks

  @override
  void initState() {
    super.initState();
    _compassSub = FlutterCompass.events?.listen((event) {
      final h = event.heading;
      if (h == null || !mounted) return;
      setState(() => _headingDeg = h);
    });
  }

  @override
  void dispose() {
    _compassSub?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  /// Needle angle in radians: the device's heading negated (heading 90° =
  /// facing east ⇒ north lies 90° to the left of "up"), minus the map's own
  /// rotation so the needle stays truthful on a rotated map. Camera not
  /// ready ⇒ rotation contributes nothing.
  double _needleAngle() {
    var deg = -_headingDeg;
    try {
      deg -= _mapCtl.camera.rotationRad * 180 / math.pi;
    } catch (_) {
      /* camera not ready — device heading only */
    }
    return deg * math.pi / 180;
  }

  /// The compass badge: white circle, red needle + N that rotates with the
  /// device so the rider can hold the phone any way and still find north.
  /// TAPPING it snaps the map back to north-up (owner 2026-11-17: the familiar
  /// tap-to-north behaviour) — a two-finger rotate no longer strands the map
  /// sideways.
  Widget _compassBadge() => Tooltip(
        message: 'Tap to switch between heading-up and north-up',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _snapNorth,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.forest, width: 1.3),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1))],
            ),
            child: Transform.rotate(
              angle: _needleAngle(),
              child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.arrow_upward, size: 15, color: AppColors.danger),
                Text('N', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, color: AppColors.forest, height: 1)),
              ]),
            ),
          ),
        ),
      );

  /// World bearing from the rider to their current destination. Used only as a
  /// fallback when no road route is available.
  double get _destinationBearing {
    if (widget.rider == null) return 0;
    final target = widget.route?.isNotEmpty == true ? widget.route!.last : (widget.pickup ?? widget.depot);
    if (target == null) return 0;
    return const Distance().bearing(widget.rider!, target);
  }

  /// The direction the rider is ACTUALLY travelling — the bearing of the road
  /// segment they are on, not the straight-line bearing to the final pin. The
  /// bike nose follows every bend instead of pointing at the destination while
  /// the road doubles back (owner 2026-11-19: "icon faces elsewhere").
  double get _routeHeading {
    final me = widget.rider;
    if (me == null) return 0;
    final route = widget.route;
    if (route == null || route.length < 2) return _destinationBearing;
    const d = Distance();
    var bestIdx = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < route.length - 1; i++) {
      final a = route[i];
      final b = route[i + 1];
      final mid = LatLng((a.latitude + b.latitude) / 2, (a.longitude + b.longitude) / 2);
      final metres = d.as(LengthUnit.Meter, me, mid);
      if (metres < bestDist) {
        bestDist = metres;
        bestIdx = i;
      }
    }
    final a = route[bestIdx];
    final b = route[bestIdx + 1];
    if ((a.latitude - b.latitude).abs() < 1e-9 && (a.longitude - b.longitude).abs() < 1e-9) {
      return _destinationBearing;
    }
    return d.bearing(a, b);
  }

  double get _mapRotationDeg {
    try { return _mapCtl.camera.rotationRad * 180 / math.pi; } catch (_) { return 0; }
  }

  /// The rider's vehicle on the map — just the vehicle, no frame/badge.
  Widget _riderMarker() {
    return SizedBox(
      width: 64,
      height: 64,
      child: Center(
        child: MapVehicleMarker(
          heading: _routeHeading - _mapRotationDeg,
          vehicle: widget.vehicleClass,
          size: 52,
        ),
      ),
    );
  }

  /// Compass tap → north-up. flutter_map's rotate(0) is due-north; guarded —
  /// the camera may not be ready yet, in which case the map is already north.
  bool _headingUp = false; // compass toggles heading-up / north-up

  /// Compass tap → FACE FORWARD (owner 2026-11-18): rotate the map so the
  /// direction the phone/rider faces is the top of the screen — for riders
  /// with the phone in a holder, "up" must mean where they are going.
  void _snapNorth() {
    HapticFeedback.selectionClick();
    _headingUp = !_headingUp;
    final deg = _headingUp ? _headingDeg : 0.0;
    try {
      _mapCtl.rotate(deg * math.pi / 180);
    } catch (_) {
      /* camera not ready — the map is already north-up */
    }
    setState(() {}); // repaint the rider badge against the new rotation
  }

  LatLngBounds? get _bounds {
    final pts = widget._points;
    if (pts.isEmpty) return null;
    double minLat = pts.first.latitude, maxLat = pts.first.latitude;
    double minLng = pts.first.longitude, maxLng = pts.first.longitude;
    for (final p in pts.skip(1)) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    if (minLat == maxLat && minLng == maxLng) {
      minLat -= 0.008; maxLat += 0.008; minLng -= 0.008; maxLng += 0.008;
    } else {
      const pad = 0.012;
      minLat -= pad; maxLat += pad; minLng -= pad; maxLng += pad;
    }
    return LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng));
  }

  @override
  void didUpdateWidget(covariant RiderMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // SMART NAVIGATION (owner 2026-11-18): as the rider moves, follow the bike
    // and zoom in nearer the destination — the map scales with the journey.
    if (widget.rider == null || widget.rider == oldWidget.rider) return;
    final target = widget.route?.isNotEmpty == true ? widget.route!.last : (widget.pickup ?? widget.depot);
    if (target == null) return;
    final metres = const Distance().as(LengthUnit.Meter, widget.rider!, target);
    final zoom = metres > 1000 ? 13.8 : metres > 400 ? 15.0 : metres > 120 ? 16.0 : 16.5;
    try {
      _mapCtl.move(widget.rider!, zoom);
      if (_headingUp) _mapCtl.rotate(_headingDeg * math.pi / 180);
    } catch (_) {
      /* camera not ready yet — initialCameraFit takes over */
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_MapAssets>(
      future: _assets,
      builder: (context, snap) {
        if (snap.hasError) {
          return _offlineFallback('Map could not load — your position and navigation are still shown.');
        }
        if (!snap.hasData) {
          return const Center(child: AppLogoSpinner(size: 26));
        }
        final firstStop = (widget.stops != null && widget.stops!.isNotEmpty)
            ? LatLng((widget.stops!.first['lat'] as num).toDouble(),
                (widget.stops!.first['lng'] as num).toDouble())
            : null;
        final center = widget.rider ?? widget.pickup ?? widget.depot ?? firstStop ?? RiderMap.chibolya;
        final bounds = _bounds;
        // Route casing: dark outline under the green core — the route reads
        // on any basemap style and on sunny-screen glare.
        final casing = widget.route != null && widget.route!.length > 1
            ? Polyline(points: widget.route!, strokeWidth: 7.5, color: const Color(0xFF0F3B2D))
            : null;
        final core = widget.route != null && widget.route!.length > 1
            ? Polyline(points: widget.route!, strokeWidth: 4.5, color: AppColors.mint)
            : null;
        return Stack(children: [
          FlutterMap(
            mapController: _mapCtl,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 13.5,
              // Zoom discipline (owner 2026-11-18 "why is the rider map
              // different"): a tight fit — rider standing on the stop — used
              // to zoom past the basemap's detail level and render a bare
              // area. Capped, so the rider map always reads like the sender's
              // tracking view.
              initialCameraFit: bounds == null ? null : CameraFit.bounds(bounds: bounds, maxZoom: 16.5),
              // Lusaka's city archive carries z16 detail; allow the camera to
              // reach it. Outside the city the basemap stops at z15.
              maxZoom: 16.5,
            ),
            children: [
              VectorTileLayer(
                theme: snap.data!.theme,
                tileProviders: TileProviders({'protomaps': snap.data!.provider}),
                fileCacheTtl: const Duration(days: 30),
              ),
              // Labels are rendered by the PMTiles/Protomaps theme; avoid third-party
              // label overlays that require external API keys.
              if (casing != null && core != null)
                PolylineLayer(polylines: widget.routeIsStraightLine
                    ? [Polyline(points: widget.route!, strokeWidth: 4, color: AppColors.mint,
                        pattern: StrokePattern.dashed(segments: const [12.0, 9.0]))]
                    : [casing, core]),
              MarkerLayer(markers: [
                if (widget.pickup != null)
                  Marker(
                    point: widget.pickup!,
                    width: 56,
                    height: 56,
                    child: widget.pickupIsDepot
                        ? const Icon(Icons.warehouse_outlined, size: 36, color: AppColors.forest)
                        : const Icon(Icons.storefront, size: 36, color: AppColors.forestLight),
                  ),
                if (widget.stops != null)
                  for (var i = 0; i < widget.stops!.length; i++)
                    Marker(
                      point: LatLng((widget.stops![i]['lat'] as num).toDouble(),
                          (widget.stops![i]['lng'] as num).toDouble()),
                      width: '${widget.stops![i]['kind']}' == 'saved' ? 56 : 34,
                      height: '${widget.stops![i]['kind']}' == 'saved' ? 68 : 34,
                      // Context pins carry a kind → a small icon badge (the
                      // "other half" of the job the rider isn't heading to
                      // right now); unkinded stops stay numbered (batch stops).
                      child: switch (widget.stops![i]['kind']) {
                        'pickup' => const Icon(Icons.storefront, size: 24, color: AppColors.forestLight),
                        'depot' => const Icon(Icons.warehouse_outlined, size: 24, color: AppColors.forest),
                        'saved' => SavedPlacePin(
                            label: '${widget.stops![i]['label'] ?? 'Saved place'}',
                            selected: '${widget.stops![i]['label'] ?? ''}' == widget.selectedSavedLabel,
                            frequent: widget.frequentSavedLabels.contains('${widget.stops![i]['label'] ?? ''}'),
                            onTap: widget.onSavedTap == null
                                ? null
                                : () => widget.onSavedTap!('${widget.stops![i]['label'] ?? ''}'),
                          ),
                        _ => CircleAvatar(
                            backgroundColor: const Color(0xFFF6B73C),
                            radius: 17,
                            child: Text('${i + 1}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppColors.forest)),
                          ),
                      },
                    ),
                if (widget.depot != null)
                  Marker(
                    point: widget.depot!,
                    width: 56,
                    height: 56,
                    child: const Icon(Icons.warehouse_outlined, size: 36, color: AppColors.forest),
                  ),
                if (widget.rider != null)
                  Marker(
                    point: widget.rider!,
                    width: 76,
                    height: 76,
                    child: _riderMarker(),
                  ),
              ]),
            ],
          ),
          // Zoom + re-fit controls — our map, our chrome.
          Positioned(
            top: 12,
            right: 12,
            child: _compassBadge(),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 8, top: 64),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _mapBtn(icon: Icons.add, onTap: () => _zoomBy(1)),
                const SizedBox(height: 6),
                _mapBtn(icon: Icons.remove, onTap: () => _zoomBy(-1)),
                if (bounds != null) ...[
                  const SizedBox(height: 6),
                  _mapBtn(icon: Icons.fit_screen, onTap: () => _refit(bounds)),
                ],
              ]),
            ),
          ),
          const Positioned(
            right: 6,
            bottom: 6,
            child: DecoratedBox(
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.all(Radius.circular(4))),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                child: Text('DropOff map · map data © OpenStreetMap contributors', style: TextStyle(color: Colors.white, fontSize: 9)),
              ),
            ),
          ),
          if (widget.routeIsStraightLine)
            const Positioned(
              left: 8,
              bottom: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.all(Radius.circular(6))),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text('Direct line — turn-by-turn unavailable', style: TextStyle(color: Colors.white, fontSize: 9.5)),
                ),
              ),
            ),
        ]);
      },
    );
  }

  Widget _mapBtn({required IconData icon, required VoidCallback onTap}) => Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: AppColors.forest, width: 1.2)),
        elevation: 2,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(width: 38, height: 38, child: Icon(icon, size: 20, color: AppColors.forest)),
        ),
      );

  void _zoomBy(double delta) {
    try {
      _mapCtl.move(_mapCtl.camera.center, (_mapCtl.camera.zoom + delta).clamp(3, 18).toDouble());
    } catch (_) {
      /* camera not ready — ignore */
    }
  }

  void _refit(LatLngBounds bounds) {
    try {
      final fitted = CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(28), maxZoom: 16)
          .fit(_mapCtl.camera);
      _mapCtl.move(fitted.center, fitted.zoom);
    } catch (_) {
      /* camera not ready — ignore */
    }
  }

  Widget _offlineFallback(String message) => Container(
        color: AppColors.forest,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.signal_wifi_off_rounded, color: Color(0xFFE8A020), size: 40),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFD8E4D8), height: 1.5)),
            ]),
          ),
        ),
      );
}
