import 'package:dropoff/ui/app_toast.dart';
import 'package:dropoff/ui/keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Toast placement (owner bug 2026-11-23): the red courier-payment error was
/// floating over the bottom of the delivery details screen, covering the very
/// "Pay K5.00 to unlock" / "Download courier receipt" actions it referred to.
void main() {
  testWidgets('error toast pins under the app bar and leaves bottom actions tappable', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const message = 'The momo prompt could not be started — no money was taken.';
    var bottomTapped = false;
    await tester.pumpWidget(MaterialApp(
      scaffoldMessengerKey: scaffoldMessengerKey,
      home: Scaffold(
        appBar: AppBar(title: const Text('Delivery details')),
        body: Stack(children: [
          const Align(alignment: Alignment.topLeft, child: Text('Help & actions')),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                  height: 48,
                  child: Builder(builder: (ctx) => ElevatedButton(
                    key: const Key('trigger'),
                    onPressed: () => AppToast.error(ctx, message),
                    child: const Text('Pay K5.00 to unlock'),
                  )),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    key: const Key('unlock-action'),
                    onPressed: () => bottomTapped = true,
                    child: const Text('Download courier receipt — locked'),
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    ));

    await tester.tap(find.byKey(const Key('trigger')));
    await tester.pumpAndSettle();

    expect(find.text(message), findsOneWidget);
    final top = tester.getTopLeft(find.text(message));
    expect(top.dy, lessThan(120), reason: 'errors belong under the app bar, not over bottom actions');
    final bottom = tester.getTopLeft(find.byKey(const Key('unlock-action')));
    expect(bottom.dy, greaterThan(500), reason: 'the action list stays where it was');

    // The message must not swallow taps meant for the action underneath it.
    await tester.tap(find.byKey(const Key('unlock-action')));
    expect(bottomTapped, isTrue);

    // Let the auto-dismiss timer fire so the test framework sees no pending timer.
    await tester.pump(const Duration(seconds: 6));
  });
}
