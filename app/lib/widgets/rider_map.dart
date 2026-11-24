import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:http/http.dart' as http;
import 'package:pmtiles/pmtiles.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';

import '../data/map_tile_sources.dart';
import '../services/crash_reporting.dart';
import '../ui/app_theme.dart';
import '../ui/app_spinner.dart';
import '../ui/saved_place_pin.dart';
import '../ui/map_vehicle_marker.dart';

/// Live in-app map on the DropOff basemap (Protomaps Zambia/Zimbabwe/Malawi/
/// Mozambique archive on our R2 bucket - no Google, no MapTiler, no external
/// navigation app). The map is ours; it grows with the fleet's rider density.
class RiderMap extends StatefulWidget {
  final LatLng? pickup;
  final LatLng? rider;
  final LatLng? depot;

  /// True when [pickup] is actually a DEPOT (rider navigating post-collection):
  /// renders the warehouse badge instead of the storefront one, so the pin
  /// never lies about what the stop is.
  final bool pickupIsDepot;

  /// Optional route to draw as a polyline (e.g. rider ? pickup ? drop-off).
  /// Road-following when the caller resolved one (OSRM); a straight line is
  /// fine for overview but the caller must label it as such.
  final List<LatLng>? route;

  /// True when [route] is a straight line (routing engine unreachable) -
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

  /// Human-readable names shown as labels on map pins.
  final String? senderName;
  final String? depotName;
  final String? recipientName;
  final String? courierName;

  /// Optional search highlight pin (search-only; does NOT change destination).
  final LatLng? searchPin;
  final String? searchPinLabel;

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
    this.senderName,
    this.depotName,
    this.recipientName,
    this.courierName,
    this.searchPin,
    this.searchPinLabel,
  });

  static const String tileUrl =
      'https://pub-f3c14b5846eb4de487b036d5a6d6a760.r2.dev/region-zm-zw-mw-mz.pmtiles';
  /// High-detail Lusaka archive from the SAME bucket (z0-16, clipped to the
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
        if (searchPin != null) searchPin!,
      ];

  @override
  State<RiderMap> createState() => _RiderMapState();
}

/// Basemap pieces: the PMTiles provider plus the theme (fonts/sprites/urls)
/// hosted on our own R2 bucket - no external map host at all.
///
/// Both are NULLABLE on purpose (owner onboarding bug 2026-11-23): a mobile
/// network that refuses HTTP Range requests must NOT blank the whole map.
/// Markers, route, compass and turn navigation render on a neutral background
/// even with no basemap, and a Retry control is offered.
class _MapAssets {
  final VectorTileProvider? provider;
  final dynamic theme;
  final String? error;
  const _MapAssets(this.provider, this.theme, this.error);

  bool get hasBasemap => provider != null && theme != null;
}

class _RiderMapState extends State<RiderMap> with SingleTickerProviderStateMixin {
  late Future<_MapAssets> _assets = _loadAssets();

  /// Open the basemap without ever failing the screen. Each part degrades
  /// independently, and the real error is reported so onboarding support can
  /// see it (the old code swallowed everything into a generic message).
  Future<_MapAssets> _loadAssets() async {
    String? error;
    // PMTiles reads via HTTP Range. Some mobile networks / VPNs / Private DNS
    // setups answer 200 instead of 206 or strip Content-Range. Open BOTH
    // archives independently and in parallel: the 30 MB Lusaka file is small
    // enough to work where the 1.5 GB regional file fails, and onboarding is
    // Lusaka-first. The PMTiles HTTP client has no timeout of its own, so cap
    // each open - the old code could spin on the spinner forever.
    Future<VectorTileProvider?> openOne(String url, Duration timeout) async {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          return await PmTilesVectorTileProvider.fromSource(url).timeout(timeout);
        } catch (e) {
          debugPrint('RiderMap could not open $url (attempt ${attempt + 1}): $e');
          error = '${error ?? ''} ${Uri.parse(url).pathSegments.last}: $e';
          if (attempt == 0) await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      }
      return null;
    }
    Future<VectorTileProvider?> openWithFallback(List<String> urls, Duration timeout) async {
      for (final url in urls) {
        final p = await openOne(url, timeout);
        if (p != null) return p;
      }
      return null;
    }

