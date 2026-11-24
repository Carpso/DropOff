// ─────────────────────────────────────────────────────────────────────
// DROPOFF — ownership stamp (do not remove)
// :Godfrey Moses Kalambo:Carpso Solutions:0968551110.
// © 2026 Godfrey Moses Kalambo · Carpso Solutions · Lusaka, Zambia.
// ─────────────────────────────────────────────────────────────────────
// Lenco v2 gateway client. Server-side only; the secret API token never
// reaches Flutter/web. Docs: https://lenco-api.readme.io/v2.0
import { withCircuit } from './circuit';
import { normalizeZmPhone, providerFromPhone, sanitizeNarration, type Env, type Provider } from './lipila';

export interface LencoInitResult {
  ok: boolean;
  gateway: 'lenco';
  reference?: string;
  lencoReference?: string;
  raw?: string;
  status: number;
}

export interface LencoStatus {
  status: 'pending' | 'success' | 'failed';
  reason?: string;
  fee?: number;
}

export function lencoBase(env: Env): string {
  if (env.LENCO_ENV === 'production') return 'https://api.lenco.co/access/v2';
  if (env.LENCO_ENV === 'sandbox') return 'https://sandbox.lenco.co/access/v2';
  return String(env.LENCO_BASE_URL ?? '').replace(/\/+$/, '');
}

