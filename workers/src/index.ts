import { Hono } from 'hono';
import { cors } from 'hono/cors';
import {
  Env, Provider, lipilaCollect, lipilaDisburse, lipilaStatus, normalizeZmPhone, providerFromPhone,
} from './lipila';
import {
  generateEmailToken, generateOtp, hashOtp, hashPassword, isValidEmail, signJwt, verifyJwtClaims, verifyPassword,
} from './auth';
import { collectionFees, computeJobTotals, MOMO_COLLECTION_FEE, platformFee, round2 } from './fees';
import { baseRiderFee, haversineKm as haversine, tierOverageFee, VEHICLE_CLASSES, VEHICLE_MAX_PARCELS, VehicleClass } from './pricing';
import { resetEmailHtml, sendMail, verifyEmailHtml } from './mail';
import { sendSms } from './sms';
import { sendToPhone } from './push';
import {
  clientIp, deviceId, userAgent, ownerPhone, ownerEmail,
  lockoutStatus, recordAttempt, noteDevice, alertOwner, raiseAlert, acknowledgeAlert,
} from './security';
import { ChatRoom } from './chat_do';

export { ChatRoom };

const app = new Hono<{ Bindings: Env; Variables: { phone?: string; role?: 'customer' | 'partner' | 'ops'; courierId?: number; reqId?: string } }>();

/* ------------------------- seller subscription packs ----------------------- */
// Silver (K350/mo, 1 parcel/day) / Gold (K700/mo, 3) / Platinum (K1500/mo, 10),
// each with one guaranteed daily sweep window (6am / 10am / 2pm). Inside the
// pack the SENDER pays no rider fee (bundled); Sweep riders are paid a flat
// per-parcel wage; pay-as-you-go riders keep 90% of the fee (platform take 10%).
type PlanTier = 'silver' | 'gold' | 'platinum';
interface PlanDef { fee_zmw: number; windows: string[]; parcels_per_day: number; parcels_per_month: number; rider_fee_zmw: number; overage_discount_pct: number; cycle_days: number; tag?: string | null }
// Editable live in D1 via /admin/tiers. These are the fallback/seed values.
// One trip (booking) consumes ONE plan slot no matter how many parcels are in it.
// Cycle is 30 days from activation; overage keeps the tier discount off PAYG.
const PLANS: Record<PlanTier, PlanDef> = {
  silver: { fee_zmw: 250, windows: ['06:00', '10:00', '14:00'], parcels_per_day: 0, parcels_per_month: 10, rider_fee_zmw: 0, overage_discount_pct: 15, cycle_days: 30 },
  gold:   { fee_zmw: 500, windows: ['06:00', '10:00', '14:00'], parcels_per_day: 0, parcels_per_month: 25, rider_fee_zmw: 0, overage_discount_pct: 25, cycle_days: 30 },
  platinum: { fee_zmw: 750, windows: ['06:00', '10:00', '14:00'], parcels_per_day: 0, parcels_per_month: 50, rider_fee_zmw: 0, overage_discount_pct: 35, cycle_days: 30 },
};

/** DB-backed catalogue (price, per-day cap, tag) â€” constants only as fallback. */
async function plans(db: D1Database): Promise<Record<PlanTier, PlanDef>> {
  const merged: Record<PlanTier, PlanDef> = {
    silver: { ...PLANS.silver, tag: null },
    gold: { ...PLANS.gold, tag: null },
    platinum: { ...PLANS.platinum, tag: null },
  };
  try {
  const { results } = await db.prepare('SELECT tier, fee_zmw, parcels_per_day, parcels_per_month, rider_fee_zmw, overage_discount_pct, cycle_days, tag FROM tiers WHERE active = 1').all();
  for (const row of results as any[]) {
    const key = row.tier as PlanTier;
    if (merged[key]) {
      merged[key] = {
        ...merged[key],
        fee_zmw: Number(row.fee_zmw),
        parcels_per_day: Number(row.parcels_per_day),
        parcels_per_month: Number(row.parcels_per_month),
        rider_fee_zmw: Number(row.rider_fee_zmw),
        overage_discount_pct: Number(row.overage_discount_pct),
        cycle_days: Number(row.cycle_days),
        tag: row.tag ?? null,
      };
    }
  }
  } catch { /* tiers table not migrated yet â€” constants rule */ }
  return merged;
}
const PLATFORM_TAKE = 0.10;           // of the rider fee, on pay-as-you-go
const PACK_RIDER_PAY_ZMW = 5;         // rider wage per swept pack parcel (density wage)
const PICKUP_WINDOWS = ['now', '06:00', '10:00', '14:00'];
// Business day = Central Africa Time (UTC+2). D1's 'localtime' is UTC, so every
// daily-cap / sweep query must use this explicit offset or the day rolls over
// at 02:00 CAT instead of midnight.
const CAT_OFFSET = '+2 hours';
const COD_FEE = 0.02;                 // platform cut on cash-on-delivery receipts
const WALLET_TOPUP_CAP_ZMW = 5000;

// Payment fees: the customer pays the DropOff leg + platform fee + Lipila legs.
// The courier's counter fare is paid at the depot and is NEVER collected by DropOff.

// Pay-as-you-go rider fee bands (raised to K45 base â€” always cheaper than the
// courier's own counter fare, which starts at K50 on most Platinum routes).
// Waiting / queue time: rider logs minutes; first 10 free, K2/min, K50 cap.
const WAIT_FREE_MINUTES = 10;
const WAIT_RATE_PER_MIN = 2;
const WAIT_CAP_ZMW = 50;

function waitFeeFor(minutes: number): number {
  if (!Number.isFinite(minutes) || minutes <= 0) return 0;
  return Math.min(WAIT_CAP_ZMW, Math.round(Math.max(0, minutes - WAIT_FREE_MINUTES) * WAIT_RATE_PER_MIN));
}

/* --------------------------- request tracing/logs -------------------------- */
// Every response carries X-Request-Id and emits one JSON access log line so
// Workers Logs / Logpush can query p50/p95 latency and error rates. Errors are
// also forwarded to Sentry when SENTRY_DSN is configured.
app.use('*', async (c, next) => {
  const reqId = c.req.header('CF-Ray') ?? crypto.randomUUID();
  c.set('reqId', reqId);
  const start = Date.now();
  try {
    await next();
  } finally {
    c.header('X-Request-Id', reqId);
    const ms = Date.now() - start;
    const line = {
      t: new Date().toISOString(), level: c.res.status >= 500 ? 'error' : c.res.status >= 400 ? 'warn' : 'info',
      req_id: reqId, method: c.req.method, path: c.req.path, status: c.res.status, ms,
      ip: c.req.header('CF-Connecting-IP') ?? null,
    };
    const msg = JSON.stringify(line);
    if (c.res.status >= 500) console.error(msg);
    else if (c.res.status >= 400) console.warn(msg);
    else console.log(msg);
  }
});

/* ------------------------------- auth guard ------------------------------- */
// Identity tiers:
//   customer  Bearer JWT (email+password or phone OTP) - senders/pay go & pack sellers
//   partner   Bearer JWT with role=partner - courier shop console (prices + ride confirm)
//   ops       X-Api-Key - rider-device service + ops console
//   admin     X-Admin-Key - superadmin pricebook / partner management (below)
// Public without auth: /health, /auth/*, /webhooks/*, /plans, courier profiles, //console pages.
const PUBLIC_GETS = new Set(['/health', '/couriers', '/cities', '/plans', '/console', '/partner/console', '/promo/check']);
app.use('*', async (c, next) => {
  const p = c.req.path;
  if (p === '/health' || p.startsWith('/auth/') || p.startsWith('/webhooks')) return next();
  if (p.startsWith('/track/')) return next(); // token IS the credential (GET page + token chat)
  const isPublicGet = c.req.method === 'GET' && (PUBLIC_GETS.has(p) || /^\/couriers\/\d+\/profile$/.test(p));
  if (isPublicGet) return next();

  const bearer = (c.req.header('Authorization') ?? '').replace(/^Bearer\s+/, '');
  if (bearer) {
    const claims = await verifyJwtClaims(bearer, c.env.JWT_SECRET);
    if (claims) {
      // role and token_version live on the account row â€” a password reset bumps
      // token_version, instantly invalidating every outstanding session
      const user = await c.env.DB.prepare(
        'SELECT role, courier_id, token_version FROM auth_users WHERE phone = ?1',
      ).bind(claims.phone).first<any>();
      if (user && Number(user.token_version ?? 0) !== Number(claims.ver ?? 0)) {
        return c.json({ error: 'session_revoked' }, 401);
      }
      c.set('phone', claims.phone);
      // The app owner's phone is always admin (OWNER_PHONE secret) — covers
      // OTP-only sign-ins that have no auth_users row.
      c.set('role', user?.role === 'partner' || user?.role === 'admin' ? user.role
        : claims.phone === ownerPhone(c.env) ? 'admin' : 'customer');
      if (user?.courier_id) c.set('courierId', user.courier_id);
      return next();
    }
  }
  if (c.req.header('X-Api-Key') === c.env.API_AUTH_KEY) {
    c.set('role', 'ops');
    return next();
  }
  // admin key authorizes /admin/* directly (owner console): the route-level
  // /admin/* guard still re-checks it below.
  if (/^\/admin\//.test(p) && c.req.header('X-Admin-Key') === c.env.ADMIN_AUTH_KEY) {
    c.set('role', 'ops');
    return next();
  }
  return c.json({ error: 'unauthorized' }, 401);
});

const isAdmin = (c: { env: Env; req: { header: (k: string) => string | undefined }; get?: (k: string) => unknown }) =>
  c.req.header('X-Admin-Key') === c.env.ADMIN_AUTH_KEY
  || (typeof c.get === 'function' && c.get('role') === 'admin')
  || (typeof c.get === 'function' && c.get('phone') === ownerPhone(c.env));

const isOwner = (c: { env: Env; get?: (k: string) => unknown }) =>
  Boolean(typeof c.get === 'function' && c.get('phone') && c.get('phone') === ownerPhone(c.env));

/** Naive per-IP throttle in D1 (e.g. 20 auth requests / hour / ip). */
async function rateLimited(
  c: { env: { DB: D1Database }; req: { header: (k: string) => string | undefined } },
  bucket: string, max = 20, minutes = 60,
): Promise<boolean> {
  const ip = c.req.header('CF-Connecting-IP') ?? 'unknown';
  const key = `ip:${ip}:${bucket}`;
  const n = (await c.env.DB.prepare(
    `SELECT COUNT(*) AS n FROM rate_hits WHERE key = ?1 AND created_at > datetime('now', ?2)`,
  ).bind(key, `-${minutes} minutes`).first<any>())?.n ?? 0;
  await c.env.DB.prepare('INSERT INTO rate_hits (key) VALUES (?1)').bind(key).run();
  return n >= max;
}

const devModeOn = (env: { AUTH_DEV_MODE?: string }) =>
  ['1', 'true', 'yes'].includes(String(env.AUTH_DEV_MODE ?? '').toLowerCase());

/* ------------------------------- fraud score ------------------------------ */
// Heuristic, not a verdict: velocity + duplicate pattern + high value + new
// account. Score >= 3 flags the job for ops review; it is never auto-cancelled
// here, because a false positive would strand a real parcel.
async function scoreJobFraud(
  env: Env, phone: string, jobId: number, ref: string,
  recipientPhone: string, pickupAddress: string, total: number,
): Promise<{ score: number; reasons: string[] }> {
  const reasons: string[] = [];
  let score = 0;
  const n1h = (await env.DB.prepare(
    `SELECT COUNT(*) AS n FROM jobs WHERE sender_phone = ?1 AND created_at > datetime('now', '-1 hour')`,
  ).bind(phone).first<any>())?.n ?? 0;
  if (n1h >= 5) { score += 2; reasons.push('velocity_1h'); }
  const n24h = (await env.DB.prepare(
    `SELECT COUNT(*) AS n FROM jobs WHERE sender_phone = ?1 AND created_at > datetime('now', '-1 day')`,
  ).bind(phone).first<any>())?.n ?? 0;
  if (n24h >= 20) { score += 2; reasons.push('velocity_24h'); }
  const dup = (await env.DB.prepare(
    `SELECT COUNT(*) AS n FROM jobs
      WHERE sender_phone = ?1 AND recipient_phone = ?2 AND pickup_address = ?3
        AND id <> ?4 AND created_at > datetime('now', '-6 hours')`,
  ).bind(phone, recipientPhone, pickupAddress, jobId).first<any>())?.n ?? 0;
  if (dup >= 1) { score += 3; reasons.push('duplicate_pattern'); }
  const acct = await env.DB.prepare('SELECT created_at FROM auth_users WHERE phone = ?1')
    .bind(phone).first<any>();
  const joined = acct?.created_at ? Date.parse(`${acct.created_at}Z`) : NaN;
  if (Number.isFinite(joined) && Date.now() - joined < 3_600_000) { score += 1; reasons.push('new_account'); }
  if (total >= 2000) { score += 2; reasons.push('high_value'); }
  if (recipientPhone === phone) { score += 1; reasons.push('self_delivery'); }
  if (score >= 3) {
    await env.DB.batch([
      env.DB.prepare('UPDATE jobs SET review_required = 1, fraud_score = ?2 WHERE id = ?1')
        .bind(jobId, score),
      env.DB.prepare(
        'INSERT INTO fraud_flags (job_id, job_ref, phone, score, reasons) VALUES (?1, ?2, ?3, ?4, ?5)',
      ).bind(jobId, ref, phone, score, reasons.join(',')),
    ]);
  }
  return { score, reasons };
}

/* ------------------------------ tracking links ---------------------------- */
// Recipients get a no-account public link (SMS/WhatsApp). Tokens are random and
// scoped to one job; the public page exposes status/live location only.
function secureToken(bytes = 18): string {
  const b = new Uint8Array(bytes);
  crypto.getRandomValues(b);
  return [...b].map((x) => x.toString(16).padStart(2, '0')).join('');
}

async function issueTrackingToken(env: Env, jobId: number, jobRef: string, phone: string | null): Promise<string> {
  const token = secureToken(18);
  await env.DB.prepare(
    'INSERT INTO tracking_tokens (token, job_id, job_ref, phone) VALUES (?1, ?2, ?3, ?4)',
  ).bind(token, jobId, jobRef, phone).run();
  return token;
}

const trackingUrl = (env: Env, token: string) =>
  `${(env.APP_URL ?? '').replace(/\/$/, '')}/track/${token}`;

/* ------------------------------ idempotency ------------------------------- */
// Clients retry on flaky networks; the same Idempotency-Key must replay the
// first response instead of creating a second job / mobile-money collect.
const idemKeyOf = (c: any, body: any): string | null => {
  const raw = c.req.header('Idempotency-Key') ?? body?.idempotency_key ?? '';
  const key = String(raw).trim();
  return key ? key.slice(0, 160) : null;
};

async function replayIdempotent(c: any, key: string | null, scope: string) {
  if (!key) return null;
  const row: any = await c.env.DB.prepare(
    'SELECT scope, status, response FROM idempotency_keys WHERE key = ?1',
  ).bind(key).first();
  if (!row || row.scope !== scope) return null;
  try { return c.json(JSON.parse(row.response), row.status); } catch { return null; }
}

async function saveIdempotent(
  env: Env, key: string | null, scope: string, phone: string | null, status: number, payload: unknown,
): Promise<void> {
  if (!key) return;
  await env.DB.prepare(
    `INSERT OR IGNORE INTO idempotency_keys (key, scope, phone, status, response)
     VALUES (?1, ?2, ?3, ?4, ?5)`,
  ).bind(key, scope, phone, status, JSON.stringify(payload)).run().catch(() => {});
}

/* --------------------------------- cors ----------------------------------- */
// Narrow CORS: only origins listed in the CORS_ORIGINS var (comma-separated) may
// call the API cross-origin â€” lets the Flutter-web admin build work without
// opening the API to every website. Same-origin calls (the HTML consoles) need
// no CORS at all. Set CORS_ORIGINS="" (default) to disable cross-origin entirely.
const corsOrigins = (raw: string | undefined): string[] =>
  (raw ?? '').split(',').map((s) => s.trim()).filter(Boolean);
app.use('*', (c, next) => {
  const allow = corsOrigins(c.env.CORS_ORIGINS);
  if (!allow.length) return next();
  return cors({
    origin: (o) => (allow.includes(o) ? o : null),
    allowHeaders: ['Content-Type', 'Authorization', 'X-Api-Key', 'X-Admin-Key'],
    allowMethods: ['GET', 'POST', 'DELETE', 'OPTIONS'],
    maxAge: 86400,
  })(c, next);
});

/* --------------------------------- edge cache ------------------------------ */
// Quasi-static read endpoints get browser/CDN cache so Zambian users never
// re-fetch the same couriers/quotes/cities/plans on every app open.
const cacheFor = (seconds: number) => async (c: any, next: any) => {
  await next();
  if (c.res.status >= 400) return;
  c.header('Cache-Control', `public, max-age=${seconds}, s-maxage=${seconds}, stale-while-revalidate=0`);
  c.header('Vary', 'Accept-Encoding');
};

// Only genuinely shared, non-personal data is cacheable. Everything else —
// jobs, wallet, partner keys, referrals, ratings, rider routes — is private and
// must never be stored by a browser or proxy (stale + privacy risk).
const PUBLIC_CACHEABLE = /^\/(health|cities|couriers(\/[^/]+(\/profile)?)?|quotes|plans)$/;
app.use('*', async (c, next) => {
  await next();
  if (c.req.method !== 'GET') return;
  if (!PUBLIC_CACHEABLE.test(c.req.path)) c.header('Cache-Control', 'private, no-store');
});

app.use('GET /health', cacheFor(15));
app.use('GET /cities', cacheFor(300));
app.use('GET /couriers', cacheFor(30));
app.use('GET /couriers/*', cacheFor(30));
app.use('GET /quotes', cacheFor(30));
app.use('GET /plans', cacheFor(30));

/* --------------------------------- health --------------------------------- */
app.get('/health', (c) => c.json({ ok: true, ts: Date.now() }));

// Identity for the signed-in caller — the app uses this to reveal admin/ops
// surfaces (the owner's phone is admin via OWNER_PHONE middleware grant).
app.get('/me', (c) => c.json({ phone: c.get('phone') ?? null, role: c.get('role') ?? null }));

/* ------------------------------ phone OTP auth ---------------------------- */
// POST /auth/request {phone}   -> { sent: true, dev_code? }
// POST /auth/verify {phone, code} -> { token }  (JWT, 30 days)
app.post('/auth/request', async (c) => {
  if (await rateLimited(c, 'otp_request', 20)) return c.json({ error: 'too_many_requests' }, 429);
  const b: any = await c.req.json().catch(() => null);
  if (!b) return c.json({ error: 'invalid JSON body' }, 400);
  let phone: string;
  try { phone = normalizeZmPhone(b.phone); } catch (e: any) { return c.json({ error: e.message }, 400); }

  // naive throttle: max 5 codes per phone per hour
  const recent = await c.env.DB.prepare(
    `SELECT COUNT(*) AS n FROM otp_codes WHERE phone = ?1 AND created_at > datetime('now', '-1 hour')`,
  ).bind(phone).first<any>();
  if ((recent?.n ?? 0) >= 5) return c.json({ error: 'too_many_codes_wait_an_hour' }, 429);

  const code = generateOtp();
  const hash = await hashOtp(code, c.env.JWT_SECRET);
  await c.env.DB.batch([
    c.env.DB.prepare('UPDATE otp_codes SET used = 1 WHERE phone = ?1 AND used = 0').bind(phone),
    c.env.DB.prepare(
      `INSERT INTO otp_codes (phone, code_hash, expires_at) VALUES (?1, ?2, datetime('now', '+10 minutes'))`,
    ).bind(phone, hash),
  ]);
  // deliver via Africa's Talking (Carpso account) when AT_* secrets are set;
  // dev mode returns the code in the response
  const sms = await sendSms(c.env, phone,
    `DropOff: your one-time code is ${code}. It expires in 10 minutes. For your security, never share this code with anyone — DropOff staff will never ask for it.`);
  const devMode = devModeOn(c.env);
  return c.json({
    sent: sms.sent, ...(sms.error ? { sms_error: sms.error } : {}),
    ...(devMode ? { dev_code: code } : {}),
  });
});

app.post('/auth/verify', async (c) => {
  if (await rateLimited(c, 'otp_verify', 30)) return c.json({ error: 'too_many_requests' }, 429);
  const b: any = await c.req.json().catch(() => null);
  if (!b) return c.json({ error: 'invalid JSON body' }, 400);
  let phone: string;
  try { phone = normalizeZmPhone(b.phone); } catch (e: any) { return c.json({ error: e.message }, 400); }
  const row = await c.env.DB.prepare(
    `SELECT id, code_hash, attempts FROM otp_codes
      WHERE phone = ?1 AND used = 0 AND expires_at > datetime('now')
      ORDER BY id DESC LIMIT 1`,
  ).bind(phone).first<any>();
  if (!row) return c.json({ error: 'code_expired_or_missing' }, 401);
  // brute-force guard: 5 wrong attempts burn the code (6-digit space is finite)
  if (Number(row.attempts ?? 0) >= 5) {
    await c.env.DB.prepare('UPDATE otp_codes SET used = 1 WHERE id = ?1').bind(row.id).run();
    return c.json({ error: 'code_expired_or_missing' }, 401);
  }
  const hash = await hashOtp(String(b.code ?? ''), c.env.JWT_SECRET);
  if (hash !== row.code_hash) {
    await c.env.DB.prepare('UPDATE otp_codes SET attempts = attempts + 1 WHERE id = ?1').bind(row.id).run();
    return c.json({ error: 'wrong_code' }, 401);
  }
  await c.env.DB.prepare('UPDATE otp_codes SET used = 1 WHERE id = ?1').bind(row.id).run();
  // JWT carries token_version 0 (a password reset on auth_users bumps it later)
  const token = await signJwt(phone, c.env.JWT_SECRET);
  return c.json({ ok: true, token, phone });
});

/* --------------------------- email + password auth ------------------------ */
// POST /auth/register {email, password, phone, full_name?} -> { token, ... }
// POST /auth/login    {email, password}                    -> { token, ... }
// JWT identity stays the phone so jobs/payments/wallets need no changes.
app.post('/auth/register', async (c) => {
  if (await rateLimited(c, 'register', 10)) return c.json({ error: 'too_many_requests' }, 429);
  const b: any = await c.req.json().catch(() => null);
  if (!b) return c.json({ error: 'invalid JSON body' }, 400);

  const email = String(b.email ?? '').trim().toLowerCase();
  const password = String(b.password ?? '');
  const fullName = b.full_name != null ? String(b.full_name).trim() : null;
  if (!isValidEmail(email)) return c.json({ error: 'invalid_email' }, 400);
  if (password.length < 8) return c.json({ error: 'password_too_short_min_8' }, 400);
  let phone: string;
  try { phone = normalizeZmPhone(b.phone); } catch (e: any) { return c.json({ error: e.message }, 400); }

  const clash = await c.env.DB.prepare(
    `SELECT email, phone FROM auth_users WHERE email = ?1 OR phone = ?2 LIMIT 1`,
  ).bind(email, phone).first<any>();
  if (clash) {
    return c.json(
      { error: clash.email === email ? 'email_already_registered' : 'phone_already_used' },
      409,
    );
  }

  const passwordHash = await hashPassword(password);
  await c.env.DB.batch([
    c.env.DB.prepare(
      `INSERT INTO auth_users (email, password_hash, phone, full_name) VALUES (?1, ?2, ?3, ?4)`,
    ).bind(email, passwordHash, phone, fullName),
    // seed the momo identity so topups/payouts resolve on day one
    c.env.DB.prepare(
      `INSERT OR IGNORE INTO wallets (phone, balance_zmw) VALUES (?1, 0)`,
    ).bind(phone),
  ]);

  // verification email (non-blocking: the account works immediately)
  const verifyLink = await createEmailLink(c, email, 'verify_email');
  const mail = verifyLink ? await sendMail(c.env, {
    to: email, subject: 'Confirm your DropOff email',
    html: verifyEmailHtml(verifyLink), text: `Confirm your DropOff email: ${verifyLink}`,
  }) : { sent: false, error: 'no_link' };

  const token = await signJwt(phone, c.env.JWT_SECRET);
  const devMode = devModeOn(c.env);
  return c.json({
    ok: true, token, email, phone, full_name: fullName,
    verification_sent: mail.sent, ...(mail.error ? { mail_error: mail.error } : {}),
    ...(devMode && verifyLink ? { dev_verify_link: verifyLink } : {}),
  }, 201);
});

/* -------- email links: verify + reset (token is passed through email) ------ */
async function createEmailLink(
  c: { env: Env; req: { url: string } },
  email: string, kind: 'verify_email' | 'reset_password',
): Promise<string | null> {
  const token = generateEmailToken();
  const hash = await hashOtp(token, c.env.JWT_SECRET);
  const ttl = kind === 'verify_email' ? '+24 hours' : '+1 hour';
  await c.env.DB.batch([
    c.env.DB.prepare('UPDATE email_tokens SET used = 1 WHERE email = ?1 AND kind = ?2 AND used = 0')
      .bind(email, kind),
    c.env.DB.prepare(
      `INSERT INTO email_tokens (email, token_hash, kind, expires_at) VALUES (?1, ?2, ?3, datetime('now', ?4))`,
    ).bind(email, hash, kind, ttl),
  ]);
  // Hono exposes `c.req.url` as a property (Request.url), NOT a function â€”
  // calling it threw TypeError and 500'd register/forgot/resend.
  const origin = new URL(c.req.url).origin;
  const base = String(c.env.APP_URL ?? '').replace(/\/$/, '') || origin;
  return `${base}/auth/link?k=${kind}&t=${encodeURIComponent(token)}`;
}

/** HTML confirm pages (public GET; the token is the only secret). */
app.get('/auth/link', async (c) => {
  const kind = c.req.query('k');
  const token = c.req.query('t') ?? '';
  const fail = (msg: string) => c.html(`<div style="font-family:sans-serif;max-width:420px;margin:80px auto;text-align:center">
    <h2>DropOff</h2><p>${msg}</p></div>`, 400);
  if (!token || (kind !== 'verify_email' && kind !== 'reset_password')) return fail('Invalid link.');
  const hash = await hashOtp(token, c.env.JWT_SECRET);
  const row = await c.env.DB.prepare(
    `SELECT id, email FROM email_tokens WHERE token_hash = ?1 AND kind = ?2 AND used = 0 AND expires_at > datetime('now')`,
  ).bind(hash, kind).first<any>();
  if (!row) return fail('This link expired or was already used.');

  if (kind === 'verify_email') {
    await c.env.DB.batch([
      c.env.DB.prepare('UPDATE email_tokens SET used = 1 WHERE id = ?1').bind(row.id),
      c.env.DB.prepare('UPDATE auth_users SET email_verified = 1 WHERE email = ?1').bind(row.email),
    ]);
    return c.html(`<div style="font-family:sans-serif;max-width:420px;margin:80px auto;text-align:center">
      <h2>âœ… Email confirmed</h2><p>${row.email} is now verified. You can close this page.</p></div>`);
  }

  // reset_password: serve the choose-new-password form
  return c.html(`<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
    <title>DropOff â€” new password</title>
    <style>body{font-family:sans-serif;max-width:420px;margin:60px auto;padding:0 16px}
    input,button{display:block;width:100%;padding:12px;margin:8px 0;border-radius:10px;border:1px solid #cfd8d4;font-size:15px}
    button{background:#17855f;color:#fff;border:0;font-weight:700}</style></head><body>
    <h2>Choose a new password</h2><p id="msg"></p>
    <form id="f"><input id="p" type="password" minlength="8" placeholder="New password (8+ chars)" required><button>Save password</button></form>
    <script>
    const t = ${JSON.stringify(token)};
    document.getElementById('f').onsubmit = async (e) => {
      e.preventDefault();
      const r = await fetch('/auth/reset', { method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-Api-Key': 'webform' },
        body: JSON.stringify({ token: t, password: document.getElementById('p').value }) });
      const m = document.getElementById('msg');
      m.textContent = r.ok ? 'Password saved â€” you can sign in in the app now.' : 'Link expired. Request a new one in the app.';
      m.style.color = r.ok ? '#17855f' : '#b3261e';
    };</script></body></html>`);
});

