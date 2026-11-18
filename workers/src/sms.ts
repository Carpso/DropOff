// OTP / notification SMS via Africa's Talking — the ChurchOnApp app
// (AT_USERNAME=ChurchOnApp, AT_FROM=Carpso; funded 2026-11-18, wallet
// ZMW 49.92). Kingdom Sponsor shares this app's wallet but sends as
// KSPONSOR — each app its own sender ID. sendSms judges success
// per-recipient (AT returns HTTP 201 even when nothing was sent) and, if a
// configured sender is ever rejected (InvalidSenderId), retries without it
// so the default route still delivers — payment/OTP SMS must never die.
//
// Env:
//   secrets: AT_API_KEY (npx wrangler secret put AT_API_KEY)  [SMS_API_KEY still works]
//   vars:    AT_USERNAME, AT_FROM, ENV                        [SMS_USERNAME / SMS_SENDER_ID still work]
//
// ENV=production -> real AT call. Anything else -> logged only, never billed.

const AT_MESSAGES_URL = 'https://api.africastalking.com/version1/messaging';

/** AT wants E.164 with a leading +. DropOff stores 260XXXXXXXXX (no +). */
export function safePhone(phone: string): string {
  const digits = String(phone).replace(/\D/g, '');
  if (digits.startsWith('260')) return `+${digits}`;
  if (digits.startsWith('0')) return `+260${digits.slice(1)}`;
  return `+${digits}`;
}

/** Africa's Talking bills per 160-GSM-char segment (K0.24). Non-GSM characters
 *  (em dashes, curly quotes, checkmarks) silently flip the whole message to
 *  UCS-2, where a segment is only 70 characters — tripling the cost of an
 *  unchanged-looking text. Rewrite those to their GSM-7 equivalents so every
 *  DropOff SMS stays on the cheap alphabet. */
const GSM_MAP: Record<string, string> = {
  '—': '-', '–': '-', '‑': '-', '‒': '-',
  '\u2018': "'", '\u2019': "'", '\u201A': "'", '\u2032': "'",
  '\u201C': '"', '\u201D': '"', '\u201E': '"',
  '\u2026': '...',
  '✓': 'OK', '✔': 'OK', '✗': 'X', '✘': 'X', '•': '*', '·': '.', '→': '->',
  '\u00A0': ' ', '\u202F': ' ', '\u2009': ' ',
};

export function gsmSafe(message: string): string {
  let out = '';
  for (const ch of message) out += GSM_MAP[ch] ?? ch;
  // Anything still outside GSM-7 gets replaced, not dropped — a stray emoji
  // must never re-price a payment instruction into a different alphabet.
  // eslint-disable-next-line no-control-regex
  return out.replace(/[^\x00-\x7F]/g, '?');
}

/** ONE SEGMENT = K0.24 (owner directive 2026-11-17). Every DropOff SMS is
 *  authored to fit 160 GSM-7 characters; this is the hard billing ceiling so
 *  an unexpected template can never silently double or triple the bill. */
export function clampSms(message: string, max = 160): string {
  const safe = gsmSafe(message);
  if (safe.length <= max) return safe;
  console.warn(JSON.stringify({ where: 'sms_clamp', length: safe.length, head: safe.slice(0, 60) }));
  return `${safe.slice(0, max - 3).trimEnd()}...`;
}

export interface SmsResult {
  sent: boolean;
  error?: string;
}

