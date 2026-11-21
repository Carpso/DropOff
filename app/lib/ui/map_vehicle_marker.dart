// DropOff map vehicle marker (owner 2026-11-21).
//
// Waze/Google-style 3D bike + car markers. When the generated sprite assets
// exist (`assets/brand/map_bike_3d.png`, `map_car_3d.png`) they are used; until
// they are generated the widget draws a branded top-down vehicle with
// CustomPaint, so the map never falls back to a generic flat icon.
//
// The marker points UP at heading 0°; [heading] is a compass bearing in
// degrees (clockwise from north), matching the OSRM/road-segment bearing the
// map already computes.

import 'dart:math' as math;

import 'package:flutter/material.dart';

class MapVehicleMarker extends StatelessWidget {
  final double heading;
  final String vehicle; // 'motorcycle' | 'car'
  final double size;
  final bool moving;
  final bool stale;

  const MapVehicleMarker({
    super.key,
    required this.heading,
    this.vehicle = 'motorcycle',
    this.size = 34,
    this.moving = true,
    this.stale = false,
  });

  @override
  Widget build(BuildContext context) {
    final isCar = vehicle == 'car';
    final isTruck = vehicle == 'truck';
    final asset = isTruck
        ? 'assets/brand/map_truck_3d.png'
        : isCar
            ? 'assets/brand/map_car_3d.png'
            : 'assets/brand/map_bike_3d.png';
    final vehicleWidget = Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => CustomPaint(
        size: Size.square(size),
        painter: _VehiclePainter(isCar: isCar, isTruck: isTruck),
      ),
    );
    return SizedBox(
      width: size,
      height: size,
      child: Opacity(
        opacity: stale ? 0.55 : 1.0,
        child: Transform.rotate(
          angle: heading * math.pi / 180,
          child: vehicleWidget,
        ),
      ),
    );
  }
}

/// Hand-drawn top-down vehicle used until the 3D sprites are generated.
/// Deliberately simple shapes but with brand colour, glass, wheels and a
/// headlight — it reads as a vehicle at map scale, never as a generic dot.
class _VehiclePainter extends CustomPainter {
  final bool isCar;
  final bool isTruck;
  _VehiclePainter({required this.isCar, this.isTruck = false});

  static const forest = Color(0xFF0E3B32);
  static const forestLight = Color(0xFF1B5A48);
  static const amber = Color(0xFFF6B73C);
  static const dark = Color(0xFF12241E);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final center = Offset(s / 2, s / 2);

    // Soft ground shadow — the "lifted off the map" cue.
    final shadow = Paint()..color = Colors.black.withValues(alpha: 0.22);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center + Offset(0, s * 0.04), width: s * 0.5, height: s * 0.9),
        Radius.circular(s * 0.1),
      ),
      shadow,
    );

    if (isTruck) {
      // Truck: larger body with cab at top, cargo bed below
      final body = Paint()..color = forest;
      // Cab
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: center + Offset(0, -s * 0.25), width: s * 0.48, height: s * 0.35),
          Radius.circular(s * 0.1),
        ),
        body,
      );
      // Cargo bed
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: center + Offset(0, s * 0.15), width: s * 0.52, height: s * 0.5),
          Radius.circular(s * 0.06),
        ),
        body,
      );
      // Wheels
      final wheel = Paint()..color = dark;
      for (final dx in [-1.0, 1.0]) {
        for (final dy in [-0.35, 0.05, 0.35]) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: center + Offset(dx * s * 0.3, dy * s),
                width: s * 0.08,
                height: s * 0.14,
              ),
              Radius.circular(s * 0.03),
            ),
            wheel,
          );
        }
      }
      // Windshield
      final glass = Paint()..color = const Color(0xFFCFE8DF);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: center + Offset(0, -s * 0.28), width: s * 0.38, height: s * 0.12),
          Radius.circular(s * 0.04),
        ),
        glass,
      );
      // Amber stripe on cab
      final stripe = Paint()..color = amber;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: center + Offset(0, -s * 0.18), width: s * 0.38, height: s * 0.06),
          Radius.circular(s * 0.02),
        ),
        stripe,
      );
      // Headlights
      final light = Paint()..color = const Color(0xFFFFE4A0);
      for (final dx in [-1.0, 1.0]) {
        canvas.drawCircle(center + Offset(dx * s * 0.16, -s * 0.4), s * 0.05, light);
      }
      return;
    }

    if (isCar) {
      // Body
      final body = Paint()..color = forest;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: center, width: s * 0.52, height: s * 0.92),
          Radius.circular(s * 0.16),
        ),
        body,
      );
      // Wheels
      final wheel = Paint()..color = dark;
      for (final dx in [-1.0, 1.0]) {
        for (final dy in [-0.3, 0.3]) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: center + Offset(dx * s * 0.3, dy * s),
                width: s * 0.08,
                height: s * 0.18,
              ),
              Radius.circular(s * 0.03),
            ),
            wheel,
          );
        }
      }
      // Windshield + rear glass
      final glass = Paint()..color = const Color(0xFFCFE8DF);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: center + Offset(0, -s * 0.22), width: s * 0.4, height: s * 0.16),
          Radius.circular(s * 0.04),
        ),
        glass,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: center + Offset(0, s * 0.28), width: s * 0.4, height: s * 0.1),
          Radius.circular(s * 0.03),
        ),
        glass,
      );
      // Roof stripe + logo dot
      final stripe = Paint()..color = amber;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: center, width: s * 0.4, height: s * 0.08),
          Radius.circular(s * 0.03),
        ),
        stripe,
      );
      // Headlights
      final light = Paint()..color = const Color(0xFFFFE4A0);
      for (final dx in [-1.0, 1.0]) {
        canvas.drawCircle(center + Offset(dx * s * 0.16, -s * 0.43), s * 0.05, light);
      }
      return;
    }

    // ── Motorcycle ──
    // Wheels (top = front)
    final wheel = Paint()..color = dark;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center + Offset(0, -s * 0.34), width: s * 0.14, height: s * 0.2),
        Radius.circular(s * 0.06),
      ),
      wheel,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center + Offset(0, s * 0.34), width: s * 0.16, height: s * 0.22),
        Radius.circular(s * 0.06),
      ),
      wheel,
    );
    // Frame / body
    final body = Paint()..color = forest;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: s * 0.24, height: s * 0.62),
        Radius.circular(s * 0.08),
      ),
      body,
    );
    // Fuel tank highlight
    final tank = Paint()..color = forestLight;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center + Offset(0, -s * 0.08), width: s * 0.18, height: s * 0.22),
        Radius.circular(s * 0.05),
      ),
      tank,
    );
    // Handlebar
    final bar = Paint()
      ..color = dark
      ..strokeWidth = s * 0.05
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      center + Offset(-s * 0.18, -s * 0.28),
      center + Offset(s * 0.18, -s * 0.28),
      bar,
    );
    // Helmet (white, branded)
    canvas.drawCircle(center + Offset(0, -s * 0.06), s * 0.13, Paint()..color = Colors.white);
    final logo = Paint()..color = forest;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center + Offset(0, -s * 0.06), width: s * 0.12, height: s * 0.12),
        Radius.circular(s * 0.02),
      ),
      logo,
    );
    // Headlight
    canvas.drawCircle(center + Offset(0, -s * 0.4), s * 0.06, Paint()..color = const Color(0xFFFFE4A0));
  }

  @override
  bool shouldRepaint(covariant _VehiclePainter old) => old.isCar != isCar || old.isTruck != isTruck;
}