/** The reset form posts here; guarded by the token itself (sent by email). */
app.post('/auth/reset', async (c) => {
  if (await rateLimited(c, 'reset', 10)) return c.json({ error: 'too_many_requests' }, 429);
  const b: any = await c.req.json().catch(() => null);
  const token = String(b?.token ?? '');
  const password = String(b?.password ?? '');
  if (password.length < 8) return c.json({ error: 'password_too_short_min_8' }, 400);
  const hash = await hashOtp(token, c.env.JWT_SECRET);
  const row = await c.env.DB.prepare(
    `SELECT id, email FROM email_tokens WHERE token_hash = ?1 AND kind = 'reset_password'
      AND used = 0 AND expires_at > datetime('now')`,
  ).bind(hash).first<any>();
  if (!row) return c.json({ error: 'link_expired_or_used' }, 401);
  const passwordHash = await hashPassword(password);
  await c.env.DB.batch([
    c.env.DB.prepare('UPDATE email_tokens SET used = 1 WHERE id = ?1').bind(row.id),
    // token_version++ revokes every outstanding JWT for this account (middleware re-checks it)
    c.env.DB.prepare(
      'UPDATE auth_users SET password_hash = ?2, token_version = COALESCE(token_version, 0) + 1 WHERE email = ?1',
    ).bind(row.email, passwordHash),
  ]);
  return c.json({ ok: true });
});

app.post('/auth/forgot', async (c) => {
  if (await rateLimited(c, 'forgot', 10)) return c.json({ error: 'too_many_requests' }, 429);
  const b: any = await c.req.json().catch(() => null);
  const email = String(b?.email ?? '').trim().toLowerCase();
  if (!isValidEmail(email)) return c.json({ error: 'invalid_email' }, 400);
  const user = await c.env.DB.prepare(
    'SELECT email FROM auth_users WHERE email = ?1',
  ).bind(email).first<any>();
  // never leak whether the email exists
  if (!user) return c.json({ ok: true, sent: true });
  const link = await createEmailLink(c, email, 'reset_password');
  if (!link) return c.json({ ok: true, sent: true });
  const mail = await sendMail(c.env, {
    to: email, subject: 'Reset your DropOff password',
    html: resetEmailHtml(link), text: `Reset your DropOff password: ${link} (valid 1 hour)`,
  });
  const devMode = devModeOn(c.env);
  return c.json({ ok: true, sent: mail.sent, ...(mail.error ? { mail_error: mail.error } : {}),
    ...(devMode ? { dev_reset_link: link } : {}) });
});

app.post('/auth/resend-verification', async (c) => {
  if (await rateLimited(c, 'verify', 10)) return c.json({ error: 'too_many_requests' }, 429);
  const b: any = await c.req.json().catch(() => null);
  const email = String(b?.email ?? '').trim().toLowerCase();
  if (!isValidEmail(email)) return c.json({ error: 'invalid_email' }, 400);
  const user = await c.env.DB.prepare(
    'SELECT email_verified FROM auth_users WHERE email = ?1',
  ).bind(email).first<any>();
  if (!user) return c.json({ ok: true, sent: true });
  if (user.email_verified) return c.json({ ok: true, sent: true, already_verified: true });
  const link = await createEmailLink(c, email, 'verify_email');
  if (!link) return c.json({ ok: true, sent: true });
  const mail = await sendMail(c.env, {
    to: email, subject: 'Confirm your DropOff email',
    html: verifyEmailHtml(link), text: `Confirm your DropOff email: ${link}`,
  });
  const devMode = devModeOn(c.env);
  return c.json({ ok: true, sent: mail.sent, ...(mail.error ? { mail_error: mail.error } : {}),
    ...(devMode ? { dev_verify_link: link } : {}) });
});

app.post('/auth/login', async (c) => {
  if (await rateLimited(c, 'login', 20)) return c.json({ error: 'too_many_requests' }, 429);
  const b: any = await c.req.json().catch(() => null);
  if (!b) return c.json({ error: 'invalid JSON body' }, 400);
  const email = String(b.email ?? '').trim().toLowerCase();
  const password = String(b.password ?? '');
  if (!isValidEmail(email) || !password) return c.json({ error: 'invalid_credentials' }, 401);

  const ip = clientIp(c);
  const ua = userAgent(c);
  const devId = deviceId(c);

  const locked = await lockoutStatus(c.env.DB, email);
  if (locked.lockedUntil) {
    await recordAttempt(c.env.DB, email, false, ip, ua, devId);
    return c.json({ error: 'account_locked', locked_until: locked.lockedUntil }, 429);
  }

  const user = await c.env.DB.prepare(
    `SELECT password_hash, phone, full_name, token_version FROM auth_users WHERE email = ?1`,
  ).bind(email).first<any>();
  const ok = user ? await verifyPassword(password, user.password_hash) : false;
  if (!user || !ok) {
    const res = await recordAttempt(c.env.DB, email, false, ip, ua, devId);
    if (res.lockUntilMinutes) {
      await alertOwner(c.env, email, 'brute_force', 'high',
        `${res.lockUntilMinutes}-minute lockout after repeated failed logins for ${email} from ${ip}.`,
        { ip, device: devId, userAgent: ua, email });
    }
    return c.json({ error: 'invalid_credentials' }, 401);
  }

  // successful login — fingerprint the device and alert the owner on a new device
  await recordAttempt(c.env.DB, email, true, ip, ua, devId);
  const phone = user.phone;
  const dev = await noteDevice(c.env.DB, phone, devId, ip);
  if (dev.isNew) {
    await alertOwner(c.env, phone, 'new_device', 'medium',
      `New device signed in to ${email}.`,
      { ip, device: devId, userAgent: ua, email });
  }

  const token = await signJwt(phone, c.env.JWT_SECRET, 60 * 60 * 24 * 30, Number(user.token_version ?? 0));
  return c.json({ ok: true, token, email, phone, full_name: user.full_name });
});

/* -------------------------- security / owner alerts ------------------------ */
app.get('/security/alerts', async (c) => {
  if (!isAdmin(c) && !isOwner(c)) return c.json({ error: 'forbidden' }, 403);
  const onlyUnacked = c.req.query('unacknowledged') === '1';
  const { results } = await c.env.DB.prepare(
    `SELECT id, phone, type, severity, detail, acknowledged, created_at
       FROM security_alerts
       ${onlyUnacked ? 'WHERE acknowledged = 0' : ''}
      ORDER BY created_at DESC LIMIT 100`,
  ).all();
  return c.json({ alerts: results });
});

app.post('/security/alerts/:id/ack', async (c) => {
  if (!isAdmin(c) && !isOwner(c)) return c.json({ error: 'forbidden' }, 403);
  const id = Number(c.req.param('id'));
  if (!Number.isFinite(id)) return c.json({ error: 'invalid id' }, 400);
  const ok = await acknowledgeAlert(c.env.DB, id);
  return c.json({ ok });
});

app.get('/security/sessions', async (c) => {
  if (!isAdmin(c) && !isOwner(c)) return c.json({ error: 'forbidden' }, 403);
  const phone = c.get('phone') as string | undefined;
  const target = phone ?? ownerPhone(c.env);
  if (!target) return c.json({ error: 'owner_phone_not_configured' }, 400);
  const { results } = await c.env.DB.prepare(
    `SELECT id, device_id, ip, first_seen, last_seen, trusted FROM device_sessions
      WHERE phone = ?1 ORDER BY last_seen DESC`,
  ).bind(target).all();
  return c.json({ phone: target, sessions: results });
});

/* -------------------------------- couriers -------------------------------- */
app.get('/couriers', async (c) => {
  const { results } = await c.env.DB.prepare(
    `SELECT co.id, co.name, co.city, co.depot_name, co.lat, co.lng, co.website, co.price_status, co.note, co.logo_url,
            pp.rail AS payment_rail, pp.merchant_id AS payment_merchant, pp.instructions AS payment_instructions,
            (SELECT ROUND(AVG(stars), 1) FROM ratings r
              WHERE r.target_type = 'courier' AND r.target_key = 'courier:' || co.id AND r.hidden = 0) AS rating_average,
            (SELECT COUNT(*) FROM ratings r
              WHERE r.target_type = 'courier' AND r.target_key = 'courier:' || co.id AND r.hidden = 0) AS rating_count
       FROM couriers co
       LEFT JOIN partner_pos pp ON pp.courier_id = co.id AND pp.active = 1
      WHERE co.active = 1 ORDER BY co.name`,
  ).all();
  return c.json({ couriers: results });
});

// Public partner profile: verified rates come straight from the quotes chargebook
app.get('/couriers/:id/profile', async (c) => {
  const id = Number(c.req.param('id'));
  const courier = await c.env.DB.prepare(
    `SELECT id, name, city, depot_name, lat, lng, website, price_status, note
       FROM couriers WHERE id = ?1 AND active = 1`,
  ).bind(id).first();
  if (!courier) return c.json({ error: 'not found' }, 404);
  const { results: rates } = await c.env.DB.prepare(
    `SELECT from_city, to_city, weight_class, service, counter_price_zmw, updated_at
       FROM quotes WHERE courier_id = ?1 ORDER BY from_city, to_city, service`,
  ).bind(id).all();
  const rating = await c.env.DB.prepare(
    `SELECT COUNT(*) AS count, ROUND(AVG(stars), 2) AS average
       FROM ratings WHERE target_type = 'courier' AND target_key = ?1`,
  ).bind(`courier:${id}`).first<any>();
  const { results: reviews } = await c.env.DB.prepare(
    `SELECT stars, comment, verified, created_at FROM ratings
      WHERE target_type = 'courier' AND target_key = ?1 AND hidden = 0 AND comment IS NOT NULL AND comment <> ''
      ORDER BY id DESC LIMIT 10`,
  ).bind(`courier:${id}`).all();
  return c.json({
    courier, rates,
    rating: { count: rating?.count ?? 0, average: rating?.average ?? null, reviews },
  });
});

/* --------------------------------- quotes --------------------------------- */
app.get('/quotes', async (c) => {
  const fromCity = c.req.query('from') ?? 'Lusaka';
  const toCity = c.req.query('to') ?? '';
  const service = c.req.query('service') ?? 'standard';
  const destLat = Number(c.req.query('dest_lat') ?? '0');
  const destLng = Number(c.req.query('dest_lng') ?? '0');
  if (!toCity) return c.json({ error: 'missing "to"' }, 400);

  const { results } = await c.env.DB.prepare(
    `SELECT q.*, co.id AS courier_id, co.name AS courier_name, co.depot_name
       FROM quotes q JOIN couriers co ON co.id = q.courier_id
      WHERE q.from_city = ?1 AND q.to_city = ?2 AND q.service = ?3`,
  ).bind(fromCity, toCity, service).all();

  const riderFee = baseRiderFee(fromCity, destLat, destLng);
  const leg2 = c.req.query('leg2') === '1';
  // Last-mile door delivery is priced like first-mile PAYG in the recipient
  // city (distance bands + vehicle multiplier), never a flat fee.
  const leg2Fee = leg2 ? baseRiderFee(toCity, 0, 0, 'motorcycle') : 0;
  const leg2Processing = leg2 ? platformFee(leg2Fee) : 0;
    const quotes = (results as any[]).map((r) => {
    const base = r.counter_price_zmw + riderFee;
    const fees = collectionFees(base, riderFee);
    return {
      courier_id: r.courier_id,
      courier_name: r.courier_name,
      depot_name: r.depot_name,
      service: r.service,
      weight_class: r.weight_class,
      counter_price_zmw: r.counter_price_zmw,
      rider_fee_zmw: riderFee,
      rider_payout_zmw: fees.rider_payout_zmw,
      leg2_fee_zmw: leg2Fee,
      leg2_processing_fee_zmw: leg2Processing,
      // DropOff NEVER holds partner money â€” split the fare explicitly.
      counter_fare_zmw: r.counter_price_zmw,       // partner's; paid at the depot
      dropoff_leg_zmw: round2(riderFee + leg2Fee + leg2Processing), // ours
      dropoff_due_zmw: collectionFees(
        round2(riderFee + leg2Fee + leg2Processing),
        riderFee,
      ).prompt_total_zmw,
      // ONE customer-visible fee line: "processing fee" (platform + momo collect).
      processing_fee_zmw: fees.processing_fee_zmw,
      total_pickup_zmw: base,
      total_pickup_fees_zmw: fees.processing_fee_zmw,
      total_pickup_prompt_zmw: fees.prompt_total_zmw,
      total_with_leg2_zmw: round2(r.counter_price_zmw + riderFee + leg2Fee + leg2Processing),
    };
  });
  return c.json({ quotes });
});

app.get('/cities', async (c) => {
  const { results } = await c.env.DB.prepare(
    `SELECT to_city AS city FROM quotes
      UNION SELECT from_city FROM quotes
      UNION SELECT city FROM couriers WHERE city IS NOT NULL
      ORDER BY city`,
  ).all();
  return c.json({ cities: (results as { city: string }[]).map((r) => r.city) });
});

/* ---------------------------------- jobs ---------------------------------- */
// Identity: a customer JWT ALWAYS books as its own phone â€” the client cannot
// spoof a sender number. Ops key may specify any phone (rider device/ops console).
app.post('/jobs', async (c) => {
  if (await rateLimited(c, 'job_create', 60)) return c.json({ error: 'too_many_requests' }, 429);
  const b: any = await c.req.json().catch(() => null);
  if (!b) return c.json({ error: 'invalid JSON body' }, 400);
  const idemKey = idemKeyOf(c, b);
  const replay = await replayIdempotent(c, idemKey, 'job');
  if (replay) return replay;
  // promo bookkeeping lives outside the try so the refund in catch can see it
  let promoConsumed = false;
  let promoCode: string | null = null;
  try {
    const senderPhone = c.get('role') === 'ops' && b.sender_phone
      ? normalizeZmPhone(b.sender_phone) : normalizeZmPhone(c.get('phone') ?? b.sender_phone ?? '');
    const recipientPhone = normalizeZmPhone(b.recipient_phone);
    if (!senderPhone) return c.json({ error: 'missing sender identity' }, 401);
    if (c.get('role') !== 'ops') {
      const n24h = (await c.env.DB.prepare(
        `SELECT COUNT(*) AS n FROM jobs WHERE sender_phone = ?1 AND created_at > datetime('now', '-1 day')`,
      ).bind(senderPhone).first<any>())?.n ?? 0;
      if (n24h >= 40) {
        return c.json({ error: 'daily_limit', message: 'Daily booking limit reached — contact support.' }, 429);
      }
    }
    if (!b.courier_id || !b.dest_city) return c.json({ error: 'courier_id and dest_city required' }, 400);

    // customer wallets are disabled â€” riders keep float, sellers pay momo/cash
    const payMethod: string = ['mobile_money', 'cash'].includes(b.pay_method)
      ? b.pay_method : 'mobile_money';
    let pickupWindow: string = b.pickup_window ?? 'now';
    if (!PICKUP_WINDOWS.includes(pickupWindow)) {
      return c.json({ error: `pickup_window must be one of ${PICKUP_WINDOWS.join(', ')}` }, 400);
    }
    // Sweep windows have booking cutoffs (06:00→05:30, 10:00→09:30, 14:00→13:30
    // CAT). A late booking never dies — it rolls forward to the next open
    // window (or instant) and the sender is told exactly what happened.
    let windowRolledFrom: string | null = null;
    if (pickupWindow !== 'now') {
      const cutoffs: Record<string, string> = { '06:00': '05:30', '10:00': '09:30', '14:00': '13:30' };
      const cat = new Date(Date.now() + 2 * 3600_000); // CAT = UTC+2
      const nowHM = `${String(cat.getUTCHours()).padStart(2, '0')}:${String(cat.getUTCMinutes()).padStart(2, '0')}`;
      if (nowHM > cutoffs[pickupWindow]) {
        windowRolledFrom = pickupWindow;
        const next = (['10:00', '14:00'] as const).find((w) => nowHM <= cutoffs[w]);
        pickupWindow = next ?? 'now';
      }
    }
    const fromCity = b.from_city ?? 'Lusaka';
    const weightClass = b.weight_class ?? '0-5kg';
    const service = b.service ?? 'standard';

    // Server-side pricing: quotes table = single source of truth. Missing
    // verified quote -> 422 quote_needed, never an invented fare.
    const quote = await c.env.DB.prepare(
      `SELECT counter_price_zmw FROM quotes
        WHERE courier_id = ?1 AND from_city = ?2 AND to_city = ?3
          AND weight_class = ?4 AND service = ?5`,
    ).bind(b.courier_id, fromCity, b.dest_city, weightClass, service).first<any>();
    if (!quote) {
      return c.json({
        error: 'quote_needed',
        detail: 'No verified counter price for this route/weight yet â€” capture it at the counter first.',
      }, 422);
    }
    const counterPrice = Number(quote.counter_price_zmw);

    // Pack inclusion: EVERY PARCEL counts as one plan slot — two parcels in
    // one trip to the same receiver = two parcels. Cycle = 30 days from
    // activation. A trip is bundled (K0 rider fee) only if all of its parcels
    // still fit under the cap; otherwise the whole trip pays the tier overage.
    const vehicleClass: VehicleClass = VEHICLE_CLASSES.includes(b.vehicle_class)
      ? b.vehicle_class : 'motorcycle';
    const parcels = Math.max(1, Math.min(Number(b.parcels ?? 1) || 1, VEHICLE_MAX_PARCELS[vehicleClass]));
    let riderFee = baseRiderFee(fromCity, Number(b.pickup_lat ?? 0), Number(b.pickup_lng ?? 0), vehicleClass);
    let packInclusion: 'pack' | 'payg' | 'none' = 'none';
    let planUsed = 0;
    let planCap = 0;
    const activeSub = await c.env.DB.prepare(
      `SELECT tier, period_start, period_end FROM subscriptions WHERE phone = ?1 AND status = 'active'
        AND period_end IS NOT NULL AND period_end > datetime('now')`,
    ).bind(senderPhone).first<any>();
    if (activeSub) {
      const packs = await plans(c.env.DB);
      const plan = packs[activeSub.tier as PlanTier];
      if (plan && activeSub.period_start && activeSub.period_end) {
        const used = await c.env.DB.prepare(
          `SELECT COALESCE(SUM(parcels), 0) AS n FROM jobs WHERE sender_phone = ?1
            AND created_at >= ?2 AND created_at < ?3`,
        ).bind(senderPhone, activeSub.period_start, activeSub.period_end).first<any>();
        planUsed = used?.n ?? 0;
        // No rollover: unused parcels expire with the cycle.
        planCap = plan.parcels_per_month;
        if (planUsed + parcels <= planCap) {
          riderFee = plan.rider_fee_zmw;
          packInclusion = 'pack';
        } else {
          packInclusion = 'payg';
          riderFee = tierOverageFee(activeSub.tier,
            baseRiderFee(fromCity, Number(b.pickup_lat ?? 0), Number(b.pickup_lng ?? 0), vehicleClass));
        }
      }
    }

    // Last-mile door delivery: same PAYG location pricing as the first mile —
    // recipient-city distance bands × vehicle multiplier (coords when supplied).
    const leg2Fee = b.dest_leg2
      ? baseRiderFee(String(b.dest_city ?? ''), Number(b.dest_lat ?? 0), Number(b.dest_lng ?? 0), vehicleClass)
      : 0;
    const leg2Processing = b.dest_leg2 ? platformFee(leg2Fee) : 0;

    // Optional seller promo â€” applies only to the DropOff leg, never the
    // partner's counter fare. Pack members already pay nothing per parcel.
    let promoDiscount = 0;
    if (b.promo_code && packInclusion !== 'pack') {
      const code = String(b.promo_code).trim().toUpperCase();
      const promo = await c.env.DB.prepare(
        'SELECT * FROM promo_codes WHERE code = ?1 AND active = 1',
      ).bind(code).first<any>();
      if (!promo) return c.json({ error: 'promo_not_found' }, 400);
      if (promo.expires_at && promo.expires_at <= new Date().toISOString().slice(0, 10)) {
        return c.json({ error: 'promo_expired' }, 400);
      }
      if (promo.applies_tier && promo.applies_tier !== activeSub?.tier) {
        return c.json({ error: `promo_only_for_${promo.applies_tier}` }, 400);
      }
      // Atomically consume a use FIRST (guard on remaining uses) so concurrent
      // bookings with uses_left = 1 cannot both burn it â€” then book the job.
      const consume = await c.env.DB.prepare(
        `UPDATE promo_codes SET uses_left = uses_left - 1
          WHERE code = ?1 AND active = 1 AND (uses_left IS NULL OR uses_left > 0)`,
      ).bind(code).run();
      if (consume.meta.changes === 0) return c.json({ error: 'promo_exhausted' }, 409);
      promoConsumed = true;
      const leg = riderFee + leg2Fee + leg2Processing;
      promoDiscount = round2((leg * Number(promo.discount_pct)) / 100);
      promoCode = code;
    }

    // partner counter fare is never touched; discount lives on the DropOff leg
    const totals = computeJobTotals({
      counterPriceZmw: counterPrice,
      riderFeeZmw: riderFee,
      leg2FeeZmw: leg2Fee,
      leg2ProcessingFeeZmw: leg2Processing,
      promoDiscountZmw: promoDiscount,
    });

    // Round trip: a second, priced leg back to the origin depot/city.
    const isRoundTrip = b.round_trip === 1 || b.round_trip === true;
    let returnLegFee = 0;
    if (isRoundTrip) {
      returnLegFee = Math.max(0, Number(b.return_leg_fee_zmw ?? 0));
      if (!b.return_city) return c.json({ error: 'return_city required for round trips' }, 400);
    }

    // Last mile: explicit flag (mirrors dest_leg2 so the UI can toggle it on
    // both pay-as-you-go and tier bookings without guessing).
    const lastMile = b.last_mile != null ? (b.last_mile === 1 || b.last_mile === true ? 1 : 0)
      : (b.dest_leg2 ? 1 : 0);

    // Timed pickup: optional ISO-8601 slot (CAT). Stored as-is; the cron
    // scheduler notifies sender + rider at T-30 / T-10 and flags misses.
    let pickupAt: string | null = null;
    if (b.pickup_at) {
      const ts = new Date(b.pickup_at).toISOString();
      if (ts === 'Invalid Date' || isNaN(new Date(ts).getTime())) {
        return c.json({ error: 'pickup_at must be ISO-8601' }, 400);
      }
      pickupAt = ts;
    }

    const total = round2(totals.total_zmw + returnLegFee);
    const dropOffLeg = totals.dropoff_leg_zmw;

    // Wider entropy: date + 5 random chars (the old 2-digit suffix was guessable)
    const ref = `DRO-${new Date().toISOString().slice(2, 10).replace(/-/g, '')}-${randomCode(5)}`;
    const { meta } = await c.env.DB.prepare(
      `INSERT INTO jobs (ref, sender_phone, sender_name, pickup_address, pickup_lat, pickup_lng,
         courier_id, recipient_name, recipient_phone, dest_city, dest_city_to_depot,
         description, weight_class, counter_price_zmw, rider_fee_zmw, leg2_fee_zmw,
         leg2_processing_fee_zmw, total_zmw,
         promo_code, promo_discount_zmw,
         pickup_time, pickup_window, pay_method,
         round_trip, return_city, return_address, return_leg_fee_zmw, pickup_at, last_mile,
         parcels, vehicle_class)
       VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16,?17,?18,?19,?20,?21,?22,?23,?24,?25,?26,?27,?28,?29,?30,?31)`,
    ).bind(
      ref, senderPhone, b.sender_name, b.pickup_address, b.pickup_lat ?? null, b.pickup_lng ?? null,
      b.courier_id, b.recipient_name, recipientPhone, b.dest_city, b.dest_leg2 ? 1 : 0,
      b.description ?? '', weightClass, counterPrice, riderFee, leg2Fee, leg2Processing, total,
      promoCode, promoDiscount,
      b.pickup_time ?? pickupWindow, pickupWindow, payMethod,
      isRoundTrip ? 1 : 0, b.return_city ?? null, b.return_address ?? null, returnLegFee,
      pickupAt, lastMile,
      parcels, vehicleClass,
    ).run();

    if (promoCode) {
      // promo_uses bookkeeping (the use itself was already consumed atomically)
      await c.env.DB.prepare(
        'INSERT INTO promo_uses (code, phone, job_id) VALUES (?1, ?2, ?3)',
      ).bind(promoCode, senderPhone, meta.last_row_id).run();
    }

    await c.env.DB.prepare(
      'INSERT INTO job_events (job_id, status, note) VALUES (?1, ?2, ?3)',
    ).bind(meta.last_row_id, 'created', 'Job created').run();
    if (windowRolledFrom) {
      const fromLabel = windowRolledFrom === 'now' ? 'instant' : (SWEEP_SLOTS[windowRolledFrom]?.range ?? windowRolledFrom);
      const toLabel = pickupWindow === 'now' ? 'instant' : (SWEEP_SLOTS[pickupWindow]?.range ?? pickupWindow);
      await c.env.DB.prepare(
        'INSERT INTO job_events (job_id, status, note) VALUES (?1, ?2, ?3)',
      ).bind(meta.last_row_id, 'window_rolled',
        `The ${fromLabel} window had closed — moved to the ${toLabel} slot automatically`).run();
    }

    c.executionCtx.waitUntil(
      scoreJobFraud(c.env, senderPhone, meta.last_row_id, ref, recipientPhone, b.pickup_address, total)
        .catch(() => {}),
    );

    // Recipient tracking link (no account): SMS the buyer a live status page.
    const trackingToken = await issueTrackingToken(c.env, meta.last_row_id, ref, recipientPhone);
    const trackUrl = trackingUrl(c.env, trackingToken);
    c.executionCtx.waitUntil(
      sendSms(c.env, recipientPhone,
      `DropOff: your parcel ${ref} is on the move. Follow it live — status, rider location and arrival time: ${trackUrl}`).catch(() => {}),
    );

    if (pickupAt) {
      await c.env.DB.prepare(
        `INSERT INTO scheduled_pickups (job_ref, phone, rider_phone, pickup_at, status)
          VALUES (?1, ?2, ?3, ?4, 'pending')`,
      ).bind(ref, senderPhone, recipientPhone, pickupAt).run();
    }

    // referral reward: the REFERRED party just booked â€” create the referrer's
    // single-use promo. Claim is a guarded UPDATE so two concurrent bookings
    // can never mint two rewards (second UPDATE matches 0 rows â†’ bail).
    try {
      const payoutRefId = meta.last_row_id;
      const claimed = await c.env.DB.prepare(
        `UPDATE referrals SET status='rewarded', referred_job_id = ?2, rewarded_at = datetime('now')
          WHERE referred_phone = ?1 AND status = 'pending'`,
      ).bind(senderPhone, payoutRefId).run();
      if (claimed.meta.changes > 0) {
        const refRow = await c.env.DB.prepare(
          'SELECT id, referrer_phone FROM referrals WHERE referred_phone = ?1',
        ).bind(senderPhone).first() as any;
        const rewardCode = `FRIEND${randomCode(5)}`;
        const pct = REF_REWARD_PCT;
        await c.env.DB.batch([
          c.env.DB.prepare(
            `INSERT INTO promo_codes (code, discount_pct, note, uses_left, active)
             VALUES (?1, ?2, ?3, 1, 1)`,
          ).bind(rewardCode, pct, `Referral reward â€” ${senderPhone} joined via your code`),
          c.env.DB.prepare(
            `UPDATE referrals SET reward_code = ?2 WHERE id = ?1`,
          ).bind(refRow.id, rewardCode),
          c.env.DB.prepare(`INSERT INTO job_events (job_id, status, note) VALUES (?1, 'referral_rewarded', ?2)`)
            .bind(payoutRefId, `Referrer ${refRow.referrer_phone} gets ${rewardCode} (${pct}% off, single-use)`),
        ]);
      }
    } catch { /* referral logging must never block a booking */ }

    // Fees ride on the payer leg only: pack parcels carry no per-parcel fees
    // (the pack renewal prompt charges the processing fee on the pack price),
    // wallet top-ups carry them once per deposit. The customer NEVER pays for
    // the rider's payout â€” that lives inside the rider's 10% take. Pack and
    // promo math happens on the DropOff leg ONLY â€” the partner fare is theirs.
    const feeBase = collectionFees(dropOffLeg, packInclusion === 'pack' ? null : riderFee);

    // Smart auto-assign: bookings get a rider immediately unless the caller opts out.
    let autoAssigned: { rider_id: number; rider: string; eta_minutes: number; km: number } | null = null;
    if (b.auto_assign !== false && Number.isFinite(b.pickup_lat ?? 0) && Number.isFinite(b.pickup_lng ?? 0)) {
      try {
        const pick = await nearestAvailableRider(c.env, b.pickup_lat, b.pickup_lng);
        if (pick) {
          const etaMin = Math.round((pick.km / 22) * 60 + 4);
          await c.env.DB.batch([
            c.env.DB.prepare(
              `UPDATE jobs SET rider_id = ?1, status = 'rider_assigned', assigned_at = datetime('now'), eta_minutes = ?2 WHERE ref = ?3`,
            ).bind(pick.rider.id, etaMin, ref),
            c.env.DB.prepare(
              `UPDATE riders SET current_load = current_load + 1, status = 'on_route', route_updated_at = datetime('now') WHERE id = ?1`,
            ).bind(pick.rider.id),
          ]);
          autoAssigned = { rider_id: pick.rider.id, rider: pick.rider.full_name, eta_minutes: etaMin, km: pick.km };
          await sendToPhone(c.env, senderPhone, {
            title: 'Rider assigned',
            body: `Rider ${pick.rider.full_name} (${pick.rider.vehicle}) is heading to your pickup â€” track them live in Bookings.`,
            data: { job_ref: ref, kind: 'rider_assigned' },
          });
        }
      } catch { /* auto-assign is best-effort â€” the batch sweep picks it up next */ }
    }

    const payload = {
      ok: true, ref, job_id: meta.last_row_id, total_zmw: total,
      dropoff_leg_zmw: dropOffLeg,
      promo_code: promoCode, promo_discount_zmw: promoDiscount,
      fees: feeBase, prompt_total_zmw: feeBase.prompt_total_zmw,
      pack_inclusion: packInclusion, pay_method: payMethod,
      auto_assigned: autoAssigned,
      tracking_token: trackingToken, tracking_url: trackUrl,
      parcels, vehicle_class: vehicleClass,
      plan_used: activeSub ? planUsed + (packInclusion === 'pack' ? parcels : 0) : null,
      plan_cap: activeSub ? planCap : null,
      plan_inclusion: packInclusion,
      pickup_window: pickupWindow,
      window_rolled_from: windowRolledFrom,
    };
    await saveIdempotent(c.env, idemKey, 'job', senderPhone, 201, payload);
    return c.json(payload, 201);
  } catch (e: any) {
    // refund a promo use we happened to consume before the booking failed
    if (promoConsumed && promoCode) {
      await c.env.DB.prepare(
        `UPDATE promo_codes SET uses_left = COALESCE(uses_left, 0) + 1 WHERE code = ?1`,
      ).bind(promoCode).run().catch(() => {});
    }
    return c.json({ error: e.message ?? 'bad request' }, 400);
  }
});

