import { describe, expect, it } from 'vitest';
import { canTrackJob, fixAgeSeconds, STALE_FIX_SECONDS, trackingStage } from '../src/tracking';

describe('live tracking stages', () => {
  it('routes a standard job from pickup to depot and stops at delivery', () => {
    expect(trackingStage('rider_assigned', 'standard')).toMatchObject({ destination: 'pickup', live: true });
    expect(trackingStage('picked_up', 'standard').destination).toBe('depot');
    expect(trackingStage('at_depot', 'standard').phase).toBe('at_depot');
    expect(trackingStage('departed', 'standard').destination).toBe('depot');
    const done = trackingStage('delivered', 'standard');
    expect(done).toMatchObject({ destination: 'done', live: false });
    expect(trackingStage('ready_for_collection', 'standard').live).toBe(false);
  });

  it('runs a collection from the depot to the recipient door', () => {
    expect(trackingStage('rider_assigned', 'collection').destination).toBe('pickup');
    expect(trackingStage('picked_up', 'collection')).toMatchObject({ destination: 'door', live: true });
    expect(trackingStage('arrived', 'collection').destination).toBe('door');
  });

  it('labels every phase in plain language', () => {
    expect(trackingStage('picked_up', 'standard').label).toContain('Picked up');
    expect(trackingStage('rider_assigned', 'collection').label).toContain('depot');
    expect(trackingStage('delivered', 'standard').label).toBe('Journey complete');
  });

  it('authorises participants and staff, never strangers', () => {
    const job = { sender_phone: '260900000001', recipient_phone: '260900000002' };
    expect(canTrackJob('customer', '260900000001', job)).toBe(true);
    expect(canTrackJob('customer', '260900000002', job)).toBe(true);
    expect(canTrackJob('rider', '260900000003', job)).toBe(false);
    expect(canTrackJob('ops', '260900000003', job)).toBe(true);
    expect(canTrackJob('admin', '260900000003', job)).toBe(true);
    expect(canTrackJob('customer', '260977000000', job)).toBe(false);
    expect(canTrackJob('customer', null, job)).toBe(false);
  });

  it('computes GPS fix age and flags stale fixes', () => {
    const now = Date.parse('2026-11-28T12:00:00Z');
    expect(fixAgeSeconds('2026-11-28 11:59:48', now)).toBe(12);
    expect(fixAgeSeconds('2026-11-28 11:58:00', now)).toBe(120);
    expect(fixAgeSeconds('', now)).toBeNull();
    expect(fixAgeSeconds('not-a-date', now)).toBeNull();
    expect(STALE_FIX_SECONDS).toBe(120);
  });
});
