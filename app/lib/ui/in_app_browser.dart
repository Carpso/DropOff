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