// Sellers can test a promo code before booking (public, read-only)
app.get('/promo/check', async (c) => {
  const code = String(c.req.query('code') ?? '').trim().toUpperCase();
  if (!code) return c.json({ error: 'missing code' }, 400);
  const promo = await c.env.DB.prepare('SELECT code, discount_pct, note, applies_tier, uses_left, expires_at, active FROM promo_codes WHERE code = ?1').bind(code).first<any>();
  if (!promo || !promo.active) return c.json({ error: 'promo_not_found' }, 404);
  if (promo.expires_at && promo.expires_at <= new Date().toISOString().slice(0, 10)) return c.json({ error: 'promo_expired' }, 410);
  if (promo.uses_left != null && Number(promo.uses_left) <= 0) return c.json({ error: 'promo_exhausted' }, 409);
  return c.json({ ok: true, code: promo.code, discount_pct: promo.discount_pct, note: promo.note, applies_tier: promo.applies_tier });
});

app.get('/jobs', async (c) => {
  const role = c.get('role');
  let phone: string | null = null;
  if (role === 'customer') phone = c.get('phone') ?? '';
  else { // ops: must specify whose jobs; admin? paygo regular listing
    try { phone = normalizeZmPhone(c.req.query('phone') ?? ''); } catch { phone = ''; }
  }
  if (!phone) return c.json({ error: 'missing phone' }, 400);
  const { results } = await c.env.DB.prepare(
    `SELECT j.*, co.name AS courier_name, co.depot_name,
            (SELECT status FROM job_events ev WHERE ev.job_id = j.id ORDER BY ev.id DESC LIMIT 1) AS last_event
       FROM jobs j JOIN couriers co ON co.id = j.courier_id
      WHERE j.sender_phone = ?1 ORDER BY j.id DESC LIMIT 50`,
  ).bind(phone).all();
  return c.json({ jobs: results });
});

app.get('/jobs/:ref', async (c) => {
  const job = await c.env.DB.prepare(
    `SELECT j.*, co.name AS courier_name, co.depot_name FROM jobs j
       JOIN couriers co ON co.id = j.courier_id WHERE j.ref = ?1`,
  ).bind(c.req.param('ref')).first() as any;
  if (!job) return c.json({ error: 'not found' }, 404);
  const phone = c.get('phone');
  const isCustomer = c.get('role') === 'customer';
  if (isCustomer && phone !== job.sender_phone && phone !== job.recipient_phone) {
    return c.json({ error: 'not found' }, 404); // no existence leak
  }

  let payload: any = { ...job };
  if (isCustomer) {
    // internal fields no seller or recipient should ever read
    for (const k of ['fraud_score', 'review_required']) delete payload[k];
    if (phone === job.recipient_phone && phone !== job.sender_phone) {
      // recipient sees delivery status only — never the sender's money side
      for (const k of ['counter_price_zmw', 'rider_fee_zmw', 'leg2_fee_zmw',
        'leg2_processing_fee_zmw', 'total_zmw', 'promo_code', 'promo_discount_zmw',
        'paid', 'pay_method', 'sender_name', 'sender_phone', 'pickup_address']) {
        delete payload[k];
      }
    }
  }

  // Timeline: public statuses only; notes stay internal for non-participants.
  const { results: events } = await c.env.DB.prepare(
    'SELECT status, note, created_at FROM job_events WHERE job_id = ?1 ORDER BY id',
  ).bind(job.id).all();
  const safeEvents = (events as any[])
    .filter((e) => ['created', 'rider_assigned', 'picked_up', 'at_depot', 'departed',
      'arrived', 'delivered', 'ready_for_collection', 'partner_confirmed'].includes(e.status))
    .map((e) => (isCustomer ? { status: e.status, created_at: e.created_at } : e));
  return c.json({ job: payload, events: safeEvents });
});

// Live location for a participant (sender/recipient) or ops/admin (fleet view)
app.get('/jobs/:ref/live', async (c) => {
  const job = await c.env.DB.prepare(
    `SELECT j.*, r.phone AS rider_phone, r.last_lat, r.last_lng, r.last_seen_at
       FROM jobs j LEFT JOIN riders r ON r.id = j.rider_id WHERE j.ref = ?1`,
  ).bind(c.req.param('ref')).first() as any;
  if (!job) return c.json({ error: 'not found' }, 404);
  if (c.get('role') === 'customer' && c.get('phone') !== job.sender_phone && c.get('phone') !== job.recipient_phone) {
    return c.json({ error: 'not found' }, 404);
  }
  if (!job.rider_phone) return c.json({ has_rider: false });
  if (job.last_lat == null) {
    return c.json({ has_rider: true, rider_phone: job.rider_phone, location: null, note: 'rider has not shared location yet' });
  }
  return c.json({
    has_rider: true,
    rider_phone: job.rider_phone,
    lat: job.last_lat,
    lng: job.last_lng,
    seen_at: job.last_seen_at,
    pickup_lat: job.pickup_lat ?? null,
    pickup_lng: job.pickup_lng ?? null,
    maps_link: `https://maps.google.com/?q=${job.last_lat},${job.last_lng}`,
  });
});

/* ------------------------- rider app: act on a job ------------------------- */
// Auth: ops key, admin key, or the ASSIGNED rider's own JWT. Statuses move
// pickup -> picked_up -> at_depot -> departed -> arrived -> delivered/ready.
// Also logs waiting minutes (billed) and COD collections (credited to wallet).
app.post('/jobs/:ref/events', async (c) => {
  const b: any = await c.req.json().catch(() => null);
  if (!b) return c.json({ error: 'invalid JSON body' }, 400);
  const status = b.status as string | undefined;
  const allowed = ['rider_assigned', 'picked_up', 'at_depot', 'departed', 'arrived', 'delivered', 'ready_for_collection'];
  if (status !== undefined && !allowed.includes(status)) return c.json({ error: 'bad status' }, 400);

  const job = await c.env.DB.prepare(
    `SELECT j.id, j.ref, j.sender_phone, j.counter_price_zmw, j.rider_fee_zmw, j.leg2_fee_zmw,
            j.leg2_processing_fee_zmw, j.promo_discount_zmw,
            j.total_zmw, j.wait_minutes, j.pay_method, j.paid,
            r.phone AS rider_phone
       FROM jobs j LEFT JOIN riders r ON r.id = j.rider_id
      WHERE j.ref = ?1`,
  ).bind(c.req.param('ref')).first() as any;
  if (!job) return c.json({ error: 'not found' }, 404);

  // authorization: ops/admin keys (handled above) or the assigned rider's JWT
  if (c.get('role') === 'customer') {
    const phone = c.get('phone');
    const isAssigned = job.rider_phone && phone === job.rider_phone;
    const isAdminKey = isAdmin(c);
    if (!isAssigned && !isAdminKey) return c.json({ error: 'only the assigned rider can act on this job' }, 403);
  }

  const dbStatements: D1PreparedStatement[] = [];

  // waiting-time billing (event kept as dispute evidence). Canonical recompute â€”
  // promo discount is honoured here too so totals never drift from /payments.
  if (b.wait_minutes !== undefined) {
    const minutes = Math.max(0, Math.min(240, Math.round(Number(b.wait_minutes) || 0)));
    const waitFee = waitFeeFor(minutes);
    const totals = computeJobTotals({
      counterPriceZmw: job.counter_price_zmw,
      riderFeeZmw: job.rider_fee_zmw,
      leg2FeeZmw: job.leg2_fee_zmw,
      leg2ProcessingFeeZmw: job.leg2_processing_fee_zmw,
      promoDiscountZmw: job.promo_discount_zmw,
      waitFeeZmw: waitFee,
    });
    dbStatements.push(c.env.DB.prepare(
      `UPDATE jobs SET wait_minutes = ?2, wait_fee_zmw = ?3, total_zmw = ?4 WHERE id = ?1`,
    ).bind(job.id, minutes, waitFee, totals.total_zmw));
    dbStatements.push(c.env.DB.prepare(
      `INSERT INTO job_events (job_id, status, note, lat, lng) VALUES (?1,'waiting',?2,?3,?4)`,
    ).bind(job.id, b.note ?? `Waited ${minutes} min (first ${WAIT_FREE_MINUTES} free = K${waitFee})`, b.lat ?? null, b.lng ?? null));
  }

  // COD collection at the door (leg-2 / partner COD): the cash FLOATS with the
  // rider/driver â€” the sender's wallet is credited only after remittance.
  if (b.cod_collected_zmw !== undefined) {
    const cod = Math.max(0, Number(b.cod_collected_zmw) || 0);
    if (cod > 0) {
      dbStatements.push(c.env.DB.prepare(
        `UPDATE jobs SET cod_collected_zmw = ?2 WHERE id = ?1`,
      ).bind(job.id, cod));
      dbStatements.push(c.env.DB.prepare(
        `INSERT INTO job_events (job_id, status, note) VALUES (?1, 'cod_collected', ?2)`,
      ).bind(job.id, b.note ?? `K${cod} collected at the door â€” cash floats with rider/driver until remittance (platform keeps ${Math.round(COD_FEE * 100)}%)`));
    }
  }

  // DropOff NEVER holds partner money: the customer pays us only the DropOff
  // leg â€” rider fee + last-mile door leg (+ its processing), minus any promo.
  const dropoffLegZmw = round2(
    Math.max(0, job.rider_fee_zmw + (job.leg2_fee_zmw || 0) + (job.leg2_processing_fee_zmw || 0) - (job.promo_discount_zmw || 0)),
  );

  // Wallet jobs settle the same DropOff leg, minus the Lipila momo leg â€”
  // the platform processing fee still applies (no free rides on the fee).
  const walletProcessing = platformFee(dropoffLegZmw);
  const walletDue = round2(dropoffLegZmw + walletProcessing);

  // wallet-method jobs are charged at pickup. The debit is guarded by balance;
  // the ledger + paid flag are written ONLY when the debit actually moved money
  // (a failed guard used to leave a ledger row and a paid job with no deduction).
  if (status === 'picked_up' && job.pay_method === 'wallet' && !job.paid) {
    const debit = await c.env.DB.prepare(
      `UPDATE wallets SET balance_zmw = balance_zmw - ?2 WHERE phone = ?1 AND balance_zmw >= ?2`,
    ).bind(job.sender_phone, walletDue).run();
    if (debit.meta.changes > 0) {
      await c.env.DB.batch([
        c.env.DB.prepare(
          `INSERT INTO wallet_ledger (phone, amount_zmw, kind, job_id) VALUES (?1, -?2, 'job_charge', ?3)`,
        ).bind(job.sender_phone, walletDue, job.id),
        c.env.DB.prepare('UPDATE jobs SET paid = 1 WHERE id = ?1').bind(job.id),
      ]);
    } else {
      return c.json({ error: 'insufficient_wallet_balance', due_zmw: walletDue }, 402);
    }
  }

  if (status) {
    dbStatements.push(c.env.DB.prepare(
      'INSERT INTO job_events (job_id, status, note, lat, lng) VALUES (?1,?2,?3,?4,?5)',
    ).bind(job.id, status, b.note ?? null, b.lat ?? null, b.lng ?? null));
    const sets = ['status = ?2'];
    const vals: unknown[] = [job.id, status];
    if (b.waybill) { sets.push('courier_waybill = ?3'); vals.push(b.waybill); }
    if (b.photo_url) { sets.push('dropoff_photo_url = ?4'); vals.push(b.photo_url); }
    dbStatements.push(c.env.DB.prepare(
      `UPDATE jobs SET ${sets.join(', ')} WHERE id = ?1`).bind(...vals));
  }
  if (dbStatements.length) await c.env.DB.batch(dbStatements);

  const updated = await c.env.DB.prepare(
    `SELECT ref, status, paid, counter_price_zmw, rider_fee_zmw, leg2_fee_zmw,
            wait_minutes, wait_fee_zmw, cod_collected_zmw, total_zmw FROM jobs WHERE id = ?1`,
  ).bind(job.id).first();
  // FCM push to the sender â€” status transitions are the parcel's whole story.
  if (status && updated) {
    const stagePush: Record<string, { title: string; body: string }> = {
      rider_assigned: { title: 'Rider assigned', body: 'Your DropOff rider is on it â€” track them live in Bookings.' },
      picked_up: { title: 'Parcel picked up', body: 'Collected from the sender â€” heading to the depot.' },
      at_depot: { title: 'At the depot', body: 'Your parcel reached the depot. You can follow the journey live.' },
      departed: { title: 'On the way', body: 'Left the depot on the DropOff leg.' },
      arrived: { title: 'Arrived', body: 'Your parcel arrived at the destination city.' },
      ready_for_collection: { title: 'Ready for collection', body: 'The parcel is waiting at your depot for pickup.' },
      delivered: { title: 'Delivered', body: 'Success â€” the parcel is signed in at the depot. Kigoda.' },
    };
    const push = stagePush[status];
    if (push) {
      await sendToPhone(c.env, job.sender_phone, { ...push, data: { job_ref: String(updated.ref), kind: 'status' } });
    }
  }
  return c.json({ ok: true, job: updated });
});

/* --------------------------------- ratings -------------------------------- */
// Rate the three sides of a delivery â€” the seller, the driver (rider) and the
// courier. Only the job's participants (sender / recipient) or ops can rate;
// sellers can't rate themselves; ratings open once the parcel is delivered or
// ready for collection. One score per reviewer per target â€” resubmits update.
const RATING_TARGETS = new Set(['seller', 'driver', 'courier']);
const RATING_OPEN = new Set(['delivered', 'ready_for_collection']);

// Lightweight comment guard — enough to keep abuse out of a public feed without
// pretending to be a full moderation system. Hidden-by-admin is the real lever.
const BLOCKED_WORDS = ['fuck', 'shit', 'bitch', 'asshole', 'dick', 'cunt', 'nigger', 'faggot'];
function containsProfanity(text: string): boolean {
  const t = text.toLowerCase();
  return BLOCKED_WORDS.some((w) => t.includes(w));
}

async function ratingTargetKey(job: any, targetType: string): Promise<string | null> {
  if (targetType === 'seller') return `phone:${job.sender_phone}`;
  if (targetType === 'driver') return job.rider_id ? `rider:${job.rider_id}` : null;
  return `courier:${job.courier_id}`;
}

app.post('/jobs/:ref/rate', async (c) => {
  if (await rateLimited(c, 'rating', 40)) return c.json({ error: 'too_many_requests' }, 429);
  const b: any = await c.req.json().catch(() => null);
  const targetType = String(b?.target_type ?? '').toLowerCase();
  if (!RATING_TARGETS.has(targetType)) return c.json({ error: 'bad target_type' }, 400);
  const stars = Math.round(Number(b?.stars));
  if (!Number.isFinite(stars) || stars < 1 || stars > 5) return c.json({ error: 'stars must be 1-5' }, 400);
  const comment = typeof b?.comment === 'string' ? b.comment.trim().slice(0, 500) : '';
  if (comment && containsProfanity(comment)) {
    return c.json({ error: 'comment_blocked', message: 'Please keep comments respectful.' }, 400);
  }

  const job = await c.env.DB.prepare(
    `SELECT id, ref, sender_phone, recipient_phone, rider_id, courier_id, status FROM jobs WHERE ref = ?1`,
  ).bind(c.req.param('ref')).first<any>();
  if (!job) return c.json({ error: 'not found' }, 404);

  const role = c.get('role');
  const reviewer = role === 'ops'
    ? normalizeZmPhone(String(b?.reviewer_phone ?? job.sender_phone))
    : (c.get('phone') as string);
  if (role === 'customer' && reviewer !== job.sender_phone && reviewer !== job.recipient_phone) {
    return c.json({ error: 'not found' }, 404); // no existence leak
  }
  if (targetType === 'seller' && reviewer === job.sender_phone) {
    return c.json({ error: 'cannot_rate_self' }, 403);
  }
  if (role === 'customer' && !RATING_OPEN.has(String(job.status))) {
    return c.json({ error: 'not_complete', message: 'Rate once the parcel is delivered or ready for collection.' }, 409);
  }
  const targetKey = await ratingTargetKey(job, targetType);
  if (!targetKey) return c.json({ error: 'no_driver_assigned' }, 409);

  await c.env.DB.prepare(
    `INSERT INTO ratings (job_ref, job_id, target_type, target_key, reviewer_phone, reviewer_role, stars, comment)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
     ON CONFLICT(job_ref, target_type, reviewer_phone)
     DO UPDATE SET stars = excluded.stars, comment = excluded.comment, updated_at = datetime('now')`,
  ).bind(job.ref, job.id, targetType, targetKey, reviewer, role ?? 'customer', stars, comment || null).run();
  await c.env.DB.prepare(
    `INSERT INTO job_events (job_id, status, note) VALUES (?1, 'rated', ?2)`,
  ).bind(job.id, `${targetType} rated ${stars}/5`).run();

  return c.json({ ok: true, target_type: targetType, stars });
});

app.get('/jobs/:ref/ratings', async (c) => {
  const job = await c.env.DB.prepare(
    `SELECT id, ref, sender_phone, recipient_phone, rider_id, courier_id FROM jobs WHERE ref = ?1`,
  ).bind(c.req.param('ref')).first<any>();
  if (!job) return c.json({ error: 'not found' }, 404);
  if (c.get('role') === 'customer' && c.get('phone') !== job.sender_phone && c.get('phone') !== job.recipient_phone) {
    return c.json({ error: 'not found' }, 404);
  }
  const { results } = await c.env.DB.prepare(
    `SELECT target_type, stars, comment, reviewer_phone, verified, hidden, created_at, updated_at
       FROM ratings WHERE job_ref = ?1 ORDER BY id`,
  ).bind(job.ref).all<any>();

  const viewer = c.get('phone');
  const mine: Record<string, number> = {};
  const masked = (results as any[]).map((r) => {
    const isMine = viewer != null && r.reviewer_phone === viewer;
    if (isMine) mine[r.target_type] = r.stars;
    // reviewers stay anonymous — only the viewer recognises their own entry
    return { ...r, reviewer_phone: isMine ? r.reviewer_phone : '***' };
  });
  const summary: Record<string, { count: number; average: number | null }> = {};
  for (const t of RATING_TARGETS) {
    const key = await ratingTargetKey(job, t);
    if (!key) continue;
    const agg = await c.env.DB.prepare(
      `SELECT COUNT(*) AS count, ROUND(AVG(stars), 2) AS average
         FROM ratings WHERE target_type = ?1 AND target_key = ?2`,
    ).bind(t, key).first<any>();
    summary[t] = { count: agg?.count ?? 0, average: agg?.average ?? null };
  }
  return c.json({ ratings: masked, my_ratings: mine, summary });
});

app.get('/ratings/summary', async (c) => {
  const targetType = String(c.req.query('target_type') ?? '');
  const targetKey = String(c.req.query('target_key') ?? '');
  if (!RATING_TARGETS.has(targetType) || !targetKey) return c.json({ error: 'bad target' }, 400);
  const agg = await c.env.DB.prepare(
    `SELECT COUNT(*) AS count, ROUND(AVG(stars), 2) AS average
       FROM ratings WHERE target_type = ?1 AND target_key = ?2`,
  ).bind(targetType, targetKey).first<any>();
  const { results: recent } = await c.env.DB.prepare(
    `SELECT stars, comment, verified, created_at FROM ratings
      WHERE target_type = ?1 AND target_key = ?2 AND hidden = 0 AND comment IS NOT NULL AND comment <> ''
      ORDER BY id DESC LIMIT 20`,
  ).bind(targetType, targetKey).all();
  return c.json({
    target_type: targetType, target_key: targetKey,
    count: agg?.count ?? 0, average: agg?.average ?? null, recent,
  });
});

/* --------------------------- rating reports ------------------------------- */
// Anyone signed in can flag a comment; it stays out of admin-hidden lists only
// after moderation (reports are evidence, not automatic censorship).
app.post('/ratings/:id/report', async (c) => {
  const id = Number(c.req.param('id'));
  const b: any = await c.req.json().catch(() => null);
  const rating = await c.env.DB.prepare('SELECT id FROM ratings WHERE id = ?1').bind(id).first();
  if (!rating) return c.json({ error: 'not found' }, 404);
  const reason = String(b?.reason ?? '').trim().slice(0, 300);
  await c.env.DB.batch([
    c.env.DB.prepare('INSERT INTO rating_reports (rating_id, reporter_phone, reason) VALUES (?1, ?2, ?3)')
      .bind(id, c.get('phone') ?? null, reason || null),
    c.env.DB.prepare(`UPDATE ratings SET report_reason = ?2, reported_at = datetime('now') WHERE id = ?1`)
      .bind(id, reason || null),
  ]);
  return c.json({ ok: true });
});

app.get('/admin/ratings', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'forbidden' }, 403);
  const reportedOnly = c.req.query('reported') === '1';
  const { results } = await c.env.DB.prepare(
    `SELECT r.*, (SELECT COUNT(*) FROM rating_reports rr WHERE rr.rating_id = r.id) AS reports
       FROM ratings r ${reportedOnly ? 'WHERE r.reported_at IS NOT NULL' : ''}
      ORDER BY r.id DESC LIMIT 200`,
  ).all();
  return c.json({ ratings: results });
});

app.post('/admin/ratings/:id/moderate', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'forbidden' }, 403);
  const b: any = await c.req.json().catch(() => null);
  const hidden = b?.hidden === true || b?.hidden === 1 ? 1 : 0;
  const res = await c.env.DB.prepare('UPDATE ratings SET hidden = ?2 WHERE id = ?1')
    .bind(Number(c.req.param('id')), hidden).run();
  return c.json({ ok: true, updated: res.meta.changes });
});

/* ----------------------------- fraud review ------------------------------- */
app.get('/admin/fraud', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'forbidden' }, 403);
  const status = c.req.query('status') ?? 'open';
  const { results } = await c.env.DB.prepare(
    `SELECT f.*, j.status AS job_status, j.total_zmw
       FROM fraud_flags f JOIN jobs j ON j.id = f.job_id
      WHERE f.status = ?1 ORDER BY f.id DESC LIMIT 200`,
  ).bind(status).all();
  return c.json({ flags: results });
});

app.post('/admin/fraud/:id/review', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'forbidden' }, 403);
  const b: any = await c.req.json().catch(() => null);
  const status = b?.status === 'confirmed' ? 'confirmed' : 'cleared';
  const flag = await c.env.DB.prepare('SELECT job_id FROM fraud_flags WHERE id = ?1')
    .bind(Number(c.req.param('id'))).first<any>();
  if (!flag) return c.json({ error: 'not found' }, 404);
  await c.env.DB.batch([
    c.env.DB.prepare(
      `UPDATE fraud_flags SET status = ?2, reviewed_at = datetime('now'), reviewer = ?3 WHERE id = ?1`,
    ).bind(Number(c.req.param('id')), status, c.get('phone') ?? null),
    c.env.DB.prepare('UPDATE jobs SET review_required = ?2 WHERE id = ?1')
      .bind(flag.job_id, status === 'confirmed' ? 1 : 0),
  ]);
  return c.json({ ok: true, status });
});

/* --------------------------- public tracking page ------------------------- */
// GET /track/:token — public (no auth). Shows status + live rider location to
// the recipient; never exposes prices, sender phone or payment data.
app.get('/track/:token', async (c) => {
  const row = await c.env.DB.prepare(
    `SELECT t.job_id, t.job_ref,
            j.ref, j.status, j.created_at, j.pickup_address, j.dest_city,
            j.recipient_name, j.eta_minutes,
            co.name AS courier_name,
            r.full_name AS rider_name, r.vehicle AS rider_vehicle,
            r.last_lat, r.last_lng, r.last_seen_at
       FROM tracking_tokens t
       JOIN jobs j ON j.id = t.job_id
       LEFT JOIN couriers co ON co.id = j.courier_id
       LEFT JOIN riders r ON r.id = j.rider_id
      WHERE t.token = ?1 AND (t.expires_at IS NULL OR t.expires_at > datetime('now'))`,
  ).bind(c.req.param('token')).first<any>();
  if (!row) return c.json({ error: 'not found' }, 404);
  // Public page: timeline statuses only — NEVER internal notes (referral,
  // fraud, payment) and never prices or sender details.
  const { results: events } = await c.env.DB.prepare(
    `SELECT status, created_at FROM job_events
      WHERE job_id = ?1 AND status IN ('created','rider_assigned','picked_up','at_depot','departed','arrived','delivered','ready_for_collection','partner_confirmed')
      ORDER BY id`,
  ).bind(row.job_id).all();
  return c.json({
    ref: row.ref,
    status: row.status,
    created_at: row.created_at,
    pickup_city: (row.pickup_address ?? '').split(',').slice(-1)[0].trim() || null,
    dest_city: row.dest_city,
    recipient_name: row.recipient_name,
    courier: row.courier_name,
    eta_minutes: row.eta_minutes ?? null,
    rider: row.rider_name ? { name: row.rider_name, vehicle: row.rider_vehicle } : null,
    location: row.last_lat != null
      ? { lat: row.last_lat, lng: row.last_lng, seen_at: row.last_seen_at }
      : null,
    events,
  });
});

