import { describe, expect, it } from 'vitest';
import { collectionFees, computeJobTotals, payoutNet, platformFee, round2 } from '../src/fees';
import { generateOtp, hashPassword, signJwt, verifyJwtClaims, verifyPassword } from '../src/auth';
import { normalizeZmPhone, providerFromPhone } from '../src/lipila';

describe('fees', () => {
  it('platform fee has a K3.48 floor', () => {
    expect(platformFee(10)).toBe(3.48);
    expect(platformFee(45)).toBe(3.48);
    expect(platformFee(500)).toBe(5.48); // 1% + 0.48 above the floor
  });

  it('rider keeps 90% minus payout transaction fees', () => {
    // K45 paygo: 40.50 share - 1.50 disbursement - 3.47 platform cut on the share
    expect(payoutNet(45)).toBe(round2(40.5 - 1.5 - platformFee(40.5)));
    expect(collectionFees(45, 45).processing_fee_zmw).toBe(round2(platformFee(45) + 2.5));
  });

  it('pack parcels carry no per-parcel fees', () => {
    const fees = collectionFees(11.7, null);
    expect(fees.processing_fee_zmw).toBe(0);
    expect(fees.prompt_total_zmw).toBe(11.7);
  });

  it('jobTotals honours promo discount and waiting fee on the dropoff leg only', () => {
    const t = computeJobTotals({
      counterPriceZmw: 50, riderFeeZmw: 45, leg2FeeZmw: 30,
      leg2ProcessingFeeZmw: 3.48, promoDiscountZmw: 10, waitFeeZmw: 6,
    });
    expect(t.total_zmw).toBe(round2(50 + 45 + 30 + 3.48 + 6)); // counter fare is the partner's own
    expect(t.dropoff_leg_zmw).toBe(round2(45 + 30 + 3.48 + 6 - 10));
  });
});

describe('phone normalization', () => {
  it('normalizes Zambian formats to 260XXXXXXXXX', () => {
    expect(normalizeZmPhone('0971234567')).toBe('260971234567');
    expect(normalizeZmPhone('260961234567')).toBe('260961234567');
    expect(normalizeZmPhone('961234567')).toBe('260961234567');
    expect(normalizeZmPhone('+260 75 1234 567')).toBe('260751234567');
  });

  it('rejects non-Zambian / invalid numbers', () => {
    expect(() => normalizeZmPhone('0112345678')).toThrow();
    expect(() => normalizeZmPhone('')).toThrow();
    expect(() => normalizeZmPhone('26097123456')).toThrow();
  });

  it('maps prefixes to providers', () => {
    expect(providerFromPhone('260971234567')).toBe('airtel');
    expect(providerFromPhone('260961234567')).toBe('mtn');
    expect(providerFromPhone('260951234567')).toBe('zamtel');
  });
});

describe('auth', () => {
  const SECRET = 'unit-test-secret';

  it('round-trips a JWT and exposes the token version', async () => {
    const token = await signJwt('260971234567', SECRET, 60, 3);
    const claims = await verifyJwtClaims(token, SECRET);
    expect(claims?.phone).toBe('260971234567');
    expect(claims?.ver).toBe(3);
    expect(await verifyJwtClaims(token + 'x', SECRET)).toBeNull();
  });

  it('rejects expired tokens', async () => {
    const token = await signJwt('260971234567', SECRET, -1);
    expect(await verifyJwtClaims(token, SECRET)).toBeNull();
  });

  it('rejects tokens signed with a different secret', async () => {
    const token = await signJwt('260971234567', SECRET, 60);
    expect(await verifyJwtClaims(token, 'other-secret')).toBeNull();
  });

  it('OTP codes are 6 digits', () => {
    for (let i = 0; i < 50; i++) expect(generateOtp()).toMatch(/^\d{6}$/);
  });

  it('password hash + verify round-trip and rejects wrong passwords', async () => {
    const hash = await hashPassword('S3curePass!');
    expect(await verifyPassword('S3curePass!', hash)).toBe(true);
    expect(await verifyPassword('wrong', hash)).toBe(false);
    expect(hash.startsWith('pbkdf2$100000$')).toBe(true);
  });
});
