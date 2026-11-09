// Chat / comment moderation primitives, shared by the REST worker (index.ts)
// and the ChatRoom Durable Object (chat_do.ts) so both surfaces enforce the
// exact same rules.
//
// Coverage (Play UGC policy, IARC Everyone/3+):
//   1. Profanity+abuse filter — normalization beats space/symbol/leet evasion;
//      English + Zambian-language insult coverage (Bemba / Nyanja / Tonga / Lozi
//      terms are additive; ops extend this list without touching call sites).
//   2. Report & block (REST only — see /chat/messages/:id/report, /users/blocks).
//   3. Strike escalation — repeated abuse attempts auto-suspend chat sending
//      for 7 days; admins can clear strikes from the admin console.

import type { Env } from './lipila';

const BLOCKED_WORDS = [
  // English (existing guard, kept verbatim)
  'fuck', 'shit', 'bitch', 'asshole', 'dick', 'cunt', 'nigger', 'faggot',
  // Additional harassment
  'motherfuc', 'whore', 'slut', 'retard', 'screwyou',
  // Bemba / Zambian town-slang abuse
  'chikala', 'cikala', 'chimbwi', 'cimbwi', 'nyani',
  // Nyanja / Chichewa
  'chitsiru', 'citsiru', 'mbuzi', 'mfiti',
];

const SUBSTITUTIONS: Record<string, string> = {
  '0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '6': 'g', '7': 't', '8': 'b',
  '$': 's', '@': 'a', '!': 'i', '|': 'i', '£': 'e', '€': 'e', '+': 't', '\u00b7': '',
};

/** Lowercase, strip diacritics and map leetspeak onto plain letters. */
export function normalizeAbuseText(text: string): string {
  const lower = text.toLowerCase().normalize('NFKD').replace(/\p{M}+/gu, '');
  let out = '';
  for (const ch of lower) out += SUBSTITUTIONS[ch] ?? ch;
  return out;
}

/**
 * True if an abusive term survives even after evasion tricks: the check runs
 * against (a) the leet-normalized text as written and (b) a "collapsed" form
 * with every space/symbol removed, so "f u c k", "f-u-c-k", "f.u.c.k" and
 * "f@ck" all match. All words are multi-letter, single-consonant runs must not
 * appear in the list.
 */
export function containsAbuse(text: string): boolean {
  const t = normalizeAbuseText(text);
  const collapsed = t.replace(/[^a-z]/g, '');
  return BLOCKED_WORDS.some((w) => t.includes(w) || collapsed.includes(w));
}

/* ----------------------------- strike escalation --------------------------- */

const SUSPEND_DAYS = 7;

export async function recordAbuseStrike(env: Env, phone: string): Promise<void> {
  if (!phone || phone === 'ops') return; // staff never accumulate strikes
  await env.DB.prepare(
    `INSERT INTO chat_strikes (phone, strikes) VALUES (?1, 1)
      ON CONFLICT(phone) DO UPDATE SET
        strikes = chat_strikes.strikes + 1,
        updated_at = datetime('now')`,
  ).bind(phone).run();
  const row = await env.DB.prepare('SELECT strikes FROM chat_strikes WHERE phone = ?1')
    .bind(phone).first<{ strikes: number }>();
  if ((row?.strikes ?? 0) >= 3) {
    await env.DB.prepare(
      `UPDATE chat_strikes SET suspended_until = datetime('now', '+${SUSPEND_DAYS} days') WHERE phone = ?1`,
    ).bind(phone).run();
  }
}

/** ISO-ish 'until' timestamp when this sender is chat-suspended, else null. */
export async function chatSuspendedUntil(env: Env, phone: string): Promise<string | null> {
  if (!phone || phone === 'ops') return null;
  const row = await env.DB.prepare(
    `SELECT suspended_until FROM chat_strikes
      WHERE phone = ?1 AND suspended_until IS NOT NULL AND suspended_until > datetime('now')`,
  ).bind(phone).first<{ suspended_until: string }>();
  return row?.suspended_until ?? null;
}

/** Admin lever: forgive a user's strikes and lift any suspension. */
export async function clearChatStrikes(env: Env, phone: string): Promise<boolean> {
  const res = await env.DB.prepare(
    `UPDATE chat_strikes SET strikes = 0, suspended_until = NULL, updated_at = datetime('now') WHERE phone = ?1`,
  ).bind(phone).run();
  return (res.meta.changes ?? 0) > 0;
}