// Participants/ops can fetch (or mint) their job's share link.
app.post('/jobs/:ref/tracking-link', async (c) => {
  const job = await c.env.DB.prepare(
    'SELECT id, ref, sender_phone, recipient_phone FROM jobs WHERE ref = ?1',
  ).bind(c.req.param('ref')).first<any>();
  if (!job) return c.json({ error: 'not found' }, 404);
  if (c.get('role') === 'customer' && c.get('phone') !== job.sender_phone && c.get('phone') !== job.recipient_phone) {
    return c.json({ error: 'not found' }, 404);
  }
  const existing = await c.env.DB.prepare(
    'SELECT token FROM tracking_tokens WHERE job_id = ?1 ORDER BY created_at DESC LIMIT 1',
  ).bind(job.id).first<{ token: string }>();
  const token = existing?.token ?? await issueTrackingToken(c.env, job.id, job.ref, job.recipient_phone);
  return c.json({ token, url: trackingUrl(c.env, token) });
});

/* ---------------------------------- chat ---------------------------------- */
// One thread per job: seller, recipient (token), assigned rider, depot partner
// and ops share it. Support threads (kind='support') connect a phone to ops.

type ChatRole = 'seller' | 'recipient' | 'rider' | 'courier' | 'ops';

async function jobChatRole(c: any, job: any): Promise<ChatRole | null> {
  const phone: string | null = c.get('phone') ?? null;
  const role: string | null = c.get('role') ?? null;
  if (role === 'ops' || isAdmin(c)) return 'ops';
  if (phone && phone === job.sender_phone) return 'seller';
  if (phone && phone === job.recipient_phone) return 'recipient';
  if (role === 'partner' && c.get('courierId') != null && Number(c.get('courierId')) === Number(job.courier_id)) return 'courier';
  if (phone && job.rider_id) {
    const rider: any = await c.env.DB.prepare('SELECT phone FROM riders WHERE id = ?1').bind(job.rider_id).first();
    if (rider?.phone === phone) return 'rider';
  }
  return null;
}

async function getOrCreateJobThread(env: Env, jobId: number): Promise<number> {
  const existing = await env.DB.prepare('SELECT id FROM chat_threads WHERE job_id = ?1').bind(jobId).first<{ id: number }>();
  if (existing) return existing.id;
  const { meta } = await env.DB.prepare(
    'INSERT INTO chat_threads (kind, job_id) VALUES (\'job\', ?1)',
  ).bind(jobId).run();
  return meta.last_row_id as number;
}

async function chatMessages(env: Env, threadId: number) {
  const { results } = await env.DB.prepare(
    `SELECT id, sender_phone, sender_role, body, created_at FROM chat_messages
      WHERE thread_id = ?1 ORDER BY id ASC LIMIT 200`,
  ).bind(threadId).all();
  return results;
}

async function markThreadRead(env: Env, threadId: number, phone: string): Promise<void> {
  const last = await env.DB.prepare(
    'SELECT MAX(id) AS m FROM chat_messages WHERE thread_id = ?1',
  ).bind(threadId).first<{ m: number | null }>();
  await env.DB.prepare(
    `INSERT INTO chat_reads (thread_id, phone, last_read_id) VALUES (?1, ?2, ?3)
      ON CONFLICT(thread_id, phone) DO UPDATE SET last_read_id = MAX(chat_reads.last_read_id, excluded.last_read_id),
        updated_at = datetime('now')`,
  ).bind(threadId, phone, last?.m ?? 0).run();
}

async function notifyChatParticipants(env: Env, thread: any, job: any, fromPhone: string, preview: string): Promise<void> {
  const targets = new Set<string>();
  if (job) {
    if (job.sender_phone) targets.add(job.sender_phone);
    if (job.recipient_phone) targets.add(job.recipient_phone);
    if (job.rider_id) {
      const rider = await env.DB.prepare('SELECT phone FROM riders WHERE id = ?1').bind(job.rider_id).first<{ phone: string }>();
      if (rider?.phone) targets.add(rider.phone);
    }
  } else if (thread?.phone) {
    targets.add(thread.phone);
    const op = ownerPhone(env);
    if (op) targets.add(op);
  }
  targets.delete(fromPhone);
  for (const t of targets) {
    await sendToPhone(env, t, { title: 'New DropOff message', body: preview, data: { kind: 'chat', thread_id: String(thread?.id ?? '') } });
  }
}

// Job thread — sellers/riders/partners/ops (JWT or key)
app.get('/jobs/:ref/chat', async (c) => {
  const job = await c.env.DB.prepare(
    'SELECT id, ref, sender_phone, recipient_phone, courier_id, rider_id FROM jobs WHERE ref = ?1',
  ).bind(c.req.param('ref')).first<any>();
  if (!job) return c.json({ error: 'not found' }, 404);
  const chatRole = await jobChatRole(c, job);
  if (!chatRole) return c.json({ error: 'not found' }, 404); // no existence leak
  const threadId = await getOrCreateJobThread(c.env, job.id);
  if (c.get('phone')) await markThreadRead(c.env, threadId, c.get('phone')!);
  return c.json({ thread_id: threadId, role: chatRole, messages: await chatMessages(c.env, threadId) });
});

app.post('/jobs/:ref/chat', async (c) => {
  if (await rateLimited(c, 'chat_send', 30, 10)) return c.json({ error: 'too_many_requests' }, 429);
  const b: any = await c.req.json().catch(() => null);
  const body = String(b?.body ?? '').trim().slice(0, 500);
  if (!body) return c.json({ error: 'body required' }, 400);
  if (containsProfanity(body)) return c.json({ error: 'message_blocked', message: 'Keep messages respectful.' }, 400);
  const job = await c.env.DB.prepare(
    'SELECT id, ref, sender_phone, recipient_phone, courier_id, rider_id FROM jobs WHERE ref = ?1',
  ).bind(c.req.param('ref')).first<any>();
  if (!job) return c.json({ error: 'not found' }, 404);
  const chatRole = await jobChatRole(c, job);
  if (!chatRole) return c.json({ error: 'not found' }, 404);
  const threadId = await getOrCreateJobThread(c.env, job.id);
  const senderPhone = c.get('phone') ?? 'ops';
  const { meta } = await c.env.DB.prepare(
    `INSERT INTO chat_messages (thread_id, sender_phone, sender_role, body) VALUES (?1, ?2, ?3, ?4)`,
  ).bind(threadId, senderPhone, chatRole, body).run();
  await markThreadRead(c.env, threadId, senderPhone);
  c.executionCtx.waitUntil(
    notifyChatParticipants(c.env, { id: threadId }, job, senderPhone, body.slice(0, 60)).catch(() => {}),
  );
  return c.json({ ok: true, id: meta.last_row_id });
});

// Recipient chat via the tracking token (no account — token is the credential)
app.get('/track/:token/chat', async (c) => {
  const row = await c.env.DB.prepare(
    `SELECT t.job_id FROM tracking_tokens t WHERE t.token = ?1 AND (t.expires_at IS NULL OR t.expires_at > datetime('now'))`,
  ).bind(c.req.param('token')).first<{ job_id: number }>();
  if (!row) return c.json({ error: 'not found' }, 404);
  const threadId = await getOrCreateJobThread(c.env, row.job_id);
  const messages = await chatMessages(c.env, threadId);
  // recipient read state keyed by their phone on the job
  const job = await c.env.DB.prepare('SELECT recipient_phone FROM jobs WHERE id = ?1').bind(row.job_id).first<{ recipient_phone: string }>();
  if (job?.recipient_phone) await markThreadRead(c.env, threadId, job.recipient_phone);
  return c.json({ thread_id: threadId, role: 'recipient', messages });
});

app.post('/track/:token/chat', async (c) => {
  if (await rateLimited(c, 'chat_send', 30, 10)) return c.json({ error: 'too_many_requests' }, 429);
  const b: any = await c.req.json().catch(() => null);
  const body = String(b?.body ?? '').trim().slice(0, 500);
  if (!body) return c.json({ error: 'body required' }, 400);
  if (containsProfanity(body)) return c.json({ error: 'message_blocked', message: 'Keep messages respectful.' }, 400);
  const row = await c.env.DB.prepare(
    `SELECT t.job_id FROM tracking_tokens t WHERE t.token = ?1 AND (t.expires_at IS NULL OR t.expires_at > datetime('now'))`,
  ).bind(c.req.param('token')).first<{ job_id: number }>();
  if (!row) return c.json({ error: 'not found' }, 404);
  const job = await c.env.DB.prepare(
    'SELECT id, ref, sender_phone, recipient_phone, courier_id, rider_id FROM jobs WHERE id = ?1',
  ).bind(row.job_id).first<any>();
  if (!job) return c.json({ error: 'not found' }, 404);
  const threadId = await getOrCreateJobThread(c.env, job.id);
  const { meta } = await c.env.DB.prepare(
    `INSERT INTO chat_messages (thread_id, sender_phone, sender_role, body) VALUES (?1, ?2, 'recipient', ?3)`,
  ).bind(threadId, job.recipient_phone, body).run();
  await markThreadRead(c.env, threadId, job.recipient_phone);
  c.executionCtx.waitUntil(
    notifyChatParticipants(c.env, { id: threadId }, job, job.recipient_phone, body.slice(0, 60)).catch(() => {}),
  );
  return c.json({ ok: true, id: meta.last_row_id });
});

// Support thread (seller/anyone signed in <-> ops)
app.post('/chat/support', async (c) => {
  if (await rateLimited(c, 'chat_send', 20, 10)) return c.json({ error: 'too_many_requests' }, 429);
  const b: any = await c.req.json().catch(() => null);
  const body = String(b?.body ?? '').trim().slice(0, 500);
  const phone = c.get('phone');
  if (!phone) return c.json({ error: 'identity_required' }, 401);
  const existing = await c.env.DB.prepare(
    `SELECT id FROM chat_threads WHERE kind = 'support' AND phone = ?1`,
  ).bind(phone).first<{ id: number }>();
  let threadId: number;
  if (existing) threadId = existing.id;
  else {
    const { meta } = await c.env.DB.prepare(
      `INSERT INTO chat_threads (kind, phone) VALUES ('support', ?1)`,
    ).bind(phone).run();
    threadId = meta.last_row_id as number;
  }
  if (body) {
    if (containsProfanity(body)) return c.json({ error: 'message_blocked' }, 400);
    await c.env.DB.prepare(
      `INSERT INTO chat_messages (thread_id, sender_phone, sender_role, body) VALUES (?1, ?2, 'seller', ?3)`,
    ).bind(threadId, phone, body).run();
    const thread = { id: threadId, phone };
    c.executionCtx.waitUntil(notifyChatParticipants(c.env, thread, null, phone, body.slice(0, 60)).catch(() => {}));
  }
  await markThreadRead(c.env, threadId, phone);
  return c.json({ thread_id: threadId, role: 'seller', messages: await chatMessages(c.env, threadId) });
});

// Ops replies on a support thread
app.post('/chat/support/:id/reply', async (c) => {
  if (c.get('role') !== 'ops' && !isAdmin(c)) return c.json({ error: 'forbidden' }, 403);
  const b: any = await c.req.json().catch(() => null);
  const body = String(b?.body ?? '').trim().slice(0, 500);
  if (!body) return c.json({ error: 'body required' }, 400);
  const threadId = Number(c.req.param('id'));
  const thread = await c.env.DB.prepare(`SELECT id, phone FROM chat_threads WHERE id = ?1 AND kind = 'support'`).bind(threadId).first<any>();
  if (!thread) return c.json({ error: 'not found' }, 404);
  await c.env.DB.prepare(
    `INSERT INTO chat_messages (thread_id, sender_phone, sender_role, body) VALUES (?1, ?2, 'ops', ?3)`,
  ).bind(threadId, c.get('phone') ?? 'ops', body).run();
  c.executionCtx.waitUntil(notifyChatParticipants(c.env, thread, null, c.get('phone') ?? 'ops', body.slice(0, 60)).catch(() => {}));
  return c.json({ ok: true });
});

// Inbox: my threads with unread counts (seller + recipient-with-JWT + rider view)
app.get('/chat/threads', async (c) => {
  const phone = c.get('phone');
  if (!phone) return c.json({ error: 'identity_required' }, 401);
  const rider = await c.env.DB.prepare('SELECT id FROM riders WHERE phone = ?1').bind(phone).first<{ id: number }>();
  const { results } = await c.env.DB.prepare(
    `SELECT t.id, t.kind, t.job_id, j.ref AS job_ref, j.dest_city,
            (SELECT body FROM chat_messages m WHERE m.thread_id = t.id ORDER BY m.id DESC LIMIT 1) AS last_message,
            (SELECT created_at FROM chat_messages m WHERE m.thread_id = t.id ORDER BY m.id DESC LIMIT 1) AS last_at,
            (SELECT COUNT(*) FROM chat_messages m WHERE m.thread_id = t.id AND m.id > COALESCE((SELECT last_read_id FROM chat_reads r WHERE r.thread_id = t.id AND r.phone = ?1), 0) AND m.sender_phone <> ?1) AS unread
       FROM chat_threads t
       LEFT JOIN jobs j ON j.id = t.job_id
      WHERE (t.kind = 'support' AND t.phone = ?1)
         OR (t.job_id IS NOT NULL AND EXISTS (
              SELECT 1 FROM jobs jj WHERE jj.id = t.job_id
                AND (jj.sender_phone = ?1 OR jj.recipient_phone = ?1
                     OR (?2 IS NOT NULL AND jj.rider_id = ?2))))`,
  ).bind(phone, rider?.id ?? null).all();
  return c.json({ threads: results });
});

/* -------- admin/superadmin SMS communication + marketing ------------------- */
// Single send or audience broadcast (marketing + operational notices). Every
// send lands in sms_broadcasts for the audit trail.

const SMS_AUDIENCES = ['all', 'accounts', 'sellers', 'subscribers'] as const;
const SMS_BROADCAST_CAP = 500;

app.post('/admin/sms', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'admin_key_required' }, 403);
  const b: any = await c.req.json().catch(() => null);
  const message = String(b?.message ?? '').trim();
  const phone = normalizeZmPhone(String(b?.phone ?? ''));
  if (!message) return c.json({ error: 'message required' }, 400);
  if (message.length > 600) return c.json({ error: 'message too long (max 600 chars)' }, 400);
  const sender = c.get('phone') ?? 'admin-key';
  const res = await sendSms(c.env, phone, message);
  await c.env.DB.prepare(
    `INSERT INTO sms_broadcasts (sender, audience, recipient_count, sent_count, body) VALUES (?1, 'single', 1, ?2, ?3)`,
  ).bind(sender, res.sent ? 1 : 0, message).run();
  return c.json({ ok: res.sent, phone, error: res.error ?? null });
});

app.post('/admin/sms/broadcast', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'admin_key_required' }, 403);
  const b: any = await c.req.json().catch(() => null);
  const message = String(b?.message ?? '').trim();
  const audience = String(b?.audience ?? '').toLowerCase();
  const extraPhones = Array.isArray(b?.phones) ? b.phones.map((p: unknown) => String(p)) : [];
  if (!message) return c.json({ error: 'message required' }, 400);
  if (message.length > 600) return c.json({ error: 'message too long (max 600 chars)' }, 400);
  if (!SMS_AUDIENCES.includes(audience as any)) {
    return c.json({ error: `audience must be one of: ${SMS_AUDIENCES.join(', ')}` }, 400);
  }

  const phones = new Set<string>();
  if (audience === 'all' || audience === 'accounts') {
    const { results } = await c.env.DB.prepare('SELECT phone FROM auth_users WHERE phone IS NOT NULL').all();
    for (const r of results as any[]) if (r.phone) phones.add(r.phone);
  }
  if (audience === 'all' || audience === 'sellers') {
    const { results } = await c.env.DB.prepare('SELECT DISTINCT sender_phone AS phone FROM jobs').all();
    for (const r of results as any[]) if (r.phone) phones.add(r.phone);
  }
  if (audience === 'all' || audience === 'subscribers') {
    const { results } = await c.env.DB.prepare(`SELECT phone FROM subscriptions WHERE status = 'active'`).all();
    for (const r of results as any[]) if (r.phone) phones.add(r.phone);
  }
  for (const raw of extraPhones) {
    try { phones.add(normalizeZmPhone(raw)); } catch { /* skip invalid */ }
  }
  // never message the ops/test service identity
  phones.delete('ops');

  const recipients = [...phones].slice(0, SMS_BROADCAST_CAP);
  const sender = c.get('phone') ?? 'admin-key';
  const { meta } = await c.env.DB.prepare(
    `INSERT INTO sms_broadcasts (sender, audience, recipient_count, body) VALUES (?1, ?2, ?3, ?4)`,
  ).bind(sender, audience, recipients.length, message).run();
  const broadcastId = meta.last_row_id as number;

  c.executionCtx.waitUntil((async () => {
    let sent = 0;
    const results = await Promise.allSettled(recipients.map((p) => sendSms(c.env, p, message)));
    for (const r of results) if (r.status === 'fulfilled' && r.value.sent) sent++;
    await c.env.DB.prepare('UPDATE sms_broadcasts SET sent_count = ?2 WHERE id = ?1')
      .bind(broadcastId, sent).run().catch(() => {});
  })());

  return c.json({ ok: true, broadcast_id: broadcastId, audience, recipients: recipients.length, capped: phones.size > SMS_BROADCAST_CAP });
});

app.get('/admin/sms/log', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'admin_key_required' }, 403);
  const { results } = await c.env.DB.prepare(
    `SELECT id, sender, audience, recipient_count, sent_count, body, created_at
       FROM sms_broadcasts ORDER BY id DESC LIMIT 50`,
  ).all();
  return c.json({ broadcasts: results });
});

/* ------------------------------ FCM push reg ------------------------------ */
// POST /push/register {token, platform} â€” upserts this device under the JWT's
// phone so the Worker can reach it on job/payment events. DELETE removes it.
app.post('/push/register', async (c) => {
  const phone = c.get('phone');
  if (!phone) return c.json({ error: 'sign in with your account' }, 403);
  const b: any = await c.req.json().catch(() => null);
  const token = b?.token ? String(b.token).trim() : '';
  const platform = b?.platform ? String(b.platform).slice(0, 20) : 'android';
  if (!token) return c.json({ error: 'missing token' }, 400);
  await c.env.DB.prepare(
    `INSERT INTO push_tokens (token, phone, platform) VALUES (?1, ?2, ?3)
      ON CONFLICT(token) DO UPDATE SET phone = ?2, platform = ?3, last_seen = datetime('now')`,
  ).bind(token, c.get('phone') as string, platform).run();
  return c.json({ ok: true });
});

app.delete('/push/register', async (c) => {
  const b: any = await c.req.json().catch(() => null);
  const token = b?.token ? String(b.token).trim() : c.req.header('X-Push-Token') ?? '';
  if (!token) return c.json({ error: 'missing token' }, 400);
  await c.env.DB.prepare('DELETE FROM push_tokens WHERE token = ?1').bind(token).run();
  return c.json({ ok: true });
});

/* ------------------------------ wallet float ------------------------------ */
// Money is ONLY ever moved through wallet_ledger rows (audit trail).
// topup +, job charge -, COD receipt +, rider earning +, rider payout -.
async function walletCreditStatements(
  c: { env: { DB: D1Database } },
  phone: string, amount: number, kind: string, jobId?: number,
): Promise<D1PreparedStatement[]> {
  return [
    c.env.DB.prepare('INSERT OR IGNORE INTO wallets (phone, balance_zmw) VALUES (?1, 0)').bind(phone),
    c.env.DB.prepare(
      `INSERT INTO wallet_ledger (phone, amount_zmw, kind, job_id) VALUES (?1, ?2, ?3, ?4)`,
    ).bind(phone, amount, kind, jobId ?? null),
    c.env.DB.prepare('UPDATE wallets SET balance_zmw = balance_zmw + ?2 WHERE phone = ?1').bind(phone, amount),
  ];
}

app.get('/wallet', async (c) => {
  if (!['ops', 'admin'].includes(c.get('role') as string)) {
    return c.json({ error: 'customer wallets are disabled â€” riders check float via ops' }, 403);
  }
  const phone = c.get('phone');
  if (!phone) return c.json({ error: 'identity_required' }, 401);
  const wallet = await c.env.DB.prepare(
    'SELECT balance_zmw FROM wallets WHERE phone = ?1').bind(phone).first<any>();
  const { results: ledger } = await c.env.DB.prepare(
    `SELECT amount_zmw, kind, job_id, created_at FROM wallet_ledger
      WHERE phone = ?1 ORDER BY id DESC LIMIT 25`,
  ).bind(phone).all();
  return c.json({ phone, balance_zmw: wallet?.balance_zmw ?? 0, ledger });
});

/* ------------------------------- payments --------------------------------- */
// Lipila collect for: kind=job (settle a job), kind=topup (wallet float),
// kind=subscription (auto-renewal). All settle idempotently below.
app.post('/payments', async (c) => {
  if (await rateLimited(c, 'payment_create', 30)) return c.json({ error: 'too_many_requests' }, 429);
  const b: any = await c.req.json().catch(() => null);
  if (!b) return c.json({ error: 'invalid JSON body' }, 400);
  const idemKey = idemKeyOf(c, b);
  const replay = await replayIdempotent(c, idemKey, 'payment');
  if (replay) return replay;
  const kind: string = ['job', 'topup', 'subscription'].includes(b.kind) ? b.kind : 'job';

  let phone: string;
  let amount = 0;        // the full prompt: base + our platform fee + Lipila legs
  let creditZmw = 0;     // what lands in the wallet on success (top-ups)
  let platformFeeZmw = 0; // DropOff's cut, recorded for the dashboard
  let lipilaFeeZmw = 0;  // Lipila's pass-through legs
  let jobId: number | null = null;
  let subscriptionId: number | null = null;
  let lipilaRef: string;
  const channel = b.channel ?? 'merchant';

  if (kind === 'job') {
    const job = await c.env.DB.prepare(
      'SELECT id, ref, total_zmw, rider_fee_zmw, leg2_fee_zmw, leg2_processing_fee_zmw, promo_discount_zmw, paid, sender_phone FROM jobs WHERE ref = ?1').bind(b.job_ref ?? '').first() as any;
    if (!job) return c.json({ error: 'job not found' }, 404);
    if (job.paid) return c.json({ error: 'job already paid' }, 409);
    // customers pay their OWN job only
    if (c.get('role') === 'customer' && c.get('phone') !== job.sender_phone) {
      return c.json({ error: 'forbidden' }, 403);
    }
    phone = c.get('role') === 'ops' && b.phone ? normalizeZmPhone(b.phone) : c.get('phone')!;
    if (!phone) return c.json({ error: 'missing phone' }, 400);
    // DropOff NEVER holds partner money: charge ONLY the DropOff leg
    // (rider fee + door leg + its processing) and platform processing fees.
    // The courier counter fare is paid directly at the depot. Counter fare is
    // irrelevant to the dropoff leg â€” pass 0 so jobTotals doesn't weight it.
    const dropoffLeg = computeJobTotals({
      counterPriceZmw: 0,
      riderFeeZmw: job.rider_fee_zmw,
      leg2FeeZmw: job.leg2_fee_zmw,
      leg2ProcessingFeeZmw: job.leg2_processing_fee_zmw,
      promoDiscountZmw: job.promo_discount_zmw,
    }).dropoff_leg_zmw;
    // server-computed fees â€” the client never sets an amount. Recorded on the
    // payment row = the CUSTOMER leg only (processing fee). Rider payout costs
    // are absorbed at payout time out of the rider's 10%.
    const fees = collectionFees(dropoffLeg, job.rider_fee_zmw);
    amount = fees.prompt_total_zmw;
    platformFeeZmw = fees.platform_fee_zmw;
    lipilaFeeZmw = fees.lipila_fee_zmw;
    jobId = job.id;
    lipilaRef = `job-${job.ref}`;
  } else if (kind === 'subscription') {
    // Pack activation/renewal: the signed-in seller pays their OWN subscription.
    const caller = c.get('phone');
    if (!caller) return c.json({ error: 'identity_required' }, 401);
    const sub = b.subscription_id
      ? await c.env.DB.prepare('SELECT id, phone, tier FROM subscriptions WHERE id = ?1')
          .bind(Number(b.subscription_id)).first<any>()
      : await c.env.DB.prepare('SELECT id, phone, tier FROM subscriptions WHERE phone = ?1 ORDER BY id DESC LIMIT 1')
          .bind(caller).first<any>();
    if (!sub) return c.json({ error: 'no_subscription', detail: 'Choose a pack first.' }, 404);
    if (c.get('role') === 'customer' && sub.phone !== caller) return c.json({ error: 'forbidden' }, 403);
    const pending = await c.env.DB.prepare(
      `SELECT id FROM payments WHERE subscription_id = ?1 AND status = 'pending'`,
    ).bind(sub.id).first<any>();
    if (pending) return c.json({ error: 'payment_already_pending' }, 409);
    const plan = (await plans(c.env.DB))[sub.tier as PlanTier];
    if (!plan || plan.fee_zmw <= 0) return c.json({ error: 'invalid_tier' }, 400);
    phone = sub.phone;
    platformFeeZmw = platformFee(plan.fee_zmw);
    lipilaFeeZmw = MOMO_COLLECTION_FEE;
    amount = round2(plan.fee_zmw + platformFeeZmw + lipilaFeeZmw);
    subscriptionId = sub.id;
    lipilaRef = `sub-${sub.id}-${new Date().toISOString().slice(0, 10).replace(/-/g, '')}`;
  } else {
    // Top-ups exist ONLY for rider/ops float (COD handling) â€” customers/sellers have no wallet.
    if (!['ops', 'admin'].includes(c.get('role') as string)) {
      return c.json({ error: 'customer wallets are disabled â€” riders top up float only' }, 403);
    }
    phone = c.get('role') === 'ops' && b.phone ? normalizeZmPhone(b.phone) : c.get('phone')!;
    if (!phone) return c.json({ error: 'missing phone' }, 400);
    creditZmw = Math.round(Number(b.amount_zmw) || 0);
    if (creditZmw < 10 || creditZmw > WALLET_TOPUP_CAP_ZMW) {
      return c.json({ error: `ride float top-up must be between K10 and K${WALLET_TOPUP_CAP_ZMW}` }, 400);
    }
    // fees collected once per deposit then amortised across many parcels
    platformFeeZmw = platformFee(creditZmw);
    lipilaFeeZmw = MOMO_COLLECTION_FEE;
    amount = round2(creditZmw + platformFeeZmw + lipilaFeeZmw);
    lipilaRef = `topup-${phone}-${Date.now().toString(36)}`;
  }

  const init = await lipilaCollect(c.env, phone, amount, lipilaRef,
    kind === 'job' ? `DropOff ${lipilaRef}`
      : kind === 'subscription' ? 'DropOff pack activation/renewal'
      : 'DropOff wallet top-up');
  if (!init.ok) return c.json({ error: 'lipila init failed', detail: init.raw }, 502);

  const provider: Provider = b.provider ?? providerFromPhone(phone);
  const { meta } = await c.env.DB.prepare(
    `INSERT INTO payments (job_id, subscription_id, phone, provider, amount_zmw, credit_zmw, platform_fee_zmw,
       lipila_fee_zmw, lipila_reference, status, channel, kind)
     VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,'pending',?10,?11)`,
  ).bind(jobId, subscriptionId, phone, provider, amount, creditZmw, platformFeeZmw, lipilaFeeZmw,
    init.lipilaReference ?? null, channel, kind).run();

  const payload = {
    ok: true, payment_id: meta.last_row_id, lipila_reference: init.lipilaReference,
    amount_zmw: amount, platform_fee_zmw: platformFeeZmw, lipila_fee_zmw: lipilaFeeZmw,
  };
  await saveIdempotent(c.env, idemKey, 'payment', phone, 200, payload);
  return c.json(payload);
});

