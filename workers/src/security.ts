// DropOff security: intrusion detection, device fingerprinting, owner alerts.
//
// Env:
//   OWNER_PHONE  (260XXXXXXXXX) — who receives intruder / new-device alerts
//   OWNER_EMAIL  — email copy of owner alerts (falls back to SMS/push only)
//   MAIL_FROM    — already configured; used as from address

import type { Env } from './lipila';
import { sendSms } from './sms';
import { sendMail } from './mail';
import { sendToPhone } from './push';

/** Progressive lockout thresholds (failures within the trailing hour). */
const LOCKOUT_TIERS: { failures: number; minutes: number }[] = [
  { failures: 5, minutes: 60 },    // 5 fails -> locked 1 hour
  { failures: 10, minutes: 1440 }, // 10 fails -> locked 24 hours
];

export function clientIp(c: any): string {
  return c.req.header('CF-Connecting-IP') ?? c.req.header('X-Forwarded-For') ?? 'unknown';
}

export function deviceId(c: any): string {
  const h = c.req.header('X-Device-Id');
  return h && h.length >= 8 ? h : 'unknown';
}

export function userAgent(c: any): string {
  return c.req.header('User-Agent') ?? 'unknown';
}

/** Friendly device label the app can supply (device_info_plus: model + OS
 *  version). Empty when the client doesn't send it — callers fall back to
 *  parsing the User-Agent. */
export function deviceName(c: any): string {
  return String(c.req.header('X-Device-Name') ?? '').trim();
}

/** The REAL device (owner 2026-11-18): the fingerprint hash told the owner
 *  nothing ("Device: dev…"). Parse a human-readable name from the User-Agent
 *  — model + OS where AT/browsers expose it — and let an explicit
 *  X-Device-Name (the app will send one via device_info_plus) win over it. */
export function friendlyDevice(ua?: string | null): string {
  const s = String(ua ?? '').trim();
  if (!s || s === 'unknown') return 'unknown device';
  const dart = /Dart\/([\d.]+)/i.exec(s);
  if (dart) return `DropOff app (Dart ${dart[1]})`;
  const android = /Android[ /]?([\d.]+)?/i.exec(s);
  if (android) {
    const os = android[1] ? `Android ${android[1]}` : 'Android';
    // Chrome/WebView Android UAs carry the model between ';' and "Build/…".
    const model = /;\s*([^;()]+?)\s+Build\//.exec(s)?.[1]?.trim()
      ?? /;\s*([^;()]+?)\s*;\s*wv\)/.exec(s)?.[1]?.trim()
      ?? null;
    return model ? `${model} · ${os}` : os;
  }
  const ios = /iPhone OS ([\d_]+)/i.exec(s);
  if (ios) return `iPhone · iOS ${ios[1].replace(/_/g, '.')}`;
  if (/iPad/i.test(s)) return 'iPad';
  if (/Windows NT/i.test(s)) return 'Windows PC';
  if (/Mac OS X/i.test(s)) return 'Mac';
  if (/Linux/i.test(s)) return 'Linux';
  return s.slice(0, 60);
}

export function ownerPhone(env: Env): string | null {
  return env.OWNER_PHONE ?? null;
}

export function ownerEmail(env: Env): string | null {
  return env.OWNER_EMAIL ?? null;
}

/** Returns { lockedUntil: string | null } if the email is currently locked. */
export async function lockoutStatus(db: D1Database, email: string): Promise<{ lockedUntil: string | null }> {
  const row = await db.prepare(
    `SELECT locked_until FROM login_attempts
      WHERE email = ?1 AND locked_until IS NOT NULL AND locked_until > datetime('now')
      ORDER BY locked_until DESC LIMIT 1`,
  ).bind(email).first<{ locked_until: string }>();
  return { lockedUntil: row?.locked_until ?? null };
}

/** Record one attempt (success or failure). Applies progressive lockout on failure.
 *  Returns { ok, lockUntilMinutes } so the caller can render the right 401/429. */
export async function recordAttempt(
  db: D1Database, email: string, ok: boolean,
  ip: string, ua: string, deviceId: string,
): Promise<{ ok: boolean; lockUntilMinutes?: number }> {
  const now = datetimeNow();
  const hourAgo = datetimeShift('-1 hour');

  const failures = (await db.prepare(
    `SELECT COUNT(*) AS n FROM login_attempts
      WHERE email = ?1 AND success = 0 AND created_at > ?2`,
  ).bind(email, hourAgo).first<{ n: number }>())?.n ?? 0;

  let lockUntilMinutes: number | undefined;
  if (!ok) {
    const tier = LOCKOUT_TIERS.find((t) => failures + 1 >= t.failures);
    if (tier) {
      await db.prepare(
        `UPDATE login_attempts SET locked_until = datetime('now', ?2)
          WHERE email = ?1 AND (locked_until IS NULL OR locked_until < datetime('now', ?2))`,
      ).bind(email, `+${tier.minutes} minutes`).run();
      lockUntilMinutes = tier.minutes;
    }
  }

  await db.prepare(
    `INSERT INTO login_attempts (email, ip, user_agent, success, created_at)
      VALUES (?1, ?2, ?3, ?4, datetime('now'))`,
  ).bind(email, ip, ua, ok ? 1 : 0).run();

  return { ok, lockUntilMinutes };
}

