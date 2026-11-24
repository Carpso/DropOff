import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest';
import { collectWithGateway, transferWithGateway } from '../src/gateway';
import type { Env } from '../src/lipila';

const baseEnv = {
  LIPILA_ENV: 'production',
  LIPILA_BASE_URL: 'https://blz.lipila.io',
  LIPILA_API_KEY: 'lipila-key',
  LENCO_ENV: 'production',
  LENCO_API_KEY: 'lenco-key',
  LENCO_ACCOUNT_ID: '340916da-db43-40de-9426-49fa8e0e51e2',
  PAYMENT_GATEWAY: 'auto',
} as unknown as Env;

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

describe('payment gateway fallback', () => {
  const originalFetch = globalThis.fetch;

  beforeEach(() => {
    vi.restoreAllMocks();
  });

  afterEach(() => {
    globalThis.fetch = originalFetch;
  });

  it('falls back to Lenco only after definitive Lipila 401', async () => {
    const calls: string[] = [];
    globalThis.fetch = vi.fn(async (input: string | URL) => {
      const url = String(input);
      calls.push(url);
      if (url.includes('lipila.io')) return new Response('', { status: 401 });
      if (url.includes('lenco.co/access/v2/collections/mobile-money')) {
        return jsonResponse(200, { status: true, data: { reference: 'ref-1', lencoReference: 'LENCO-1' } });
      }
      throw new Error(`unexpected ${url}`);
    }) as any;

    const res = await collectWithGateway(baseEnv, 'auto', '260968551110', 1, 'ref-1', 'test');
    expect(res.ok).toBe(true);
    expect(res.gateway).toBe('lenco');
    expect(calls.some((u) => u.includes('lipila.io'))).toBe(true);
    expect(calls.some((u) => u.includes('lenco.co'))).toBe(true);
  });

  it('does not fall back on ambiguous Lipila timeout/5xx', async () => {
    const calls: string[] = [];
    globalThis.fetch = vi.fn(async (input: string | URL) => {
      const url = String(input);
      calls.push(url);
      if (url.includes('lipila.io')) return new Response('upstream error', { status: 503 });
      if (url.includes('lenco.co')) return jsonResponse(200, { status: true, data: { reference: 'ref-2' } });
      throw new Error(`unexpected ${url}`);
    }) as any;

    const res = await collectWithGateway(baseEnv, 'auto', '260968551110', 1, 'ref-2', 'test');
    expect(res.ok).toBe(false);
    expect(res.gateway).toBe('lipila');
    expect(calls.some((u) => u.includes('lenco.co'))).toBe(false);
  });

  it('uses Lenco directly when explicitly requested', async () => {
    const calls: string[] = [];
    globalThis.fetch = vi.fn(async (input: string | URL) => {
      const url = String(input);
      calls.push(url);
      if (url.includes('lenco.co/access/v2/transfers/mobile-money')) {
        return jsonResponse(200, { status: true, data: { reference: 'ref-3', lencoReference: 'LENCO-3' } });
      }
      throw new Error(`unexpected ${url}`);
    }) as any;

    const res = await transferWithGateway(baseEnv, 'lenco', '260976847775', 1, 'ref-3', 'test');
    expect(res.ok).toBe(true);
    expect(res.gateway).toBe('lenco');
    expect(calls.some((u) => u.includes('lipila.io'))).toBe(false);
  });
});
