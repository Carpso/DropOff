import 'dart:io';

import 'package:flutter/material.dart';

import '../data/dropoff_api.dart';
import '../ui/app_theme.dart';
import '../ui/receipt_viewer.dart';

/// Compact proof/parcel photo preview with an optional remove button.
/// Accepts a local camera/gallery path (instant, before upload) or a server URL
/// (after upload) — so the sender always sees the photo they are submitting.
class PhotoPreview extends StatelessWidget {
  final String pathOrUrl;
  final VoidCallback? onRemove;
  final double size;
  final String label;

  /// Tapping the photo OPENS it (zoomable). Deletion only ever happens through
  /// the explicit, labelled remove button — never by tapping the image itself.
  final VoidCallback? onTap;

  const PhotoPreview({
    super.key,
    required this.pathOrUrl,
    this.onRemove,
    this.onTap,
    this.size = 84,
    this.label = 'Photo',
  });

  bool get _isLocal => !pathOrUrl.startsWith('http') && !pathOrUrl.startsWith('/media');

  void _openFullScreen(BuildContext context) {
    final p = pathOrUrl.trim();
    if (p.isEmpty) return;
    if (_isLocal) {
      Navigator.of(context).push<void>(MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
          body: InteractiveViewer(maxScale: 5, child: Center(child: Image.file(File(p), fit: BoxFit.contain))),
        ),
      ));
      return;
    }
    ReceiptViewer.show(
      context,
      path: p,
      title: label.isNotEmpty ? label : 'Photo',
      shareTooltip: 'Download / share photo',
      shareLabel: 'Download & share photo',
    );
  }

  @override
  Widget build(BuildContext context) {
    final image = _isLocal
        ? Image.file(File(pathOrUrl), fit: BoxFit.cover, width: size, height: size)
        : Image.network(ReceiptViewer.resolve(pathOrUrl),
            headers: DropOffApi.authHeaders, // evidence photos live behind the auth-gated /media route
            fit: BoxFit.cover, width: size, height: size,
            errorBuilder: (_, __, ___) => Container(
                  width: size, height: size, color: AppColors.line.withValues(alpha: 0.25),
                  child: const Icon(Icons.broken_image_outlined, color: AppColors.muted)));

    final tap = onTap ?? () => _openFullScreen(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(fit: StackFit.expand, children: [
        Positioned.fill(child: GestureDetector(onTap: tap, child: image)),
        Positioned(
          left: 0, right: 0, bottom: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 2),
            color: const Color(0x99000000),
            child: Text(label, textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w800)),
          ),
        ),
        if (onRemove != null)
          Positioned(
            top: 2, right: 2,
            child: Tooltip(
              message: 'Remove this photo',
              child: InkWell(
                onTap: onRemove,
                child: Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: Color(0xCC000000), shape: BoxShape.circle),
                  child: const Icon(Icons.close, size: 15, color: Colors.white),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