export async function sendSms(
  env: {
    ENV?: string;
    AT_USERNAME?: string;
    AT_API_KEY?: string;
    AT_FROM?: string;
    SMS_USERNAME?: string;
    SMS_API_KEY?: string;
    SMS_SENDER_ID?: string;
    DB?: any; // D1Database — optional; enables STOP opt-out enforcement
  },
  phoneE164: string,
  message: string,
  opts?: { transactional?: boolean },
): Promise<SmsResult> {
  // Africa's Talking STOP handling: marketing/broadcast/nurture SMS is blocked
  // for any phone that sent STOP (auth_users.sms_opt_out = 1). OTP, payment and
  // code-bearing SMS (transactional) is never blocked — opting out of marketing
  // can never lock you out of your own money or parcel.
  if (!opts?.transactional && env?.DB) {
    try {
      const row: any = await env.DB.prepare(
        'SELECT sms_opt_out FROM auth_users WHERE phone = ?1',
      ).bind(String(phoneE164).replace(/\D/g, '')).first();
      if (Number(row?.sms_opt_out ?? 0) === 1) {
        return { sent: false, error: 'sms_opted_out' };
      }
    } catch { /* best-effort gate — delivery wins, matching payments */ }
  }
  const user = String(env.AT_USERNAME ?? env.SMS_USERNAME ?? '');
  const key = String(env.AT_API_KEY ?? env.SMS_API_KEY ?? '');
  // Sender ID is OPTIONAL now (2026-11-18): the funded kingdom_sponsor app has
  // NO approved alphanumeric sender, but its default route delivers fine
  // (K0.24). A hardcoded fallback forced "Carpso" onto every call and got
  // InvalidSenderId — the sender is only used when explicitly configured.
  const from = String(env.AT_FROM ?? env.SMS_SENDER_ID ?? '').trim();
  const production = String(env.ENV ?? '').toLowerCase() === 'production';

  // Dev / sandbox: never call AT (no billing), just surface the text so the
  // route can return a dev_code when AUTH_DEV_MODE=1.
  if (!production) {
    console.log(`[SMS ${safePhone(phoneE164)}] ${clampSms(message)}`);
    return { sent: false, error: 'sms_dev_only' };
  }
  if (!user || !key) return { sent: false, error: 'sms_not_configured' };

  const text = clampSms(message);
  // AT returns HTTP 201 even when ZERO recipients were accepted (e.g.
  // InvalidSenderId) — so success is judged from the per-recipient statuses,
  // never from the HTTP status alone.
  const post = async (useFrom: boolean): Promise<SmsResult> => {
    const form = new URLSearchParams({
      username: user,
      to: safePhone(phoneE164),
      message: text,
      ...(useFrom && from ? { from } : {}),
    });
    const res = await fetch(AT_MESSAGES_URL, {
      method: 'POST',
      headers: {
        Apikey: key,
        'Content-Type': 'application/x-www-form-urlencoded',
        Accept: 'application/json',
      },
      body: form.toString(),
    });
    const body = await res.text().catch(() => '');
    if (!res.ok) {
      return { sent: false, error: `at_status_${res.status}${body ? `:${body.slice(0, 120)}` : ''}` };
    }
    let recipients: any[] = [];
    try {
      recipients = JSON.parse(body)?.SMSMessageData?.Recipients ?? [];
    } catch { /* non-JSON body — treat as unconfirmed */ }
    if (!recipients.length) {
      const reason = String(body.match(/"Message":"([^"]+)"/)?.[1] ?? 'no_recipients');
      return { sent: false, error: `at_reject:${reason.slice(0, 80)}` };
    }
    const ok = recipients.some(
      (r) => Number(r?.statusCode) === 100 || String(r?.status ?? '').toLowerCase() === 'success',
    );
    if (ok) return { sent: true };
    return { sent: false, error: `at_reject:${String(recipients[0]?.status ?? 'unknown').slice(0, 80)}` };
  };
  try {
    // Preferred: the configured sender ID. On InvalidSenderId (sender not
    // approved on this AT app) fall back to the default route — delivery
    // beats branding, and the OTP/payment SMS must land either way.
    if (from) {
      const withSender = await post(true);
      if (withSender.sent) return withSender;
      if (!/InvalidSenderId/i.test(withSender.error ?? '')) return withSender;
    }
    return await post(false);
  } catch (e: any) {
    return { sent: false, error: e?.message ?? 'sms_failed' };
  }
}
