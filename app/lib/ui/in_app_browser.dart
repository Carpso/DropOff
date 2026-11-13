import 'package:url_launcher/url_launcher.dart';

/// Open a web URL inside an in-app browser where the platform supports it
/// (Android Custom Tabs / iOS Safari View Controller). Falls back to the
/// platform browser only when no in-app view is available (some desktops).
Future<bool> openInApp(String url) async {
  final uri = Uri.parse(url);
  if (!await canLaunchUrl(uri)) return false;
  for (final mode in const [LaunchMode.inAppBrowserView, LaunchMode.inAppWebView]) {
    try {
      if (await launchUrl(uri, mode: mode)) return true;
    } catch (_) {
      // try next mode
    }
  }
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Open turn-by-turn DIRECTIONS to the given place.
///
/// Tries, in order:
///   1. the dedicated navigation deep-link for the selected app (waze:// or
///      google.navigation:) — opens the full-screen turn-by-turn screen,
///   2. the device's default geo: handler (Google Maps / Waze / Organic Maps),
///   3. the universal web link (https://waze.com / https://maps.google.com).
///
/// Never depends on which map app is installed; never silently no-ops.
Future<bool> openDirections({
  required double? lat,
  required double? lng,
  required String query,
  required String app, // 'waze' | 'gmaps'
}) async {
  final wazeDeep = (lat != null && lng != null)
      ? 'waze://?ll=$lat,$lng&navigate=yes&follow_deep=1'
      : 'waze://?q=${Uri.encodeComponent(query)}&navigate=yes';
  final mapsDeep = (lat != null && lng != null)
      ? 'google.navigation:q=$lat,$lng'
      : 'google.navigation:q=${Uri.encodeComponent(query)}';
  final geo = (lat != null && lng != null)
      ? 'geo:$lat,$lng?q=${Uri.encodeComponent(query.isNotEmpty ? query : '$lat,$lng')}'
      : 'geo:0,0?q=${Uri.encodeComponent(query)}';
  final wazeHttp = (lat != null && lng != null)
      ? 'https://waze.com/ul?ll=$lat,$lng&navigate=yes'
      : 'https://waze.com/ul?q=${Uri.encodeComponent(query)}&navigate=yes';
  final mapsHttp = (lat != null && lng != null)
      ? 'https://maps.google.com/?q=$lat,$lng'
      : 'https://maps.google.com/?q=${Uri.encodeComponent(query)}';

  final candidates = app == 'waze'
      ? [wazeDeep, mapsDeep, geo, wazeHttp]
      : [mapsDeep, wazeDeep, geo, mapsHttp];

  for (final c in candidates) {
    final uri = Uri.parse(c);
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return true;
    } catch (_) {
      // try next candidate
    }
  }
  return false;
}