// Idempotent settlement: the `settled` flag is flipped in the same batch as the
// ledger rows; webhook + status-poll can race safely. Subscription rows renew.
async function settlePaymentSuccess(env: Env, paymentId: number, finalStatus: string): Promise<void> {
  if (finalStatus !== 'success') return;
  const claim = await env.DB.prepare(
    `UPDATE payments SET status = 'success', settled = 1, paid_at = datetime('now')
      WHERE id = ?1 AND settled = 0`,
  ).bind(paymentId).run();
  if (!claim.meta.changes) return; // someone else (webhook/poll) sank it already

  const pay = await env.DB.prepare(
    'SELECT id, phone, amount_zmw, job_id, subscription_id, kind FROM payments WHERE id = ?1',
  ).bind(paymentId).first<any>();
  if (!pay) return;

  if (pay.kind === 'topup') {
    const db = env.DB;
    // credit the base amount only â€” the customer already covered the prompt fee
    const base = pay.credit_zmw && pay.credit_zmw > 0 ? pay.credit_zmw : pay.amount_zmw;
    const stmts: D1PreparedStatement[] = [
      db.prepare('INSERT OR IGNORE INTO wallets (phone, balance_zmw) VALUES (?1, 0)').bind(pay.phone),
      db.prepare(`INSERT INTO wallet_ledger (phone, amount_zmw, kind, job_id) VALUES (?1, ?2, 'topup', NULL)`)
        .bind(pay.phone, base),
      db.prepare('UPDATE wallets SET balance_zmw = balance_zmw + ?2 WHERE phone = ?1').bind(pay.phone, base),
    ];
    if (pay.job_id) stmts.push(db.prepare('UPDATE jobs SET paid = 1 WHERE id = ?1').bind(pay.job_id));
    await env.DB.batch(stmts);
  } else if (pay.kind === 'subscription' && pay.subscription_id) {
    // Activate/renew the pack for another 30-day cycle. Unused parcels do NOT
    // roll over — they expire with the cycle.
    const sub = await env.DB.prepare('SELECT phone, tier, period_start, period_end FROM subscriptions WHERE id = ?1')
      .bind(pay.subscription_id).first<any>();
    const nowStr = new Date().toISOString().slice(0, 19).replace('T', ' ');
    let newStart = nowStr;
    if (sub && sub.period_start && sub.period_end) {
      newStart = sub.period_end > nowStr ? sub.period_start : nowStr;
    }
    await env.DB.prepare(
      `UPDATE subscriptions SET status = 'active',
         period_start = ?2,
         period_end = datetime(?2, '+30 days'),
         rollover_parcels = 0,
         rollover_period = NULL,
         expires_at = datetime(?2, '+30 days'),
         started_at = datetime('now')
       WHERE id = ?1`,
    ).bind(pay.subscription_id, newStart).run();
    await sendToPhone(env, pay.phone, {
      title: sub?.tier ? `${sub.tier} pack renewed` : 'Pack renewed',
      body: 'Renewed for another 30 days. Unused parcels do not carry over — book away!',
      data: { kind: 'subscription_active' },
    });
  } else if (pay.kind === 'upgrade' && pay.subscription_id) {
    // Mid-cycle upgrade: tier + cap already bumped at purchase; this just
    // confirms the prorated payment and celebrates.
    const sub = await env.DB.prepare('SELECT tier FROM subscriptions WHERE id = ?1').bind(pay.subscription_id).first<any>();
    await sendToPhone(env, pay.phone, {
      title: 'Pack upgraded',
      body: sub?.tier ? `You are now on ${sub.tier} — bigger cap, live immediately.` : 'Upgrade complete.',
      data: { kind: 'subscription_active' },
    });
  } else if (pay.kind === 'job' && pay.job_id) {
    // direct mobile-money job payment: mark paid (no wallet rows â€” customers have no wallet)
    await env.DB.batch([
      env.DB.prepare(`UPDATE jobs SET paid = 1 WHERE id = ?1 AND paid = 0`).bind(pay.job_id),
    ]);
    const job = await env.DB.prepare('SELECT ref FROM jobs WHERE id = ?1').bind(pay.job_id).first<{ ref: string }>();
    await sendToPhone(env, pay.phone, {
      title: 'Payment received',
      body: 'Confirmed! Your parcel is booked â€” follow every step in Bookings.',
      data: { job_ref: job?.ref ?? '', kind: 'payment' },
    });
  } else if (pay.kind === 'topup') {
    await sendToPhone(env, pay.phone, {
      title: 'Wallet topped up',
      body: `Your wallet balance is updated.`,
    });
  } else if (pay.kind === 'cod_remit' && pay.job_id) {
    await env.DB.prepare(
      `INSERT INTO job_events (job_id, status, note) VALUES (?1, 'cod_remit_paid', ?2)`,
    ).bind(pay.job_id, 'COD remit paid to sender momo (webhook)').run();
  }
}

/* ---------------------- cron: reconcile stuck payments -------------------- */
// Pending collects can miss their webhook (network, phone off). Sweep every
// pending payment older than 2 minutes, re-check with Lipila and settle what
// actually succeeded. Rows stuck >7 days are closed as failed.
async function reconcilePayments(env: Env): Promise<void> {
  try {
    const { results } = await env.DB.prepare(
      `SELECT id, lipila_reference FROM payments
        WHERE status = 'pending' AND lipila_reference IS NOT NULL
          AND created_at < datetime('now', '-2 minutes')
          AND created_at > datetime('now', '-2 days')
        ORDER BY id LIMIT 50`,
    ).all<any>();
    for (const pay of results ?? []) {
      const status = await lipilaStatus(env, pay.lipila_reference);
      if (status === 'pending') continue;
      await env.DB.prepare('UPDATE payments SET status = ?2 WHERE id = ?1').bind(pay.id, status).run();
      await settlePaymentSuccess(env, pay.id, status);
    }
    const expired = await env.DB.prepare(
      `SELECT id, kind, subscription_id, meta FROM payments
        WHERE status = 'pending' AND created_at < datetime('now', '-7 days')`,
    ).all();
    for (const row of expired.results as any[]) {
      // Abandoned mid-cycle upgrades: hand the seller their old tier back.
      if (row.kind === 'upgrade' || row.meta) {
        try {
          const info = JSON.parse(row.meta ?? '{}') as { prevTier?: string };
          if (info.prevTier && row.subscription_id) {
            await env.DB.prepare('UPDATE subscriptions SET tier = ?2 WHERE id = ?1')
              .bind(row.subscription_id, info.prevTier).run();
          }
        } catch { /* bad meta — skip revert */ }
      }
    }
    await env.DB.prepare(
      `UPDATE payments SET status = 'failed'
        WHERE status = 'pending' AND created_at < datetime('now', '-7 days')`,
    ).run();
  } catch { /* reconciliation is best-effort */ }
}

app.get('/payments/:id/status', async (c) => {
  const id = Number(c.req.param('id'));
  const pay = await c.env.DB.prepare(
    'SELECT id, job_id, phone, provider, amount_zmw, lipila_reference, status, kind FROM payments WHERE id = ?1',
  ).bind(id).first<any>();
  if (!pay) return c.json({ error: 'not found' }, 404);
  const isOwner = c.get('phone') === pay.phone || c.get('role') === 'ops';
  if (!isOwner) return c.json({ error: 'forbidden' }, 403);

  if (pay.status === 'pending' && pay.lipila_reference) {
    const status = await lipilaStatus(c.env, pay.lipila_reference);
    if (status !== 'pending') {
      await c.env.DB.prepare('UPDATE payments SET status = ?2 WHERE id = ?1').bind(pay.id, status).run();
      await settlePaymentSuccess(c.env, pay.id, status);
    }
    return c.json({ status });
  }
  return c.json({ status: pay.status });
});

app.get('/payments/:id/receipt', async (c) => {
  const id = Number(c.req.param('id'));
  const pay = await c.env.DB.prepare(
    `SELECT p.*, j.ref AS job_ref, j.sender_name, j.pickup_address, j.dest_city,
            co.name AS courier_name
       FROM payments p
       LEFT JOIN jobs j ON j.id = p.job_id
       LEFT JOIN couriers co ON co.id = j.courier_id
      WHERE p.id = ?1`,
  ).bind(id).first<any>();
  if (!pay) return c.json({ error: 'not found' }, 404);
  if (c.get('role') === 'customer' && c.get('phone') !== pay.phone) return c.json({ error: 'forbidden' }, 403);
  return c.json({
    receipt_no: `RCPT-${pay.id}`,
    payment_id: pay.id,
    status: pay.status,
    kind: pay.kind,
    paid_at: pay.paid_at,
    created_at: pay.created_at,
    phone: pay.phone,
    job_ref: pay.job_ref ?? null,
    sender_name: pay.sender_name ?? null,
    pickup_address: pay.pickup_address ?? null,
    dest_city: pay.dest_city ?? null,
    courier: pay.courier_name ?? null,
    amounts: {
      total_zmw: pay.amount_zmw,
      credit_zmw: pay.credit_zmw ?? 0,
      platform_fee_zmw: pay.platform_fee_zmw ?? 0,
      lipila_fee_zmw: pay.lipila_fee_zmw ?? 0,
    },
    refund_of_payment_id: pay.refund_of_payment_id ?? null,
    refunded_at: pay.refunded_at ?? null,
    lipila_reference: pay.lipila_reference ?? null,
  });
});

/* ---------------------------- Lipila webhook ------------------------------ */
// NEVER trust the webhook body: anyone can POST {"reference": â€¦, "status":
// "success"} and get free rides. The reported status is ignored â€” we look the
// payment up and re-verify the true status with Lipila's API before settling.
// (cod_remit rows are disbursements we initiated ourselves; we only log them.)
app.post('/webhooks/lipila', async (c) => {
  // Optional shared-secret gate (defence in depth — the body is never trusted).
  if (c.env.LIPILA_WEBHOOK_SECRET) {
    const got = c.req.header('X-Lipila-Signature') ?? c.req.header('X-Webhook-Secret') ?? '';
    const want = c.env.LIPILA_WEBHOOK_SECRET;
    const equal = got.length === want.length && got.split('').every((ch, i) => ch === want[i]);
    if (!equal) return c.json({ error: 'unauthorized' }, 401);
  }
  const b: any = await c.req.json().catch(() => null);
  if (!b) return c.json({ ok: true });
  const ref = b.reference ?? b.data?.reference;
  if (!ref) return c.json({ ok: true });
  const pay = await c.env.DB.prepare(
    'SELECT id, status, kind, lipila_reference FROM payments WHERE lipila_reference = ?1 ORDER BY id DESC LIMIT 1',
  ).bind(String(ref)).first<any>();
  if (!pay) return c.json({ ok: true });

  if (pay.kind === 'cod_remit') {
    // our own disbursement â€” only mark the audit event, settle flag not needed
    if (pay.status !== 'success') await c.env.DB.prepare('UPDATE payments SET status = ?2 WHERE id = ?1').bind(pay.id, 'success').run();
    return c.json({ ok: true });
  }

  if (pay.status === 'pending' && pay.lipila_reference) {
    // authoritative check straight from Lipila â€” body status is advisory only
    const status = await lipilaStatus(c.env, pay.lipila_reference);
    if (status !== 'pending') {
      await c.env.DB.prepare('UPDATE payments SET status = ?2 WHERE id = ?1').bind(pay.id, status).run();
      await settlePaymentSuccess(c.env, pay.id, status);
      return c.json({ ok: true, status });
    }
  }
  return c.json({ ok: true, status: pay.status });
});

/* ------------------------- seller subscription packs ----------------------- */
app.get('/plans', async (c) => c.json({ plans: await plans(c.env.DB), rider_pack_pay_zmw: PACK_RIDER_PAY_ZMW, platform_take: PLATFORM_TAKE }));

/* ---------------------------- partner shop portal -------------------------- */
// Partner accounts are normal auth_users with role='partner' + courier_id, set
// by the superadmin (POST /admin/partners). They log in like any customer, then:
//   GET  /partner/quotes            â†’ the courier's published counter prices
//   POST /partner/quotes            â†’ upsert/confirm a counter price
//   GET  /partner/rides             â†’ parcels handed to this courier
//   POST /partner/rides/:ref/confirm â†’ acknowledge hand-off at the depot
function partnerCourierId(c: { get: (k: string) => unknown }): number | null {
  if (c.get('role') === 'partner') return c.get('courierId') as number ?? null;
  return null;
}

app.get('/partner/me', async (c) => {
  const courierId = partnerCourierId(c);
  const user = await c.env.DB.prepare(
    'SELECT email, full_name FROM auth_users WHERE phone = ?1 AND role = ?2',
  ).bind(c.get('phone') ?? '', c.get('role') ?? 'partner').first<any>();
  const courier = courierId
    ? await c.env.DB.prepare('SELECT id, name, city, depot_name, price_status FROM couriers WHERE id = ?1')
      .bind(courierId).first()
    : null;
  return c.json({
    email: user?.email ?? null, full_name: user?.full_name ?? null,
    courier, role: c.get('role'),
  });
});

app.get('/partner/quotes', async (c) => {
  const courierId = partnerCourierId(c);
  // Partner JWTs are pinned to their own courier — no `?courier_id=` browsing.
  // Ops/admin keys may inspect any courier explicitly.
  const target = c.get('role') === 'partner'
    ? courierId
    : (isAdmin(c) || c.get('role') === 'ops' ? Number(c.req.query('courier_id') ?? 0) : null);
  if (!target) return c.json({ error: 'partner_not_linked_to_courier' }, 403);
  const { results } = await c.env.DB.prepare(
    `SELECT id, courier_id, from_city, to_city, weight_class, service, counter_price_zmw, updated_at
       FROM quotes WHERE courier_id = ?1 ORDER BY to_city, weight_class`,
  ).bind(target).all();
  return c.json({ quotes: results });
});

app.post('/partner/quotes', async (c) => {
  const b: any = await c.req.json().catch(() => null);
  const courierId = partnerCourierId(c);
  const required = ['courier_id', 'from_city', 'to_city', 'weight_class', 'service', 'counter_price_zmw'];
  for (const k of required) if (b?.[k] === undefined) return c.json({ error: `${k} required` }, 400);
  if (courierId && Number(b.courier_id) !== courierId) return c.json({ error: 'forbidden_courier' }, 403);
  if (Number(b.counter_price_zmw) <= 0) return c.json({ error: 'counter_price_zmw must be > 0' }, 400);
  const exists = await c.env.DB.prepare(
    `SELECT id FROM quotes WHERE courier_id = ?1 AND from_city = ?2 AND to_city = ?3
       AND weight_class = ?4 AND service = ?5`,
  ).bind(b.courier_id, b.from_city, b.to_city, b.weight_class, b.service).first<any>();
  let id: number;
  if (exists) {
    await c.env.DB.prepare(
      `UPDATE quotes SET counter_price_zmw = ?2, updated_at = datetime('now') WHERE id = ?1`,
    ).bind(exists.id, b.counter_price_zmw).run();
    id = exists.id;
  } else {
    const { meta } = await c.env.DB.prepare(
      `INSERT INTO quotes (courier_id, from_city, to_city, weight_class, service, counter_price_zmw)
       VALUES (?1,?2,?3,?4,?5,?6)`,
    ).bind(b.courier_id, b.from_city, b.to_city, b.weight_class, b.service, b.counter_price_zmw).run();
    id = meta.last_row_id;
  }
  await c.env.DB.prepare(
    `UPDATE couriers SET price_status = 'confirmed_by_partner' WHERE id = ?1`,
  ).bind(b.courier_id).run();
  return c.json({ ok: true, id, confirmed: true });
});

app.get('/partner/rides', async (c) => {
  const courierId = partnerCourierId(c);
  // Same pinning as quotes: partners only ever see their own depot's rides.
  const target = c.get('role') === 'partner'
    ? courierId
    : (isAdmin(c) || c.get('role') === 'ops' ? Number(c.req.query('courier_id') ?? 0) : null);
  if (!target) return c.json({ error: 'partner_not_linked_to_courier' }, 403);
  const { results } = await c.env.DB.prepare(
    `SELECT j.ref, j.recipient_name, j.recipient_phone, j.dest_city, j.weight_class,
            j.counter_price_zmw, j.total_zmw, j.status, j.paid, j.created_at,
            (SELECT status FROM job_events ev WHERE ev.job_id = j.id ORDER BY ev.id DESC LIMIT 1) AS last_event
       FROM jobs j WHERE j.courier_id = ?1 ORDER BY j.id DESC LIMIT 50`,
  ).bind(target).all();
  return c.json({ jobs: results });
});

app.post('/partner/rides/:ref/confirm', async (c) => {
  const courierId = partnerCourierId(c);
  const job = await c.env.DB.prepare(
    'SELECT id, courier_id FROM jobs WHERE ref = ?1',
  ).bind(c.req.param('ref')).first<any>();
  if (!job) return c.json({ error: 'job not found' }, 404);
  // A partner JWT can only confirm hand-offs at ITS OWN depot — an unlinked
  // partner account confirms nothing.
  if (c.get('role') === 'partner' && (!courierId || job.courier_id !== courierId)) {
    return c.json({ error: 'not_your_courier_job' }, 403);
  }
  if (c.get('role') !== 'partner' && !isAdmin(c) && c.get('role') !== 'ops') {
    return c.json({ error: 'forbidden' }, 403);
  }
  const b: any = await c.req.json().catch(() => ({}));
  await c.env.DB.prepare(
    'INSERT INTO job_events (job_id, status, note) VALUES (?1, ?2, ?3)',
  ).bind(job.id, 'partner_confirmed',
    b?.note ?? `Depot confirmed hand-off${b?.waybill ? ` â€” waybill ${b.waybill}` : ''}`).run();
  if (b?.waybill) {
    await c.env.DB.prepare('UPDATE jobs SET courier_waybill = ?2 WHERE id = ?1').bind(job.id, b.waybill).run();
  }
  return c.json({ ok: true, ref: c.req.param('ref') });
});

/* -------- partner webhook ingestion (any POS/dispatch system) ------------- */
// A courier shop plugs THEIR system into ours with one HTTPS call. Status maps
// 1:1 onto the parcel timeline the sender already watches.
const PARTNER_EVENT_MAP: Record<string, string> = {
  at_depot: 'at_depot', departed: 'departed', arrived: 'arrived',
  ready_for_collection: 'ready_for_collection', delivered: 'delivered',
};
app.post('/webhooks/partner-status', async (c) => {
  const key = c.req.header('X-Partner-Key') ?? '';
  const pk = await c.env.DB.prepare('SELECT courier_id FROM partner_keys WHERE api_key = ?1').bind(key).first<any>();
  if (!pk) return c.json({ error: 'bad_partner_key' }, 403);
  const b: any = await c.req.json().catch(() => null);
  if (!b) return c.json({ error: 'invalid JSON body' }, 400);
  const status = String(b.status ?? '').toLowerCase();
  if (!PARTNER_EVENT_MAP[status]) {
    return c.json({ error: 'status must be one of: ' + Object.keys(PARTNER_EVENT_MAP).join(', ') }, 400);
  }
  const waybill = String(b.waybill ?? '').trim();
  const ref = String(b.ref ?? '').trim();
  if (!waybill && !ref) return c.json({ error: 'waybill or ref required' }, 400);
  let job: any = null;
  if (waybill) job = await c.env.DB.prepare('SELECT id, ref FROM jobs WHERE courier_waybill = ?1 LIMIT 1').bind(waybill).first();
  if (!job && ref) job = await c.env.DB.prepare('SELECT id, ref FROM jobs WHERE ref = ?1 LIMIT 1').bind(ref).first();
  if (!job) return c.json({ error: 'unknown_waybill' }, 404);
  const since = new Date(Date.now() - 5 * 60 * 1000).toISOString().replace('T', ' ').slice(0, 19);
  const dup = await c.env.DB.prepare(
    'SELECT id FROM job_events WHERE job_id = ?1 AND status = ?2 AND created_at > ?3 LIMIT 1',
  ).bind(job.id, PARTNER_EVENT_MAP[status], since).first<any>();
  if (dup) return c.json({ ok: true, deduped: true });
  await c.env.DB.batch([
    c.env.DB.prepare('INSERT INTO job_events (job_id, status, note) VALUES (?1,?2,?3)')
      .bind(job.id, PARTNER_EVENT_MAP[status], `[partner] ${b.note ?? status}${b.at ? ` @ ${b.at}` : ''}`),
    c.env.DB.prepare('UPDATE jobs SET status = ?2 WHERE id = ?1')
      .bind(job.id, PARTNER_EVENT_MAP[status]),
  ]);
  return c.json({ ok: true, ref: job.ref });
});

// Per-partner webhook key. Generate/rotate from the superadmin console.
app.post('/admin/partner-keys', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'admin_key_required' }, 403);
  const b: any = await c.req.json().catch(() => null);
  const cid = Number(b?.courier_id);
  if (!cid) return c.json({ error: 'courier_id required' }, 400);
  const key = crypto.randomUUID().replace(/-/g, '');
  await c.env.DB.prepare(
    `INSERT INTO partner_keys (courier_id, api_key) VALUES (?1, ?2)
     ON CONFLICT(courier_id) DO UPDATE SET api_key = excluded.api_key, created_at = datetime('now')`,
  ).bind(cid, key).run();
  return c.json({
    ok: true, courier_id: cid, api_key: key,
    usage: 'POST /webhooks/partner-status  X-Partner-Key: <key>  {"waybill":"...","status":"departed|arrived|delivered|ready_for_collection|at_depot","note":"optional","at":"ISO"}',
  });
});

/* -------- tiers (seller packs â€” live editable) + promo codes ------------- */
app.get('/admin/tiers', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'admin_key_required' }, 403);
  const packs = await plans(c.env.DB);
  return c.json({ tiers: Object.entries(packs).map(([tier, v]) => ({ tier, ...v })) });
});
app.post('/admin/tiers', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'admin_key_required' }, 403);
  const b: any = await c.req.json().catch(() => null);
  const tier = String(b?.tier ?? '').trim().toLowerCase();
  if (!/^[a-z0-9_]{2,20}$/.test(tier)) return c.json({ error: 'tier id must be 2-20 lowercase letters/digits/_' }, 400);
  const fee = Math.max(0, Number(b?.fee_zmw ?? 0));
  const ppm = Math.max(0, Math.round(Number(b?.parcels_per_month ?? 0)));
  const disc = Math.max(0, Math.min(100, Number(b?.overage_discount_pct ?? 0)));
  const days = Math.max(1, Math.round(Number(b?.cycle_days ?? 30)));
  const rider = Math.max(0, Number(b?.rider_fee_zmw ?? 0));
  const tag = b?.tag == null || String(b.tag).trim() === '' ? null : String(b.tag).trim().slice(0, 40);
  await c.env.DB.prepare(
    `INSERT INTO tiers (tier, fee_zmw, parcels_per_day, parcels_per_month, rider_fee_zmw, overage_discount_pct, cycle_days, tag, active)
     VALUES (?1, ?2, 0, ?3, ?4, ?5, ?6, ?7, 1)
     ON CONFLICT(tier) DO UPDATE SET fee_zmw=excluded.fee_zmw, parcels_per_month=excluded.parcels_per_month,
       rider_fee_zmw=excluded.rider_fee_zmw, overage_discount_pct=excluded.overage_discount_pct,
       cycle_days=excluded.cycle_days, tag=excluded.tag, active=1`,
  ).bind(tier, fee, ppm, rider, disc, days, tag).run();
  return c.json({ ok: true, tier, fee_zmw: fee, parcels_per_month: ppm, rider_fee_zmw: rider,
    overage_discount_pct: disc, cycle_days: days, tag });
});

app.get('/admin/promos', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'admin_key_required' }, 403);
  const { results } = await c.env.DB.prepare('SELECT * FROM promo_codes ORDER BY created_at DESC LIMIT 200').all();
  return c.json({ promos: results });
});
app.post('/admin/promos', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'admin_key_required' }, 403);
  const b: any = await c.req.json().catch(() => null);
  const code = String(b?.code ?? '').trim().toUpperCase();
  if (!/^[A-Z0-9_-]{3,24}$/.test(code)) return c.json({ error: 'code must be 3-24 A-Z/0-9/_/-' }, 400);
  const pct = Number(b?.discount_pct);
  if (!(pct > 0 && pct <= 100)) return c.json({ error: 'discount_pct must be 0-100' }, 400);
  const tier = b?.applies_tier ? String(b.applies_tier).trim().toLowerCase() : null;
  const uses = b?.uses_left == null ? null : Math.max(0, Math.round(Number(b.uses_left)));
  const exp = b?.expires_at ? String(b.expires_at) : null;
  await c.env.DB.prepare(
    `INSERT INTO promo_codes (code, discount_pct, note, applies_tier, uses_left, expires_at, active)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, 1)
     ON CONFLICT(code) DO UPDATE SET discount_pct=excluded.discount_pct, note=excluded.note,
       applies_tier=excluded.applies_tier, uses_left=excluded.uses_left, expires_at=excluded.expires_at, active=1`,
  ).bind(code, pct, b?.note ?? null, tier, uses, exp).run();
  return c.json({ ok: true, code, discount_pct: pct });
});

/* -------- partner collection rails (THEIR POS â€” never DropOff money) ------- */
// Sellers pay the courier directly at the counter/depot using the partner's
// own merchant till (momo / bank / POS terminal / WhatsApp order). DropOff
// bridges the context, not the custody: the money is the partner's, always.
app.post('/partner/pos', async (c) => {
  if (c.get('role') !== 'partner') return c.json({ error: 'partner role required' }, 403);
  const cid = Number(c.get('courierId'));
  if (!cid) return c.json({ error: 'no courier linked to this account' }, 400);
  const b: any = await c.req.json().catch(() => null);
  const rail = String(b?.rail ?? '').trim().toLowerCase();
  if (!['momo', 'bank', 'pos_terminal', 'whatsapp', 'cash'].includes(rail)) {
    return c.json({ error: 'rail must be momo|bank|pos_terminal|whatsapp|cash' }, 400);
  }
  const instructions = String(b?.instructions ?? '').trim() || null;
  const merchant = String(b?.merchant_id ?? '').trim() || null;
  await c.env.DB.prepare(
    `INSERT INTO partner_pos (courier_id, rail, merchant_id, instructions) VALUES (?1,?2,?3,?4)
     ON CONFLICT(courier_id) DO UPDATE SET rail=excluded.rail, merchant_id=excluded.merchant_id,
       instructions=excluded.instructions, updated_at=datetime('now')`,
  ).bind(cid, rail, merchant, instructions).run();
  return c.json({ ok: true, courier_id: cid, rail });
});

async function partnerPosList(db: D1Database) {
  const { results } = await db.prepare(
    `SELECT p.*, co.name AS courier_name FROM partner_pos p JOIN couriers co ON co.id = p.courier_id WHERE p.active = 1 ORDER BY co.name`,
  ).all();
  return results;
}
app.get('/partner/pos', async (c) => {
  const role = c.get('role');
  if (role === 'partner') {
    const cid = Number(c.get('courierId'));
    const row = cid ? await c.env.DB.prepare('SELECT * FROM partner_pos WHERE courier_id = ?1').bind(cid).first() : null;
    const key = cid ? await c.env.DB.prepare('SELECT api_key FROM partner_keys WHERE courier_id = ?1').bind(cid).first() : null;
    return c.json({ pos: row ?? null, webhook_key: (key as any)?.api_key ?? null });
  }
  if (!isAdmin(c)) return c.json({ error: 'admin_key_required' }, 403);
  return c.json({ pos: await partnerPosList(c.env.DB) });
});
app.post('/admin/pos', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'admin_key_required' }, 403);
  const b: any = await c.req.json().catch(() => null);
  const cid = Number(b?.courier_id);
  const rail = String(b?.rail ?? '').trim().toLowerCase();
  if (!cid || !['momo', 'bank', 'pos_terminal', 'whatsapp', 'cash'].includes(rail)) {
    return c.json({ error: 'courier_id and rail (momo|bank|pos_terminal|whatsapp|cash) required' }, 400);
  }
  await c.env.DB.prepare(
    `INSERT INTO partner_pos (courier_id, rail, merchant_id, instructions) VALUES (?1,?2,?3,?4)
     ON CONFLICT(courier_id) DO UPDATE SET rail=excluded.rail, merchant_id=excluded.merchant_id,
       instructions=excluded.instructions, updated_at=datetime('now')`,
  ).bind(cid, rail, String(b?.merchant_id ?? '').trim() || null, String(b?.instructions ?? '').trim() || null).run();
  return c.json({ ok: true, courier_id: cid, rail });
});
app.get('/admin/pos', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'admin_key_required' }, 403);
  return c.json({ pos: await partnerPosList(c.env.DB) });
});

