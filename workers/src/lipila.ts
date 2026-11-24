// ─────────────────────────────────────────────────────────────────────
// DROPOFF — ownership stamp (do not remove)
// :Godfrey Moses Kalambo:Carpso Solutions:0968551110.
// © 2026 Godfrey Moses Kalambo · Carpso Solutions · Lusaka, Zambia.
// ─────────────────────────────────────────────────────────────────────
// Circuit breaker for external payment providers.
import { withCircuit } from './circuit';

// Environment types (declared here so both modules share them)
export interface Env {
  DB: D1Database;
  LIPILA_BASE_URL: string;        // sandbox https://api.lipila.dev · production https://blz.lipila.io
  LIPILA_ENV?: string;            // explicit environment selector, mirrors chisomo
  LIPILA_API_KEY: string;
  HUGGINGFACE_TOKEN?: string;
  LIPILA_CALLBACK_URL?: string;   // posted as the callbackUrl header on collect/disburse
  APP_URL?: string;               // API base — internal /health + server-to-server
  APP_PUBLIC_URL?: string;        // user-facing links: dropoff.carpsosolutions.store
  MAIL_FROM?: string;             // e.g. no-reply@dropoffzm.com (domain must be on Email Sending)
  SMS_USERNAME?: string;          // legacy Africas Talking name (fallback)
  SMS_API_KEY?: string;
  SMS_SENDER_ID?: string;
  // Africa's Talking — the Carpso account (see sms.ts). Preferred over SMS_*.
  ENV?: string;                   // "production" = real AT send; anything else = log only
  AT_USERNAME?: string;           // e.g. "ChurchOnApp"
  AT_API_KEY?: string;
  AT_FROM?: string;               // approved sender ID, e.g. "Carpso"
  API_AUTH_KEY: string;
  JWT_SECRET: string;
  ADMIN_AUTH_KEY: string;
  AUTH_DEV_MODE?: string;         // "1" = return OTP codes / email tokens in responses (no SMS/EMAIL yet)
  CORS_ORIGINS?: string;
  FIREBASE_SERVICE_ACCOUNT?: string;          // comma-separated allowed cross-origins ("" = same-origin only)
  SENTRY_DSN?: string;                        // optional error tracking (Sentry)
  LIPILA_WEBHOOK_SECRET?: string;             // optional shared secret for callback headers
  BACKUPS?: R2Bucket;                         // daily app-data exports land here (optional)
  APPLE_TEAM_ID?: string;                     // set to your Apple Team ID to enable universal links
  /** Workers AI binding: address parsing, support drafts, rider-doc checks. */
  AI?: Ai;
  CHAT: DurableObjectNamespace;               // realtime chat rooms (one per thread)
  EMAIL?: { send(msg: { to: string; from: { email: string; name?: string }; subject: string; html?: string; text?: string }): Promise<Response> };
  /** Owner who receives intrusion / new-device alerts (260XXXXXXXXX). */
  OWNER_PHONE?: string;
  /** Email copy of owner alerts (SMS/push used if absent). */
  OWNER_EMAIL?: string;
  /** Business momo that receives ALL platform income (fees + processing).
   *  Scheduled sweeps disburse accumulated fees to this number via Lipila. */
  BUSINESS_PHONE?: string;
}

// Lipila integration — VERIFIED against https://docs.lipila.dev:
//   Sandbox base:   https://api.lipila.dev
//   Production base: https://blz.lipila.io
//   Auth header:    x-api-key (NOT Bearer)
//   Collect:        POST /api/v1/collections/mobile-money
//   Payout:         POST /api/v1/disbursements/mobile-money  (payout destinations only RECEIVE — no registration required)
//   Status checks:  GET  /api/v1/collections/check-status?referenceId=…
//                   GET  /api/v1/disbursements/check-status?referenceId=…
// All phone numbers normalized to 260XXXXXXXXX. ZICTA national numbering plan
// (ITU Dec-2024 notification): mobile = 5x/7x/9x (9-digit NS). Airtel 77/97/57,
// MTN 76/96/56, Zamtel 75/95/55, Beeline 78/98. VoIP (6x) and premium-rate (90)
// are NOT mobile-charging rails and are rejected.

export type Provider = 'airtel' | 'mtn' | 'zamtel';

/** Normalize a Zambian mobile number to 260XXXXXXXXX */
export function normalizeZmPhone(raw: string): string {
  let d = raw.replace(/\D/g, '');
  if (d.startsWith('00260')) d = d.slice(2);           // international escape
  else if (d.startsWith('0') && d.length === 10) d = '260' + d.slice(1); // trunk 0
  else if (d.length === 9) d = '260' + d;              // bare national significant
  if (!/^260(5[0-9]|7[0-9]|9[1-9])\d{7}$/.test(d)) {
    throw new Error(`Invalid Zambian mobile number: ${raw}`);
  }
  return d;
}

