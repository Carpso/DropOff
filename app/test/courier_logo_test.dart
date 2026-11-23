import 'package:dropoff/widgets/courier_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Courier logos must never depend on a third-party hotlink (owner 2026-11-23:
/// Platinum/Mercury/DHL/One World/Falcon logo URLs were all 404 or timed out).
void main() {
  testWidgets('bundled logo renders from the app asset bundle', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Center(child: CourierLogo(name: 'Mercury Express', logoUrl: 'assets/couriers/mercury.png', size: 48)),
    ));
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<AssetImage>());
    expect((image.image as AssetImage).assetName, 'assets/couriers/mercury.png');
  });

  testWidgets('no logo URL shows a designed monogram, not a broken image', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Center(child: CourierLogo(name: 'Platinum Courier Services', size: 48)),
    ));
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    expect(find.text('PC'), findsOneWidget);
  });

  testWidgets('external URL is only attempted when no local logo exists', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Center(child: CourierLogo(name: 'Some Depot', logoUrl: 'https://example.com/logo.png', size: 48)),
    ));
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
  });
}