    const altAssetsBase = 'https://pub-d23651cb1a9d491f998c73094d54f379.r2.dev';
    final regionalUrls = <String>[
      RiderMap.tileUrl,
      '$altAssetsBase/region-zm-zw-mw-mz.pmtiles',
    ];
    final lusakaUrls = <String>[
      RiderMap.lusakaTileUrl,
      '$altAssetsBase/tiles/lusaka-z0-16.pmtiles',
    ];

    Future<VectorTileProvider?> openLusakaReliable() async {
      // Prefer a full download for Lusaka (30 MB): Range requests often "open"
      // but fail to serve tiles on some mobile networks, causing a blank basemap.
      for (final url in lusakaUrls) {
        try {
          final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 45));
          if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
            final archive = await PmTilesArchive.fromBytes(res.bodyBytes);
            debugPrint('RiderMap: Lusaka full download (${res.bodyBytes.length} bytes) from $url');
            return PmTilesVectorTileProvider.fromArchive(archive);
          }
        } catch (e) {
          debugPrint('RiderMap: Lusaka full download failed for $url: $e');
        }
      }
      // Last resort: range-open (can work where full download is too slow).
      return openWithFallback(lusakaUrls, const Duration(seconds: 8));
    }

    final opened = await Future.wait([
      openWithFallback(regionalUrls, const Duration(seconds: 8)),
      openLusakaReliable(),
    ]);
    VectorTileProvider? regional = opened[0];
    VectorTileProvider? lusaka = opened[1];
    VectorTileProvider? provider;
    if (regional != null && lusaka != null) {
      provider = CityFirstTileProvider(
        regional: regional,
        city: lusaka,
        cityBounds: RiderMap.lusakaBounds,
      );
    } else {
      // Either archive alone is a usable basemap: city covers Lusaka (where
      // onboarding starts), regional covers the rest of the country.
      provider = lusaka ?? regional;
    }
    if (provider != null) error = null; // at least one basemap opened

    // The theme JSON ships in the app bundle; its glyphs + sprite templates
    // point at OUR R2 bucket, so nothing on the map touches another host.
    dynamic theme;
    try {
      final raw = await rootBundle.loadString('assets/map/theme-light-v4.json');
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final layers = (decoded['layers'] as List).cast<Map<String, Object>>();
      theme = ProtomapsThemes(
        glyphs: decoded['glyphs'] as String,
        sprites: decoded['sprite'] as String,
      ).build(layers);
    } catch (e) {
      error = '${error ?? ''} theme: $e';
      debugPrint('RiderMap theme load failed: $e');
    }
    if (error != null) {
      CrashReporting.reportCaught('RiderMap basemap degraded', error);
    }
    return _MapAssets(provider, theme, error);
  }

  void _retryMap() {
    if (!mounted) return;
    setState(() => _assets = _loadAssets());
  }
  final MapController _mapCtl = MapController();

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
      // Sensor noise can stream at 60 Hz; only rebuild the map when the needle
      // visibly moves. Without this the vector layer rebuilds continuously.
      if ((h - _headingDeg).abs() < 1.0) return;
      setState(() => _headingDeg = h);
    });
  }

  @override
  void dispose() {
    _compassSub?.cancel();
    super.dispose();
  }

  /// Needle angle in radians: the device's heading negated (heading 90 deg =
  /// facing east -> north lies 90 deg to the left of "up"), minus the map's own
  /// rotation so the needle stays truthful on a rotated map. Camera not
  /// ready ? rotation contributes nothing.
  double _needleAngle() {
    var deg = -_headingDeg;
    try {
      deg -= _mapCtl.camera.rotationRad * 180 / math.pi;
    } catch (_) {
      /* camera not ready - device heading only */
    }
    return deg * math.pi / 180;
  }

  /// The compass badge: white circle, red needle + N that rotates with the
  /// device so the rider can hold the phone any way and still find north.
  /// TAPPING it snaps the map back to north-up (owner 2026-11-17: the familiar
  /// tap-to-north behaviour) - a two-finger rotate no longer strands the map
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

  /// The direction the rider is ACTUALLY travelling - the bearing of the road
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

  /// A map pin with a readable name label beneath it — so riders and senders
  /// see "where" not just "what icon".
  Widget _labeledPin({
    required IconData icon,
    required Color color,
    required String label,
    bool highlight = false,
  }) {
    final bg = highlight ? AppColors.amber.withValues(alpha: 0.16) : Colors.white.withValues(alpha: 0.94);
    final border = highlight ? AppColors.amber : color.withValues(alpha: 0.35);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: Border.all(color: border, width: highlight ? 2 : 1.4),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1))],
        ),
        child: Icon(icon, size: 22, color: highlight ? const Color(0xFF7A5200) : color),
      ),
      const SizedBox(height: 2),
      Container(
        constraints: const BoxConstraints(maxWidth: 110),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: border),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: highlight ? const Color(0xFF7A5200) : AppColors.forest),
        ),
      ),
    ]);
  }

  /// The rider's vehicle on the map - just the vehicle, no frame/badge.
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

  /// Compass tap -> north-up. flutter_map's rotate(0) is due-north; guarded -
  /// the camera may not be ready yet, in which case the map is already north.
  bool _headingUp = false; // compass toggles heading-up / north-up

  /// Compass tap ? FACE FORWARD (owner 2026-11-18): rotate the map so the
  /// direction the phone/rider faces is the top of the screen - for riders
  /// with the phone in a holder, "up" must mean where they are going.
  void _snapNorth() {
    HapticFeedback.selectionClick();
    _headingUp = !_headingUp;
    final deg = _headingUp ? _headingDeg : 0.0;
    try {
      _mapCtl.rotate(deg * math.pi / 180);
    } catch (_) {
      /* camera not ready - the map is already north-up */
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
    // and zoom in nearer the destination - the map scales with the journey.
    if (widget.rider == null || widget.rider == oldWidget.rider) return;
    final target = widget.route?.isNotEmpty == true ? widget.route!.last : (widget.pickup ?? widget.depot);
    if (target == null) return;
    final metres = const Distance().as(LengthUnit.Meter, widget.rider!, target);
    final zoom = metres > 1000 ? 13.8 : metres > 400 ? 15.0 : metres > 120 ? 16.0 : 16.5;
    try {
      _mapCtl.move(widget.rider!, zoom);
      if (_headingUp) _mapCtl.rotate(_headingDeg * math.pi / 180);
    } catch (_) {
      /* camera not ready yet - initialCameraFit takes over */
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_MapAssets>(
      future: _assets,
      builder: (context, snap) {
        if (snap.hasError) {
          // Defensive: _loadAssets catches its own failures, but a future
          // regression must never blank the map during onboarding.
          CrashReporting.reportCaught('RiderMap assets future failed', snap.error, snap.stackTrace);
          return _offlineFallback('Basemap could not load - retry below.', onRetry: _retryMap);
        }
        if (!snap.hasData) {
          return const Center(child: AppLogoSpinner(size: 26));
        }
        final assets = snap.data!;
        final firstStop = (widget.stops != null && widget.stops!.isNotEmpty)
            ? LatLng((widget.stops!.first['lat'] as num).toDouble(),
                (widget.stops!.first['lng'] as num).toDouble())
            : null;
        final center = widget.rider ?? widget.pickup ?? widget.depot ?? firstStop ?? RiderMap.chibolya;
        final bounds = _bounds;
        // Route casing: dark outline under the green core - the route reads
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
              // different"): a tight fit - rider standing on the stop - used
              // to zoom past the basemap's detail level and render a bare
              // area. Capped, so the rider map always reads like the sender's
              // tracking view.
              initialCameraFit: bounds == null ? null : CameraFit.bounds(bounds: bounds, maxZoom: 16.5),
              // Lusaka's city archive carries z16 detail; allow the camera to
              // reach it. Outside the city the basemap stops at z15.
              maxZoom: 16.5,
            ),
            children: [
              if (assets.hasBasemap)
                VectorTileLayer(
                  theme: assets.theme,
                  tileProviders: TileProviders({'protomaps': assets.provider!}),
                  fileCacheTtl: const Duration(days: 30),
                )
              else
                // Neutral canvas instead of a dead green box: riders still get
                // their bike, stops, route and compass while the basemap heals.
                const IgnorePointer(child: ColoredBox(color: Colors.white)),
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
                    width: 100,
                    height: 72,
                    child: _labeledPin(
                      icon: widget.pickupIsDepot ? Icons.warehouse_outlined : Icons.storefront,
                      color: widget.pickupIsDepot ? AppColors.forest : AppColors.forestLight,
                      label: widget.pickupIsDepot
                          ? (widget.depotName ?? 'Depot')
                          : (widget.senderName ?? 'Pickup'),
                    ),
                  ),
                if (widget.stops != null)
                  for (var i = 0; i < widget.stops!.length; i++)
                    Marker(
                      point: LatLng((widget.stops![i]['lat'] as num).toDouble(),
                          (widget.stops![i]['lng'] as num).toDouble()),
                      width: '${widget.stops![i]['kind']}' == 'saved' ? 56 : 34,
                      height: '${widget.stops![i]['kind']}' == 'saved' ? 68 : 34,
                      // Context pins carry a kind ? a small icon badge (the
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
                    width: 100,
                    height: 72,
                    child: _labeledPin(
                      icon: Icons.warehouse_outlined,
                      color: AppColors.forest,
                      label: widget.depotName ?? widget.courierName ?? 'Depot',
                    ),
                  ),
                if (widget.searchPin != null)
                  Marker(
                    point: widget.searchPin!,
                    width: 120,
                    height: 72,
                    child: _labeledPin(
                      icon: Icons.place,
                      color: AppColors.amber,
                      label: widget.searchPinLabel ?? 'Search result',
                      highlight: true,
                    ),
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
          // Zoom + re-fit controls - our map, our chrome.
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
                child: Text('DropOff map - map data - OpenStreetMap contributors', style: TextStyle(color: Colors.white, fontSize: 9)),
              ),
            ),
          ),
          if (!assets.hasBasemap)
            Positioned(
              top: 10,
              left: 10,
              right: 60,
              child: Material(
                color: Colors.white.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(children: [
                    const Icon(Icons.map_outlined, size: 17, color: AppColors.amber),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      const Text('Basemap offline - your position and route still show.',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.ink)),
                      if ((assets.error ?? '').isNotEmpty)
                        Padding(padding: const EdgeInsets.only(top: 3), child: Text(
                          assets.error!.length > 150 ? '${assets.error!.substring(0, 150)}...' : assets.error!,
                          style: const TextStyle(fontSize: 9.5, color: AppColors.muted),
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                        )),
                    ])),
                    TextButton(onPressed: _retryMap, child: const Text('Retry')),
                  ]),
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
                  child: Text('Direct line - turn-by-turn unavailable', style: TextStyle(color: Colors.white, fontSize: 9.5)),
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
      /* camera not ready - ignore */
    }
  }

  void _refit(LatLngBounds bounds) {
    try {
      final fitted = CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(28), maxZoom: 16)
          .fit(_mapCtl.camera);
      _mapCtl.move(fitted.center, fitted.zoom);
    } catch (_) {
      /* camera not ready - ignore */
    }
  }

  Widget _offlineFallback(String message, {required VoidCallback onRetry}) => Container(
        // Neutral canvas, never the old solid-green dead end (owner onboarding
        // report: 'green on maps'). The normal degraded path keeps markers and
        // route; this is only the rare defensive error path.
        color: const Color(0xFFEDF2EC),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.map_outlined, color: AppColors.amber, size: 40),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w700, height: 1.5)),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry map'),
              ),
            ]),
          ),
        ),
      );
}
