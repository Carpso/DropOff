import 'package:dropoff/services/app_update.dart';
import 'package:flutter_test/flutter_test.dart';

/// Owner 2026-11-26: the update curtain must be driven by the version ACTUALLY
/// published on Play, not only by our own policy string. These pin the parser
/// against Play's compact listing shape and against noise in the same HTML.
void main() {
  test('parses the version from a real shaped Play listing', () {
    const html = '<div data="1">[[["0.5.96"]],[[36]],[[24,"7.0"]]]</div>';
    expect(parsePlayStoreVersion(html), '0.5.96');
  });

  test('handles four-part versions', () {
    expect(parsePlayStoreVersion('x[[["1.2.3.4"]]]y'), '1.2.3.4');
  });

  test('returns null when the listing shape changes or is absent', () {
    expect(parsePlayStoreVersion('no version here'), isNull);
    expect(parsePlayStoreVersion('[[["not.a.version"]]]'), isNull);
    expect(parsePlayStoreVersion(''), isNull);
  });

  test('ignores unrelated version-looking numbers in Play HTML', () {
    const html = '1.44.3 24.04.47 2.04.81 0.0.0 [[["0.5.97"]]]';
    expect(parsePlayStoreVersion(html), '0.5.97');
  });

  test('version compare keeps product versions, not versionCodes', () {
    expect(compareAppVersions('0.5.96', '0.5.95'), 1);
    expect(compareAppVersions('0.5.96+106', '0.5.96'), 0);
    expect(compareAppVersions('0.5.90', '0.6.0'), -1);
  });
}