/* -------- rider live pings + smart pickup routing (nearest-neighbor) ------ */
app.post('/rider/ping', async (c) => {
  const b: any = await c.req.json().catch(() => null);
  const lat = Number(b?.lat), lng = Number(b?.lng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return c.json({ error: 'lat/lng required' }, 400);
  const phone = c.get('phone') ?? (c.get('role') === 'ops' ? (b?.phone ?? null) : null);
  if (!phone) return c.json({ error: 'identity_required' }, 401);
  const status = b?.status ? String(b.status) : null;
  if (status && !['available', 'on_route', 'offline'].includes(status)) {
    return c.json({ error: 'status must be available|on_route|offline' }, 400);
  }
  await c.env.DB.prepare(
    `UPDATE riders SET last_lat = ?2, last_lng = ?3, last_seen_at = datetime('now')
       ${status ? ', status = ?4' : ''} WHERE phone = ?1`,
  ).bind(phone, lat, lng, ...(status ? [status] : [])).run();
  return c.json({ ok: true });
});

/** Greedy nearest-neighbor pickup order for a rider's open jobs today. */
function nearestRoute(
  origin: { lat: number; lng: number },
  stops: { ref: string; address: string; lat: number; lng: number }[],
): { ref: string; address: string; lat: number; lng: number; km_from_previous: number }[] {
  const remaining = [...stops];
  const ordered: { ref: string; address: string; lat: number; lng: number; km_from_previous: number }[] = [];
  let cur = origin;
  while (remaining.length) {
    let best = 0, bestKm = Infinity;
    for (let i = 0; i < remaining.length; i++) {
      const km = haversine(cur.lat, cur.lng, remaining[i].lat, remaining[i].lng);
      if (km < bestKm) { bestKm = km; best = i; }
    }
    const [next] = remaining.splice(best, 1);
    ordered.push({ ...next, km_from_previous: round2(bestKm) });
    cur = { lat: next.lat, lng: next.lng };
  }
  return ordered;
}
app.get('/route/pickup', async (c) => {
  if (!['ops', 'admin'].includes(c.get('role') as string)) return c.json({ error: 'ops or admin role required' }, 403);
  let phone = c.req.query('phone');
  if (phone) { try { phone = normalizeZmPhone(phone); } catch { return c.json({ error: 'bad phone' }, 400); } }
  const q = phone
    ? c.env.DB.prepare(
        // jobs assigned to this rider OR still unassigned, today, still open.
        // (fixed: no phantom rider_phone column + parenthesised OR/AND precedence)
        `SELECT j.ref, j.pickup_address, j.pickup_lat, j.pickup_lng, j.pickup_at, j.round_trip
           FROM jobs j
          WHERE (j.rider_id IS NULL OR j.rider_id IN (SELECT id FROM riders WHERE phone = ?1))
            AND date(j.created_at, '${CAT_OFFSET}') = date('now', '${CAT_OFFSET}')
            AND j.status NOT IN ('delivered','ready_for_collection')
            AND j.pickup_lat IS NOT NULL AND j.pickup_lng IS NOT NULL`,
      ).bind(phone).all()
    : c.env.DB.prepare(
        `SELECT ref, pickup_address, pickup_lat, pickup_lng, pickup_at, round_trip FROM jobs
          WHERE date(created_at, '${CAT_OFFSET}') = date('now', '${CAT_OFFSET}')
            AND status NOT IN ('delivered','ready_for_collection')
            AND pickup_lat IS NOT NULL AND pickup_lng IS NOT NULL`,
      ).all();
  const { results } = await q;
  const hub = { lat: -15.4255, lng: 28.2805 }; // Platinum Chibolya depot anchor
  const rows = (results as any[]);
  // Timed pickups first (earliest slot first), then the ASAP run optimized by
  // nearest-neighbor â€” so a rider never misses a booked window.
  const timed = rows.filter((r) => r.pickup_at).sort((a, b) => String(a.pickup_at).localeCompare(String(b.pickup_at)));
  const asap = rows.filter((r) => !r.pickup_at);
  return c.json({
    origin: hub,
    timed: timed.map((r) => ({ ...r, km_from_previous: null })),
    asap: nearestRoute(hub, asap.map((r) => ({ ref: r.ref, address: r.pickup_address, lat: r.pickup_lat, lng: r.pickup_lng }))),
    count: rows.length,
  });
});

/* -------- batch pickup scheduling (no zigzag) ----------------------------- */
// Sweep algorithm: bucket scattered stops by latitude bands and walk each band
// east-west / west-east alternately ("snake" rasterisation) â€” provably minimal
// crossings, the classic non-crossing courier path for a city-wide route.
// Band = ~1.3 km; stop cap 25 per rider.
app.get('/batch/pickup', async (c) => {
  if (!['ops', 'admin'].includes(c.get('role') as string)) {
    return c.json({ error: 'ops or admin role required' }, 403);
  }
  const dateParam = c.req.query('date') ?? new Date().toISOString().slice(0, 10);
  const maxStops = Math.max(1, Math.min(60, Number(c.req.query('max_stops') ?? '25') || 25));
  const bandDeg = Number(c.req.query('band_km') ?? '1.3') / 111; // ~1Â° â‰ˆ 111km
  const { results } = await c.env.DB.prepare(
    `SELECT ref, pickup_address, pickup_lat, pickup_lng, weight_class, description
       FROM jobs
      WHERE date(created_at, '${CAT_OFFSET}') = ?1
        AND status IN ('created', 'rider_assigned')
        AND pickup_lat IS NOT NULL AND pickup_lng IS NOT NULL`,
  ).bind(dateParam).all();

  const stops = (results as any[]).map((r) => ({
    ref: r.ref, address: r.pickup_address, lat: r.pickup_lat, lng: r.pickup_lng,
    weight: r.weight_class, note: r.description ?? '',
  }));

  const bands = new Map<number, typeof stops>();
  for (const s of stops) {
    const key = Math.floor(s.lat / bandDeg);
    const list = bands.get(key) ?? [];
    list.push(s); bands.set(key, list);
  }
  const orderedAll: typeof stops = [];
  [...bands.keys()].sort((a, b) => a - b).forEach((k, i) => {
    const row = bands.get(k) ?? [];
    row.sort((a, b) => (i % 2 === 0 ? a.lng - b.lng : b.lng - a.lng)); // snake
    orderedAll.push(...row);
  });

  const hub = { lat: -15.4255, lng: 28.2805 };
  const routes: ReturnType<typeof buildRoute>[] = [];
  while (orderedAll.length) routes.push(buildRoute(orderedAll.splice(0, maxStops), hub, routes.length + 1));
  return c.json({
    date: dateParam,
    hub: 'Platinum Chibolya',
    stop_count: stops.length,
    routes,
    algorithm: `snake-latbands band=${bandDeg.toFixed(4)}Â° cap=${maxStops}`,
  });
});

function buildRoute(stops: { ref: string; address: string; lat: number; lng: number; weight: string; note: string }[], hub: { lat: number; lng: number }, idx: number) {
  let prev = hub, km = 0;
  const out = stops.map((s, i) => {
    const d = haversine(prev.lat, prev.lng, s.lat, s.lng);
    km += d;
    prev = { lat: s.lat, lng: s.lng };
    return {
      seq: i + 1, ref: s.ref, address: s.address, weight: s.weight,
      km_from_prev: round2(d), cum_km: round2(km), note: s.note,
    };
  });
  return {
    route: idx,
    stops: out,
    total_km: round2(km),
    est_minutes: Math.round((km / 22) * 60 + stops.length * 4),
    // quick rider workload hint: split evenly-ish across a 3-rider fleet
    rider_hint: `rider-${((idx - 1) % 3) + 1}`,
  };
}

/* ------------------ smart rider auto-assign + dynamic re-optimization ----- */
// Nearest available rider with free capacity gets the job; ties broken by
// current load (emptiest rider first) so work spreads evenly.
async function nearestAvailableRider(env: Env, lat: number, lng: number): Promise<{ rider: any; km: number } | null> {
  const riders = await env.DB.prepare(
    `SELECT id, phone, full_name, vehicle, last_lat, last_lng, status, active, capacity, current_load
       FROM riders WHERE active = 1 AND status IN ('available', 'on_route')`
  ).all<any>();
  let best: { rider: any; km: number } | null = null;
  for (const r of (riders.results ?? [])) {
    const load = Number(r.current_load ?? 0), cap = Number(r.capacity ?? 8);
    if (load >= cap) continue;
    const km = haversine(lat, lng, Number(r.last_lat ?? -15.4255), Number(r.last_lng ?? 28.2805));
    const score = km + load * 0.5; // prefer nearer, then emptier
    if (!best || score < best.km + Number(best.rider.current_load ?? 0) * 0.5) best = { rider: r, km };
  }
  return best;
}

app.post('/jobs/:ref/auto-assign', async (c) => {
  if (!['ops', 'admin'].includes(c.get('role') as string)) return c.json({ error: 'ops or admin required' }, 403);
  const ref = c.req.param('ref');
  const job = await c.env.DB.prepare(
    `SELECT j.*, c.lat AS depot_lat, c.lng AS depot_lng FROM jobs j
      LEFT JOIN couriers c ON c.id = j.courier_id WHERE j.ref = ?1`,
  ).bind(ref).first<any>();
  if (!job) return c.json({ error: 'not found' }, 404);
  if (job.rider_id) return c.json({ error: 'already assigned', rider_id: job.rider_id }, 409);
  if (!Number.isFinite(job.pickup_lat) || !Number.isFinite(job.pickup_lng)) {
    return c.json({ error: 'job has no pickup coordinates' }, 400);
  }
  const pick = await nearestAvailableRider(c.env, job.pickup_lat, job.pickup_lng);
  if (!pick) return c.json({ error: 'no rider with capacity near pickup' }, 404);
  const etaMin = Math.round((pick.km / 22) * 60 + 4); // ~22 km/h city + 4 min stop
  await c.env.DB.batch([
    c.env.DB.prepare(
      `UPDATE jobs SET rider_id = ?1, status = 'rider_assigned', assigned_at = datetime('now'), eta_minutes = ?2 WHERE ref = ?3`,
    ).bind(pick.rider.id, etaMin, ref),
    c.env.DB.prepare(
      `UPDATE riders SET current_load = current_load + 1, status = 'on_route', route_updated_at = datetime('now') WHERE id = ?1`,
    ).bind(pick.rider.id),
  ]);
  // notify the rider + sender that a rider was assigned
  await sendToPhone(c.env, job.sender_phone, {
    title: 'Rider assigned',
    body: `Rider ${pick.rider.full_name} (${pick.rider.vehicle}) is heading to your pickup â€” track them live in Bookings.`,
    data: { job_ref: ref, kind: 'rider_assigned' },
  });
  if (pick.rider.phone !== job.sender_phone) {
    await sendToPhone(c.env, pick.rider.phone, {
      title: 'New pickup assigned',
      body: `Job ${ref} â€” ${job.pickup_address}, ETA ~${etaMin} min.`,
      data: { job_ref: ref, kind: 'job_assigned' },
    });
  }
  return c.json({ ok: true, ref, rider_id: pick.rider.id, rider: pick.rider.full_name, eta_minutes: etaMin, km: round2(pick.km) });
});

// Re-optimize ONE rider's route from their live location, optionally inserting
// a brand-new stop at the cheapest position (mid-route top-up). Returns the
// ordered stop list with ETAs so the rider's app can redraw the map.
app.post('/batch/reoptimize', async (c) => {
  if (!['ops', 'admin'].includes(c.get('role') as string)) return c.json({ error: 'ops or admin required' }, 403);
  const b: any = await c.req.json().catch(() => null);
  const phone = b?.rider_phone ? normalizeZmPhone(b.rider_phone) : null;
  if (!phone) return c.json({ error: 'rider_phone required' }, 400);
  const rider = await c.env.DB.prepare(
    `SELECT id, full_name, last_lat, last_lng, capacity, current_load FROM riders WHERE phone = ?1 AND active = 1`,
  ).bind(phone).first<any>();
  if (!rider) return c.json({ error: 'rider not found' }, 404);
  const origin = { lat: Number(rider.last_lat ?? -15.4255), lng: Number(rider.last_lng ?? 28.2805) };
  const stops: { ref: string; address: string; lat: number; lng: number; weight?: string; note?: string }[] = [];
  const rows = await c.env.DB.prepare(
    `SELECT ref, pickup_address, pickup_lat, pickup_lng, weight_class, description FROM jobs
       WHERE rider_id = ?1 AND status IN ('created', 'rider_assigned', 'picked_up')
         AND pickup_lat IS NOT NULL AND pickup_lng IS NOT NULL`,
  ).bind(rider.id).all<any>();
  for (const r of (rows.results ?? [])) stops.push({ ref: r.ref, address: r.pickup_address, lat: r.pickup_lat, lng: r.pickup_lng, weight: r.weight_class, note: r.description ?? '' });
  // optional new stop inserted at the cheapest position (mid-route top-up)
  if (b?.new_stop && Number.isFinite(b.new_stop.lat) && Number.isFinite(b.new_stop.lng)) {
    const ns = { ref: b.new_stop.ref ?? 'new', address: b.new_stop.address ?? '', lat: b.new_stop.lat, lng: b.new_stop.lng, weight: b.new_stop.weight, note: b.new_stop.note ?? '' };
    if (stops.length === 0) stops.push(ns);
    else {
      let bestIdx = 0, bestExtra = Infinity;
      let prev = origin;
      for (let i = 0; i <= stops.length; i++) {
        const next = i < stops.length ? stops[i] : null;
        const a = haversine(prev.lat, prev.lng, ns.lat, ns.lng);
        const bDist = next ? haversine(ns.lat, ns.lng, next.lat, next.lng) : 0;
        const direct = next ? haversine(prev.lat, prev.lng, next.lat, next.lng) : 0;
        const extra = a + bDist - direct;
        if (extra < bestExtra) { bestExtra = extra; bestIdx = i; }
        if (next) prev = { lat: next.lat, lng: next.lng };
      }
      stops.splice(bestIdx, 0, ns);
    }
  }
  const ordered = nearestRoute(origin, stops);
  let elapsedKm = 0;
  const etaStops = ordered.map((s) => {
    const d = haversine(origin.lat, origin.lng, s.lat, s.lng); // approx cum from rider pos
    elapsedKm = d; // nearestRoute already gives km_from_prev; recompute cum simply
    return { ...s, est_minutes_from_now: Math.round((elapsedKm / 22) * 60 + stops.indexOf(s) * 4) };
  });
  await c.env.DB.prepare(
    `UPDATE riders SET route_json = ?2, route_updated_at = datetime('now') WHERE id = ?1`,
  ).bind(rider.id, JSON.stringify(etaStops)).run();
  return c.json({ rider: rider.full_name, origin, stops: etaStops, total_stops: etaStops.length, algorithm: 'nearest-neighbor + cheapest-insert' });
});

// Rider's current optimized route (JWT-authenticated rider phone).
app.get('/rider/route', async (c) => {
  const phone = c.get('phone');
  if (!phone) return c.json({ error: 'identity_required' }, 401);
  const rider = await c.env.DB.prepare(
    `SELECT id, full_name, last_lat, last_lng, route_json, route_updated_at, capacity, current_load FROM riders WHERE phone = ?1 AND active = 1`,
  ).bind(phone).first<any>();
  if (!rider) return c.json({ error: 'rider not found' }, 404);
  const route = rider.route_json ? JSON.parse(rider.route_json) : null;
  const jobs = await c.env.DB.prepare(
    `SELECT ref, pickup_address, status, eta_minutes FROM jobs WHERE rider_id = ?1 AND status NOT IN ('delivered','ready_for_collection') ORDER BY assigned_at`,
  ).bind(rider.id).all<any>();
  return c.json({ rider: rider.full_name, load: `${rider.current_load}/${rider.capacity}`, last_seen_at: rider.route_updated_at, route, jobs: jobs.results ?? [] });
});
/* --------------------- rider task queue (slot batches) -------------------- */
// The rider's day, grouped into sweep windows like a task queue: stop order,
// ETA chain, parcel totals, majority destination branch, target drop-off time.
const SWEEP_SLOTS: Record<string, { label: string; cutoff: string; start: string; target: string; range: string }> = {
  '06:00': { label: '06:00–07:30 slot', cutoff: '05:30', start: '06:00', target: '08:30', range: '6:00–7:30 AM' },
  '10:00': { label: '10:00–11:30 slot', cutoff: '09:30', start: '10:00', target: '12:30', range: '10:00–11:30 AM' },
  '14:00': { label: '14:00–15:30 slot', cutoff: '13:30', start: '14:00', target: '16:30', range: '2:00–3:30 PM' },
};

function catHM(offsetMinutes = 0): string {
  const d = new Date(Date.now() + 2 * 3600_000 + offsetMinutes * 60_000);
  return `${String(d.getUTCHours()).padStart(2, '0')}:${String(d.getUTCMinutes()).padStart(2, '0')}`;
}

function minutesOf(hm: string): number {
  const [h, m] = hm.split(':').map(Number);
  return h * 60 + m;
}

function hmOf(minutes: number): string {
  const m = ((minutes % 1440) + 1440) % 1440;
  return `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;
}

app.get('/rider/queue', async (c) => {
  let phone = c.get('phone') ?? '';
  if (c.get('role') === 'ops') {
    try { phone = normalizeZmPhone(c.req.query('phone') ?? (phone || '')); }
    catch { return c.json({ error: 'invalid_phone' }, 400); }
  }
  if (!phone) return c.json({ error: 'identity_required' }, 401);
  const rider = await c.env.DB.prepare(
    'SELECT id, full_name, last_lat, last_lng FROM riders WHERE phone = ?1 AND active = 1',
  ).bind(phone).first<any>();
  if (!rider) return c.json({ error: 'rider not found' }, 404);

  const { results } = await c.env.DB.prepare(
    `SELECT j.ref, j.pickup_address, j.pickup_lat, j.pickup_lng, j.parcels, j.status,
            j.sender_name, j.eta_minutes, j.pickup_window, j.created_at,
            co.name AS courier_name, co.depot_name, co.city AS courier_city
       FROM jobs j JOIN couriers co ON co.id = j.courier_id
      WHERE j.rider_id = ?1 AND j.status NOT IN ('delivered', 'ready_for_collection')
      ORDER BY j.created_at`,
  ).bind(rider.id).all<any>();

  // Bucket into sweep slots (instant = ASAP).
  const buckets: Record<string, any[]> = { instant: [], '06:00': [], '10:00': [], '14:00': [] };
  for (const job of results) {
    const w = SWEEP_SLOTS[job.pickup_window] ? job.pickup_window : 'instant';
    buckets[w].push(job);
  }

  const depot = { lat: -15.4255, lng: 28.2805 };
  const batches = Object.entries(buckets)
    .filter(([, jobs]) => jobs.length > 0)
    .map(([slot, jobs]) => {
      // Nearest-neighbour stop chain from the rider's last known position.
      let curLat = Number(rider.last_lat ?? depot.lat);
      let curLng = Number(rider.last_lng ?? depot.lng);
      const remaining = [...jobs];
      const stops: any[] = [];
      // Window slots start sweeping at the slot time; instant starts now.
      let clockMin = slot === 'instant'
        ? minutesOf(catHM())
        : minutesOf(SWEEP_SLOTS[slot].start);
      const slotStartMin = clockMin;
      while (remaining.length) {
        let bestIdx = 0;
        let bestKm = Infinity;
        for (let i = 0; i < remaining.length; i++) {
          const lat = Number(remaining[i].pickup_lat ?? 0);
          const lng = Number(remaining[i].pickup_lng ?? 0);
          const km = lat && lng ? haversine(curLat, curLng, lat, lng) : 2; // no coords -> ~2km guess
          if (km < bestKm) { bestKm = km; bestIdx = i; }
        }
        const job = remaining.splice(bestIdx, 1)[0];
        clockMin += Math.max(5, Math.round((bestKm / 22) * 60 + 4)); // 22 km/h + 4 min stop
        stops.push({
          n: stops.length + 1,
          time: hmOf(clockMin),
          ref: job.ref,
          address: job.pickup_address,
          seller: job.sender_name,
          parcels: Number(job.parcels ?? 1),
          status: job.status,
          courier: job.courier_name,
        });
        curLat = Number(job.pickup_lat ?? curLat);
        curLng = Number(job.pickup_lng ?? curLng);
      }
      // Majority destination branch across the batch.
      const counts = new Map<string, { name: string; branch: string; city: string; n: number }>();
      for (const j of jobs) {
        const key = `${j.courier_name}|${j.depot_name}`;
        const e = counts.get(key) ?? { name: j.courier_name, branch: j.depot_name, city: j.courier_city, n: 0 };
        e.n++;
        counts.set(key, e);
      }
      const dest = [...counts.values()].sort((a, b) => b.n - a.n)[0];
      const totalParcels = jobs.reduce((s, j) => s + Number(j.parcels ?? 1), 0);
      const target = slot === 'instant'
        ? hmOf(minutesOf(catHM()) + 120)
        : SWEEP_SLOTS[slot].target;
      return {
        slot,
        label: slot === 'instant' ? 'INSTANT PICK-UPS' : SWEEP_SLOTS[slot].label,
        cutoff: slot === 'instant' ? null : SWEEP_SLOTS[slot].cutoff,
        total_parcels: totalParcels,
        total_stops: jobs.length,
        destination: dest ? { courier: dest.name, branch: dest.branch, city: dest.city } : null,
        target_dropoff: target,
        minutes_on_road: clockMin - slotStartMin,
        stops,
      };
    });

  return c.json({
    rider: rider.full_name,
    generated_at: catHM(),
    batches,
  });
});

const REF_REWARD_PCT = 20;  // referrer gets a single-use promo for their own next leg
const REF_SHARE_PREFIX = 'DRP';

function randomCode(len: number): string {
  const abc = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  let s = '';
  for (let i = 0; i < len; i++) s += abc[Math.floor(Math.random() * abc.length)];
  return s;
}

/** Return the user's share code, generating + persisting it on first use. */
async function ensureReferralCode(db: D1Database, phone: string): Promise<string> {
  const existing = await db.prepare('SELECT referral_code FROM auth_users WHERE phone = ?1').bind(phone).first<any>();
  if (existing?.referral_code) return existing.referral_code as string;
  for (let i = 0; i < 6; i++) {
    const code = `${REF_SHARE_PREFIX}-${randomCode(5)}`;
    const taken = await db.prepare('SELECT phone FROM auth_users WHERE referral_code = ?1').bind(code).first<any>();
    if (taken) continue;
    await db.prepare('UPDATE auth_users SET referral_code = ?2 WHERE phone = ?1').bind(phone, code).run();
    return code;
  }
  const fallback = `${REF_SHARE_PREFIX}-${randomCode(6)}`;
  await db.prepare('UPDATE auth_users SET referral_code = ?2 WHERE phone = ?1').bind(phone, fallback).run();
  return fallback;
}

app.get('/refer/code', async (c) => {
  const phone = c.get('phone');
  if (!phone) return c.json({ error: 'identity_required' }, 401);
  const code = await ensureReferralCode(c.env.DB, phone);
  const stats = await c.env.DB.prepare(
    `SELECT SUM(CASE WHEN status='pending' THEN 1 ELSE 0 END) AS pending,
            SUM(CASE WHEN status='rewarded' THEN 1 ELSE 0 END) AS rewarded,
            COUNT(*) AS total
       FROM referrals WHERE referrer_phone = ?1`,
  ).bind(phone).first<any>();
  return c.json({
    code,
    share_text: `Join me on DropOff â€” sellers get home pickup to their courier. Use my code ${code}: https://dropoff-api.godfreymoseskalambo.workers.dev`,
    stats: { pending: stats?.pending ?? 0, rewarded: stats?.rewarded ?? 0, total: stats?.total ?? 0 },
  });
});

app.post('/refer/claim', async (c) => {
  const b: any = await c.req.json().catch(() => null);
  const code = String(b?.code ?? '').trim().toUpperCase();
  if (!code) return c.json({ error: 'missing code' }, 400);
  const phone = c.get('phone');
  if (!phone) return c.json({ error: 'identity_required' }, 401);
  const referrer = await c.env.DB.prepare('SELECT phone FROM auth_users WHERE referral_code = ?1').bind(code).first<any>();
  if (!referrer) return c.json({ error: 'referral_code_not_found' }, 404);
  if (referrer.phone === phone) return c.json({ error: 'cannot_refer_yourself' }, 400);
  const out = await c.env.DB.prepare(
    'INSERT OR IGNORE INTO referrals (referrer_phone, referred_phone) VALUES (?1, ?2)',
  ).bind(referrer.phone, phone).run();
  return c.json({ ok: true, tracked: (out.meta.changes ?? 0) > 0, referrer: referrer.phone });
});

/* -------- admin reporting of the referral funnel ------------------------- */
app.get('/admin/referrals', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'admin_key_required' }, 403);
  const { results } = await c.env.DB.prepare(
    `SELECT referrer_phone, referred_phone, status, reward_code, created_at, rewarded_at
       FROM referrals ORDER BY id DESC LIMIT 200`,
  ).all();
  const agg = await c.env.DB.prepare(
    `SELECT SUM(CASE WHEN status='pending' THEN 1 ELSE 0 END) AS pending,
            SUM(CASE WHEN status='rewarded' THEN 1 ELSE 0 END) AS rewarded,
            COUNT(*) AS total FROM referrals`,
  ).first<any>();
  return c.json({ total: agg?.total ?? 0, pending: agg?.pending ?? 0, rewarded: agg?.rewarded ?? 0, recent: results });
});

/* -------- recurring parcel plans (standing orders) ------------------------- */
// Sellers pre-register repetitive drops ("every Tuesday to Ndola"); the app one-taps
// them into a booking so the rider arrives with the route already loaded.
app.post('/recurring', async (c) => {
  const b: any = await c.req.json().catch(() => null);
  if (!b) return c.json({ error: 'invalid JSON body' }, 400);
  const role = c.get('role');
  const phone = role === 'ops'
    ? normalizeZmPhone(String(b.phone ?? ''))
    : normalizeZmPhone(c.get('phone') ?? String(b.phone ?? ''));
  if (!phone) return c.json({ error: 'missing phone' }, 401);
  const dest = String(b.dest_city ?? '').trim();
  if (!dest) return c.json({ error: 'dest_city required' }, 400);
  const freq = String(b.frequency ?? 'weekly');
  if (!['weekly', 'biweekly', 'monthly'].includes(freq)) {
    return c.json({ error: 'frequency must be weekly | biweekly | monthly' }, 400);
  }
  const wc = String(b.weight_class ?? '0-5kg');
  if (!['0-5kg', '5-15kg', '15kg+'].includes(wc)) return c.json({ error: 'bad weight_class' }, 400);
  // optional wiring for the cron materialiser: courier + origin route (NULL = create
  // from the app UI manually; the standing order stays a template)
  const courierId = b.courier_id == null ? null : Math.round(Number(b.courier_id) || 0) || null;
  const fromCity = b.from_city ? String(b.from_city).trim().slice(0, 40) : 'Lusaka';
  const { meta } = await c.env.DB.prepare(
    `INSERT INTO recurring_plans (phone, dest_city, weight_class, recipient_name, recipient_phone,
       description, pickup_address, frequency, weekday, courier_id, from_city)
     VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11)`,
  ).bind(
    phone, dest, wc, b.recipient_name ?? null, b.recipient_phone ?? null,
    b.description ?? null, b.pickup_address ?? null, freq,
    b.weekday == null ? null : Math.min(7, Math.max(1, Math.round(Number(b.weekday)))),
    courierId, fromCity,
  ).run();
  return c.json({ ok: true, id: meta.last_row_id }, 201);
});

app.get('/recurring', async (c) => {
  const role = c.get('role');
  const q = c.req.query('phone');
  const phone = role === 'ops' && q ? normalizeZmPhone(q) : c.get('phone')!;
  if (!phone) return c.json({ error: 'missing phone' }, 401);
  const { results } = await c.env.DB.prepare(
    'SELECT * FROM recurring_plans WHERE phone = ?1 ORDER BY id DESC',
  ).bind(phone).all();
  return c.json({ recurring: results });
});

app.post('/recurring/:id/toggle', async (c) => {
  const id = Number(c.req.param('id'));
  if (!id) return c.json({ error: 'bad id' }, 400);
  const role = c.get('role');
  const plan = await c.env.DB.prepare('SELECT * FROM recurring_plans WHERE id = ?1').bind(id).first() as any;
  if (!plan) return c.json({ error: 'not found' }, 404);
  if (role !== 'ops' && c.get('phone') !== plan.phone) return c.json({ error: 'forbidden' }, 403);
  await c.env.DB.prepare('UPDATE recurring_plans SET active = CASE active WHEN 1 THEN 0 ELSE 1 END WHERE id = ?1').bind(id).run();
  const updated = await c.env.DB.prepare('SELECT active FROM recurring_plans WHERE id = ?1').bind(id).first() as any;
  return c.json({ ok: true, id, active: updated.active });
});

