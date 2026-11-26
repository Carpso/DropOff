import 'package:dropoff/ui/staff_email_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Staff email entry (owner 2026-11-26). Owner/admin/ops/CFO accounts must be
/// able to type an address in the app; the copy must be honest that reset links
/// for protected accounts still go to the phone. Rendered at the three widths
/// the repo pins so a long explanation can never collapse into vertical text.
void main() {
  Future<void> pump(WidgetTester tester, double width, {String? email}) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: StaffEmailCard(phone: '260968551110', email: email),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  for (final width in <double>[320, 360, 390]) {
    testWidgets('staff email card fits and explains phone resets at ${width.toInt()} px', (tester) async {
      await pump(tester, width);

      expect(find.text('Your email address'), findsOneWidget);
      expect(find.text('STAFF'), findsOneWidget);
      expect(find.text('Save email'), findsOneWidget);
      expect(
        find.textContaining('Owner and admin passwords are always reset with a link to your phone'),
        findsOneWidget,
      );
      // Nothing typed yet → the button stays disabled.
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });
  }

  testWidgets('save enables only for a valid, changed email', (tester) async {
    await pump(tester, 360, email: 'old@example.com');

    final field = find.byType(TextField);
    await tester.enterText(field, 'not-an-email');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);

    await tester.enterText(field, 'old@example.com');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);

    await tester.enterText(field, 'owner@carpsosolutions.store');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
  });
}
