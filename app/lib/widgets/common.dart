import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../ui/in_app_browser.dart';
import '../models/booking.dart';
import '../ui/app_theme.dart';

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
          Flexible(child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12))),
        ]),
      );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 76, height: 76,
              decoration: const BoxDecoration(color: Color(0xFFE8EEE9), shape: BoxShape.circle),
              child: Icon(icon, size: 34, color: AppColors.forest),
            ),
            const SizedBox(height: 18),
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, height: 1.5)),
            if (action != null) ...[const SizedBox(height: 20), action!],
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
