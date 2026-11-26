// TOTP (RFC 6238) for DropOff accounts — SHA-1, 30 s step, 6 digits.
//
// Pure WebCrypto implementation so it runs unchanged on Cloudflare Workers and
// in Node/vitest. The shared secret never leaves the server after enrollment;
// the app only ever sees it once, in the otpauth:// URI the authenticator scans.

const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

export function base32Encode(bytes: Uint8Array): string {
  let bits = 0;
  let value = 0;
  let out = '';
  for (const b of bytes) {
    value = (value << 8) | b;
    bits += 8;
    while (bits >= 5) {
      out += ALPHABET[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) out += ALPHABET[(value << (5 - bits)) & 31];
  return out;
}

export function base32Decode(input: string): Uint8Array {
  const clean = input.toUpperCase().replace(/=+$/, '').replace(/[\s-]/g, '');
  let bits = 0;
  let value = 0;
  const out: number[] = [];
  for (const ch of clean) {
    const idx = ALPHABET.indexOf(ch);
    if (idx < 0) throw new Error('invalid base32');
    value = (value << 5) | idx;
    bits += 5;
    if (bits >= 8) {
      out.push((value >>> (bits - 8)) & 255);
      bits -= 8;
    }
  }
  return new Uint8Array(out);
}

/** Generate a 20-byte (160-bit) secret, base32 for authenticator apps. */
export function generateTotpSecret(): string {
  return base32Encode(crypto.getRandomValues(new Uint8Array(20)));
}

function secretBytes(secret: string): Uint8Array {
  return base32Decode(secret);
}

/** The 6-digit TOTP code at time [atMs]. */
export async function totpCode(secret: string, atMs: number = Date.now()): Promise<string> {
  const counter = Math.floor(atMs / 30000);
  const buf = new ArrayBuffer(8);
  new DataView(buf).setBigUint64(0, BigInt(counter), false);
  const key = await crypto.subtle.importKey('raw', secretBytes(secret), { name: 'HMAC', hash: 'SHA-1' }, false, ['sign']);
  const sig = new Uint8Array(await crypto.subtle.sign('HMAC', key, buf));
  const offset = sig[sig.length - 1] & 0x0f;
  const binary = ((sig[offset] & 0x7f) << 24) | (sig[offset + 1] << 16) | (sig[offset + 2] << 8) | sig[offset + 3];
  return String(binary % 1000000).padStart(6, '0');
}

/** True when [code] matches the code for now or one 30 s window either side. */
export async function verifyTotp(code: string, secret: string, atMs: number = Date.now()): Promise<boolean> {
  const candidate = String(code ?? '').replace(/\D/g, '');
  if (!/^\d{6}$/.test(candidate)) return false;
  for (const drift of [-30000, 0, 30000]) {
    if (candidate === await totpCode(secret, atMs + drift)) return true;
  }
  return false;
}

/** otpauth:// URI for Google Authenticator, Authy, 1Password, etc. */
export function otpauthUri(secret: string, phone: string, issuer = 'DropOff'): string {
  const label = `${issuer}:${phone}`;
  return `otpauth://totp/${encodeURIComponent(label)}?secret=${secret}&issuer=${encodeURIComponent(issuer)}&algorithm=SHA1&digits=6&period=30`;
}
