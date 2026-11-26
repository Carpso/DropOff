import 'package:dropoff/ui/map_credit_stamp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The map copyright stamp (owner 2026-11-26): a circled (c) beside the
/// DropOff name, with the map-data credit alongside. Rendered at the narrowest
/// supported widths so it can never overflow or wrap into vertical text.
void main() {
  testWidgets('credit stamp shows the circled C, DropOff and the map credit', (tester) async {
    for (final width in [320.0, 360.0, 390.0]) {
      tester.view.physicalSize = Size(width, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Align(alignment: Alignment.topLeft, child: MapCreditStamp()),
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'width=$width');
      expect(find.text('C'), findsOneWidget);
      expect(find.text('DropOff'), findsOneWidget);
      expect(find.textContaining('OpenStreetMap'), findsOneWidget);
      // Single line: the stamp must stay a slim pill, not a tall block.
      final size = tester.getSize(find.byType(MapCreditStamp));
      expect(size.height, lessThan(30), reason: 'width=$width');
      expect(size.width, lessThan(width), reason: 'width=$width');
    }
  });
}
