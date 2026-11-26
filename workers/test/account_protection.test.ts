import { describe, expect, it } from 'vitest';
import {
  PROTECTED_RESET_DETAIL,
  PROTECTED_ROLES,
  canRedeemResetToken,
  isProtectedAccount,
  resetChannelFor,
} from '../src/account_protection';

// Owner directive 2026-11-26: "protect it as the app owner". The owner's email
// account (godfreymoseskalambo@gmail.com / 260968551110) is the root of the
// admin console, so an emailed reset link must never be enough to take it over.
describe('owner / admin account protection', () => {
  const env = { OWNER_PHONE: '260968551110', OWNER_EMAIL: 'godfreymoseskalambo@gmail.com' };

  it('protects the owner identity by phone and by email', () => {
    expect(isProtectedAccount({ email: 'godfreymoseskalambo@gmail.com', phone: '260000000000', role: 'customer' }, env)).toBe(true);
    expect(isProtectedAccount({ email: 'someone@else.com', phone: '260968551110', role: 'customer' }, env)).toBe(true);
  });

  it('matches the owner identity regardless of case or phone formatting', () => {
    expect(isProtectedAccount({ email: 'GodfreyMosesKalambo@Gmail.com', phone: null, role: null }, env)).toBe(true);
    expect(isProtectedAccount({ email: 'x@y.com', phone: '+260 968 551 110', role: null }, env)).toBe(true);
  });

  it('protects every staff role that can move money or mint roles', () => {
    for (const role of ['admin', 'superadmin', 'owner', 'cfo', 'ops']) {
      expect(isProtectedAccount({ email: 'staff@dropoff.zm', phone: '260971111111', role }, env)).toBe(true);
    }
    expect(PROTECTED_ROLES.has('admin')).toBe(true);
    // A rider or sender is not a protected account.
    expect(isProtectedAccount({ email: 'rider@dropoff.zm', phone: '260972222222', role: 'rider' }, env)).toBe(false);
    expect(isProtectedAccount({ email: 'sender@dropoff.zm', phone: '260973333333', role: 'customer' }, env)).toBe(false);
    expect(isProtectedAccount({ email: 'partner@shop.zm', phone: '260974444444', role: 'partner' }, env)).toBe(false);
  });

  it('sends protected resets to the phone, normal resets by email', () => {
    expect(resetChannelFor(true)).toBe('sms');
    expect(resetChannelFor(false)).toBe('email');
  });

  it('refuses an emailed token for a protected account (old links die)', () => {
    // Every link minted before this policy is 'email' (the column default).
    expect(canRedeemResetToken('email', true)).toBe(false);
    expect(canRedeemResetToken(null, true)).toBe(false);
    expect(canRedeemResetToken(undefined, true)).toBe(false);
    // The two sanctioned channels work.
    expect(canRedeemResetToken('sms', true)).toBe(true);
    expect(canRedeemResetToken('admin', true)).toBe(true);
  });

  it('never blocks a normal customer reset', () => {
    expect(canRedeemResetToken('email', false)).toBe(true);
    expect(canRedeemResetToken('sms', false)).toBe(true);
    expect(canRedeemResetToken(null, false)).toBe(true);
  });

  it('has plain-language refusal copy with no internals', () => {
    expect(PROTECTED_RESET_DETAIL).toContain('account phone');
    expect(PROTECTED_RESET_DETAIL.toLowerCase()).not.toContain('token');
    expect(PROTECTED_RESET_DETAIL.toLowerCase()).not.toContain('sql');
    expect(PROTECTED_RESET_DETAIL).not.toContain('$');
  });
});
