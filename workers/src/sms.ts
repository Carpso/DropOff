// OTP / notification SMS via Africa's Talking — the Carpso account
// (AT_USERNAME=ChurchOnApp, AT_FROM=Carpso), same wiring as Kingdom Sponsor
// (chisomo/src/sms.ts) and Grand Elephants.
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

/** Africa's Talking sends concatenated multi-part SMS, so long messages are
 *  fine — this is a sanity ceiling (4 segments ≈ 616 GSM-7 chars), never a
 *  silent trim of meaningful copy. */
export function clampSms(message: string, max = 600): string {
  if (message.length <= max) return message;
  return `${message.slice(0, max - 3).trimEnd()}...`;
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
  const from = String(env.AT_FROM ?? env.SMS_SENDER_ID ?? 'Carpso');
  const production = String(env.ENV ?? '').toLowerCase() === 'production';

  // Dev / sandbox: never call AT (no billing), just surface the text so the
  // route can return a dev_code when AUTH_DEV_MODE=1.
  if (!production) {
    console.log(`[SMS ${safePhone(phoneE164)}] ${clampSms(message)}`);
    return { sent: false, error: 'sms_dev_only' };
  }
  if (!user || !key) return { sent: false, error: 'sms_not_configured' };

  const text = clampSms(message);
  try {
    // AT requires lowercase form fields (username/to/message/from).
    const form = new URLSearchParams({
      username: user,
      to: safePhone(phoneE164),
      message: text,
      ...(from ? { from } : {}),
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
    if (res.ok) return { sent: true };
    const body = await res.text().catch(() => '');
    return { sent: false, error: `at_status_${res.status}${body ? `:${body.slice(0, 120)}` : ''}` };
  } catch (e: any) {
    return { sent: false, error: e?.message ?? 'sms_failed' };
  }
}
