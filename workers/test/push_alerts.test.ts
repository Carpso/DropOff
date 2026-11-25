import { describe, expect, it } from 'vitest';
import { androidChannelId, buildFcmMessage, isOrderAlert } from '../src/push';

// Owner bug 2026-11-23: rider phones did not ring or show a curtain alert for a
// new order. The worker used to send every push as a normal FCM notification on
// the `dropoff_jobs` channel (default priority, no sound/vibration), and the
// max-importance `dropoff_orders` channel was never selected by a server push.
describe('new-order push alarm', () => {
  it('routes assignment/transfer pushes to the max-importance orders channel', () => {
    expect(androidChannelId('rider_assigned')).toBe('dropoff_orders');
    expect(androidChannelId('trip_transferred')).toBe('dropoff_orders');
    expect(androidChannelId('claim_available')).toBe('dropoff_orders');
    expect(isOrderAlert('rider_assigned')).toBe(true);
  });

  it('keeps ordinary pushes on their normal channels', () => {
    expect(androidChannelId('payment')).toBe('dropoff_payments');
    expect(androidChannelId('chat')).toBe('dropoff_chat');
    expect(androidChannelId('marketing')).toBe('dropoff_marketing');
    expect(androidChannelId('status')).toBe('dropoff_jobs');
    expect(isOrderAlert('status')).toBe(false);
  });

  it('sends orders as high-priority data-only so the app can render the alarm', () => {
    const msg = buildFcmMessage('fcm-token', {
      title: 'New delivery assigned',
      body: 'Job DRO-1 is waiting',
      data: { job_ref: 'DRO-1', kind: 'rider_assigned' },
    }) as any;
    const m = msg.message;
    expect(m.token).toBe('fcm-token');
    expect(m.notification).toBeUndefined(); // FCM must not post its own quiet notification
    expect(m.data).toEqual({
      job_ref: 'DRO-1', kind: 'rider_assigned',
      title: 'New delivery assigned', body: 'Job DRO-1 is waiting',
    });
    expect(m.android.priority).toBe('high');
    expect(m.android.ttl).toBe('300s'); // stale orders must not ring later
    expect(m.android.notification).toBeUndefined(); // app renders the alarm + full-screen intent
  });

  it('keeps the system notification for non-order pushes', () => {
    const msg = buildFcmMessage('tok', {
      title: 'Payment received', body: 'K50 paid',
      data: { kind: 'payment' },
    }) as any;
    const m = msg.message;
    expect(m.notification).toEqual({ title: 'Payment received', body: 'K50 paid' });
    expect(m.android.notification.channel_id).toBe('dropoff_payments');
    expect(m.android.notification.notification_priority).toBe('PRIORITY_HIGH');
    expect(m.android.ttl).toBeUndefined();
  });
});