export function providerFromPhone(zm: string): Provider {
  if (/^260(57|77|97)/.test(zm)) return 'airtel';
  if (/^260(56|76|96)/.test(zm)) return 'mtn';
  // Zamtel: 55/75/95. Beeline (58/78/98) rides the Zamtel rail on Lipila today.
  return 'zamtel';
}

/** Environment-aware base URL, matching chisomo's production/sandbox selector. */
export function lipilaBase(env: Env): string {
  if (env.LIPILA_ENV === 'production') return 'https://blz.lipila.io';
  if (env.LIPILA_ENV === 'sandbox') return 'https://api.lipila.dev';
  return String(env.LIPILA_BASE_URL ?? '').replace(/\/+$/, '');
}

/** Trim accidental dotenv quotes/whitespace before sending the secret. */
export function lipilaApiKey(env: Env): string {
  return String(env.LIPILA_API_KEY ?? '').trim().replace(/^["']|["']$/g, '');
}

function lipilaHeaders(apiKey: string, env: Env): HeadersInit {
  // Chisomo pattern: embed our shared secret directly in the callbackUrl —
  // Lipila echoes the full URL back on the webhook, so /webhooks/lipila can
  // verify the `secret` query param (Lipila does NOT send signature headers).
  const callbackUrl = env.LIPILA_CALLBACK_URL
    ? (env.LIPILA_WEBHOOK_SECRET
        ? `${env.LIPILA_CALLBACK_URL}?secret=${encodeURIComponent(env.LIPILA_WEBHOOK_SECRET)}`
        : env.LIPILA_CALLBACK_URL)
    : undefined;
  return {
    'accept': 'application/json',
    'Content-Type': 'application/json',
    'x-api-key': apiKey,
    ...(callbackUrl ? { callbackUrl } : {}),
  };
}

/**
 * Lipila rejects any narration containing anything but letters, numbers and
 * spaces (HTTP 400 "Narration can only contain letters, numbers and
 * spaces"). Colons, dashes, apostrophes and emoji all fail the whole
 * request — sanitize first, exactly as chisomo (Kingdom Sponsor) does.
 */
export function sanitizeNarration(s: string): string {
  return String(s ?? '')
    .normalize('NFKD')
    .replace(/[^A-Za-z0-9 ]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 50);
}

/** Customer collection (pushes a pin prompt to the payer's phone). */
export async function lipilaCollect(
  env: Env,
  phoneZm: string,
  amountZmw: number,
  reference: string,
  note: string,
  email?: string,
): Promise<{ ok: boolean; lipilaReference?: string; raw?: string; status: number }> {
  let res: Response;
  try {
    res = await withCircuit('lipila-collect', () => fetch(`${lipilaBase(env)}/api/v1/collections/mobile-money`, {
      method: 'POST',
      headers: lipilaHeaders(lipilaApiKey(env), env),
      body: JSON.stringify({
        referenceId: reference,
        amount: amountZmw,
        narration: sanitizeNarration(note),
        accountNumber: phoneZm,
        currency: 'ZMW',
        ...(email ? { email } : {}),
      }),
      // Hard cap — without this a slow provider hangs the whole payment
      // request past the app's timeout and users see "network error".
      signal: AbortSignal.timeout(8000),
    }));
  } catch (e: any) {
    if (e?.status === 503) {
      return { ok: false, status: 503, lipilaReference: undefined, raw: 'circuit_open' };
    }
    return { ok: false, status: 502, lipilaReference: undefined, raw: String(e?.message ?? e) };
  }
  const text = await res.text();
  if (!res.ok) {
    console.error(JSON.stringify({
      where: 'lipila-collect', status: res.status, body: text.slice(0, 300),
    }));
  }
  let data: any = null;
  try { data = JSON.parse(text); } catch { /* keep raw */ }
  const ref = data?.referenceId ?? data?.reference ?? data?.transactionReference ?? data?.transactionId ?? data?.lipilaReference ?? null;
  return { ok: res.ok, status: res.status, lipilaReference: ref ? String(ref) : undefined, raw: text };
}

/** Rider/partner payout. The momo numbers being paid only RECEIVE — they do
 *  not need to be registered/added in the Lipila dashboard (owner confirmed
 *  with Lipila: payout destinations require no prior registration; the same
 *  holds for our own platform momo main number which only receives the sweep
 *  of platform income). Sandbox funding must have disbursement float or
 *  payouts fail cleanly (ok=false) and are surfaced to ops. */
export async function lipilaDisburse(
  env: Env,
  phoneZm: string,
  amountZmw: number,
  reference: string,
  note: string,
): Promise<{ ok: boolean; lipilaReference?: string; raw?: string; status: number }> {
  let res: Response;
  try {
    res = await withCircuit('lipila-disbursements', () => fetch(`${lipilaBase(env)}/api/v1/disbursements/mobile-money`, {
      method: 'POST',
      headers: lipilaHeaders(lipilaApiKey(env), env),
      body: JSON.stringify({
        referenceId: reference,
        amount: amountZmw,
        accountNumber: phoneZm,
        currency: 'ZMW',
        narration: sanitizeNarration(note),
      }),
      signal: AbortSignal.timeout(8000),
    }));
  } catch (e: any) {
    if (e?.status === 503) {
      return { ok: false, status: 503, lipilaReference: undefined, raw: 'circuit_open' };
    }
    return { ok: false, status: 502, lipilaReference: undefined, raw: String(e?.message ?? e) };
  }
  const text = await res.text();
  if (!res.ok) {
    console.error(JSON.stringify({
      where: 'lipila-disburse', status: res.status, body: text.slice(0, 300),
    }));
  }
  let data: any = null;
  try { data = JSON.parse(text); } catch { /* keep raw */ }
  const ref = data?.referenceId ?? data?.reference ?? data?.transactionReference ?? data?.transactionId ?? data?.lipilaReference ?? null;
  return { ok: res.ok, status: res.status, lipilaReference: ref ? String(ref) : undefined, raw: text };
}

/** Poll a collection WITH the telco's failure reason. On a failed prompt
 *  Lipila returns e.g. "User wallet does not have enough money to cover the
 *  payable amount." — the owner directive (2026-11-17) is that the app must
 *  show the payer WHY it failed, not a generic rejection. The reason is only
 *  populated on 'failed'; success/pending messages are transport noise. */
export async function lipilaStatusDetail(env: Env, reference: string): Promise<{ status: 'pending' | 'success' | 'failed'; reason?: string }> {
  let res: Response;
  try {
    res = await withCircuit('lipila-status', () => fetch(`${lipilaBase(env)}/api/v1/collections/check-status?referenceId=${encodeURIComponent(reference)}`, {
      headers: { accept: 'application/json', 'x-api-key': lipilaApiKey(env) },
      signal: AbortSignal.timeout(8000),
    }));
  } catch {
    return { status: 'pending' }; // circuit open: treat as pending, never block a payment on a status poll
  }
  if (!res.ok) return { status: 'pending' };
  const data: any = await res.json().catch(() => null);
  const raw = data?.status ?? data?.paymentStatus ?? data?.state ?? data?.transactionStatus ?? data?.result;
  const status = mapLipilaStatus(raw);
  const message = typeof data?.message === 'string' ? data.message.trim() : '';
  return { status, reason: status === 'failed' && message ? message.slice(0, 200) : undefined };
}

/** Poll a collection. The app polls every ~2s for up to 40s. */
export async function lipilaStatus(env: Env, reference: string): Promise<'pending' | 'success' | 'failed'> {
  return (await lipilaStatusDetail(env, reference)).status;
}

/** Poll a DISBURSEMENT (payout). Separate status endpoint from collections —
 *  the worker must reconcile pending payouts (reimbursements, payroll, refunds,
 *  sweeps) against Lipila's own verdict instead of trusting only the init
 *  response, which can leave forever-pending rows. */
export async function lipilaDisburseStatusDetail(env: Env, reference: string): Promise<{ status: 'pending' | 'success' | 'failed'; reason?: string }> {
  let res: Response;
  try {
    res = await withCircuit('lipila-disburse-status', () => fetch(`${lipilaBase(env)}/api/v1/disbursements/check-status?referenceId=${encodeURIComponent(reference)}`, {
      headers: { accept: 'application/json', 'x-api-key': lipilaApiKey(env) },
      signal: AbortSignal.timeout(8000),
    }));
  } catch {
    return { status: 'pending' };
  }
  if (!res.ok) return { status: 'pending' };
  const data: any = await res.json().catch(() => null);
  const raw = data?.status ?? data?.paymentStatus ?? data?.state ?? data?.transactionStatus ?? data?.result;
  const status = mapLipilaStatus(raw);
  const message = typeof data?.message === 'string' ? data.message.trim() : '';
  return { status, reason: status === 'failed' && message ? message.slice(0, 200) : undefined };
}

function mapLipilaStatus(raw: unknown): 'pending' | 'success' | 'failed' {
  const s = String(raw ?? '').toLowerCase();
  if (s === 'success' || s === 'successful' || s === 'paid') return 'success';
  if (s === 'failed' || s === 'rejected' || s === 'cancelled') return 'failed';
  return 'pending';
}
