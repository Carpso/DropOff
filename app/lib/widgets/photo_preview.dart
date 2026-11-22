import 'dart:io';

import 'package:flutter/material.dart';

import '../data/dropoff_api.dart';
import '../ui/app_theme.dart';

/// Compact proof/parcel photo preview with an optional remove button.
/// Accepts a local camera/gallery path (instant, before upload) or a server URL
/// (after upload) — so the sender always sees the photo they are submitting.
class PhotoPreview extends StatelessWidget {
  final String pathOrUrl;
  final VoidCallback? onRemove;
  final double size;
  final String label;

  const PhotoPreview({
    super.key,
    required this.pathOrUrl,
    this.onRemove,
    this.size = 84,
    this.label = 'Photo',
  });

  bool get _isLocal => !pathOrUrl.startsWith('http');

  @override
  Widget build(BuildContext context) {
    final image = _isLocal
        ? Image.file(File(pathOrUrl), fit: BoxFit.cover, width: size, height: size)
        : Image.network('${DropOffApi.baseUrl}${pathOrUrl.startsWith('/') ? '' : '/'}$pathOrUrl',
            headers: DropOffApi.authHeaders, // evidence photos live behind the auth-gated /media route
            fit: BoxFit.cover, width: size, height: size,
            errorBuilder: (_, __, ___) => Container(
                  width: size, height: size, color: AppColors.line.withValues(alpha: 0.25),
                  child: const Icon(Icons.broken_image_outlined, color: AppColors.muted)));

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(fit: StackFit.expand, children: [
        image,
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
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(color: Color(0xCC000000), shape: BoxShape.circle),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
      ]),
    );
  }
}