export function lencoApiKey(env: Env): string {
  return String(env.LENCO_API_KEY ?? '').trim().replace(/^["']|["']$/g, '');
}

export function lencoAccountId(env: Env): string {
  return String(env.LENCO_ACCOUNT_ID ?? '').trim();
}

export function lencoConfigured(env: Env): boolean {
  return !!lencoBase(env) && !!lencoApiKey(env) && !!lencoAccountId(env);
}

function headers(env: Env): HeadersInit {
  return {
    accept: 'application/json',
    'Content-Type': 'application/json',
    Authorization: `Bearer ${lencoApiKey(env)}`,
  };
}

function detailOf(raw: string, status: number): string {
  const text = raw.trim();
  if (text) return text.slice(0, 500);
  if (status === 401 || status === 403) return `Lenco HTTP ${status} (check LENCO_API_KEY / account access)`;
  return `Lenco HTTP ${status}`;
}

/** Mobile-money collection. Lenco deducts its fee from merchant settlement;
 *  `bearer: merchant` keeps the customer's authorised amount exact. */
export async function lencoCollect(
  env: Env,
  phoneRaw: string,
  amountZmw: number,
  reference: string,
  note: string,
): Promise<LencoInitResult> {
  if (!lencoConfigured(env)) {
    return { ok: false, gateway: 'lenco', status: 503, raw: 'Lenco is not configured (API key/account/base URL missing).' };
  }
  const phone = normalizeZmPhone(phoneRaw);
  const operator: Provider = providerFromPhone(phone);
  let res: Response;
  try {
    res = await withCircuit('lenco-collect', () => fetch(`${lencoBase(env)}/collections/mobile-money`, {
      method: 'POST',
      headers: headers(env),
      body: JSON.stringify({
        amount: amountZmw,
        reference,
        phone,
        operator,
        country: 'zm',
        currency: 'ZMW',
        bearer: 'merchant',
      }),
      signal: AbortSignal.timeout(10000),
    }));
  } catch (e: any) {
    return {
      ok: false, gateway: 'lenco', status: e?.status === 503 ? 503 : 502,
      raw: e?.status === 503 ? 'circuit_open' : String(e?.message ?? e),
    };
  }
  const raw = await res.text().catch(() => '');
  let data: any = null;
  try { data = JSON.parse(raw); } catch { /* retain raw */ }
  const ok = res.ok && data?.status !== false;
  return {
    ok,
    gateway: 'lenco',
    reference: data?.data?.reference ? String(data.data.reference) : reference,
    lencoReference: data?.data?.lencoReference ? String(data.data.lencoReference) : undefined,
    status: res.status,
    raw: ok ? raw : detailOf(raw, res.status),
  };
}

/** Mobile-money transfer/payout from the configured Carpso Solutions account. */
export async function lencoTransfer(
  env: Env,
  phoneRaw: string,
  amountZmw: number,
  reference: string,
  note: string,
): Promise<LencoInitResult> {
  if (!lencoConfigured(env)) {
    return { ok: false, gateway: 'lenco', status: 503, raw: 'Lenco is not configured (API key/account/base URL missing).' };
  }
  const phone = normalizeZmPhone(phoneRaw);
  const operator: Provider = providerFromPhone(phone);
  let res: Response;
  try {
    res = await withCircuit('lenco-transfer', () => fetch(`${lencoBase(env)}/transfers/mobile-money`, {
      method: 'POST',
      headers: headers(env),
      body: JSON.stringify({
        accountId: lencoAccountId(env),
        amount: amountZmw,
        reference,
        phone,
        operator,
        country: 'zm',
        currency: 'ZMW',
        narration: sanitizeNarration(note).slice(0, 100),
      }),
      signal: AbortSignal.timeout(10000),
    }));
  } catch (e: any) {
    return {
      ok: false, gateway: 'lenco', status: e?.status === 503 ? 503 : 502,
      raw: e?.status === 503 ? 'circuit_open' : String(e?.message ?? e),
    };
  }
  const raw = await res.text().catch(() => '');
  let data: any = null;
  try { data = JSON.parse(raw); } catch { /* retain raw */ }
  const ok = res.ok && data?.status !== false;
  return {
    ok,
    gateway: 'lenco',
    reference: data?.data?.reference ? String(data.data.reference) : reference,
    lencoReference: data?.data?.lencoReference ? String(data.data.lencoReference) : undefined,
    status: res.status,
    raw: ok ? raw : detailOf(raw, res.status),
  };
}

function mapStatus(raw: unknown): LencoStatus['status'] {
  const s = String(raw ?? '').toLowerCase();
  if (s === 'success' || s === 'successful' || s === 'paid' || s === 'settled') return 'success';
  if (s === 'failed' || s === 'rejected' || s === 'cancelled' || s === 'declined') return 'failed';
  return 'pending'; // pending / pay-offline / unknown => never settle on uncertainty
}

export async function lencoCollectionStatus(env: Env, reference: string): Promise<LencoStatus> {
  if (!lencoConfigured(env)) return { status: 'pending' };
  try {
    const res = await withCircuit('lenco-collection-status', () => fetch(
      `${lencoBase(env)}/collections/status/${encodeURIComponent(reference)}`,
      { headers: { accept: 'application/json', Authorization: `Bearer ${lencoApiKey(env)}` }, signal: AbortSignal.timeout(8000) },
    ));
    if (!res.ok) return { status: 'pending' };
    const data: any = await res.json().catch(() => null);
    const row = data?.data ?? {};
    return {
      status: mapStatus(row.status),
      reason: typeof row.reasonForFailure === 'string' && row.reasonForFailure.trim()
        ? row.reasonForFailure.trim().slice(0, 200)
        : undefined,
      fee: Number.isFinite(Number(row.fee)) ? Number(row.fee) : undefined,
    };
  } catch { return { status: 'pending' }; }
}

export async function lencoTransferStatus(env: Env, reference: string): Promise<LencoStatus> {
  if (!lencoConfigured(env)) return { status: 'pending' };
  try {
    const res = await withCircuit('lenco-transfer-status', () => fetch(
      `${lencoBase(env)}/transfers/status/${encodeURIComponent(reference)}`,
      { headers: { accept: 'application/json', Authorization: `Bearer ${lencoApiKey(env)}` }, signal: AbortSignal.timeout(8000) },
    ));
    if (!res.ok) return { status: 'pending' };
    const data: any = await res.json().catch(() => null);
    const row = data?.data ?? {};
    return {
      status: mapStatus(row.status),
      reason: typeof row.reasonForFailure === 'string' && row.reasonForFailure.trim()
        ? row.reasonForFailure.trim().slice(0, 200)
        : undefined,
      fee: Number.isFinite(Number(row.fee)) ? Number(row.fee) : undefined,
    };
  } catch { return { status: 'pending' }; }
}

/** Lenco signs the RAW request body with HMAC-SHA512 using SHA256(API token). */
export async function verifyLencoWebhook(env: Env, rawBody: string, signature: string): Promise<boolean> {
  const key = String(env.LENCO_WEBHOOK_KEY ?? '').trim();
  const token = lencoApiKey(env);
  if ((!key && !token) || !signature) return false;
  const enc = new TextEncoder();
  let webhookKey = key;
  if (!webhookKey) {
    const digest = await crypto.subtle.digest('SHA-256', enc.encode(token));
    webhookKey = Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, '0')).join('');
  }
  const cryptoKey = await crypto.subtle.importKey(
    'raw', enc.encode(webhookKey), { name: 'HMAC', hash: 'SHA-512' }, false, ['sign'],
  );
  const expected = Array.from(new Uint8Array(await crypto.subtle.sign('HMAC', cryptoKey, enc.encode(rawBody))))
    .map((b) => b.toString(16).padStart(2, '0')).join('');
  return expected.length === signature.length
    && expected.split('').every((ch, i) => ch === signature[i]);
}

export async function lencoAccounts(env: Env): Promise<any> {
  const res = await fetch(`${lencoBase(env)}/accounts`, {
    headers: { accept: 'application/json', Authorization: `Bearer ${lencoApiKey(env)}` },
    signal: AbortSignal.timeout(8000),
  });
  const raw = await res.text().catch(() => '');
  if (!res.ok) throw new Error(detailOf(raw, res.status));
  return JSON.parse(raw);
}

export async function lencoBalance(env: Env): Promise<any> {
  const id = lencoAccountId(env);
  const res = await fetch(`${lencoBase(env)}/accounts/${encodeURIComponent(id)}/balance`, {
    headers: { accept: 'application/json', Authorization: `Bearer ${lencoApiKey(env)}` },
    signal: AbortSignal.timeout(8000),
  });
  const raw = await res.text().catch(() => '');
  if (!res.ok) throw new Error(detailOf(raw, res.status));
  return JSON.parse(raw);
}
