// Unified server-side payment gateway selection. Lipila stays primary; Lenco
// is an explicit alternative and an automatic fallback only after Lipila
// definitively rejects authentication (401/403). Timeouts/5xx are ambiguous,
// so they NEVER trigger a second provider and can never double-charge.
import {
  lipilaCollect, lipilaDisburse, lipilaStatusDetail, lipilaDisburseStatusDetail,
  lipilaApiKey, type Env,
} from './lipila';
import {
  lencoCollect, lencoTransfer, lencoCollectionStatus, lencoTransferStatus,
  lencoConfigured,
} from './lenco';

export type Gateway = 'lipila' | 'lenco';
export type GatewayPreference = Gateway | 'auto';

export interface GatewayInit {
  ok: boolean;
  gateway: Gateway;
  /** Our client reference — use this for status polling. */
  reference: string;
  /** Provider's own reference/identifier, for audit only. */
  providerReference?: string;
  raw?: string;
  status: number;
}

export interface GatewayStatus {
  status: 'pending' | 'success' | 'failed';
  reason?: string;
  fee?: number;
}

export function gatewayPreference(env: Env, requested?: unknown): GatewayPreference {
  const raw = String(requested ?? env.PAYMENT_GATEWAY ?? 'auto').toLowerCase();
  return raw === 'lenco' || raw === 'lipila' ? raw : 'auto';
}

export function gatewayConfigured(env: Env, gateway: Gateway): boolean {
  return gateway === 'lenco' ? lencoConfigured(env) : !!lipilaApiKey(env);
}

/** Definitive rejection only. A duplicate-reference 400, rate limit, timeout,
 *  circuit open or 5xx is not proof that no prompt/transfer exists. */
function shouldFallback(env: Env, init: GatewayInit): boolean {
  return !init.ok && init.gateway === 'lipila'
    && (init.status === 401 || init.status === 403)
    && lencoConfigured(env);
}

function fromLipila(init: Awaited<ReturnType<typeof lipilaCollect>>, reference: string): GatewayInit {
  return {
    ok: init.ok,
    gateway: 'lipila',
    reference,
    providerReference: init.lipilaReference,
    raw: init.raw,
    status: init.status,
  };
}

function fromLenco(init: Awaited<ReturnType<typeof lencoCollect>>, reference: string): GatewayInit {
  return {
    ok: init.ok,
    gateway: 'lenco',
    reference,
    providerReference: init.lencoReference,
    raw: init.raw,
    status: init.status,
  };
}

export async function collectWithGateway(
  env: Env,
  requested: GatewayPreference | undefined,
  phone: string,
  amount: number,
  reference: string,
  note: string,
  email?: string,
): Promise<GatewayInit> {
  const pref = gatewayPreference(env, requested);
  if (pref === 'lenco') return fromLenco(await lencoCollect(env, phone, amount, reference, note), reference);
  const lipila = fromLipila(await lipilaCollect(env, phone, amount, reference, note, email), reference);
  if (shouldFallback(env, lipila)) {
    console.warn(JSON.stringify({ where: 'gateway', event: 'lipila_auth_fallback', reference, status: lipila.status }));
    return fromLenco(await lencoCollect(env, phone, amount, reference, note), reference);
  }
  return lipila;
}

export async function transferWithGateway(
  env: Env,
  requested: GatewayPreference | undefined,
  phone: string,
  amount: number,
  reference: string,
  note: string,
): Promise<GatewayInit> {
  const pref = gatewayPreference(env, requested);
  if (pref === 'lenco') return fromLenco(await lencoTransfer(env, phone, amount, reference, note), reference);
  const lipila = fromLipila(await lipilaDisburse(env, phone, amount, reference, note), reference);
  if (shouldFallback(env, lipila)) {
    console.warn(JSON.stringify({ where: 'gateway', event: 'lipila_auth_fallback_transfer', reference, status: lipila.status }));
    return fromLenco(await lencoTransfer(env, phone, amount, reference, note), reference);
  }
  return lipila;
}

export async function collectionStatus(env: Env, gateway: Gateway, reference: string): Promise<GatewayStatus> {
  return gateway === 'lenco' ? lencoCollectionStatus(env, reference) : lipilaStatusDetail(env, reference);
}

export async function transferStatus(env: Env, gateway: Gateway, reference: string): Promise<GatewayStatus> {
  return gateway === 'lenco' ? lencoTransferStatus(env, reference) : lipilaDisburseStatusDetail(env, reference);
}
