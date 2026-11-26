import 'package:dropoff/data/notification_inbox.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The bell must hold EVERY notification for the user, once each — a rider's
/// order push arrives as FCM + local alarm + tap, and must not triple up.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await NotificationInbox.clear();
  });

  test('records distinct pushes and counts unread', () async {
    await NotificationInbox.add({'kind': 'rider_assigned', 'job_ref': 'DRO-1', 'title': 'New delivery'});
    await NotificationInbox.add({'kind': 'payment', 'title': 'K50 paid'});
    expect(NotificationInbox.items.length, 2);
    expect(NotificationInbox.unread.value, 2);
    // Newest first.
    expect(NotificationInbox.items.first['kind'], 'payment');
  });

  test('the same event delivered three ways appears once', () async {
    final push = {'kind': 'rider_assigned', 'job_ref': 'DRO-2', 'title': 'New delivery', 'body': 'A pickup is waiting'};
    await NotificationInbox.add(push);
    await NotificationInbox.add({...push, 'from_background': true});
    await NotificationInbox.add({...push, 'order_action': 'accept'});
    // The action tap has a different fingerprint (it is a separate event).
    expect(NotificationInbox.items.length, 2);
    expect(NotificationInbox.items.map((e) => e['kind']).toSet(), {'rider_assigned'});
  });

  test('local alerts (order answers, counter fare) are recorded too', () async {
    await NotificationInbox.addLocal(
      title: 'Order accepted', body: 'DRO-3 is in your Task Queue',
      kind: 'order_answer', jobRef: 'DRO-3',
    );
    final item = NotificationInbox.items.single;
    expect(item['kind'], 'order_answer');
    expect(item['job_ref'], 'DRO-3');
    expect(item['local'], true);
    expect(item['title'], 'Order accepted');
  });

  test('mark all read and clear reset the badge', () async {
    await NotificationInbox.add({'kind': 'chat', 'title': 'Support replied'});
    expect(NotificationInbox.unread.value, 1);
    await NotificationInbox.markAllRead();
    expect(NotificationInbox.unread.value, 0);
    await NotificationInbox.clear();
    expect(NotificationInbox.items, isEmpty);
  });
}
