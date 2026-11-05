import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';

/// Live rider map on our Church On App R2 PMTiles Zambia basemap — no Google/MapTiler.
class RiderMap extends StatefulWidget {
  final LatLng? pickup;
  final LatLng? rider;
  final LatLng depot;

  const RiderMap({
    super.key,
    required this.pickup,
    required this.rider,
    required this.depot,
  });

  static const String tileUrl = 'https://maps.churchonapp.com/zambia.pmtiles';
  static const LatLng chibolya = LatLng(-15.4255, 28.2805);

  @override
  State<RiderMap> createState() => _RiderMapState();
}

class _RiderMapState extends State<RiderMap> {
  late final Future<PmTilesVectorTileProvider> _provider =
      PmTilesVectorTileProvider.fromSource(RiderMap.tileUrl);

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
        final center = widget.rider ?? widget.pickup ?? widget.depot;
        return Stack(children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: center,
              initialZoom: 13.5,
            ),
            children: [
              VectorTileLayer(
                theme: ProtomapsThemes.lightV4(),
                tileProviders: TileProviders({'protomaps': snap.data!}),
                fileCacheTtl: const Duration(days: 7),
              ),
              MarkerLayer(markers: [
                if (widget.pickup != null)
                  Marker(
                    point: widget.pickup!,
                    width: 56,
                    height: 56,
                    child: const Icon(Icons.storefront, size: 36, color: Color(0xFF17855F)),
                  ),
                Marker(
                  point: widget.depot,
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
                child: Text('Church on App mapping · map data © OpenStreetMap contributors', style: TextStyle(color: Colors.white, fontSize: 9)),
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