const deleteRecurringPlan = async (c: any) => {
  const id = Number(c.req.param('id'));
  const role = c.get('role');
  const plan = await c.env.DB.prepare('SELECT phone FROM recurring_plans WHERE id = ?1').bind(id).first() as any;
  if (!plan) return c.json({ error: 'not found' }, 404);
  if (role !== 'ops' && c.get('phone') !== plan.phone) return c.json({ error: 'forbidden' }, 403);
  await c.env.DB.prepare('DELETE FROM recurring_plans WHERE id = ?1').bind(id).run();
  return c.json({ ok: true });
};
app.delete('/recurring/:id', deleteRecurringPlan);
app.post('/recurring/:id/delete', deleteRecurringPlan); // client-friendly alias

// pickup route is available to ops/admin JWT roles too; no new role needed.

/* ---------------------------- web console pages ---------------------------- */
// GET /console?key=â€¦ (superadmin HTML dashboard) + GET /partner/console (partner
// panel; the page speaks JSON to /partner/* with the login token it asks for).
const CONSOLE_CSS = `body{font-family:-apple-system,Segoe UI,Roboto,sans-serif;max-width:860px;margin:24px auto;padding:0 16px;color:#10312a}
h1{font-size:20px} table{border-collapse:collapse;width:100%;margin:12px 0} td,th{padding:6px 10px;border-bottom:1px solid #dde6e2;text-align:left;font-size:14px}
th{background:#eef4f1} .kpi{display:inline-block;background:#eef4f1;border-radius:10px;padding:10px 16px;margin:4px 8px 4px 0;font-size:13px}
.kpi b{display:block;font-size:20px} input,button,select{padding:8px;border-radius:8px;border:1px solid #cfd8d4;font-size:14px}
button{background:#17855f;color:#fff;border:0;font-weight:700}`;

/** Superadmin console â€” open as https://<worker>/console?key=<ADMIN_AUTH_KEY> */
app.get('/console', (c) => c.html(`<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<title>DropOff â€” Admin</title><style>${CONSOLE_CSS}</style></head><body>
<h1>DropOff â€” superadmin console</h1>
<div id="kpis">Loadingâ€¦</div>
<table id="tbl"><thead><tr><th>KPI</th><th>Last 30 days</th></tr></thead><tbody></tbody></table>
<h2>Partner shops</h2>
<p>Add email + courier id â†’ the partner logs in with that email and confirms prices/rides.</p>
<input id="pEmail" placeholder="partner@shop.co.zm"><input id="pCourier" type="number" placeholder="courier id">
<button onclick="makePartner()">Promote to partner</button><span id="pMsg"></span>

<h2>Tiers (pack prices â€” editable live)</h2>
<table id="tiersTbl"><thead><tr><th>tier</th><th>fee K/mo</th><th>parcels/day</th><th>rider fee K</th><th>tag</th><th></th></tr></thead><tbody></tbody></table>
<div>
<select id="tTier"><option>silver</option><option>gold</option><option>platinum</option></select>
<input id="tFee" type="number" placeholder="fee ZMW" step="1">
<input id="tPpd" type="number" placeholder="parcels/day" step="1">
<input id="tRider" type="number" placeholder="rider fee (0 = bundled)" step="1">
<input id="tTag" placeholder="tag e.g. Most popular / PROMO">
<button onclick="saveTier()">Save tier</button><span id="tMsg"></span>
</div>

<h2>Promo codes (sellers)</h2>
<table id="promosTbl"><thead><tr><th>code</th><th>% off</th><th>uses left</th><th>expires</th><th>applies</th><th>note</th></tr></thead><tbody></tbody></table>
<div>
<input id="prCode" placeholder="CODE e.g. FIRSTM10" style="text-transform:uppercase">
<input id="prPct" type="number" placeholder="% off leg" step="0.5">
<input id="prUses" type="number" placeholder="max uses (blank = unlimited)">
<input id="prExp" type="date">
<input id="prTier" placeholder="applies to tier (blank = any)">
<input id="prNote" placeholder="note">
<button onclick="savePromo()">Save promo</button><span id="prMsg"></span>
</div>

<h2>Partner collection rails (their POS â€” never our money)</h2>
<p>Set how the customer pays the courier directly at the counter/depot. Shown on the courier page.</p>
<table id="posTbl"><thead><tr><th>courier id</th><th>rail</th><th>merchant</th><th>instructions</th></tr></thead><tbody></tbody></table>
<div>
<input id="posCourier" type="number" placeholder="courier id">
<select id="posRail"><option>momo</option><option>bank</option><option>pos_terminal</option><option>whatsapp</option><option>cash</option></select>
<input id="posMerchant" placeholder="merchant/till/momo number">
<input id="posInstructions" placeholder="e.g. Send K110 to 096â€¦ ref=waybill" size="46">
<button onclick="savePos()">Save POS</button><span id="posMsg"></span>
</div>
<script>
const key = new URLSearchParams(location.search).get('key') || '';
// keep the admin key out of browser history / Referer headers
if (key) history.replaceState(null, '', location.pathname);
const H = { 'X-Admin-Key': key };
fetch('/admin/stats', { headers: H }).then(r => r.json()).then(s => {
  document.getElementById('kpis').innerHTML = [
    ['active pack sellers', s.paying_sellers_active],
    ['paygo regulars (3+/mo)', s.paygo_regulars],
    ['parcels (30d)', s.parcels_last_30d],
    ['platform fees (30d)', 'K' + (s.platform_fees_last_30d ?? 0).toFixed(2)],
    ['Lipila fees (30d)', 'K' + (s.lipila_fees_last_30d ?? 0).toFixed(2)],
    ['wallet float', 'K' + (s.wallet_float_total ?? 0).toFixed(2)],
    ['referrals pending', s.referrals_pending ?? 0],
    ['referrals rewarded', s.referrals_rewarded ?? 0],
  ].map(([label, v]) => '<span class="kpi"><b>' + esc(v) + '</b>' + label + '</span>').join('');
  const tb = document.querySelector('#tbl tbody'); tb.innerHTML = '';
  for (const [k, v] of Object.entries(s)) if (!(v instanceof Object)) {
    tb.insertAdjacentHTML('beforeend', '<tr><td>' + esc(k) + '</td><td>' + esc(v) + '</td></tr>');
  }
  const tiers = s.subs_by_tier ?? [];
  for (const t of tiers) tb.insertAdjacentHTML('beforeend', '<tr><td>pack: ' + esc(t.tier) + '</td><td>' + esc(t.n) + ' active</td></tr>');
}).catch(() => document.getElementById('kpis').textContent = 'Admin key wrong â€” reload with ?key=');
// note: esc() is defined further down â€” hoisted function, safe here
async function makePartner() {
  const r = await fetch('/admin/partners', { method: 'POST', headers: { ...H, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: document.getElementById('pEmail').value.trim(), courier_id: Number(document.getElementById('pCourier').value) }) });
  const j = await r.json(); document.getElementById('pMsg').textContent = r.ok ? 'âœ” ' + esc(j.email) + ' â†’ ' + esc(j.role) : 'âœ– ' + esc(j.error || 'failed');
}
function esc(v) { return (v ?? '').toString().replace(/[&<>"]/g, (m) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[m])); }
async function loadTiers() {
  const r = await fetch('/admin/tiers', { headers: H }); const j = await r.json(); const tb = document.querySelector('#tiersTbl tbody'); tb.innerHTML = '';
  for (const t of j.tiers ?? []) tb.insertAdjacentHTML('beforeend', '<tr><td>' + esc(t.tier) + '</td><td>' + t.fee_zmw + '</td><td>' + t.parcels_per_day + '</td><td>' + t.rider_fee_zmw + '</td><td>' + esc(t.tag ?? '') + '</td><td><button style="background:#b6c4bd;color:#10312a" onclick="editTier(\'' + esc(t.tier) + '\',' + t.fee_zmw + ',' + t.parcels_per_day + ',' + t.rider_fee_zmw + ',\'' + esc(t.tag ?? '') + '\')">edit</button></td></tr>');
}
function editTier(tier, fee, ppd, rider, tag) { tTier.value = tier; tFee.value = fee; tPpd.value = ppd; tRider.value = rider; tTag.value = tag; }
async function saveTier() {
  const r = await fetch('/admin/tiers', { method: 'POST', headers: { ...H, 'Content-Type': 'application/json' },
    body: JSON.stringify({ tier: tTier.value, fee_zmw: Number(tFee.value), parcels_per_day: Number(tPpd.value), rider_fee_zmw: Number(tRider.value), tag: tTag.value.trim() || null }) });
  const j = await r.json(); tMsg.textContent = r.ok ? ' âœ” saved' : ' âœ– ' + esc(j.error || 'failed'); loadTiers();
}
async function loadPromos() {
  const r = await fetch('/admin/promos', { headers: H }); const j = await r.json(); const tb = document.querySelector('#promosTbl tbody'); tb.innerHTML = '';
  for (const p of j.promos ?? []) tb.insertAdjacentHTML('beforeend', '<tr><td>' + esc(p.code) + '</td><td>' + p.discount_pct + '</td><td>' + (p.uses_left ?? 'âˆž') + '</td><td>' + esc(p.expires_at ?? '') + '</td><td>' + esc(p.applies_tier ?? 'any') + '</td><td>' + esc(p.note ?? '') + '</td></tr>');
}
async function savePromo() {
  const r = await fetch('/admin/promos', { method: 'POST', headers: { ...H, 'Content-Type': 'application/json' },
    body: JSON.stringify({ code: prCode.value.trim().toUpperCase(), discount_pct: Number(prPct.value), uses_left: prUses.value ? Number(prUses.value) : null, expires_at: prExp.value || null, applies_tier: prTier.value.trim().toLowerCase() || null, note: prNote.value.trim() || null }) });
  const j = await r.json(); prMsg.textContent = r.ok ? ' âœ” saved' : ' âœ– ' + esc(j.error || 'failed'); loadPromos();
}
async function loadPos() {
  const r = await fetch('/admin/pos', { headers: H }); const j = await r.json(); const tb = document.querySelector('#posTbl tbody'); tb.innerHTML = '';
  for (const p of j.pos ?? []) tb.insertAdjacentHTML('beforeend', '<tr><td>' + p.courier_id + '</td><td>' + esc(p.rail) + '</td><td>' + esc(p.merchant_id ?? '') + '</td><td>' + esc(p.instructions ?? '') + '</td></tr>');
}
async function savePos() {
  const r = await fetch('/admin/pos', { method: 'POST', headers: { ...H, 'Content-Type': 'application/json' },
    body: JSON.stringify({ courier_id: Number(posCourier.value), rail: posRail.value, merchant_id: posMerchant.value.trim(), instructions: posInstructions.value.trim() }) });
  const j = await r.json(); posMsg.textContent = r.ok ? ' âœ” saved' : ' âœ– ' + esc(j.error || 'failed'); loadPos();
}
loadTiers(); loadPromos(); loadPos();
</script></body></html>`));

/** Partner console â€” the partner logs in (email) and pastes the token. */
app.get('/partner/console', (c) => c.html(`<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<title>DropOff â€” Partner</title><style>${CONSOLE_CSS}</style></head><body>
<h1>DropOff â€” courier partner console</h1>
<p>Paste your login token from the app or one issued to you. In-browser logins keep the token local.</p>
<input id="token" placeholder="login token" style="width:100%">
<button onclick="load()">Open</button>
<div id="me"></div>
<h2>Counter prices</h2>
<table id="q"><thead><tr><th>from</th><th>to</th><th>weight</th><th>service</th><th>price K</th><th>updated</th></tr></thead><tbody></tbody></table>
<h3>Confirm/update a price</h3>
<div style="display:flex;gap:6px;flex-wrap:wrap">
<input id="fCity" placeholder="from" value="Lusaka"><input id="tCity" placeholder="to">
<input id="w" placeholder="0-5kg" value="0-5kg"><input id="sv" placeholder="standard" value="standard">
<input id="p" type="number" placeholder="K"><button onclick="save()">Save</button><span id="msg"></span></div>
<h2>Parcels handed to us</h2>
<table id="r"><thead><tr><th>ref</th><th>to</th><th>weight</th><th>status</th><th>paid</th><th></th></tr></thead><tbody></tbody></table>
<script>
let t = new URLSearchParams(location.search).get('t') || localStorage.getItem('dof_partner_token') || '';
// don't keep the login token in browser history / Referer headers
if (new URLSearchParams(location.search).has('t')) history.replaceState(null, '', location.pathname);
document.getElementById('token').value = t;
let CID = null;
const H = () => ({ 'Authorization': 'Bearer ' + document.getElementById('token').value.trim(), 'Content-Type': 'application/json' });
function esc(v) { return (v ?? '').toString().replace(/[&<>"]/g, (m) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[m])); }
async function load() {
  t = document.getElementById('token').value.trim();
  localStorage.setItem('dof_partner_token', t);
  const me = await (await fetch('/partner/me', { headers: H() })).json();
  if (!me.courier) { document.getElementById('me').textContent = 'Not a partner account yet.'; return; }
  CID = me.courier.id;
  document.getElementById('me').innerHTML = '<b>' + esc(me.email) + '</b> â€” ' + esc(me.courier.name) + ' (' + esc(me.courier.city) + ', ' + esc(me.courier.depot_name) + ')';
  const q = await (await fetch('/partner/quotes', { headers: H() })).json();
  document.querySelector('#q tbody').innerHTML =
    (q.quotes || []).map(z => '<tr><td>' + esc(z.from_city) + '</td><td>' + esc(z.to_city) + '</td><td>' + esc(z.weight_class) + '</td><td>' + esc(z.service) + '</td><td>K' + esc(z.counter_price_zmw) + '</td><td>' + esc(z.updated_at) + '</td></tr>').join('');
  const r = await (await fetch('/partner/rides', { headers: H() })).json();
  document.querySelector('#r tbody').innerHTML =
    (r.jobs || []).map(z => '<tr><td>' + esc(z.ref) + '</td><td>' + esc(z.dest_city) + '</td><td>' + esc(z.weight_class) + '</td><td>' + esc(z.last_event) + '</td><td>' + (z.paid ? 'paid' : 'â€”') + '</td><td><button onclick="confirmRide(\\'' + z.ref + '\\')">confirm</button></td></tr>').join('');
}
async function save() {
  const r = await fetch('/partner/quotes', { method: 'POST', headers: H(), body: JSON.stringify({
    courier_id: CID, from_city: document.getElementById('fCity').value, to_city: document.getElementById('tCity').value,
    weight_class: document.getElementById('w').value, service: document.getElementById('sv').value,
    counter_price_zmw: Number(document.getElementById('p').value) }) });
  const j = await r.json(); document.getElementById('msg').textContent = r.ok ? 'âœ” price confirmed' : 'âœ– ' + esc(j.error || '');
  if (r.ok) load();
}
async function confirmRide(ref) {
  await fetch('/partner/rides/' + ref + '/confirm', { method: 'POST', headers: H() });
  load();
}
</script></body></html>`));
app.post('/subscriptions', async (c) => {
  const b: any = await c.req.json().catch(() => null);
  if (!b) return c.json({ error: 'invalid JSON body' }, 400);
  const tier: PlanTier = b.tier;
  const packs = await plans(c.env.DB);
  const plan = packs[tier];
  if (!plan || plan.fee_zmw <= 0) return c.json({ error: 'tier must be "silver", "gold" or "platinum"' }, 400);
  // identity: customers subscribe their own phone; ops/admin may set any
  const phone = c.get('role') === 'customer' ? c.get('phone')! : normalizeZmPhone(b.phone ?? '');
  if (!phone) return c.json({ error: 'missing phone' }, 401);
  const window: string = b.pickup_window ?? '10:00';
  if (!plan.windows.includes(window)) {
    return c.json({ error: `pickup_window must be one of ${plan.windows.join(', ')}` }, 400);
  }
  const { meta } = await c.env.DB.prepare(
    `INSERT INTO subscriptions (phone, sender_name, tier, city, pickup_window, status, period_start, period_end)
     VALUES (?1,?2,?3,?4,?5,
       CASE WHEN EXISTS (SELECT 1 FROM subscriptions s2 WHERE s2.phone = ?1 AND s2.status = 'active' AND s2.period_end > datetime('now'))
            THEN 'active' ELSE 'pending_payment' END,
       datetime('now'), datetime('now', '+30 days'))
     ON CONFLICT(phone) DO UPDATE SET
       tier = excluded.tier, sender_name = excluded.sender_name, city = excluded.city,
       pickup_window = excluded.pickup_window,
       status = CASE WHEN subscriptions.status = 'active' AND subscriptions.period_end > datetime('now')
                  THEN 'active' ELSE 'pending_payment' END,
       period_start = CASE WHEN subscriptions.status = 'active' AND subscriptions.period_end > datetime('now')
                  THEN subscriptions.period_start ELSE datetime('now') END,
       period_end = CASE WHEN subscriptions.status = 'active' AND subscriptions.period_end > datetime('now')
                  THEN subscriptions.period_end ELSE datetime('now', '+30 days') END`,
  ).bind(phone, b.sender_name ?? null, tier, b.city ?? 'Lusaka', window).run();
  const sub = await c.env.DB.prepare('SELECT id, tier, period_start, period_end FROM subscriptions WHERE phone = ?1')
    .bind(phone).first<any>();
  return c.json({
    ok: true, id: sub?.id, tier, pickup_window: window,
    monthly_fee_zmw: plan.fee_zmw, parcels_per_month: plan.parcels_per_month,
    period_start: sub?.period_start, period_end: sub?.period_end,
    cycle_days: plan.cycle_days,
    note: 'Approve the Lipila prompt to activate your pack. Auto-renewal bills via Lipila 3 days before the cycle ends.',
  });
});

app.get('/subscriptions/:phone?', async (c) => {
  let phone = c.req.param('phone') ?? '';
  if (c.get('role') === 'customer' || !phone) phone = c.get('phone') ?? normalizeZmPhone(phone);
  else phone = normalizeZmPhone(phone);
  const sub = await c.env.DB.prepare(
    `SELECT id, tier, city, pickup_window, status, started_at, period_start, period_end
       FROM subscriptions WHERE phone = ?1`,
  ).bind(phone).first<any>();
  if (!sub) return c.json({ subscription: null });
  const plan = (await plans(c.env.DB))[sub.tier as PlanTier] ?? null;
  let usedThisPeriod = 0;
  let effectiveCap = plan?.parcels_per_month ?? 0;
  let rollover = 0;
  if (sub.period_start && sub.period_end) {
    // Every parcel counts: usage is the sum of parcels across the cycle's trips.
    usedThisPeriod = (await c.env.DB.prepare(
      `SELECT COALESCE(SUM(parcels), 0) AS n FROM jobs WHERE sender_phone = ?1
        AND created_at >= ?2 AND created_at < ?3`,
    ).bind(phone, sub.period_start, sub.period_end).first<any>())?.n ?? 0;
    rollover = 0; // no rollover — unused parcels expire with the cycle
    effectiveCap = (plan?.parcels_per_month ?? 0);
  }
  return c.json({
    subscription: sub,
    plan,
    usage_this_period: usedThisPeriod,
    remaining_this_period: plan ? Math.max(0, effectiveCap - usedThisPeriod) : null,
    effective_cap: plan ? effectiveCap : null,
    rollover_parcels: rollover,
  });
});

/* ----------------------- mid-cycle upgrade (prorated) ---------------------- */
// Pay the difference for the remaining days; the new tier's cap applies the
// moment the upgrade is requested. Failed/abandoned payments are reverted by
// the reconciliation sweep using the prevTier stored on the payment row.
const TIER_RANK: Record<string, number> = { silver: 0, gold: 1, platinum: 2 };

app.post('/subscriptions/upgrade', async (c) => {
  if (await rateLimited(c, 'payment_create', 30)) return c.json({ error: 'too_many_requests' }, 429);
  const b: any = await c.req.json().catch(() => null);
  const tier = String(b?.tier ?? '').toLowerCase() as PlanTier;
  const phone = c.get('role') === 'customer' ? c.get('phone')! : normalizeZmPhone(b?.phone ?? '');
  if (!phone) return c.json({ error: 'identity_required' }, 401);
  const packs = await plans(c.env.DB);
  const newPlan = packs[tier];
  if (!newPlan || newPlan.fee_zmw <= 0) return c.json({ error: 'tier must be "silver", "gold" or "platinum"' }, 400);
  const sub = await c.env.DB.prepare(
    `SELECT id, phone, tier, period_start, period_end FROM subscriptions WHERE phone = ?1 ORDER BY id DESC LIMIT 1`,
  ).bind(phone).first<any>();
  if (!sub) return c.json({ error: 'no_subscription', detail: 'Choose a pack first.' }, 404);
  if ((TIER_RANK[tier] ?? 0) <= (TIER_RANK[sub.tier] ?? 0)) {
    return c.json({ error: 'upgrades_only', detail: 'Downgrades apply automatically at your next renewal.' }, 400);
  }
  if (sub.status !== 'active' || !sub.period_end || sub.period_end <= new Date().toISOString().slice(0, 19).replace('T', ' ')) {
    return c.json({ error: 'pack_not_active', detail: 'Subscribe (pay) first, then upgrade.' }, 400);
  }
  const pending = await c.env.DB.prepare(
    `SELECT id FROM payments WHERE subscription_id = ?1 AND status = 'pending'`,
  ).bind(sub.id).first<any>();
  if (pending) return c.json({ error: 'payment_already_pending' }, 409);

  const oldPlan = packs[sub.tier as PlanTier];
  const cycleDays = oldPlan?.cycle_days || 30;
  const remainingMs = Date.parse(`${sub.period_end}Z`) - Date.now();
  const remainingDays = Math.max(1, Math.ceil(remainingMs / 86_400_000));
  const prorated = round2(Math.max(0, ((newPlan.fee_zmw - (oldPlan?.fee_zmw ?? 0)) * remainingDays) / cycleDays));

  // Bump the tier NOW — the bigger cap is live immediately.
  await c.env.DB.prepare('UPDATE subscriptions SET tier = ?2 WHERE id = ?1').bind(sub.id, tier).run();

  if (prorated <= 0) {
    return c.json({ ok: true, tier, prorated_zmw: 0, detail: 'Upgraded — nothing extra to pay for the rest of this cycle.' });
  }

  const platformFeeZmw = platformFee(prorated);
  const amount = round2(prorated + platformFeeZmw + MOMO_COLLECTION_FEE);
  const lipilaRef = `upg-${sub.id}-${new Date().toISOString().slice(0, 10).replace(/-/g, '')}`;
  const init = await lipilaCollect(c.env, phone, amount, lipilaRef, `DropOff ${tier} upgrade (prorated)`);
  if (!init.ok) {
    // revert the bump so a failed collect never leaves a free upgrade
    await c.env.DB.prepare('UPDATE subscriptions SET tier = ?2 WHERE id = ?1').bind(sub.id, sub.tier).run();
    return c.json({ error: 'lipila init failed', detail: init.raw }, 502);
  }
  const provider: Provider = providerFromPhone(phone);
  await c.env.DB.prepare(
    `INSERT INTO payments (subscription_id, phone, provider, amount_zmw, platform_fee_zmw,
       lipila_fee_zmw, lipila_reference, status, channel, kind, meta)
     VALUES (?1,?2,?3,?4,?5,?6,?7,'pending','merchant','upgrade',?8)`,
  ).bind(sub.id, phone, provider, amount, platformFeeZmw, MOMO_COLLECTION_FEE,
    init.lipilaReference ?? null, JSON.stringify({ prevTier: sub.tier, newTier: tier, prorated })).run();
  return c.json({ ok: true, tier, prorated_zmw: prorated, amount_zmw: amount,
    note: 'Approve the Lipila prompt. Your bigger cap is already live.' });
});

/* ------------------ admin (superadmin pricebook + ops) -------------------- */
app.use('/admin/*', async (c, next) => {
  // Team management stays ops-accessible (rider devices register their crew);
  // every other /admin/* surface is admin/owner only.
  if (c.req.path === '/admin/riders' && c.req.method === 'POST' && c.get('role') === 'ops') return next();
  if (!isAdmin(c)) return c.json({ error: 'admin_key_required' }, 403);
  return next();
});

// Upsert courier partner profile (the partner "page" sellers see in-app)
app.post('/admin/couriers', async (c) => {
  const b: any = await c.req.json().catch(() => null);
  if (!b?.name || !b.city || !b.depot_name) return c.json({ error: 'name, city, depot_name required' }, 400);
  if (b.id) {
    await c.env.DB.prepare(
      `UPDATE couriers SET name = ?2, city = ?3, depot_name = ?4, lat = ?5, lng = ?6,
         website = ?7, price_status = ?8, note = ?9, logo_url = ?10
       WHERE id = ?1`,
    ).bind(b.id, b.name, b.city, b.depot_name, b.lat ?? null, b.lng ?? null,
      b.website ?? null, b.price_status ?? null, b.note ?? null, b.logo_url ?? null).run();
    return c.json({ ok: true, id: b.id });
  }
  const { meta } = await c.env.DB.prepare(
    `INSERT INTO couriers (name, city, depot_name, lat, lng, website, price_status, note, logo_url)
     VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9)`,
  ).bind(b.name, b.city, b.depot_name, b.lat ?? null, b.lng ?? null,
    b.website ?? null, b.price_status ?? null, b.note ?? null, b.logo_url ?? null).run();
  return c.json({ ok: true, id: meta.last_row_id });
});

// Price-list entry (chargebook) â€” superadmin captures depot tariffs here
app.post('/admin/quotes', async (c) => {
  const b: any = await c.req.json().catch(() => null);
  const required = ['courier_id', 'from_city', 'to_city', 'weight_class', 'service', 'counter_price_zmw'];
  for (const k of required) if (b?.[k] === undefined) return c.json({ error: `${k} required` }, 400);
  if (b.counter_price_zmw <= 0) return c.json({ error: 'counter_price_zmw must be > 0' }, 400);
  const exists = await c.env.DB.prepare(
    `SELECT id FROM quotes WHERE courier_id = ?1 AND from_city = ?2 AND to_city = ?3
       AND weight_class = ?4 AND service = ?5`,
  ).bind(b.courier_id, b.from_city, b.to_city, b.weight_class, b.service).first<any>();
  if (exists) {
    await c.env.DB.prepare(
      `UPDATE quotes SET counter_price_zmw = ?2, updated_at = datetime('now') WHERE id = ?1`,
    ).bind(exists.id, b.counter_price_zmw).run();
    return c.json({ ok: true, id: exists.id, updated: true });
  }
  const { meta } = await c.env.DB.prepare(
    `INSERT INTO quotes (courier_id, from_city, to_city, weight_class, service, counter_price_zmw)
     VALUES (?1,?2,?3,?4,?5,?6)`,
  ).bind(b.courier_id, b.from_city, b.to_city, b.weight_class, b.service, b.counter_price_zmw).run();
  return c.json({ ok: true, id: meta.last_row_id });
});

// Rider roster (rider identity lives here; rider apps log in by phone OTP)
app.post('/admin/riders', async (c) => {
  // Team management is ops-domain: ops key (rider device) or admin key/owner.
  if (!isAdmin(c) && c.get('role') !== 'ops') return c.json({ error: 'admin_key_required' }, 403);
  const b: any = await c.req.json().catch(() => null);
  if (!b?.full_name || !b.vehicle) return c.json({ error: 'full_name and vehicle required' }, 400);
  const phone = normalizeZmPhone(b.phone ?? '');
  if (!phone) return c.json({ error: 'phone required' }, 400);
  const vc = VEHICLE_CLASSES.includes(b.vehicle_class) ? b.vehicle_class : 'motorcycle';
  await c.env.DB.prepare(
    `INSERT INTO riders (phone, full_name, vehicle, vehicle_class) VALUES (?1,?2,?3,?4)
     ON CONFLICT(phone) DO UPDATE SET full_name = excluded.full_name, vehicle = excluded.vehicle,
       vehicle_class = excluded.vehicle_class, active = 1`,
  ).bind(phone, b.full_name, b.vehicle, vc).run();
  const rider = await c.env.DB.prepare('SELECT id FROM riders WHERE phone = ?1').bind(phone).first<any>();
  return c.json({ ok: true, id: rider?.id, vehicle_class: vc });
});

