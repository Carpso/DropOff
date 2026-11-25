import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dropoff/services/app_update.dart';

void main() {
  test('semantic version comparison ignores build numbers', () {
    expect(compareAppVersions('0.5.92', '0.5.92+102'), 0);
    expect(compareAppVersions('0.5.91', '0.5.92'), lessThan(0));
    expect(compareAppVersions('1.0.0', '0.99.99'), greaterThan(0));
    expect(compareAppVersions('v0.6.0', '0.5.99'), greaterThan(0));
    expect(compareAppVersions('0.5', '0.5.1'), lessThan(0));
  });

  testWidgets('update curtain renders without overflow at 320 / 360 / 390', (tester) async {
    const info = AppUpdateInfo(
      latest: '0.5.93',
      minimum: '0.5.93',
      force: false,
      message: 'A faster, smoother DropOff is ready.',
    );
    for (final width in [320.0, 360.0, 390.0]) {
      tester.view.physicalSize = Size(width, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: AppUpdateCurtain(info: info, required: false)),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'width=$width');
      expect(find.textContaining('Update DropOff'), findsOneWidget);
    }
  });
}
