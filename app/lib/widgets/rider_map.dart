import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';

/// Live in-app map on the DropOff basemap (Protomaps Zambia/Zimbabwe/Malawi/
/// Mozambique archive on our R2 bucket — no Google, no MapTiler, no external
/// navigation app). The map is ours; it grows with the fleet's rider density.
class RiderMap extends StatefulWidget {
  final LatLng? pickup;
  final LatLng? rider;
  final LatLng? depot;

  /// Optional route to draw as a polyline (e.g. rider → pickup → drop-off).
  /// Points with no bearing between them render as-is; no road snapping yet.
  final List<LatLng>? route;

  /// Extra labelled pins (e.g. batched pickup stops 1..n).
  final List<Map<String, dynamic>>? stops;

  const RiderMap({
    super.key,
    required this.pickup,
    required this.rider,
    this.depot,
    this.route,
    this.stops,
  });

  static const String tileUrl =
      'https://pub-f3c14b5846eb4de487b036d5a6d6a760.r2.dev/region-zm-zw-mw-mz.pmtiles';
  static const LatLng chibolya = LatLng(-15.4255, 28.2805);

  /// All map markers currently on screen (for camera fitting).
  List<LatLng> get _points => [
        if (pickup != null) pickup!,
        if (rider != null) rider!,
        if (depot != null) depot!,
        ...?route,
        ...?stops?.map((s) => LatLng((s['lat'] as num).toDouble(), (s['lng'] as num).toDouble())),
      ];

  @override
  State<RiderMap> createState() => _RiderMapState();
}

class _RiderMapState extends State<RiderMap> {
  late final Future<PmTilesVectorTileProvider> _provider =
      PmTilesVectorTileProvider.fromSource(RiderMap.tileUrl);

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
  Widget build(BuildContext context) {
    return FutureBuilder<PmTilesVectorTileProvider>(
      future: _provider,
      builder: (context, snap) {
        if (snap.hasError) {
          return _offlineFallback('Map could not load — the rider position still shows as "last seen" below.');
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
        }
        final firstStop = (widget.stops != null && widget.stops!.isNotEmpty)
            ? LatLng((widget.stops!.first['lat'] as num).toDouble(),
                (widget.stops!.first['lng'] as num).toDouble())
            : null;
        final center = widget.rider ?? widget.pickup ?? widget.depot ?? firstStop ?? RiderMap.chibolya;
        final bounds = _bounds;
        return Stack(children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: center,
              initialZoom: 13.5,
              initialCameraFit: bounds == null ? null : CameraFit.bounds(bounds: bounds),
            ),
            children: [
              VectorTileLayer(
                theme: ProtomapsThemes.lightV4(),
                tileProviders: TileProviders({'protomaps': snap.data!}),
                fileCacheTtl: const Duration(days: 7),
              ),
              if (widget.route != null && widget.route!.length > 1)
                PolylineLayer(polylines: [
                  Polyline(
                    points: widget.route!,
                    strokeWidth: 4.5,
                    color: const Color(0xFF17855F),
                  ),
                ]),
              MarkerLayer(markers: [
                if (widget.pickup != null)
                  Marker(
                    point: widget.pickup!,
                    width: 56,
                    height: 56,
                    child: const Icon(Icons.storefront, size: 36, color: Color(0xFF17855F)),
                  ),
                if (widget.stops != null)
                  for (var i = 0; i < widget.stops!.length; i++)
                    Marker(
                      point: LatLng((widget.stops![i]['lat'] as num).toDouble(),
                          (widget.stops![i]['lng'] as num).toDouble()),
                      width: 34,
                      height: 34,
                      child: CircleAvatar(
                        backgroundColor: const Color(0xFFF6B73C),
                        radius: 17,
                        child: Text('${i + 1}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF123C32))),
                      ),
                    ),
                if (widget.depot != null)
                  Marker(
                    point: widget.depot!,
                    width: 56,
                    height: 56,
                    child: const Icon(Icons.warehouse_outlined, size: 36, color: Color(0xFF10312A)),
                  ),
                if (widget.rider != null)
                  Marker(
                    point: widget.rider!,
                    width: 56,
                    height: 56,
                    child: const Icon(Icons.two_wheeler, size: 38, color: Color(0xFFE8A020)),
                  ),
              ]),
            ],
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
        ]);
      },
    );
  }

  Widget _offlineFallback(String message) => Container(
        color: const Color(0xFF10312A),
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
