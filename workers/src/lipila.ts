// Circuit breaker for external payment providers.
import { withCircuit } from './circuit';

// Environment types (declared here so both modules share them)
export interface Env {
  DB: D1Database;
  LIPILA_BASE_URL: string;        // sandbox https://api.lipila.dev · production https://blz.lipila.io
  LIPILA_API_KEY: string;
  HUGGINGFACE_TOKEN?: string;
  LIPILA_CALLBACK_URL?: string;   // posted as the callbackUrl header on collect/disburse
  APP_URL?: string;               // links used inside transactional emails
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
  /** Workers AI binding: address parsing, support drafts, rider-doc checks. */
  AI?: Ai;
  CHAT: DurableObjectNamespace;               // realtime chat rooms (one per thread)
  EMAIL?: { send(msg: { to: string; from: { email: string; name?: string }; subject: string; html?: string; text?: string }): Promise<Response> };
  /** Owner who receives intrusion / new-device alerts (260XXXXXXXXX). */
  OWNER_PHONE?: string;
  /** Email copy of owner alerts (SMS/push used if absent). */
  OWNER_EMAIL?: string;
}

// Lipila integration — VERIFIED against https://docs.lipila.dev:
//   Sandbox base:   https://api.lipila.dev
//   Production base: https://blz.lipila.io
//   Auth header:    x-api-key (NOT Bearer)
//   Collect:        POST /api/v1/collections/mobile-money
//   Payout:         POST /api/v1/disbursements/mobile-money  (needs IP whitelisting!)
//   Status checks:  GET  /api/v1/collections/check-status?referenceId=…
//                   GET  /api/v1/disbursements/check-status?referenceId=…
// All phone numbers normalized to 260XXXXXXXXX (Airtel 097/077, MTN 096/076, Zamtel 095/075).

export type Provider = 'airtel' | 'mtn' | 'zamtel';

/** Normalize a Zambian phone number to 260XXXXXXXXX */
export function normalizeZmPhone(raw: string): string {
  let d = raw.replace(/\D/g, '');
  if (d.startsWith('09') || d.startsWith('07')) d = '260' + d.slice(1);
  else if (d.startsWith('260')) { /* already fine */ }
  else if (d.length === 9) d = '260' + d;
  if (!/^260(97|77|96|76|95|75)\d{7}$/.test(d)) throw new Error(`Invalid Zambian phone: ${raw}`);
  return d;
}

export function providerFromPhone(zm: string): Provider {
  if (/^260(97|77)/.test(zm)) return 'airtel';
  if (/^260(96|76)/.test(zm)) return 'mtn';
  return 'zamtel';
}

function lipilaHeaders(apiKey: string, env: Env): HeadersInit {
  return {
    'accept': 'application/json',
    'Content-Type': 'application/json',
    'x-api-key': apiKey,
    ...(env.LIPILA_CALLBACK_URL ? { callbackUrl: env.LIPILA_CALLBACK_URL } : {}),
  };
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
    res = await withCircuit('lipila-collect', () => fetch(`${env.LIPILA_BASE_URL}/api/v1/collections/mobile-money`, {
      method: 'POST',
      headers: lipilaHeaders(env.LIPILA_API_KEY, env),
      body: JSON.stringify({
        referenceId: reference,
        amount: amountZmw,
        narration: note,
        accountNumber: phoneZm,
        currency: 'ZMW',
        ...(email ? { email } : {}),
        referenceData: note,
      }),
    }));
  } catch (e: any) {
    if (e?.status === 503) {
      return { ok: false, status: 503, lipilaReference: undefined, raw: 'circuit_open' };
    }
    return { ok: false, status: 502, lipilaReference: undefined, raw: String(e?.message ?? e) };
  }
  const text = await res.text();
  let data: any = null;
  try { data = JSON.parse(text); } catch { /* keep raw */ }
  const ref = data?.referenceId ?? data?.reference ?? data?.transactionReference ?? data?.transactionId ?? data?.lipilaReference ?? null;
  return { ok: res.ok, status: res.status, lipilaReference: ref ? String(ref) : undefined, raw: text };
}

/** Rider/partner payout. Lipila REQUIRES the server IP whitelisted before this works. */
export async function lipilaDisburse(
  env: Env,
  phoneZm: string,
  amountZmw: number,
  reference: string,
  note: string,
): Promise<{ ok: boolean; lipilaReference?: string; raw?: string; status: number }> {
  let res: Response;
  try {
    res = await withCircuit('lipila-disbursements', () => fetch(`${env.LIPILA_BASE_URL}/api/v1/disbursements/mobile-money`, {
      method: 'POST',
      headers: lipilaHeaders(env.LIPILA_API_KEY, env),
      body: JSON.stringify({
        referenceId: reference,
        amount: amountZmw,
        accountNumber: phoneZm,
        currency: 'ZMW',
        narration: note,
        referenceData: note,
      }),
    }));
  } catch (e: any) {
    if (e?.status === 503) {
      return { ok: false, status: 503, lipilaReference: undefined, raw: 'circuit_open' };
    }
    return { ok: false, status: 502, lipilaReference: undefined, raw: String(e?.message ?? e) };
  }
  const text = await res.text();
  let data: any = null;
  try { data = JSON.parse(text); } catch { /* keep raw */ }
  const ref = data?.referenceId ?? data?.reference ?? data?.transactionReference ?? data?.transactionId ?? data?.lipilaReference ?? null;
  return { ok: res.ok, status: res.status, lipilaReference: ref ? String(ref) : undefined, raw: text };
}

/** Poll a collection. The app polls every ~2s for up to 40s. */
export async function lipilaStatus(env: Env, reference: string): Promise<'pending' | 'success' | 'failed'> {
  let res: Response;
  try {
    res = await withCircuit('lipila-status', () => fetch(`${env.LIPILA_BASE_URL}/api/v1/collections/check-status?referenceId=${encodeURIComponent(reference)}`, {
      headers: { accept: 'application/json', 'x-api-key': env.LIPILA_API_KEY },
    }));
  } catch {
    return 'pending'; // circuit open: treat as pending, never block a payment on a status poll
  }
  if (!res.ok) return 'pending';
  const data: any = await res.json().catch(() => null);
  const raw = data?.status ?? data?.paymentStatus ?? data?.state ?? data?.transactionStatus ?? data?.result;
  return mapLipilaStatus(raw);
}

function mapLipilaStatus(raw: unknown): 'pending' | 'success' | 'failed' {
  const s = String(raw ?? '').toLowerCase();
  if (s === 'success' || s === 'successful' || s === 'paid') return 'success';
  if (s === 'failed' || s === 'rejected' || s === 'cancelled') return 'failed';
  return 'pending';
}
