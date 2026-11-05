// Transactional email via the Cloudflare Email Service Workers binding.
// Requires wrangler.toml `send_email` binding + the sender domain onboarded:
//   npx wrangler email sending enable <sender-domain>
// Falls back to an in-response dev link while AUTH_DEV_MODE=1 (no SEND path).

export interface MailArgs {
  to: string;
  subject: string;
  html: string;
  text: string;
}

export async function sendMail(env: any, m: MailArgs): Promise<{ sent: boolean; error?: string }> {
  const from = env.MAIL_FROM;
  if (!env.EMAIL) return { sent: false, error: 'email_binding_missing' };
  if (!from) return { sent: false, error: 'MAIL_FROM_missing' };
  try {
    await env.EMAIL.send({
      to: m.to,
      from: { email: from, name: 'DropOff' },
      subject: m.subject,
      html: m.html,
      text: m.text,
    });
    return { sent: true };
  } catch (e: any) {
    return { sent: false, error: e?.message ?? 'send_failed' };
  }
}

const WRAP = (body: string) => `
<div style="font-family:-apple-system,Segoe UI,Roboto,sans-serif;max-width:520px;margin:0 auto;padding:24px;color:#10312a">
  <p style="font-size:15px;font-weight:800;letter-spacing:1.2px;margin:0 0 18px">DROPOFF 🇿🇲</p>
  <div style="border:1px solid #d8e2de;border-radius:14px;padding:22px">
    ${body}
  </div>
  <p style="font-size:11px;color:#7a8a85;margin-top:14px">Sent by DropOff — home or shop pickup to your chosen Zambian courier depot.</p>
</div>`;

export function verifyEmailHtml(link: string): string {
  return WRAP(`
    <h2 style="margin:0 0 10px">Confirm your email</h2>
    <p style="line-height:1.6">Tap the button to confirm this address for your DropOff account. The link expires in 24 hours.</p>
    <p style="margin:18px 0"><a href="${link}" style="background:#17855f;color:#fff;padding:12px 22px;border-radius:10px;text-decoration:none;font-weight:700">Verify email</a></p>
    <p style="font-size:12px;color:#7a8a85;word-break:break-all">Or paste this link: ${link}</p>`);
}

export function resetEmailHtml(link: string): string {
  return WRAP(`
    <h2 style="margin:0 0 10px">Reset your password</h2>
    <p style="line-height:1.6">Someone (hopefully you) asked to reset the DropOff password for this email. The link expires in 1 hour and can be used once.</p>
    <p style="margin:18px 0"><a href="${link}" style="background:#17855f;color:#fff;padding:12px 22px;border-radius:10px;text-decoration:none;font-weight:700">Choose a new password</a></p>
    <p style="font-size:12px;color:#7a8a85">If this wasn't you, ignore this email — your password stays unchanged.</p>`);
}
