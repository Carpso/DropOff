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
  if (!res.ok) {
    const txt = await res.text().catch(() => '');
    console.error(JSON.stringify({ where: 'fcm_token_exchange', kind: 'exchange_failed', status: res.status, body: txt.slice(0, 300) }));
    return null;
  }
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

/** Android notification channel — the app pre-creates these channels with
 *  sound enabled (push_service.dart). Routing the FCM message into the
 *  matching channel is what makes an incoming ORDER ping even when the app is
 *  closed: without a channel_id, FCM dumps background notifications into a
 *  silent "Miscellaneous" channel. */
function androidChannelId(data: Record<string, string> | undefined): string {
  const kind = `${data?.['kind'] ?? ''}`.toLowerCase();
  if (kind.startsWith('chat') || kind.includes('support')) return 'dropoff_chat';
  if (kind.includes('payment') || kind.includes('deposit') || kind.includes('plan') || kind.includes('subscription')) return 'dropoff_payments';
  if (kind.includes('marketing') || kind.includes('promo')) return 'dropoff_marketing';
  if (kind.includes('security') || kind.includes('alert') || kind.includes('fraud')) return 'dropoff_alerts';
  return 'dropoff_jobs';
}

/** Sends a notification to every registered device for a phone. Best-effort. */
export async function sendToPhone(env: Env, phone: string | null | undefined, payload: PushPayload): Promise<void> {
  try {
    if (!phone || !env.FIREBASE_SERVICE_ACCOUNT) {
      if (phone && !env.FIREBASE_SERVICE_ACCOUNT) {
        console.error(JSON.stringify({ where: 'fcm_send', kind: 'no_service_account', phone }));
      }
      return;
    }
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
            android: { priority: 'high', notification: { channel_id: androidChannelId(payload.data) } },
            apns: { headers: { 'apns-priority': '10' }, payload: { aps: { sound: 'default' } } },
          },
        }),
      });
      if (res.status === 404 || res.status === 410) {
        // Token unregistered/stale — drop it so the table never grows unbounded.
        await env.DB.prepare('DELETE FROM push_tokens WHERE token = ?1').bind(token).run();
        console.log(JSON.stringify({ where: 'fcm_send', kind: 'token_gone', phone, status: res.status }));
      } else if (!res.ok) {
        console.error(JSON.stringify({ where: 'fcm_send', kind: 'send_failed', phone, status: res.status, body: (await res.text().catch(() => '')).slice(0, 160) }));
      } else {
        console.log(JSON.stringify({ where: 'fcm_send', kind: 'send_ok', phone }));
      }
    }
  } catch {
    // push is strictly best-effort; never fail the caller
  }
}
