import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

import '../data/dropoff_api.dart';
import '../widgets/common.dart';
import 'app_toast.dart';

/// One place for "see the proof-of-payment receipt" and "send it to someone".
/// Works for the sender's collection form and the recipient's tracking screen.
class ReceiptViewer {
  const ReceiptViewer._();

  /// Uploads return either `/media/...` or an absolute URL — never glue the
  /// API host onto an absolute URL (that was the broken-preview bug).
  static String resolve(String path) {
    final p = path.trim();
    return p.startsWith('http') ? p : '${DropOffApi.baseUrl}$p';
  }

  /// Fetch with the signed-in token, then hand the image to the OS share sheet
  /// so it can be sent to the recipient on WhatsApp / SMS / anywhere.
  static Future<void> share(BuildContext context, String path, String ref) async {
    if (path.trim().isEmpty) return;
    try {
      final uri = Uri.parse(resolve(path));
      final res = await http.get(uri, headers: DropOffApi.authHeaders).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw StateError('http_${res.statusCode}');
      final isPng = uri.path.toLowerCase().endsWith('.png');
      await Share.shareXFiles(
        [XFile.fromData(res.bodyBytes,
            mimeType: isPng ? 'image/png' : 'image/jpeg',
            name: 'dropoff-receipt-${ref.isEmpty ? 'proof' : ref}.${isPng ? 'png' : 'jpg'}')],
        subject: 'DropOff payment receipt',
      );
    } catch (_) {
      if (context.mounted) {
        AppToast.error(context, 'Could not download the receipt — check your connection and try again.');
      }
    }
  }

  /// Full-screen, pinch-to-zoom view with a Download & share action.
  static void show(
    BuildContext context, {
    required String path,
    required String title,
    String ref = '',
    String shareTooltip = 'Download / share receipt',
    String shareLabel = 'Download & share receipt',
  }) {
    final url = resolve(path);
    Navigator.of(context).push<void>(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          actions: [
            IconButton(
              tooltip: shareTooltip,
              icon: const Icon(Icons.ios_share),
              onPressed: () => share(context, path, ref),
            ),
          ],
        ),
        body: InteractiveViewer(maxScale: 5, child: Center(child: AuthedImage(url, fit: BoxFit.contain))),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: FilledButton.icon(
              onPressed: () => share(context, path, ref),
              icon: const Icon(Icons.ios_share, size: 17),
              label: Text(shareLabel),
            ),
          ),
        ),
      ),
    ));
  }
}
