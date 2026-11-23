import 'package:dropoff/widgets/promo_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Layout regression (owner bug 2026-11-23): the Business promo/retention card
/// used to render its body one character per line down the left edge and clip
/// at the bottom. That happens when a long Text is a direct child of a Row (it
/// gets only the width left over by its siblings) or lives in a fixed-height
/// box. The card now puts the body on its own full-width line; this test pins
/// that by measuring the painted text at narrow AND standard phone widths.
void main() {
  const title = 'You outgrew the SILVER plan this cycle';
  const body =
      'Promo adds 25 parcels for K500 — pro-rated to the day. One tap in Manage.';
  const cta = 'See GOLD';

  Widget card() => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              PromoBanner(
                icon: Icons.savings_outlined,
                title: title,
                body: body,
                cta: cta,
                onCta: () {},
              ),
            ],
          ),
        ),
      );

  for (final width in [320.0, 360.0, 390.0]) {
    testWidgets('promo text wraps by words at ${width.toInt()}px (no vertical ribbon)', (tester) async {
      tester.view.physicalSize = Size(width, 760);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (details) => errors.add(details);
      addTearDown(() => FlutterError.onError = previous);

      await tester.pumpWidget(card());
      await tester.pumpAndSettle();

      final bodySize = tester.getSize(find.text(body));
      final titleSize = tester.getSize(find.text(title));
      final ctaSize = tester.getSize(find.byType(FilledButton));

      // A one-character-per-line ribbon is ~8-14 px wide and 200+ px tall.
      expect(bodySize.width, greaterThan(width * 0.55),
          reason: 'body must use the card width, not the leftover Row sliver');
      expect(bodySize.height, lessThan(150),
          reason: 'body must wrap into a few lines, not one character per line');
      expect(titleSize.width, greaterThan(width * 0.35),
          reason: 'the icon rail must not squeeze the title');
      expect(ctaSize.width, greaterThan(width * 0.6),
          reason: 'CTA stays full width');
      expect(find.byIcon(Icons.savings_outlined), findsOneWidget);
      expect(errors, isEmpty, reason: 'no RenderFlex overflow / layout warnings');
    });
  }
}
