// Phone OTP login + HS256 JWT helpers (WebCrypto — no dependencies).

interface Env {
  DB: D1Database;
  LIPILA_BASE_URL: string;
  LIPILA_API_KEY: string;
  API_AUTH_KEY: string;
  JWT_SECRET: string;
  ADMIN_AUTH_KEY: string;
  AUTH_DEV_MODE?: string; // "1" = return OTP in response (SMS gateway still to wire)
}

const enc = new TextEncoder();

function b64url(bytes: Uint8Array): string {
  let bin = '';
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function b64urlJson(obj: unknown): string {
  return b64url(enc.encode(JSON.stringify(obj)));
}

async function hmac(data: string, secret: string): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey(
    'raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  );
  return new Uint8Array(await crypto.subtle.sign('HMAC', key, enc.encode(data)));
}

/** sha-256(code + ':' + secret) hex — codes are never stored in clear */
export async function hashOtp(code: string, secret: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', enc.encode(`${code}:${secret}`));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

export function generateOtp(): string {
  // crypto-random, not Math.random — the code is the only possession factor
  const buf = crypto.getRandomValues(new Uint32Array(1));
  return String(100000 + (buf[0] % 900000));
}

/** URL-safe random token for email links (verify / reset). */
export function generateEmailToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(24));
  return [...bytes].map((b) => b.toString(16).padStart(2, '0')).join('');
}

interface JwtPayload { phone: string; exp: number; ver?: number; did?: string } // ver = token_version; did = device id

export async function signJwt(
  phone: string, secret: string, ttlSeconds = 60 * 60 * 24 * 30, ver = 0, deviceId?: string,
): Promise<string> {
  const header = b64urlJson({ alg: 'HS256', typ: 'JWT' });
  const payload = b64urlJson({
    phone,
    exp: Math.floor(Date.now() / 1000) + ttlSeconds,
    ver,
    ...(deviceId ? { did: deviceId } : {}),
  } satisfies JwtPayload);
  const sig = b64url(await hmac(`${header}.${payload}`, secret));
  return `${header}.${payload}.${sig}`;
}

/** Returns the phone if the JWT is valid and unexpired, else null. */
export async function verifyJwt(token: string, secret: string): Promise<string | null> {
  const claims = await verifyJwtClaims(token, secret);
  return claims?.phone ?? null;
}

/** Returns phone + token_version when the JWT is valid and within its expiry
 *  (or within [opts.allowExpiredWithinSeconds] past expiry - used by the refresh
 *  session flow), else null. */
export async function verifyJwtClaims(token: string, secret: string, opts?: { allowExpiredWithinSeconds?: number }): Promise<JwtPayload | null> {
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  const [header, payload, sig] = parts;
  const expected = b64url(await hmac(`${header}.${payload}`, secret));
  if (!constantEq(expected, sig)) return null;
  try {
    const b64 = payload.replace(/-/g, '+').replace(/_/g, '/');
    const json = atob(b64 + '='.repeat((4 - (b64.length % 4)) % 4));
    const data = JSON.parse(json) as JwtPayload;
    const graceMs = (opts?.allowExpiredWithinSeconds ?? 0) * 1000;
    if (!data.phone || data.exp * 1000 < Date.now() - graceMs) return null;
    return data;
  } catch {
    return null;
  }
}

/* ------------------------------ password auth ----------------------------- */
// PBKDF2-SHA256, 100k iterations (Workers runtime caps at 100k), 32-byte hash, random 16-byte salt.
// Stored as: pbkdf2$100000$<saltHex>$<hashHex>

const PBKDF2_ITERATIONS = 100_000;

function toHex(bytes: Uint8Array): string {
  return [...bytes].map((b) => b.toString(16).padStart(2, '0')).join('');
}

function fromHex(hex: string): Uint8Array {
  if (hex.length % 2 !== 0 || /[^0-9a-f]/i.test(hex)) throw new Error('bad hex');
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  return out;
}

async function pbkdf2(password: string, salt: Uint8Array, iterations = PBKDF2_ITERATIONS): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey('raw', enc.encode(password), 'PBKDF2', false, [
    'deriveBits',
  ]);
  const bits = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', hash: 'SHA-256', salt, iterations },
    key,
    256,
  );
  return new Uint8Array(bits);
}

export async function hashPassword(password: string): Promise<string> {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const hash = await pbkdf2(password, salt);
  return `pbkdf2$${PBKDF2_ITERATIONS}$${toHex(salt)}$${toHex(hash)}`;
}

/** Length-independent compare so wrong-password timing doesn't leak. */
function constantEq(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/** Verifies a password against a stored hash. The iteration count is read from
 *  the hash itself (format pbkdf2$<iter>$<salt>$<hash>) so hashes minted with an
 *  older parameter set keep working after PBKDF2_ITERATIONS is raised — a strict
 *  equality check here silently invalidated every existing account login. */
export async function verifyPassword(password: string, stored: string): Promise<boolean> {
  const parts = stored.split('$');
  if (parts.length !== 4) return false;
  const iterations = Number(parts[1]);
  if (!Number.isFinite(iterations) || iterations < 1_000 || iterations > 100_000_000) return false;
  try {
    const hash = await pbkdf2(password, fromHex(parts[2]), iterations);
    return constantEq(toHex(hash), parts[3]);
  } catch {
    return false;
  }
}

/** True when a stored hash uses fewer iterations than the current policy —
 *  re-hash it opportunistically on the next successful login (transparent
 *  upgrade, the password never touches the DB in clear). */
export function passwordNeedsRehash(stored: string): boolean {
  const parts = stored.split('$');
  return parts.length !== 4 || Number(parts[1]) !== PBKDF2_ITERATIONS;
}

export function isValidEmail(email: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email) && email.length <= 254;
}