/** On a successful login: fingerprint the device. Returns true if this is a brand-new device
 *  for this phone (caller should then raise a new_device alert). */
export async function noteDevice(
  db: D1Database, phone: string, devId: string, ip: string, ua?: string | null,
): Promise<{ isNew: boolean }> {
  const existing = await db.prepare(
    'SELECT id FROM device_sessions WHERE phone = ?1 AND device_id = ?2',
  ).bind(phone, devId).first<{ id: number }>();
  if (existing) {
    await db.prepare(
      'UPDATE device_sessions SET last_seen = datetime("now"), ip = COALESCE(?2, ip), ua = COALESCE(?3, ua) WHERE id = ?1',
    ).bind(existing.id, ip, ua ?? null).run();
    return { isNew: false };
  }
  await db.prepare(
    'INSERT INTO device_sessions (phone, device_id, ip, ua, first_seen, last_seen, trusted) VALUES (?1, ?2, ?3, ?4, datetime("now"), datetime("now"), 1)',
  ).bind(phone, devId, ip, ua ?? null).run();
  return { isNew: true };
}

export async function raiseAlert(
  db: D1Database, phone: string, type: string, severity: string, detail: string,
): Promise<number | null> {
  const res = await db.prepare(
    `INSERT INTO security_alerts (phone, type, severity, detail)
      VALUES (?1, ?2, ?3, ?4)`,
  ).bind(phone, type, severity, detail).run();
  return res.meta.last_row_id as number | null;
}

export async function acknowledgeAlert(db: D1Database, id: number): Promise<boolean> {
  const res = await db.prepare(
    `UPDATE security_alerts SET acknowledged = 1 WHERE id = ?1 AND acknowledged = 0`,
  ).bind(id).run();
  return (res.meta.changes ?? 0) > 0;
}

/** Notify the owner of an intrusion / new-device event. Channel policy
 *  (owner directive 2026-11-18): security alerts are EMAIL-first — full
 *  forensics, no per-SMS cost — plus an app push. SMS is reserved for
 *  HIGH-severity intrusions only (brute-force lockouts and worse). The
 *  device line carries the REAL device (friendly name), the fingerprint id
 *  is demoted to a short correlation tag. */
export async function alertOwner(env: Env, phone: string, type: string, severity: string, detail: string,
  extra?: { ip?: string; device?: string; deviceName?: string; userAgent?: string; email?: string }): Promise<void> {
  const op = ownerPhone(env);
  const oe = ownerEmail(env);
  const subject = `DropOff security alert — ${type}`;

  const suggestion = type === 'brute_force'
    ? 'Suggested response: no action if you recognise the device; otherwise the account is already locked and will stay locked for the window shown. Change the password in-app to force-sign-out every session.'
    : type === 'new_device'
      ? 'Suggested response: if this was you, nothing to do. If you do not recognise it, change the password in-app immediately — every other session is revoked automatically.'
      : 'Suggested response: if this was not you, change the password in-app immediately and review active devices.';

  const ua = String(extra?.userAgent ?? '').trim();
  const deviceName = String(extra?.deviceName ?? '').trim() || friendlyDevice(ua);
  const deviceTag = extra?.device && extra.device !== 'unknown' ? ` (id …${extra.device.slice(-6)})` : '';
  const deviceLine = `${deviceName}${deviceTag}`;

  const alertLines = [
    `DropOff SECURITY ALERT (${severity.toUpperCase()})`,
    `Event: ${type}`,
    `Account: ${extra?.email ?? phone}`,
    `From IP: ${extra?.ip ?? 'unknown'}`,
    `Device: ${deviceLine}`,
    `App: ${ua.slice(0, 80) || 'unknown'}`,
    `When: ${new Date().toISOString()} (UTC)`,
    detail,
    suggestion,
  ];
  const smsText = alertLines.join('\n');
  const body = `${smsText}\nIf this wasn't you, change your password and revoke sessions immediately.`;

  const smsWorthy = severity === 'high' || severity === 'critical';
  await Promise.allSettled([
    smsWorthy && op ? sendSms(env, op, smsText) : Promise.resolve({ sent: false }),
    oe ? sendMail(env, { to: oe, subject, html: `<pre>${body.replace(/\n/g, '<br>')}</pre>`, text: body }) : Promise.resolve({ sent: false }),
    sendToPhone(env, op, { title: `DropOff security: ${type}`, body: detail, data: { kind: 'security_alert', phone, severity } }),
  ]);
  if (op) {
    await raiseAlert(env.DB, op ?? phone, type, severity, detail).catch(() => {});
  }
}

function datetimeNow(): string { return new Date().toISOString().slice(0, 19).replace('T', ' '); }
function datetimeShift(shift: string): string { return new Date(Date.now() + shiftMs(shift)).toISOString().slice(0, 19).replace('T', ' '); }
function shiftMs(shift: string): number {
  const m = /^(-?)(\d+)(minute|hour|day)s?$/.exec(shift);
  if (!m) return 0;
  const mult: Record<string, number> = { minute: 60_000, hour: 3_600_000, day: 86_400_000 };
  const unit = m[3];
  return (m[1] === '-' ? -1 : 1) * Number(m[2]) * (mult[unit] ?? 60_000);
}
