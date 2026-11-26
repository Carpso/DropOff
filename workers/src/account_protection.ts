// Owner account protection (owner directive 2026-11-26: "protect it as the
// app owner").
//
// The owner signs in with godfreymoseskalambo@gmail.com / 260968551110, and
// that email account is the root of the admin console. Before this policy a
// single emailed reset link — anyone who could read that mailbox, or any link
// left in an old inbox — was enough to take over the whole app. The rules
// below make an emailed link insufficient for owner/staff accounts:
//
//   • a protected account's reset link is delivered to the account PHONE (SMS),
//     never to the mailbox;
//   • a token minted for the email channel can never reset a protected account,
//     even if it is still valid in `email_tokens` (defence in depth for links
//     sent before this change);
//   • only the superadmin key may mint a protected-account link (`admin`).
//
// Pure functions so the policy is unit-tested instead of trusted.

/** Roles that can move money, mint roles or read every customer's data. */
export const PROTECTED_ROLES: ReadonlySet<string> = new Set([
  'admin', 'superadmin', 'owner', 'cfo', 'ops',
]);

export interface ProtectedEnv {
  OWNER_PHONE?: string;
  OWNER_EMAIL?: string;
}

export interface AccountIdentity {
  email?: string | null;
  phone?: string | null;
  role?: string | null;
}

/** Channel a reset token was delivered through. */
export type ResetChannel = 'email' | 'sms' | 'admin';

/** True when the account must never be resettable from an emailed link. */
export function isProtectedAccount(acct: AccountIdentity, env: ProtectedEnv): boolean {
  const email = String(acct.email ?? '').trim().toLowerCase();
  const phone = String(acct.phone ?? '').replace(/\D/g, '');
  const role = String(acct.role ?? '').trim().toLowerCase();
  const ownerMail = String(env.OWNER_EMAIL ?? '').trim().toLowerCase();
  const ownerTel = String(env.OWNER_PHONE ?? '').replace(/\D/g, '');
  if (ownerMail && email && email === ownerMail) return true;
  if (ownerTel && phone && phone === ownerTel) return true;
  return PROTECTED_ROLES.has(role);
}

/** Where a reset link for this account may be delivered. */
export function resetChannelFor(protectedAccount: boolean): ResetChannel {
  return protectedAccount ? 'sms' : 'email';
}

/**
 * Whether a stored token may be redeemed. Protected accounts accept only
 * `sms` (sent to the phone) or `admin` (minted by the superadmin key) tokens.
 * Anything else — including every link sent before the policy existed — is
 * refused.
 */
export function canRedeemResetToken(issuedVia: string | null | undefined, protectedAccount: boolean): boolean {
  if (!protectedAccount) return true;
  const via = String(issuedVia ?? 'email').trim().toLowerCase();
  return via === 'sms' || via === 'admin';
}

/** Copy for the rider-facing refusal (plain language, no internals). */
export const PROTECTED_RESET_DETAIL =
  'For your safety, owner and admin passwords are reset with a link sent to the account phone, never by email.';
