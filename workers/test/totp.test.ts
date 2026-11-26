import { describe, expect, it } from 'vitest';
import { base32Decode, base32Encode, generateTotpSecret, otpauthUri, totpCode, verifyTotp } from '../src/totp';

// Owner 2026-11-26: MFA available to every account. TOTP must match an
// authenticator app (RFC 6238), so the vector and the round-trip are pinned.
describe('TOTP MFA', () => {
  it('matches the RFC 6238 SHA-1 test vector', async () => {
    // Secret "12345678901234567890" base32, 59 s -> 6-digit RFC code 287082
    // (the 8-digit vector is 94287082).
    const secret = base32Encode(new TextEncoder().encode('12345678901234567890'));
    expect(await totpCode(secret, 59000)).toBe('287082');
  });

  it('base32 round-trips a 160-bit secret', () => {
    const bytes = crypto.getRandomValues(new Uint8Array(20));
    expect([...base32Decode(base32Encode(bytes))]).toEqual([...bytes]);
  });

  it('generates a 32-character secret and an otpauth URI', () => {
    const secret = generateTotpSecret();
    expect(secret).toMatch(/^[A-Z2-7]{32}$/);
    const uri = otpauthUri(secret, '260968551110');
    expect(uri).toContain('secret=' + secret);
    expect(uri).toContain('issuer=DropOff');
    expect(uri).toContain('period=30');
  });

  it('accepts the current code and one step of clock drift', async () => {
    const secret = generateTotpSecret();
    const now = Date.now();
    const code = await totpCode(secret, now);
    expect(await verifyTotp(code, secret, now)).toBe(true);
    expect(await verifyTotp(code, secret, now + 30000)).toBe(true);
    expect(await verifyTotp(code, secret, now - 30000)).toBe(true);
  });

  it('rejects wrong codes, malformed input and unknown secrets', async () => {
    const secret = generateTotpSecret();
    const now = Date.now();
    const code = await totpCode(secret, now);
    const wrong = code === '000000' ? '111111' : '000000';
    expect(await verifyTotp(wrong, secret, now)).toBe(false);
    expect(await verifyTotp('12345', secret, now)).toBe(false);
    expect(await verifyTotp('abc123', secret, now)).toBe(false);
    expect(await verifyTotp(code, generateTotpSecret(), now)).toBe(false);
  });
});
