import 'package:dropoff/ui/map_offline_banner.dart';
import 'package:dropoff/ui/offline_map_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Owner rule (2026-11-26): the map's offline banner must read like a premium
/// product and never expose internals. These tests render it at the three
/// phone widths the repo standardises on and fail on any overflow, while also
/// proving the raw strings that used to leak cannot appear.
void main() {
  Future<void> pump(WidgetTester tester, double width, Widget child) async {
    tester.view.physicalSize = Size(width, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: SizedBox(width: width - 70, child: child),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  for (final width in <double>[320, 360, 390]) {
    testWidgets('offline banner is calm and fits at ${width.toInt()} px', (tester) async {
      await pump(
        tester,
        width,
        MapOfflineBanner(onRetry: () {}, onDownload: () {}),
      );

      expect(find.text('Map detail is offline'), findsOneWidget);
      expect(find.text('Your position, route and turn cues still work.'), findsOneWidget);
      expect(find.text('Save the map for offline'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      // No raw internals, ever.
      expect(find.textContaining('pmtiles'), findsNothing);
      expect(find.textContaining('TimeoutException'), findsNothing);
      expect(find.textContaining('Future not completed'), findsNothing);
      expect(find.textContaining('http'), findsNothing);
    });
  }

  for (final width in <double>[320, 360, 390]) {
    testWidgets('offline map sheet fits at ${width.toInt()} px', (tester) async {
      await pump(tester, width, const OfflineMapSheet());

      expect(find.text('Offline map'), findsOneWidget);
      expect(find.text('Lusaka, Zambia'), findsOneWidget);
      expect(find.text('Download for offline use'), findsOneWidget);
      // Nothing has been downloaded in a test environment.
      expect(find.text('NOT SAVED'), findsOneWidget);
    });
  }

  testWidgets('banner buttons fire their callbacks', (tester) async {
    var retried = 0;
    var downloaded = 0;
    await pump(
      tester,
      360,
      MapOfflineBanner(onRetry: () => retried++, onDownload: () => downloaded++),
    );
    await tester.tap(find.text('Retry'));
    await tester.tap(find.text('Save the map for offline'));
    expect(retried, 1);
    expect(downloaded, 1);
  });
}
