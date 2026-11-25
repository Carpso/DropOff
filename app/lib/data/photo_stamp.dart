// DropOff photo evidence stamp (owner directive 2026-11-20).
//
// EVERY photo captured by a sender or a rider is burned with:
//   • the DropOff watermark (left edge, amber accent), and
//   • the exact capture time in CAT (right edge),
//   • plus the evidence tag (PARCEL / PICKUP / DROPOFF / RECEIPT / SELFIE).
//
// Burned-in pixels survive re-uploads, gallery picks and third-party viewers,
// so a photo can never be quietly re-dated or swapped for an older shot.
// If anything fails the original bytes are returned untouched — stamping must
// never block a capture.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Burn the DropOff watermark + capture timestamp into [bytes].
///
/// Returns `null` when [bytes] is not a decodable image (the caller then
/// uploads the original bytes unchanged).
class PhotoStamp {
  const PhotoStamp._();

  /// CAT = UTC+2 (Zambia has no daylight saving).
  static DateTime catNow() => DateTime.now().toUtc().add(const Duration(hours: 2));

  /// Longest side kept after stamping. Phone cameras shoot 4000–8000 px
  /// photos; a 1600 px JPEG uploads in well under half the time on Zambian
  /// mobile data while staying perfectly legible for parcel evidence.
  static const int maxSide = 1600;

  static Uint8List? tryApply(
    List<int> bytes, {
    DateTime? at,
    String tag = 'EVIDENCE',
  }) {
    try {
      final Uint8List raw = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
      final decoded = img.decodeImage(raw);
      if (decoded == null) return null;
      // EXIF-rotated phone shots must be stamped on the UPRIGHT image, or the
      // timestamp would sit along a side edge instead of the bottom strip.
      var image = img.bakeOrientation(decoded);
      if (image.numChannels < 3) image = image.convert(numChannels: 3);
      // Downscale BEFORE drawing so the encoder works on a smaller buffer.
      final longest = image.width >= image.height ? image.width : image.height;
      if (longest > maxSide) {
        final scale = maxSide / longest;
        image = img.copyResize(
          image,
          width: math.max(1, (image.width * scale).round()),
          height: math.max(1, (image.height * scale).round()),
          interpolation: img.Interpolation.average,
        );
      }

      final wide = image.width >= 900;
      final font = wide ? img.arial48 : img.arial24;
      final pad = wide ? 26 : 12;
      final barH = wide ? 86 : 46;
      final top = image.height - barH;
      if (top <= 0) return null;

      // Forest bar with a slight transparency so the parcel stays visible.
      img.fillRect(
        image,
        x1: 0,
        y1: top,
        x2: image.width,
        y2: image.height,
        color: img.ColorRgba8(8, 57, 41, 185),
      );
      // Amber brand rule above the strip (the DropOff accent).
      img.fillRect(
        image,
        x1: 0,
        y1: top,
        x2: image.width,
        y2: top + (wide ? 5 : 3),
        color: img.ColorRgba8(255, 193, 7, 230),
      );

      final when = at != null ? _stampTime(at) : _stampTime(catNow());
      const left = 'DropOff';
      final right = '$when CAT${tag.trim().isEmpty ? '' : ' · ${tag.trim().toUpperCase()}'}';
      final baseline = top + barH ~/ 2 + (wide ? 10 : 5);

      // Brand mark: amber square with a dark "D" beside the DropOff name.
      final markSize = wide ? 52 : 26;
      final markX = pad;
      final markY = baseline - (wide ? 26 : 13);
      img.fillRect(
        image,
        x1: markX,
        y1: markY,
        x2: markX + markSize,
        y2: markY + markSize,
        color: img.ColorRgba8(255, 193, 7, 245),
      );
      img.drawString(
        image,
        'D',
        font: font,
        x: markX + (wide ? 14 : 7),
        y: baseline - (wide ? 28 : 14),
        color: img.ColorRgba8(8, 57, 41, 255),
      );
      final textX = pad + markSize + (wide ? 10 : 5);
      img.drawString(
        image,
        left,
        font: font,
        x: textX,
        y: baseline - (wide ? 16 : 8),
        color: img.ColorRgba8(255, 255, 255, 245),
      );
      // Right-aligned capture time: pixels survive any later re-upload.
      final rightW = _textWidth(font, right);
      final rightX = image.width - pad - rightW;
      if (rightX > textX + _textWidth(font, left) + pad) {
        img.drawString(
          image,
          right,
          font: font,
          x: rightX,
          y: baseline - (wide ? 16 : 8),
          color: img.ColorRgba8(255, 226, 128, 245),
        );
      } else {
        // Narrow crop: put the time on its own line under the watermark.
        img.drawString(
          image,
          when,
          font: font,
          x: pad,
          y: top + (wide ? 52 : 26),
          color: img.ColorRgba8(255, 226, 128, 245),
        );
      }
      return Uint8List.fromList(img.encodeJpg(image, quality: 84));
    } catch (_) {
      return null;
    }
  }

  static String _stampTime(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  static int _textWidth(img.BitmapFont font, String text) {
    var width = 0;
    for (final code in text.codeUnits) {
      final ch = font.characters[code];
      if (ch != null) width += ch.xAdvance;
    }
    return width;
  }
}