app.post('/admin/jobs/:ref/assign', async (c) => {
  const b: any = await c.req.json().catch(() => null);
  const phone = normalizeZmPhone(b?.phone ?? '');
  if (!phone) return c.json({ error: 'phone required' }, 400);
  const rider = await c.env.DB.prepare('SELECT id, active FROM riders WHERE phone = ?1').bind(phone).first<any>();
  if (!rider || !rider.active) return c.json({ error: 'rider not found or inactive' }, 404);
  const job = await c.env.DB.prepare('SELECT id FROM jobs WHERE ref = ?1').bind(c.req.param('ref')).first<any>();
  if (!job) return c.json({ error: 'job not found' }, 404);
  await c.env.DB.batch([
    c.env.DB.prepare('UPDATE jobs SET rider_id = ?2 WHERE id = ?1').bind(job.id, rider.id),
    c.env.DB.prepare(`INSERT INTO job_events (job_id, status, note) VALUES (?1, 'rider_assigned', ?2)`)
      .bind(job.id, `Rider ${phone} assigned`),
  ]);
  return c.json({ ok: true, rider_id: rider.id });
});

// Promote an email account to a partner shop tied to a courier row.
// Partner then signs in with that email and uses /partner/* or /partner/console.
app.post('/admin/partners', async (c) => {
  const b: any = await c.req.json().catch(() => null);
  const email = String(b?.email ?? '').trim().toLowerCase();
  const courierId = Number(b?.courier_id ?? 0);
  if (!isValidEmail(email) || !courierId) return c.json({ error: 'email and courier_id required' }, 400);
  const courier = await c.env.DB.prepare('SELECT id FROM couriers WHERE id = ?1').bind(courierId).first<any>();
  if (!courier) return c.json({ error: 'courier not found' }, 404);
  const user = await c.env.DB.prepare('SELECT email FROM auth_users WHERE email = ?1').bind(email).first<any>();
  if (!user) return c.json({ error: 'that email has no account yet â€” ask them to register in the app first' }, 404);
  await c.env.DB.prepare(
    `UPDATE auth_users SET role = 'partner', courier_id = ?2 WHERE email = ?1`,
  ).bind(email, courierId).run();
  return c.json({ ok: true, email, role: 'partner', courier_id: courierId });
});

// Rider earnings/cash-out + COD remittance (float settlement is admin-controlled).
// kind='cod_remit' settles cash the rider/driver floated from a job's door collection:
// the sender's wallet gets the COD amount net of the platform's COD cut.
app.post('/admin/payouts', async (c) => {
  const b: any = await c.req.json().catch(() => null);
  const kind: string = ['rider_earning', 'rider_payout', 'cod_remit'].includes(b?.kind) ? b.kind : 'rider_earning';
  if (kind === 'cod_remit') {
    const job = await c.env.DB.prepare(
      'SELECT id, ref, sender_phone, cod_collected_zmw FROM jobs WHERE ref = ?1').bind(b?.job_ref ?? '').first() as any;
    if (!job) return c.json({ error: 'job not found' }, 404);
    if (!job.cod_collected_zmw) return c.json({ error: 'no cash collected on this job' }, 409);
    const cod = Number(job.cod_collected_zmw);
    const net = Math.round(cod * (1 - COD_FEE) * 100) / 100;
    // Customers/sellers have NO wallet â€” settle COD straight to their momo.
    const ref = `cod-${job.ref}-${Date.now().toString(36)}`;
    const disb = await lipilaDisburse(c.env, job.sender_phone, net, ref, `DropOff COD remit ${job.ref}`);
    if (!disb.ok) return c.json({ error: 'lipila disbursement failed', detail: disb.raw ?? null }, 502);
    await c.env.DB.batch([
      c.env.DB.prepare(
        `INSERT INTO payments (job_id, phone, provider, amount_zmw, credit_zmw, platform_fee_zmw, lipila_fee_zmw, lipila_reference, status, channel, kind)
         VALUES (?1, ?2, ?3, ?4, ?4, 0, 0, ?5, 'pending', 'merchant', 'cod_remit')`,
      ).bind(job.id, job.sender_phone, providerFromPhone(job.sender_phone), net, disb.lipilaReference ?? ref),
      c.env.DB.prepare(`INSERT INTO job_events (job_id, status, note) VALUES (?1, 'cod_remit_initiated', ?2)`)
        .bind(job.id, `COD K${cod} remitted via momo â€” sender gets K${net} (platform keeps K${(cod - net).toFixed(2)}). Ref ${disb.lipilaReference ?? ref}`),
    ]);
    return c.json({ ok: true, job_ref: job.ref, credited_zmw: net, platform_kept_zmw: round2(cod - net), lipila_reference: disb.lipilaReference ?? ref, settlement: 'momo_disbursement' });
  }
  const phone = normalizeZmPhone(b?.phone ?? '');
  const amount = Math.round(Math.abs(Number(b?.amount_zmw) || 0) * 100) / 100;
  if (!phone || amount <= 0) return c.json({ error: 'phone and positive amount required' }, 400);
  await c.env.DB.batch(await walletCreditStatements(c, phone, b.kind === 'rider_payout' ? -amount : amount, kind));
  return c.json({ ok: true });
});

// Refund a settled payment to the payer's momo. Admin-key only: this moves money.
app.post('/admin/payments/:id/refund', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'forbidden' }, 403);
  const id = Number(c.req.param('id'));
  const pay = await c.env.DB.prepare(
    `SELECT id, job_id, phone, provider, amount_zmw, status FROM payments WHERE id = ?1`,
  ).bind(id).first<any>();
  if (!pay) return c.json({ error: 'not found' }, 404);
  if (pay.status !== 'success') return c.json({ error: 'only settled payments can be refunded' }, 409);
  const amount = Math.round(Number(pay.amount_zmw) * 100) / 100;
  if (!(amount > 0)) return c.json({ error: 'nothing to refund' }, 409);
  const ref = `refund-${pay.id}-${Date.now().toString(36)}`;
  const disb = await lipilaDisburse(c.env, pay.phone, amount, ref, `DropOff refund payment ${pay.id}`);
  if (!disb.ok) return c.json({ error: 'lipila refund failed', detail: disb.raw ?? null }, 502);
  await c.env.DB.batch([
    c.env.DB.prepare(
      `INSERT INTO payments (job_id, phone, provider, amount_zmw, credit_zmw, platform_fee_zmw,
         lipila_fee_zmw, lipila_reference, status, channel, kind, refund_of_payment_id, refunded_at)
       VALUES (?1,?2,?3,?4,0,0,0,?5,'pending','merchant','refund',?6,datetime('now'))`,
    ).bind(pay.job_id, pay.phone, pay.provider, amount, disb.lipilaReference ?? ref, pay.id),
    c.env.DB.prepare(`UPDATE payments SET status = 'refunded', refunded_at = datetime('now') WHERE id = ?1`).bind(pay.id),
  ]);
  if (pay.job_id) {
    await c.env.DB.prepare(
      `INSERT INTO job_events (job_id, status, note) VALUES (?1, 'refunded', ?2)`,
    ).bind(pay.job_id, `Payment ${pay.id} refunded K${amount} via momo`).run();
  }
  return c.json({ ok: true, refund_reference: disb.lipilaReference ?? ref, amount_zmw: amount });
});

// Growth dashboard: tiers, paygo regulars (target: 100 paying sellers/mo)
app.get('/admin/stats', async (c) => {
  const db = c.env.DB;
  const one = async (sql: string, ...bind: unknown[]) => (await db.prepare(sql).bind(...bind).first<any>())?.n ?? 0;
  const tiers = await db.prepare(
    `SELECT tier, COUNT(*) AS n FROM subscriptions WHERE status = 'active' GROUP BY tier`,
  ).all();
  const stats = {
    paying_sellers_active: (await db.prepare(
      `SELECT COUNT(DISTINCT phone) AS n FROM subscriptions WHERE status = 'active'
        AND (expires_at IS NULL OR expires_at > datetime('now'))`,
    ).first<any>())?.n ?? 0,
    subs_by_tier: tiers.results,
    paygo_last_30d: await one(
      `SELECT COUNT(DISTINCT sender_phone) AS n FROM jobs
        WHERE datetime(created_at, '${CAT_OFFSET}') > datetime('now', '-30 days') AND sender_phone NOT IN
        (SELECT phone FROM subscriptions WHERE status = 'active')`,
    ),
    paygo_regulars: await one(
      `SELECT COUNT(*) AS n FROM (
         SELECT sender_phone FROM jobs WHERE datetime(created_at, '${CAT_OFFSET}') > datetime('now', '-30 days')
         GROUP BY sender_phone HAVING COUNT(*) >= 3
       ) WHERE sender_phone NOT IN (SELECT phone FROM subscriptions WHERE status = 'active')`,
    ),
    parcels_last_30d: await one(
      `SELECT COUNT(*) AS n FROM jobs WHERE datetime(created_at, '${CAT_OFFSET}') > datetime('now', '-30 days')`,
    ),
    revenue_job_payments: await one(
      `SELECT COALESCE(SUM(amount_zmw), 0) AS n FROM payments WHERE status = 'success'
        AND kind = 'job' AND datetime(ifnull(paid_at, created_at), '${CAT_OFFSET}') > datetime('now', '-30 days')`,
    ),
    revenue_topups: await one(
      `SELECT COALESCE(SUM(amount_zmw), 0) AS n FROM payments WHERE status = 'success'
        AND kind = 'topup' AND datetime(ifnull(paid_at, created_at), '${CAT_OFFSET}') > datetime('now', '-30 days')`,
    ),
    // fee-engine income (Chisomo / Wardrobe-Valet pattern): what DropOff earned
    platform_fees_last_30d: await one(
      `SELECT COALESCE(SUM(platform_fee_zmw), 0) AS n FROM payments WHERE status = 'success'
        AND datetime(ifnull(paid_at, created_at), '${CAT_OFFSET}') > datetime('now', '-30 days')`,
    ),
    lipila_fees_last_30d: await one(
      `SELECT COALESCE(SUM(lipila_fee_zmw), 0) AS n FROM payments WHERE status = 'success'
        AND datetime(ifnull(paid_at, created_at), '${CAT_OFFSET}') > datetime('now', '-30 days')`,
    ),
    wallet_float_total: await one(`SELECT COALESCE(SUM(balance_zmw), 0) AS n FROM wallets`),
    cod_last_30d: await one(
      `SELECT COALESCE(SUM(cod_collected_zmw), 0) AS n FROM jobs
        WHERE cod_collected_zmw > 0 AND datetime(created_at, '${CAT_OFFSET}') > datetime('now', '-30 days')`,
    ),
    wait_fee_last_30d: await one(
      `SELECT COALESCE(SUM(wait_fee_zmw), 0) AS n FROM jobs
        WHERE wait_fee_zmw > 0 AND datetime(created_at, '${CAT_OFFSET}') > datetime('now', '-30 days')`,
    ),
    referrals_pending: await one(`SELECT COUNT(*) AS n FROM referrals WHERE status = 'pending'`),
    referrals_rewarded: await one(`SELECT COUNT(*) AS n FROM referrals WHERE status = 'rewarded'`),
  };
  return c.json(stats);
});

/* ------------------- subscription auto-renewal (cron) ---------------------- */
// Billing sweeps 3 days before expiry; grace of 7 days before the pack lapses.
async function billExpiringSubscriptions(env: Env): Promise<{ billed: number; failed: number; expired: number }> {
  const due = await env.DB.prepare(
    `SELECT s.id, s.phone, s.tier FROM subscriptions s WHERE s.status = 'active'
       AND s.period_end IS NOT NULL AND s.period_end <= datetime('now', '+3 days')`,
  ).all().then((r: { results?: unknown[] }) => (r.results ?? []) as any[]);
  let billed = 0, failed = 0;
  for (const sub of due) {
    const plan = (await plans(env.DB))[sub.tier as PlanTier];
    if (!plan) continue;
    const existing = await env.DB.prepare(
      `SELECT id FROM payments WHERE subscription_id = ?1 AND status = 'pending'`,
    ).bind(sub.id).first<any>();
    if (existing) continue;
    const ref = `sub-${sub.id}-${new Date().toISOString().slice(0, 10).replace(/-/g, '')}`;
    // pack renewals carry the full collection fees (platform cut + Lipila legs)
    const pf = platformFee(plan.fee_zmw);
    const renewAmount = round2(plan.fee_zmw + pf + MOMO_COLLECTION_FEE);
    const init = await lipilaCollect(env, sub.phone, renewAmount, ref, `DropOff ${sub.tier} pack renewal`);
    if (init.ok) {
      await env.DB.prepare(
        `INSERT INTO payments (phone, provider, amount_zmw, credit_zmw, platform_fee_zmw,
           lipila_fee_zmw, lipila_reference, status, channel, kind, subscription_id)
         VALUES (?1,?2,?3,?4,?5,?6,?7,'pending','merchant','subscription',?8)`,
      ).bind(sub.phone, providerFromPhone(sub.phone), renewAmount, plan.fee_zmw, pf, MOMO_COLLECTION_FEE,
        init.lipilaReference ?? null, sub.id).run();
      billed++;
    } else {
      failed++;
    }
  }
  // lapse packs past their 30-day cycle (overage keeps them selling until renewal)
  const lapse = await env.DB.prepare(
    `UPDATE subscriptions SET status = 'expired'
      WHERE status = 'active' AND period_end IS NOT NULL AND period_end < datetime('now', '-7 days')
        AND NOT EXISTS (SELECT 1 FROM payments WHERE subscription_id = subscriptions.id AND status = 'pending')`,
  ).run();
  return { billed, failed, expired: lapse.meta.changes ?? 0 };
}

/* --------------------- cron: 80%-cap renewal nudge ------------------------- */
// One SMS per cycle per seller, at >=80% of their effective cap. The nudge is
// honest: parcels left + renewal date + the upgrade lever.
async function notifyCapNudges(env: Env): Promise<void> {
  try {
    const packs = await plans(env.DB);
    const { results } = await env.DB.prepare(
      `SELECT s.id, s.phone, s.tier, s.period_start, s.period_end, s.cap_nudge_period,
              (SELECT COALESCE(SUM(j.parcels), 0) FROM jobs j
                WHERE j.sender_phone = s.phone AND j.created_at >= s.period_start
                  AND j.created_at < s.period_end) AS used
         FROM subscriptions s
        WHERE s.status = 'active' AND s.period_end IS NOT NULL AND s.period_end > datetime('now')`,
    ).all();
    for (const row of results as any[]) {
      const plan = packs[row.tier as PlanTier];
      if (!plan || !row.period_start) continue;
      const cap = plan.parcels_per_month;
      const used = Number(row.used ?? 0);
      if (cap <= 0 || used < cap * 0.8) continue;
      if (row.cap_nudge_period === row.period_start) continue; // once per cycle
      const left = Math.max(0, cap - used);
      const renewDate = String(row.period_end).slice(0, 10);
      await sendSms(env, row.phone,
        `DropOff: ${left} parcel${left === 1 ? '' : 's'} left on your ${row.tier} pack this cycle (renews ${renewDate}). Renew or upgrade in the app to keep your free rider rate.`);
      await env.DB.prepare('UPDATE subscriptions SET cap_nudge_period = ?2 WHERE id = ?1')
        .bind(row.id, row.period_start).run().catch(() => {});
    }
  } catch { /* nudges are best-effort — never break the cron */ }
}

/* ----------------------- cron: purge stale auth rows ----------------------- */
// rate_hits / login_attempts / expired otp_codes + email_tokens otherwise grow
// forever (every throttled request inserts a row).
async function purgeStaleRows(env: Env): Promise<void> {
  try {
    await env.DB.batch([
      env.DB.prepare(`DELETE FROM rate_hits WHERE created_at < datetime('now', '-2 hours')`),
      env.DB.prepare(`UPDATE subscriptions SET status = 'expired' WHERE status = 'pending_payment' AND period_end IS NOT NULL AND period_end < datetime('now', '-7 days')`),
      env.DB.prepare(`DELETE FROM subscriptions WHERE status = 'expired' AND period_end IS NOT NULL AND period_end < datetime('now', '-90 days')`),
      env.DB.prepare(`DELETE FROM login_attempts WHERE created_at < datetime('now', '-25 hours')`),
      env.DB.prepare(`DELETE FROM otp_codes  WHERE expires_at < datetime('now', '-1 day')`),
      env.DB.prepare(`DELETE FROM email_tokens WHERE expires_at < datetime('now', '-1 day')`),
      env.DB.prepare(`DELETE FROM job_events WHERE created_at IS NULL`), // data hygiene no-op guard
      env.DB.prepare(`DELETE FROM idempotency_keys WHERE created_at < datetime('now', '-7 days')`),
    ]);
  } catch { /* purge is best-effort â€” never break billing */ }
}

/* ----------------------- cron: daily app-data backup ----------------------- */
// Every CAT night at 02:00, dump core business entities from D1 as gzipped
// JSONL into R2 (dropoff-backups). Read-only: never mutates production data.
// If R2 isn't configured the cron silently skips (never blocks billing/purge).

async function gzipBytes(text: string): Promise<Uint8Array> {
  const stream = new CompressionStream('gzip');
  const writer = stream.writable.getWriter();
  writer.write(new TextEncoder().encode(text));
  writer.close();
  const chunks: Uint8Array[] = [];
  const reader = stream.readable.getReader();
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    chunks.push(value!);
  }
  const out = new Uint8Array(chunks.reduce((n, c) => n + c.byteLength, 0));
  let o = 0;
  for (const c of chunks) { out.set(c, o); o += c.byteLength; }
  return out;
}

async function dumpTable(env: Env, table: string): Promise<string | null> {
  try {
    const { results } = await env.DB.prepare(`SELECT * FROM ${table}`).all();
    const rows = (results ?? []) as any[];
    return rows.map((r) => JSON.stringify(r)).join('\n') + (rows.length ? '\n' : '');
  } catch { return null; }
}

async function backupAppData(env: Env): Promise<void> {
  if (!env.BACKUPS) return;
  const tables = ['auth_users','jobs','payments','wallets','wallet_ledger','subscriptions',
    'recurring_plans','referrals','riders','couriers','quotes','job_events'];
  const stamp = new Date(Date.now() + 2 * 3600_000).toISOString().slice(0, 10); // CAT date
  const ok: string[] = [], skipped: string[] = [];
  for (const table of tables) {
    const payload = await dumpTable(env, table);
    if (payload == null) { skipped.push(table); continue; }
    const blob = await gzipBytes(payload);
    const key = `backups/${stamp}/${table}.jsonl.gz`;
    try {
      await env.BACKUPS.put(key, blob, { httpMetadata: { contentType: 'application/gzip' } });
      ok.push(key);
    } catch { skipped.push(table); }
  }
  const manifest = JSON.stringify({ date: stamp, ok, skipped, generated_at: new Date().toISOString() });
  try { await env.BACKUPS.put(`backups/${stamp}/manifest.json`, manifest, { httpMetadata: { contentType: 'application/json' } }); } catch {}
}

/* ------------- cron: timed-pickup reminders (every minute) ----------------- */
// Jobs with a booked pickup_at get a push at T-30 and T-10 to sender + rider,
// and are flagged 'missed' when the window passes without a status change.
// Keeps timed parcels honest without a separate queue infra.
async function checkTimedPickups(env: Env): Promise<void> {
  try {
    const now = new Date().toISOString();
    const due = await env.DB.prepare(
      `SELECT sp.job_ref, sp.phone, sp.rider_phone, sp.pickup_at, sp.status,
              j.pickup_address, j.dest_city, j.ref
         FROM scheduled_pickups sp
         JOIN jobs j ON j.ref = sp.job_ref
        WHERE sp.status = 'pending'
          AND sp.pickup_at <= datetime('now', '+30 minutes')
          AND sp.pickup_at > datetime('now', '-10 minutes')
          AND (j.status IS NULL OR j.status NOT IN ('delivered','ready_for_collection'))`,
    ).all<{ job_ref: string; phone: string; rider_phone: string | null; pickup_at: string; pickup_address: string | null; dest_city: string | null; ref: string }>();
    const rows = (due.results ?? []) as any[];
    for (const r of rows) {
      const mins = Math.round((new Date(r.pickup_at).getTime() - new Date(now).getTime()) / 60000);
      const when = mins <= 0 ? 'now' : `in ${mins} min`;
      await sendToPhone(env, r.phone, {
        title: 'Timed pickup due',
        body: `Job ${r.job_ref} â€” ${r.pickup_address ?? ''} â†’ ${r.dest_city ?? ''}, pickup ${when}.`,
        data: { job_ref: r.job_ref, kind: 'pickup_reminder' },
      });
      if (r.rider_phone && r.rider_phone !== r.phone) {
        await sendToPhone(env, r.rider_phone, {
          title: 'Rider: timed pickup due',
          body: `Job ${r.job_ref} â€” ${r.pickup_address ?? ''} â†’ ${r.dest_city ?? ''}, pickup ${when}.`,
          data: { job_ref: r.job_ref, kind: 'pickup_reminder' },
        });
      }
      await env.DB.prepare(
        `UPDATE scheduled_pickups SET status = 'notified', notified_at = datetime('now')
          WHERE job_ref = ?1 AND status = 'pending'`,
      ).bind(r.job_ref).run();
    }
    // Missed: window passed and the job never left 'created'/'rider_assigned'
    await env.DB.prepare(
      `UPDATE scheduled_pickups SET status = 'missed'
        WHERE status = 'pending' AND pickup_at < datetime('now', '-10 minutes')
          AND job_ref IN (SELECT ref FROM jobs WHERE status IN ('created','rider_assigned'))`,
    ).run();
    // Completed: job moved on
    await env.DB.prepare(
      `UPDATE scheduled_pickups SET status = 'completed'
        WHERE status IN ('pending','notified')
          AND job_ref IN (SELECT ref FROM jobs WHERE status IN ('delivered','ready_for_collection'))`,
    ).run();
  } catch { /* timed pickups are best-effort â€” never block the cron */ }
}

/* ------------- cron: materialise recurring plans into jobs ----------------- */
// Standing orders become real jobs on their due day (CAT). Rules: weekly =
// the plan's weekday; biweekly = every other ISO week (parity by plan id);
// monthly = the weekday recurring every 4th week. A job is only created when a
// verified chargebook price exists â€” else the plan is skipped this run (never
// invent a fare). Jobs are pre-booked and need rider assignment as usual.
async function materializeRecurringJobs(env: Env): Promise<{ created: number; skipped: number }> {
  let created = 0, skipped = 0;
  try {
    const todayIso = new Date(Date.now() + 2 * 3600_000).toISOString().slice(0, 10); // CAT date
    const { results } = await env.DB.prepare(
      `SELECT * FROM recurring_plans WHERE active = 1 AND courier_id IS NOT NULL
         AND (last_created_at IS NULL OR last_created_at <> ?1)`,
    ).bind(todayIso).all();
    const catDate = new Date(todayIso + 'T12:00:00Z'); // mid-day so date math is stable
    const dow = catDate.getUTCDay() === 0 ? 7 : catDate.getUTCDay();          // 1=Mon â€¦ 7=Sun
    const isoWeek = Number(await env.DB.prepare("SELECT strftime('%W', ?1) AS w")
      .bind(todayIso).first<any>().then((r: any) => r?.w ?? '0'));            // 00â€“53
    for (const plan of results as any[]) {
      const due =
        plan.frequency === 'weekly' ? Number(plan.weekday) === dow :
        plan.frequency === 'biweekly' ? Number(plan.weekday) === dow && isoWeek % 2 === Math.abs(plan.id) % 2 :
        Number(plan.weekday) === dow && Math.floor(isoWeek / 4) % 2 === Math.abs(plan.id) % 2;
      if (!due) continue;
      const fromCity = plan.from_city ?? 'Lusaka';
      const quote = await env.DB.prepare(
        `SELECT counter_price_zmw FROM quotes
          WHERE courier_id = ?1 AND from_city = ?2 AND to_city = ?3 AND weight_class = ?4 AND service = 'standard'`,
      ).bind(plan.courier_id, fromCity, plan.dest_city, plan.weight_class ?? '0-5kg').first<any>();
      if (!quote) { skipped++; continue; }
      const totals = computeJobTotals({
        counterPriceZmw: Number(quote.counter_price_zmw),
        riderFeeZmw: baseRiderFee(fromCity, 0, 0, 'motorcycle'),
      });
      const ref = `DRO-${todayIso.replace(/-/g, '')}-${randomCode(5)}`;
      try {
        await env.DB.prepare(
          `INSERT INTO jobs (ref, sender_phone, sender_name, pickup_address, courier_id,
             recipient_name, recipient_phone, dest_city, description, weight_class,
             counter_price_zmw, rider_fee_zmw, total_zmw, pay_method)
           VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, 'mobile_money')`,
        ).bind(
          ref, plan.phone, null, plan.pickup_address ?? null, plan.courier_id,
          plan.recipient_name ?? null, plan.recipient_phone ?? null, plan.dest_city,
          plan.description ?? (freqLabel(plan.frequency) + ' standing order'),
          plan.weight_class ?? '0-5kg',
          Number(quote.counter_price_zmw), baseRiderFee(fromCity, 0, 0, 'motorcycle'), totals.total_zmw,
        ).run();
        created++;
        await env.DB.prepare('UPDATE recurring_plans SET last_created_at = ?2 WHERE id = ?1')
          .bind(plan.id, todayIso).run();
      } catch {
        skipped++;
      }
    }
  } catch { /* recurring is best-effort â€” do not fail the cron */ }
  return { created, skipped };
}

function freqLabel(f: string): string {
  return f === 'weekly' ? 'Weekly' : f === 'biweekly' ? 'Fortnightly' : 'Monthly';
}

/* --------------------------- error reporting ------------------------------ */
// Minimal Sentry "store" client (no SDK): one POST per uncaught error. Safe to
// leave unset — telemetry must never break a delivery.
async function captureError(env: Env, err: unknown, req: { method: string; url: string }): Promise<void> {
  const dsn = env.SENTRY_DSN;
  if (!dsn) return;
  try {
    const u = new URL(dsn);
    const project = u.pathname.replace(/^\//, '');
    const e = err as any;
    const event = {
      event_id: crypto.randomUUID().replace(/-/g, ''),
      timestamp: new Date().toISOString(),
      platform: 'javascript',
      level: 'error',
      logger: 'dropoff-worker',
      environment: env.ENV ?? 'production',
      transaction: `${req.method} ${new URL(req.url).pathname}`,
      exception: { values: [{ type: e?.name ?? 'Error', value: String(e?.message ?? e).slice(0, 1000) }] },
    };
    await fetch(`${u.protocol}//${u.host}/api/${project}/store/`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Sentry-Auth': `Sentry sentry_version=7, sentry_key=${u.username}, sentry_client=dropoff-worker/1.0`,
      },
      body: JSON.stringify(event),
    });
  } catch { /* telemetry is best-effort */ }
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    try {
      // Realtime chat: hand WebSocket upgrades to the per-thread Durable Object.
      const url = new URL(request.url);
      if (url.pathname.startsWith('/ws/chat/')) {
        if (request.headers.get('Upgrade')?.toLowerCase() !== 'websocket') {
          return new Response(JSON.stringify({ error: 'websocket_required' }), {
            status: 426, headers: { 'Content-Type': 'application/json' },
          });
        }
        const id = env.CHAT.idFromName(url.pathname);
        return env.CHAT.get(id).fetch(request);
      }
      return await app.fetch(request, env, ctx);
    } catch (e) {
      await captureError(env, e, request);
      return new Response(JSON.stringify({ error: 'internal_error' }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      });
    }
  },
  async scheduled(event: ScheduledEvent, env: Env, ctx: ExecutionContext): Promise<void> {
    ctx.waitUntil((async () => {
      try {
        if (event.cron === '* * * * *') {
          await checkTimedPickups(env);
          await notifyCapNudges(env);
          return;
        }
        await purgeStaleRows(env);
        await billExpiringSubscriptions(env);
        await materializeRecurringJobs(env);
        await backupAppData(env);
        await reconcilePayments(env);
      } catch (e) {
        await captureError(env, e, { method: 'CRON', url: `https://cron/${event.cron}` });
      }
    })());
  },
};
