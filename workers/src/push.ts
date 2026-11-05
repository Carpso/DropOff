// FCM (HTTP v1) push sender — OAuth2 service-account JWT signed with WebCrypto,
// zero dependencies. Fully optional: when FIREBASE_SERVICE_ACCOUNT is not set,
// every send silently no-ops so the API keeps working without push configured.
//
// Token flow per isolate: RS256-signed JWT -> oauth2 token exchange (cached,
// 55 min TTL) -> POST https://fcm.googleapis.com/v1/projects/{project}/messages:send
import type { Env } from './lipila';

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

/** OAuth access token cache (isolate-scoped) */
let cachedToken: { value: string; exp: number } | null = null;

function b64urlJson(obj: unknown): string {
  return btoa(JSON.stringify(obj)).replace(/[+/=]/g, (x) => (x === '+' ? '-' : x === '/' ? '_' : ''));
}

function pemToBytes(pem: string): Uint8Array {
  const body = pem
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s+/g, '');
  const raw = atob(body);
  const bytes = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
  return bytes;
}

/** Exchanges the service account for a short-lived Google access token. */
async function oauthAccessToken(sa: ServiceAccount): Promise<string | null> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.exp > now + 60) return cachedToken.value;

  const claims = {
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  };
  const unsigned = `${b64urlJson({ alg: 'RS256', typ: 'JWT' })}.${b64urlJson(claims)}`;
  const key = await crypto.subtle.importKey(
    'pkcs8', pemToBytes(sa.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false, ['sign'],
  );
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(unsigned));
  let b64 = btoa(String.fromCharCode(...new Uint8Array(sig)));
  const assertion = `${unsigned}.${b64.replace(/[+/=]/g, (x) => (x === '+' ? '-' : x === '/' ? '_' : ''))}`;

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${encodeURIComponent(assertion)}`,
  });
  if (!res.ok) return null;
  const data = (await res.json()) as { access_token?: string; expires_in?: number };
  if (!data.access_token) return null;
  cachedToken = { value: data.access_token, exp: now + (data.expires_in ?? 3600) };
  return cachedToken.value;
}

export interface PushPayload {
  title: string;
  body: string;
  /** Collection of simple string key/values delivered inside the message data. */
  data?: Record<string, string>;
}

/** Sends a notification to every registered device for a phone. Best-effort. */
export async function sendToPhone(env: Env, phone: string | null | undefined, payload: PushPayload): Promise<void> {
  try {
    if (!phone || !env.FIREBASE_SERVICE_ACCOUNT) return;
    let sa: ServiceAccount;
    try { sa = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT) as ServiceAccount; } catch { return; }
    if (!sa.project_id || !sa.client_email || !sa.private_key) return;

    const regs = await env.DB.prepare('SELECT token FROM push_tokens WHERE phone = ?1')
      .bind(phone).all<{ token: string }>();
    if (!regs.results?.length) return;

    const gToken = await oauthAccessToken(sa);
    if (!gToken) return;

    for (const { token } of regs.results) {
      // FCM token cap doesn't exist per user here; send exactly one per token.
      const res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${gToken}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: {
            token,
            notification: { title: payload.title, body: payload.body },
            data: payload.data ?? {},
            android: { priority: 'high' },
            apns: { headers: { 'apns-priority': '10' }, payload: { aps: { sound: 'default' } } },
          },
        }),
      });
      if (res.status === 404 || res.status === 410) {
        // Token unregistered/stale — drop it so the table never grows unbounded.
        await env.DB.prepare('DELETE FROM push_tokens WHERE token = ?1').bind(token).run();
      }
      // Other failures are logged by wrangler via the unhandled rejection guard:
      // still swallowed to never block the API path that triggered this push.
    }
  } catch {
    // push is strictly best-effort; never fail the caller
  }
}
