import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/dropoff_api.dart';
import '../ui/in_app_browser.dart';
import '../models/booking.dart';
import '../ui/app_theme.dart';
import '../ui/app_spinner.dart';

/// Parses a server timestamp ("2026-11-17 05:09:12", always UTC) into the
/// phone's local time. Every screen formats times through this so the CAT
/// clock the customer sees is never the UTC wall clock.
DateTime serverTime(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return DateTime.now();
  final normalized = s.contains('T') ? s : s.replaceFirst(' ', 'T');
  final withZone = normalized.endsWith('Z') || normalized.contains('+') ? normalized : '${normalized}Z';
  final parsed = DateTime.tryParse(withZone);
  if (parsed == null) return DateTime.now();
  return parsed.isUtc ? parsed.toLocal() : parsed;
}

/// Loads a DropOff media file (/media/uploads/...) with the signed-in user's
/// token — media routes require an authenticated participant, so a plain
/// Image.network would 401. Empty paths render a neutral placeholder.
class AuthedImage extends StatelessWidget {
  final String? path;
  final double? width;
  final double? height;
  final BoxFit fit;
  const AuthedImage(this.path, {super.key, this.width, this.height, this.fit = BoxFit.cover});

  Widget _box({Widget? child}) => Container(
        width: width,
        height: height,
        color: const Color(0xFFE9EFEA),
        alignment: Alignment.center,
        child: child ?? const Icon(Icons.image_outlined, color: AppColors.muted),
      );

  @override
  Widget build(BuildContext context) {
    final p = (path ?? '').trim();
    if (p.isEmpty) return _box();
    final uri = p.startsWith('http') ? p : '${DropOffApi.baseUrl}$p';
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        uri,
        width: width,
        height: height,
        fit: fit,
        headers: DropOffApi.token == null ? null : {'Authorization': 'Bearer ${DropOffApi.token}'},
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : _box(child: const AppLogoSpinner(size: 18)),
        errorBuilder: (_, __, ___) => _box(),
      ),
    );
  }
}

/// Opens the phone dialer for [raw] (keeps digits and '+'). Returns false when
/// the device can't dial (web console, tablet) so the caller can surface the
/// number as text instead of a dead button.
Future<bool> callPhoneNumber(String raw) async {
  final tel = raw.replaceAll(RegExp(r'[^0-9+]'), '');
  if (tel.isEmpty) return false;
  try {
    return await launchUrl(Uri(scheme: 'tel', path: tel), mode: LaunchMode.platformDefault);
  } catch (_) {
    return false;
  }
}

class DropOffLogo extends StatelessWidget {
  final double size;
  const DropOffLogo({super.key, this.size = 44});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.24),
        child: Image.asset('assets/brand/dropoff_logo.png', width: size, height: size),
      );
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  const SectionTitle(this.title, {super.key, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink))),
          if (actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      );
}

class InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const InfoPill({super.key, required this.icon, required this.label, this.color = AppColors.forest});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(30)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Flexible(child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12, height: 1.35))),
        ]),
      );
}

/// Typographic empty state (Scher discipline): no icon bubble — an eyebrow,
/// one display-scale line, one short sentence, one CTA. If a screen has
/// nothing to show, it says so with type, not clip-arts.
class EmptyState extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String message;
  final Widget? action;
  const EmptyState({super.key, this.eyebrow = 'DROPOFF', required this.title, required this.message, this.action});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('DROPOFF', style: AppType.eyebrow),
            const SizedBox(height: 10),
            Text(title, style: AppType.title),
            const SizedBox(height: 10),
            Text(message, style: AppType.body),
            if (action != null) ...[const SizedBox(height: 22), action!],
          ]),
        ),
      );
}

String kwacha(num? value) => value == null ? 'Quote needed' : 'K${value.toStringAsFixed(value % 1 == 0 ? 0 : 2)}';

/// Body text where every http(s) URL is tappable and opens in the browser —
/// used for courier source / pricing notes so sources stay one tap away.
class LinkableText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final TextAlign textAlign;
  const LinkableText({super.key, required this.text, this.style, this.textAlign = TextAlign.start});

  @override
  State<LinkableText> createState() => _LinkableTextState();
}

class _LinkableTextState extends State<LinkableText> {
  static final _urlPattern = RegExp(r'https?://[^\s<>\)]+');
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  List<InlineSpan> _spans() {
    // Rebuilt on every frame: drop recognizers from the previous build first.
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in _urlPattern.allMatches(widget.text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: widget.text.substring(cursor, match.start)));
      }
      // Trailing sentence punctuation belongs to the sentence, not the URL.
      final url = match.group(0)!.replaceFirst(RegExp(r'[.,;:!?]+$'), '');
      if (url.isEmpty) continue;
      final recognizer = TapGestureRecognizer()
        ..onTap = () => openInApp(url);
      _recognizers.add(recognizer);
      spans.add(TextSpan(
        text: url,
        style: const TextStyle(color: AppColors.forest, fontWeight: FontWeight.w700, decoration: TextDecoration.underline),
        recognizer: recognizer,
      ));
      cursor = match.start + url.length;
    }
    if (cursor < widget.text.length) spans.add(TextSpan(text: widget.text.substring(cursor)));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final spans = _spans();
    if (spans.isEmpty) return Text(widget.text, style: widget.style, textAlign: widget.textAlign);
    return Text.rich(TextSpan(style: widget.style, children: spans), textAlign: widget.textAlign);
  }
}

/// Rounded initials chip for a courier operator (used wherever a courier is
/// shown: directory, booking step 2, collections form).
class CourierAvatar extends StatelessWidget {
  final CourierInfo courier;
  final double size;
  const CourierAvatar({super.key, required this.courier, this.size = 50});

  String get initials {
    final words = courier.name.split(' ');
    return words.length == 1 ? words.first.substring(0, 1) : '${words.first[0]}${words[1][0]}';
  }

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Color(courier.colorValue).withValues(alpha: 0.11), borderRadius: BorderRadius.circular(size * 0.3)),
        child: Text(initials, style: TextStyle(color: Color(courier.colorValue), fontWeight: FontWeight.w900, fontSize: size * 0.32)),
      );
}
