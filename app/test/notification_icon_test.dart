import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('notification small icon is a transparent silhouette, not a white square', () {
    final file = File('android/app/src/main/res/drawable-xhdpi/ic_stat_dropoff.png');
    final decoded = img.decodePng(file.readAsBytesSync());
    expect(decoded, isNotNull);

    var transparent = 0;
    var opaque = 0;
    // Use the decoded byte buffer directly so the test is independent of
    // image-package pixel accessor signatures. PNGs decode to RGBA here.
    final bytes = decoded!.toUint8List();
    final channels = decoded.numChannels;
    for (var i = 0; i + (channels - 1) < bytes.length; i += channels) {
      final a = bytes[i + (channels - 1)];
      if (a < 32) {
        transparent++;
      } else {
        opaque++;
      }
    }

    final total = decoded.width * decoded.height;
    expect(transparent, greaterThan(total ~/ 3),
        reason: 'the old icon was 100% opaque and Android rendered a white square');
    expect(opaque, greaterThan(total ~/ 8),
        reason: 'a completely transparent icon would be invisible in the shade');
  });

  test('notification large icon is a real logo image', () {
    final decoded = img.decodePng(
      File('android/app/src/main/res/drawable-xxhdpi/ic_notification_large.png').readAsBytesSync(),
    );
    expect(decoded, isNotNull);
    expect(decoded!.width, 144);
    expect(decoded.height, 144);
  });
}
