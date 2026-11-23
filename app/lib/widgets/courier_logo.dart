import 'package:flutter/material.dart';

/// Premium courier mark: a real bundled logo when we have one, otherwise a
/// crisp brand-coloured monogram. NEVER a broken hotlinked image — most courier
/// website logo URLs rot within months (owner 2026-11-23, all four required
/// fixes came from dead hotlinks).
class CourierLogo extends StatelessWidget {
  const CourierLogo({
    super.key,
    required this.name,
    this.logoUrl,
    this.colorValue = 0xFF176B87,
    this.size = 42,
  });

  final String name;
  final String? logoUrl;
  final int colorValue;
  final double size;

  String get _initials {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) return words.first.substring(0, words.first.length.clamp(1, 2)).toUpperCase();
    return '${words[0][0]}${words[1][0]}'.toUpperCase();
  }

  Widget _monogram() {
    final color = Color(colorValue);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.92), color],
        ),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.22), blurRadius: size * 0.25, offset: Offset(0, size * 0.08)),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        _initials,
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: size * 0.36,
          letterSpacing: -0.5,
        ),
      ),
    );
  }

  ImageProvider? _provider(String url) {
    if (url.startsWith('assets/')) return AssetImage(url);
    if (url.startsWith('http://') || url.startsWith('https://')) return NetworkImage(url);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final url = (logoUrl ?? '').trim();
    final provider = url.isEmpty ? null : _provider(url);
    if (provider == null) return _monogram();
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.28),
      child: Container(
        width: size,
        height: size,
        color: Colors.white,
        padding: EdgeInsets.all(size * 0.07),
        child: Image(
          image: provider,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _monogram(),
          loadingBuilder: (_, child, progress) =>
              progress == null ? child : Center(child: SizedBox(
                    width: size * 0.34, height: size * 0.34,
                    child: CircularProgressIndicator(strokeWidth: 1.6, valueColor: AlwaysStoppedAnimation(Color(colorValue))),
                  )),
        ),
      ),
    );
  }
}
