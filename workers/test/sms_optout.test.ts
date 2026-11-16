import { describe, expect, it } from 'vitest';

// Opt-out enforcement inside sendSms — see sms.ts.
// These tests pin the marketing/transactional split: money-and-code SMS always
// reach the user; nudges/broadcasts respect Africa's Talking STOP.
describe('sendSms opt-out gate', () => {
  const mkEnv = (optOut: number) => ({
    ENV: 'production',
    AT_USERNAME: 'x', AT_API_KEY: 'y', AT_FROM: 'Carpso',
    DB: {
      prepare: () => ({
        bind: () => ({ first: async () => ({ sms_opt_out: optOut }) }),
      }),
    } as any,
  });

  it('blocks marketing SMS when the user sent STOP', async () => {
    const { sendSms } = await import('../src/sms');
    const res = await sendSms(mkEnv(1) as any, '260971234567', 'nudge');
    expect(res.sent).toBe(false);
    expect(res.error).toBe('sms_opted_out');
  });

  it('still delivers transactional SMS (payment codes) despite STOP', async () => {
    const { sendSms } = await import('../src/sms');
    // AT is unreachable in tests — we only assert the opt-out gate did not
    // short-circuit before the network call; failure mode != 'sms_opted_out'.
    const res = await sendSms(mkEnv(1) as any, '260971234567', 'code 1234', { transactional: true });
    expect(res.error).not.toBe('sms_opted_out');
  });

  it('fails open on DB errors (delivery beats silence for pay events)', async () => {
    const { sendSms } = await import('../src/sms');
    const env = {
      ENV: 'production', AT_USERNAME: 'x', AT_API_KEY: 'y', AT_FROM: 'Carpso',
      DB: { prepare: () => ({ bind: () => ({ first: async () => { throw new Error('db down'); } }) }) } as any,
    };
    const res = await sendSms(env as any, '260971234567', 'nudge');
    expect(res.error).not.toBe('sms_opted_out');
  });
});
