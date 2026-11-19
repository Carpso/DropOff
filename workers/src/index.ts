// ─────────────────────────────────────────────────────────────────────
// DROPOFF — ownership stamp (do not remove)
// :Godfrey Moses Kalambo:Carpso Solutions:0968551110.
// © 2026 Godfrey Moses Kalambo · Carpso Solutions · Lusaka, Zambia.
// All rights reserved — unauthorised copying, resale or rebranding of
// this source code is prohibited.
// ─────────────────────────────────────────────────────────────────────
import { Hono } from 'hono';
import { cors } from 'hono/cors';
import {
  Env, Provider, lipilaCollect, lipilaDisburse, lipilaDisburseStatusDetail, lipilaStatus,
  lipilaStatusDetail, normalizeZmPhone, providerFromPhone,
} from './lipila';

import {
  generateEmailToken, generateOtp, hashOtp, hashPassword, isValidEmail, passwordNeedsRehash, signJwt,
  verifyJwtClaims, verifyPassword,
} from './auth';
import { collectionFees, computeJobTotals, MOMO_COLLECTION_FEE, platformFee, round2, PLATFORM_SWEEP_MIN_ZMW } from './fees';
import { PRIVACY_MD, PRIVACY_TITLE, TERMS_MD, TERMS_TITLE, mdToHtml } from './legal';
import { baseRiderFee, haversineKm as haversine, tierOverageFee, VEHICLE_CLASSES, VehicleClass, parcelCapFor } from './pricing';
import { resetEmailHtml, sendMail, verifyEmailHtml } from './mail';
import { sendSms } from './sms';
import { sendToPhone } from './push';
import {
  clientIp, deviceId, deviceName, userAgent, ownerPhone, ownerEmail,
  lockoutStatus, recordAttempt, noteDevice, alertOwner, raiseAlert, acknowledgeAlert,
} from './security';
import { ChatRoom } from './chat_do';
import {
  containsAbuse, recordAbuseStrike, chatSuspendedUntil, clearChatStrikes,
} from './moderation';

export { ChatRoom };

const app = new Hono<{ Bindings: Env; Variables: { phone?: string; email?: string; role?: 'customer' | 'partner' | 'ops' | 'admin' | 'rider'; riderId?: number; courierId?: number; reqId?: string } }>();

/* ------------------------- seller subscription packs ----------------------- */
// MODEL (post-reprice, Daily Dash removed):
//   — Plans are monthly: Silver K250 / 10 trips, Gold K500 / 25 trips,
//     Platinum K750 / 50 trips. Plus Weekly Sprint K399 / 20 trips / 7 days.
//   — Each trip (booking) consumes ONE plan slot no matter how many parcels
//     are inside it. Cycle = 30 days from activation (weekly = 7 days).
//   — Inside the cap the sender pays no per-trip rider fee (bundled).
//   — After the cap, the seller keeps the plan's discount off pay-as-you-go:
//     Silver 15%, Gold 25%, Platinum 35% off the normal rider fee.
//   — Truck runs cost more (big cargo: fridges, sofas). Multipliers apply to
//     the normal rider fee; trucks have a K100 minimum.
//   — Pay-as-you-go (no plan) is the default at a Yango-competitive rate —
//     see baseRiderFee() in pricing.ts.
//   — Daily Dash removed: not offered for new purchase; existing subscribers
//     run out their cycle.
// PlanTier includes 'rider_daily' (the on-demand daily pass).
// 'daily' is reserved for the long-removed Daily Dash product and is never
// surfaced even if a stale row lingers in D1.
type PlanTier = 'rider_daily' | 'weekly' | 'silver' | 'gold' | 'platinum';
interface PlanDef { fee_zmw: number; windows: string[]; parcels_per_day: number; parcels_per_month: number; rider_fee_zmw: number; overage_discount_pct: number; cycle_days: number; tag?: string | null }
// Editable live in D1 via /admin/tiers. These are the fallback/seed values.
// Editable live in D1 via /admin/tiers. These are the fallback/seed values.
// Every parcel counts as one plan slot (owner decision 2026-11-15) — a trip
// rides the plan only when ALL its parcels fit under the cap; otherwise the
// whole trip pays the tier overage discount off PAYG. Cycle = cycle_days
// from activation (daily = 1 day, weekly = 7, monthly packs = 30).
const PLANS: Record<PlanTier, PlanDef> = {
  // Daily Rider: on-demand, Yango-style casual use. Activates instantly on
  // payment, lasts 24h, 1 parcel per day, Day-day overage stays undiscounted.
  // (The old Daily Dash was removed per product decision; this is a different,
  // leaner product re-introduced at the owner's request.)
  rider_daily: { fee_zmw: 49, windows: ['now', '06:00', '10:00', '14:00'], parcels_per_day: 1, parcels_per_month: 0, rider_fee_zmw: 0, overage_discount_pct: 0, cycle_days: 1, tag: 'Daily Rider' },
  weekly:  { fee_zmw: 399, windows: ['06:00', '10:00', '14:00'], parcels_per_day: 0, parcels_per_month: 20, rider_fee_zmw: 0, overage_discount_pct: 0, cycle_days: 7, tag: 'Weekly Sprint' },
  silver: { fee_zmw: 250, windows: ['06:00', '10:00', '14:00'], parcels_per_day: 0, parcels_per_month: 10, rider_fee_zmw: 0, overage_discount_pct: 0, cycle_days: 30 },
  gold:   { fee_zmw: 500, windows: ['06:00', '10:00', '14:00'], parcels_per_day: 0, parcels_per_month: 25, rider_fee_zmw: 0, overage_discount_pct: 0, cycle_days: 30 },
  platinum: { fee_zmw: 750, windows: ['06:00', '10:00', '14:00'], parcels_per_day: 0, parcels_per_month: 50, rider_fee_zmw: 0, overage_discount_pct: 0, cycle_days: 30 },
};

/**
 * DB-backed catalogue (price, per-day cap, tag) — constants only as fallback.
 * A tier toggled OFF in the admin console is hidden from sales and listings
 * entirely. Existing subscribers mid-cycle keep their benefit: the booking
 * engine passes `forExistingSubscribers` so their pack still covers the
 * rider leg even while the pack is not for sale.
 */
async function plans(db: D1Database, opts?: { forExistingSubscribers?: boolean }): Promise<Record<PlanTier, PlanDef>> {
  const merged: Record<PlanTier, PlanDef> = {
    rider_daily: { ...PLANS.rider_daily, tag: null },
    weekly: { ...PLANS.weekly, tag: null },
    silver: { ...PLANS.silver, tag: null },
    gold: { ...PLANS.gold, tag: null },
    platinum: { ...PLANS.platinum, tag: null },
  };
  try {
  // Do NOT filter active = 1 here — read ALL known rows so a tier toggled OFF
  // can be excluded entirely (previously a deactivated pack still surfaced via
  // the constants fallback). Unknown tiers in D1 are ignored.
  const { results } = await db.prepare('SELECT tier, fee_zmw, parcels_per_day, parcels_per_month, rider_fee_zmw, overage_discount_pct, cycle_days, tag, active FROM tiers WHERE tier IN (\'rider_daily\',\'weekly\',\'silver\',\'gold\',\'platinum\')').all();
  for (const row of results as any[]) {
    const key = row.tier as PlanTier;
    // Daily Dash is removed - never surface it even if a stale row lingers in D1.
    if ((key as unknown) === 'daily') continue;
    if (!merged[key]) continue;
    if (Number(row.active) !== 1) {
      // Toggled OFF by the superadmin/admin — hide from sales completely, even
      // the fallback. Existing subscribers mid-cycle keep their coverage
      // (booking math passes forExistingSubscribers).
      if (!opts?.forExistingSubscribers) delete merged[key];
      continue;
    }
    merged[key] = {
      ...merged[key],
      // || fallback guards NULL/legacy columns (fresh DBs pre-0035).
      fee_zmw: Number(row.fee_zmw) || merged[key].fee_zmw,
      parcels_per_day: Number(row.parcels_per_day) || merged[key].parcels_per_day,
      parcels_per_month: Number(row.parcels_per_month) || merged[key].parcels_per_month,
      rider_fee_zmw: Number(row.rider_fee_zmw) || merged[key].rider_fee_zmw,
      overage_discount_pct: Number(row.overage_discount_pct) || merged[key].overage_discount_pct,
      cycle_days: Number(row.cycle_days) || merged[key].cycle_days,
      tag: row.tag ?? null,
    };
  }
  } catch { /* tiers table not migrated yet — constants rule */ }
  return merged;
}

/* --------------------------- platform feature flags -------------------------- */
// Flags live in the D1 `app_settings` table (migration 0061) so the owner can
// flip them from the admin console WITHOUT a deploy. Both default to OFF.
async function getSetting(db: D1Database, key: string): Promise<string | null> {
  try {
    const row = await db.prepare('SELECT value FROM app_settings WHERE key = ?1').bind(key).first<{ value: string | null }>();
    return row?.value ?? null;
  } catch {
    return null; // table absent — treat as off
  }
}
async function setSetting(db: D1Database, key: string, value: string, by: string): Promise<void> {
  await db.prepare(
    `INSERT INTO app_settings (key, value, updated_by) VALUES (?1, ?2, ?3)
     ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = datetime('now'), updated_by = excluded.updated_by`,
  ).bind(key, value, by).run();
}
const flagOn = (v: string | null) => v === '1' || v === 'true' || v === 'on';
const PLATFORM_TAKE = 0.10;           // of the rider fee, on pay-as-you-go
// Sweep riders are salaried, not per-parcel: K3,000/month INCLUSIVE of a
// weekly fuel allowance of K300/week (4 weeks = K1,200), so the base wage is
// K1,800 and the fuel is K1,200-dispensable weekly. Payment runs from plan
// revenue on two schedules (rider's `riders.pay_cycle`):
//   - weekly: every Sunday 16:00 CAT — fuel K300 + base week K450 (K1,800/4)
//   - monthly: on the 1st, 16:00 CAT — full K3,000 (cycle='monthly') or the
//     month's balance top-up for cycle='weekly' riders (K3,000 − weeks paid)
// Paying a period requires being on-pace with the sweep target for that
// period (see riderTargets / month pace line):
//   - on pace (>= target): full base + full fuel
//   - behind pace: base and fuel are pro-rated to the shortfall ratio;
//     two consecutive off-pace weeks trigger an ops performance review.
// Every payout row is generated automatically by cron and requires admin →
// superadmin confirmation before it disburses; each payment produces a
// downloadable proof-of-payment receipt (/admin/payroll/:id/proof).
// (peer benchmark: Bolt/Yango-style fleets pay per-trip; salaried + fuel
//  matches depot-to-depot contract courier economics — see docs/PLAY_BOOK.md)
const DRIVER_MONTHLY_PAY_ZMW = 3000;  // inclusive of the fuel allowance below
const DRIVER_FUEL_ALLOWANCE_WEEKLY_ZMW = 300;
const DRIVER_FUEL_MONTHLY_ZMW = DRIVER_FUEL_ALLOWANCE_WEEKLY_ZMW * 4; // 1200
const DRIVER_BASE_MONTHLY_ZMW = DRIVER_MONTHLY_PAY_ZMW - DRIVER_FUEL_MONTHLY_ZMW; // 1800
const DRIVER_WEEKLY_PAY_ZMW = DRIVER_MONTHLY_PAY_ZMW / 4; // K750/week — weekly-paid riders get this per week
const DRIVER_DAILY_TARGET = 30;       // parcels/day each rider is expected to sweep
// Over-target incentive paid at MONTH CLOSE (never per-parcel "rate" — riders
// stay salaried; bonuses sit on top of base pay; payroll pays them):
//   K200  flat when the month's target is met
//   K5    per parcel delivered beyond the target (max 135 counted, K675 cap)
//   K150  extra stretch bonus at >= 1.25x target
const DRIVER_COMPLETION_BONUS_ZMW = 200;
const DRIVER_OVER_TARGET_BONUS_ZMW = 5;
const DRIVER_OVER_TARGET_CAP = 135;            // 4.5x the daily target / month
const DRIVER_STRETCH_RATIO = 1.25;
const DRIVER_STRETCH_BONUS_ZMW = 150;
// LUSAKA-FIRST POLICY (owner directive 2026-11-18): same-city recipients get
// NO 4-digit PIN SMS — they track live in-app, optionally confirm receipt and
// rate. Door codes are minted ONLY for true intercity collections (e.g.
// Ndola), where a depot handover needs the stronger proof.
function isIntercity(fromCity: string | null | undefined, destCity: string | null | undefined): boolean {
  const a = `${fromCity ?? ''}`.trim().toLowerCase();
  const b = `${destCity ?? ''}`.trim().toLowerCase();
  return a.length > 0 && b.length > 0 && a !== b;
}
const PICKUP_WINDOWS = ['now', '06:00', '10:00', '14:00', 'tomorrow:06:00'];
// Business day = Central Africa Time (UTC+2). D1's 'localtime' is UTC, so every
// daily-cap / sweep query must use this explicit offset or the day rolls over
// at 02:00 CAT instead of midnight.
const CAT_OFFSET = '+2 hours';
const COD_FEE = 0.02;                 // LEGACY: COD is removed; retained only to read historical ledger rows
const WALLET_TOPUP_CAP_ZMW = 5000;

// Payment fees: the customer pays the DropOff leg + platform fee + Lipila legs.
// The courier's counter fare is paid at the depot and is NEVER collected by DropOff.

// Pay-as-you-go rider fee bands (raised to K45 base — always cheaper than the
// courier's own counter fare, which starts at K50 on most Platinum routes).
// Waiting / queue time: rider logs minutes; first 10 free, K2/min, K50 cap.
const WAIT_FREE_MINUTES = 10;
const WAIT_RATE_PER_MIN = 2;
const WAIT_CAP_ZMW = 50;

/* ------------------------------- pagination ------------------------------- */
// Keyset (cursor) pagination so list endpoints stay O(1) at 1M+ rows.
// Clients pass `?after=<last_id_seen>`; the server returns `next_after` + `has_more`.
const PAGE_DEFAULT = 50;
const PAGE_MAX = 200;
function pageLimit(raw: string | null | undefined): number {
  const n = Number(raw ?? '');
  return Number.isFinite(n) && n > 0 ? Math.min(Math.floor(n), PAGE_MAX) : PAGE_DEFAULT;
}
function cacheSeconds(seconds: number): Record<string, string> {
  return { 'Cache-Control': `public, max-age=${seconds}, stale-while-revalidate=${Math.floor(seconds / 2)}` };
}

function waitFeeFor(minutes: number): number {
  if (!Number.isFinite(minutes) || minutes <= 0) return 0;
  return Math.min(WAIT_CAP_ZMW, Math.round(Math.max(0, minutes - WAIT_FREE_MINUTES) * WAIT_RATE_PER_MIN));
}

/* --------------------- rider daily / monthly targets ---------------------- */
// A driver's day is 30 parcels; if a day is missed the shortfall must still be
// caught up inside the month, so the pace line is 30 x day-of-month and the
// hard month target is 30 x days-in-month. Counted from completion events
// (depot drop for first mile, delivered/ready for last mile), one job per day.
interface RiderTargetStats {
  today: number;
  daily_target: number;
  daily_remaining: number;
  daily_met: boolean;
  month: number;
  month_target: number;
  pace_target: number;
  month_remaining: number;
  behind_by: number;
  on_track: boolean;
  day_of_month: number;
  days_in_month: number;
  bonus: {
    extra_parcels: number;
    counted_extra: number;
    completion_bonus_zmw: number;
    over_target_bonus_zmw: number;
    stretch_bonus_zmw: number;
    total_bonus_zmw: number;
    target_met: boolean;
    programme?: string;
    programme_id?: number;
  };
}

function monthCalendar(): { dayOfMonth: number; daysInMonth: number } {
  const cat = new Date(Date.now() + 2 * 60 * 60 * 1000);
  return {
    dayOfMonth: cat.getUTCDate(),
    daysInMonth: new Date(Date.UTC(cat.getUTCFullYear(), cat.getUTCMonth() + 1, 0)).getUTCDate(),
  };
}

interface IncentiveProgramme {
  id: number;
  title: string;
  completion_bonus_zmw: number;
  per_extra_parcel_zmw: number;
  per_extra_cap: number;
  stretch_ratio: number;
  stretch_bonus_zmw: number;
  active: boolean;
}

// Load the active incentive programme (if any). Falls back to the constants
// when none is configured — promos are optional, never mandatory.
async function incentiveProgramme(env: Env): Promise<IncentiveProgramme> {
  try {
    const row = await env.DB.prepare(
      `SELECT id, title, completion_bonus_zmw, per_extra_parcel_zmw, per_extra_cap,
              stretch_ratio, stretch_bonus_zmw, active, starts_on, ends_on
         FROM incentive_programmes
        WHERE active = 1
          AND (starts_on IS NULL OR starts_on <= date('now', '+2 hours'))
          AND (ends_on IS NULL OR ends_on >= date('now', '+2 hours'))
        ORDER BY id DESC LIMIT 1`,
    ).first<any>();
    if (row) {
      return {
        id: Number(row.id),
        title: String(row.title ?? 'Rider incentive'),
        completion_bonus_zmw: Number(row.completion_bonus_zmw ?? DRIVER_COMPLETION_BONUS_ZMW),
        per_extra_parcel_zmw: Number(row.per_extra_parcel_zmw ?? DRIVER_OVER_TARGET_BONUS_ZMW),
        per_extra_cap: Number(row.per_extra_cap ?? DRIVER_OVER_TARGET_CAP),
        stretch_ratio: Number(row.stretch_ratio ?? DRIVER_STRETCH_RATIO),
        stretch_bonus_zmw: Number(row.stretch_bonus_zmw ?? DRIVER_STRETCH_BONUS_ZMW),
        active: true,
      };
    }
  } catch {
    // Table missing or read error — fall back to the built-in incentive.
  }
  return {
    id: 0,
    title: 'Built-in rider incentive',
    completion_bonus_zmw: DRIVER_COMPLETION_BONUS_ZMW,
    per_extra_parcel_zmw: DRIVER_OVER_TARGET_BONUS_ZMW,
    per_extra_cap: DRIVER_OVER_TARGET_CAP,
    stretch_ratio: DRIVER_STRETCH_RATIO,
    stretch_bonus_zmw: DRIVER_STRETCH_BONUS_ZMW,
    active: true,
  };
}

/** Over-target incentive for a month (paid through payroll, additive to salary). */
function riderBonusSplits(trips: number, monthTarget: number, prog?: IncentiveProgramme | null) {
  const p = prog ?? { completion_bonus_zmw: DRIVER_COMPLETION_BONUS_ZMW, per_extra_parcel_zmw: DRIVER_OVER_TARGET_BONUS_ZMW, per_extra_cap: DRIVER_OVER_TARGET_CAP, stretch_ratio: DRIVER_STRETCH_RATIO, stretch_bonus_zmw: DRIVER_STRETCH_BONUS_ZMW };
  const target = Math.max(0, monthTarget);
  const extra = Math.max(0, trips - target);
  const completion = trips >= target && target > 0 ? p.completion_bonus_zmw : 0;
  const capped = Math.min(extra, p.per_extra_cap);
  const over = round2(capped * p.per_extra_parcel_zmw);
  const stretch = trips >= target * p.stretch_ratio && target > 0 ? p.stretch_bonus_zmw : 0;
  return {
    extra_parcels: extra,
    counted_extra: capped,
    completion_bonus_zmw: completion,
    over_target_bonus_zmw: over,
    stretch_bonus_zmw: stretch,
    total_bonus_zmw: round2(completion + over + stretch),
    target_met: trips >= target && target > 0,
    programme: prog?.title ?? 'Built-in incentive',
    programme_id: prog?.id ?? 0,
  };
}

function shapeTargets(today: number, month: number, prog?: IncentiveProgramme | null): RiderTargetStats {
  const { dayOfMonth, daysInMonth } = monthCalendar();
  const monthTarget = DRIVER_DAILY_TARGET * daysInMonth;
  const paceTarget = DRIVER_DAILY_TARGET * dayOfMonth;
  const bonus = riderBonusSplits(month, monthTarget, prog ?? null);
  return {
    today,
    daily_target: DRIVER_DAILY_TARGET,
    daily_remaining: Math.max(0, DRIVER_DAILY_TARGET - today),
    daily_met: today >= DRIVER_DAILY_TARGET,
    month,
    month_target: monthTarget,
    pace_target: paceTarget,
    month_remaining: Math.max(0, monthTarget - month),
    behind_by: Math.max(0, paceTarget - month),
    on_track: month >= paceTarget,
    day_of_month: dayOfMonth,
    days_in_month: daysInMonth,
    bonus,
  };
}

async function riderTargetStats(db: D1Database, riderId?: number, prog?: IncentiveProgramme | null): Promise<Map<number, RiderTargetStats>> {
  const sql = `SELECT j.rider_id,
      COUNT(DISTINCT CASE WHEN date(je.created_at, '${CAT_OFFSET}') = date('now', '${CAT_OFFSET}') THEN j.id END) AS today,
      COUNT(DISTINCT CASE WHEN date(je.created_at, '${CAT_OFFSET}') >= date('now', 'start of month', '${CAT_OFFSET}') THEN j.id END) AS month
    FROM job_events je JOIN jobs j ON j.id = je.job_id
   WHERE je.status IN ('at_depot','delivered','ready_for_collection')
     AND j.rider_id IS NOT NULL${riderId ? ' AND j.rider_id = ?1' : ''}
   GROUP BY j.rider_id`;
  try {
    const stmt = db.prepare(sql);
    const { results } = await (riderId ? stmt.bind(riderId) : stmt).all<any>();
    const out = new Map<number, RiderTargetStats>();
    for (const row of (results ?? []) as any[]) {
      out.set(Number(row.rider_id), shapeTargets(Number(row.today ?? 0), Number(row.month ?? 0), prog ?? null));
    }
    return out;
  } catch {
    return new Map();
  }
}

/** R2 key from a stored /media/uploads/... path (uploads are served by /media). */
function r2KeyFromUrl(url: string): string | null {
  const clean = String(url ?? '').replace(/^https?:\/\/[^/]+/, '');
  const m = clean.match(/^\/media\/(.+)$/);
  return m ? m[1] : null;
}

/** Validate that the file bytes really look like an image (magic bytes).
 *  Prevents a client from uploading an HTML/JS payload with a .jpg extension
 *  and having it served back with attacker-chosen Content-Type (XSS). */
const IMAGE_MAGIC: [string, Uint8Array][] = [
  ['jpg', new Uint8Array([0xFF, 0xD8, 0xFF])],
  ['png', new Uint8Array([0x89, 0x50, 0x4E, 0x47])],
  ['gif', new Uint8Array([0x47, 0x49, 0x46, 0x38])],
  ['webp', new Uint8Array([0x52, 0x49, 0x46, 0x46])], // RIFF; WEBP check below
];
function looksLikeImage(bytes: Uint8Array, ext: string): boolean {
  if (ext === 'heic' || ext === 'heif') return true; // iOS HEIC — complex ftyp box, allow by ext
  if (ext === 'webp') {
    if (bytes.length < 12) return false;
    const riff = new TextDecoder().decode(bytes.slice(0, 4)) === 'RIFF';
    const webp = new TextDecoder().decode(bytes.slice(8, 12)) === 'WEBP';
    return riff && webp;
  }
  for (const [e, sig] of IMAGE_MAGIC) {
    if (ext === e && bytes.length >= sig.length) {
      let match = true;
      for (let i = 0; i < sig.length; i++) if (bytes[i] !== sig[i]) { match = false; break; }
      if (match) return true;
    }
  }
  return false;
}

const RIDER_DOC_FIELDS = [
  'nrc_number', 'license_number', 'plate_number', 'vehicle_make', 'vehicle_color',
  'photo_url', 'nrc_photo_url', 'license_photo_url', 'plate_photo_url',
] as const;

function riderDocSelect(): string {
  return `id, phone, full_name, vehicle, vehicle_class, active, status, capacity, current_load,
          nrc_number, license_number, plate_number, vehicle_make, vehicle_color,
          photo_url, nrc_photo_url, license_photo_url, plate_photo_url,
          verification_status, verification_note, verified_by, verified_at,
          submitted_at, ai_check_json`;
}


/* --------------------------- request tracing/logs -------------------------- */
// Every response carries X-Request-Id and emits one JSON access log line so
// Workers Logs / Logpush can query p50/p95 latency and error rates. Errors are
// also forwarded to Sentry when SENTRY_DSN is configured.
app.use('*', async (c, next) => {
  const reqId = c.req.header('CF-Ray') ?? crypto.randomUUID();
  c.set('reqId', reqId);
  const start = Date.now();
  try {
    await next();
  } finally {
    c.header('X-Request-Id', reqId);
    const ms = Date.now() - start;
    const line = {
      t: new Date().toISOString(), level: c.res.status >= 500 ? 'error' : c.res.status >= 400 ? 'warn' : 'info',
      req_id: reqId, method: c.req.method, path: c.req.path, status: c.res.status, ms,
      ip: c.req.header('CF-Connecting-IP') ?? null,
    };
    const msg = JSON.stringify(line);
    if (c.res.status >= 500) console.error(msg);
    else if (c.res.status >= 400) console.warn(msg);
    else console.log(msg);
  }
});

/* ------------------------------- auth guard ------------------------------- */
// Identity tiers:
//   customer  Bearer JWT (email+password or phone OTP) - senders/pay go & pack sellers
//   partner   Bearer JWT with role=partner - courier shop console (prices + ride confirm)
//   ops       X-Api-Key - rider-device service + ops console
//   admin     X-Admin-Key - superadmin pricebook / partner management (below)
// Public without auth: /health, /auth/*, /webhooks/*, /plans, courier profiles, //console pages.
const PUBLIC_GETS = new Set(['/health', '/couriers', '/cities', '/plans', '/console', '/partner/console', '/promo/check']);
app.use('*', async (c, next) => {
  const p = c.req.path;
  if (p === '/health' || p.startsWith('/auth/') || p.startsWith('/webhooks') || p.startsWith('/legal/') || p.startsWith('/.well-known/') || p.startsWith('/delete-data')) return next();
  // '/track/incoming' is the signed-in recipient's parcel list - it needs the
  // JWT identity, so it does NOT get the public bypass.
  // All other '/track/*' routes do their own account check in trackAccess —
  // the link alone is never a credential (no account ⇒ no data).
  if (p.startsWith('/track/') && p !== '/track/incoming') return next();
  const isPublicGet = c.req.method === 'GET' && (PUBLIC_GETS.has(p) || /^\/couriers\/\d+\/profile$/.test(p));
  if (isPublicGet) return next();

  const bearer = (c.req.header('Authorization') ?? '').replace(/^Bearer\s+/, '');
  if (bearer) {
    const claims = await verifyJwtClaims(bearer, c.env.JWT_SECRET);
    if (claims) {
      // role and token_version live on the account row — a password reset bumps
      // token_version, instantly invalidating every outstanding session
      const user = await c.env.DB.prepare(
        'SELECT role, courier_id, token_version, email FROM auth_users WHERE phone = ?1',
      ).bind(claims.phone).first<any>();
      if (user && Number(user.token_version ?? 0) !== Number(claims.ver ?? 0)) {
        return c.json({ error: 'session_revoked' }, 401);
      }
      c.set('phone', claims.phone);
      if (user?.email) c.set('email', user.email);
      if (claims.did && claims.did !== 'unknown') {
        const dev = await c.env.DB.prepare(
          'SELECT trusted FROM device_sessions WHERE phone = ?1 AND device_id = ?2',
        ).bind(claims.phone, claims.did).first<{ trusted: number }>();
        if (dev && Number(dev.trusted ?? 1) === 0) {
          return c.json({ error: 'device_revoked' }, 401);
        }
        if (!dev) {
          try { await noteDevice(c.env.DB, claims.phone, claims.did, clientIp(c), userAgent(c), { deviceName: deviceName(c), location: c.req.header('CF-IPCountry') }); } catch { /* best-effort */ }
        } else {
          try { await noteDevice(c.env.DB, claims.phone, claims.did, clientIp(c), userAgent(c), { deviceName: deviceName(c), location: c.req.header('CF-IPCountry') }); } catch { /* best-effort */ }
        }
      }
      // The app owner's phone is always admin (OWNER_PHONE secret) — covers
      // OTP-only sign-ins that have no auth_users row, and any user a
      // superadmin has promoted via /admin/users/role ('partner', 'rider',
      // 'ops', 'admin' or 'cfo').
      let role = ['partner', 'admin', 'rider', 'ops', 'cfo'].includes(user?.role ?? '') ? user.role
        : claims.phone === ownerPhone(c.env) ? 'admin' : null;
      // Rider identity: an accepted DB role also binds the rider's roster row if
      // one exists (not required - role='rider' is usable without a roster row).
      if (role === 'rider' || !role) {
        const rider = await c.env.DB.prepare(
          'SELECT id FROM riders WHERE phone = ?1 AND active = 1',
        ).bind(claims.phone).first<{ id: number }>();
        if (rider) {
          c.set('riderId', rider.id);
        }
        if (!role && rider) role = 'rider';
      }
      c.set('role', role ?? 'customer');
      if (user?.courier_id) c.set('courierId', user.courier_id);
      return next();
    }
  }
  if (c.req.header('X-Api-Key') === c.env.API_AUTH_KEY) {
    c.set('role', 'ops');
    return next();
  }
  // ADMIN_AUTH_KEY is the superadmin key: it authorizes /admin/* AND every
  // staff surface (/security/*, /me, —). Minted as role='admin' so route-level
  // isAdmin()/isSuperAdmin() checks all agree with it.
  if (c.req.header('X-Admin-Key') === c.env.ADMIN_AUTH_KEY) {
    c.set('role', 'admin');
    return next();
  }
  return c.json({ error: 'unauthorized' }, 401);
});

const isAdmin = (c: { env: Env; req: { header: (k: string) => string | undefined }; get?: (k: string) => unknown }) =>
  c.req.header('X-Admin-Key') === c.env.ADMIN_AUTH_KEY
  || (typeof c.get === 'function' && c.get('role') === 'admin')
  || (typeof c.get === 'function' && c.get('phone') === ownerPhone(c.env));

// CFO = finance executive. Same visibility as admin/ops on the payroll/tax/stats
// ledger surfaces (they are in charge of the audited books), but NOTHING that
// mints roles, edits passengers/riders, broadcasts SMS, moves money without the
// two-signature chain, or touches ops dispatch. Money moves only by the
// admin/superadmin chain — a CFO admin never disburses or voids.
const isFinanceExec = (c: { env?: Env; req: { header: (k: string) => string | undefined }; get?: (k: string) => unknown }) => {
  const role = typeof c.get === 'function' ? String(c.get('role') ?? '') : '';
  return role === 'cfo' || role === 'ops' || isAdmin(c as any);
};

const isOwner = (c: { env: Env; get?: (k: string) => unknown }) =>
  Boolean(typeof c.get === 'function' && c.get('phone') && c.get('phone') === ownerPhone(c.env));

// Superadmin ⊂ Admin (single role, no hierarchy): every admin can do every
// admin thing. The one server-side hard refusal kept deliberately is that the
// OWNER_PHONE account can never be deleted/demoted — silent guard, no UI hint.
const isSuperAdmin = isAdmin;

/** Naive per-IP throttle in D1 (e.g. 20 auth requests / hour / ip). */
async function rateLimited(
  c: { env: { DB: D1Database }; req: { header: (k: string) => string | undefined } },
  bucket: string, max = 20, minutes = 60,
): Promise<boolean> {
  const ip = c.req.header('CF-Connecting-IP') ?? 'unknown';
  const key = `ip:${ip}:${bucket}`;
  const n = (await c.env.DB.prepare(
    `SELECT COUNT(*) AS n FROM rate_hits WHERE key = ?1 AND created_at > datetime('now', ?2)`,
  ).bind(key, `-${minutes} minutes`).first<any>())?.n ?? 0;
  await c.env.DB.prepare('INSERT INTO rate_hits (key) VALUES (?1)').bind(key).run();
  return n >= max;
}

const devModeOn = (env: { AUTH_DEV_MODE?: string }) =>
  ['1', 'true', 'yes'].includes(String(env.AUTH_DEV_MODE ?? '').toLowerCase());

/* ---------------- local-language SMS helpers (Bemba/Tonga/Lozi/Nyanja) ----- */
// SMS are English-only until the user sets an app language preference.
// When locale prefs land, resolve per-recipient and append a short local hint.
function localSkipSuffix(_locale?: string | null): string { return ''; }
function localHandoverSuffix(_locale?: string | null): string { return ''; }

/* -------------------------- handover OTP (anti-fraud) ---------------------- */
// Yango-style "false parcel" protection: the RECIPIENT gets a 4-digit DropOff
// code by SMS at booking; the assigned rider MUST enter it when marking the
// job 'delivered'. SHA-256 over ref+code+jwt secret (fast — 4 digits only has
// 9k combinations server-side, answered exactly, attempts capped at 8).
async function handoverOtpHash(env: Env, ref: string, code: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(`${ref}:${code}:${env.JWT_SECRET}`),
  );
  return [...new Uint8Array(digest)].map((x) => x.toString(16).padStart(2, '0')).join('');
}

/* ------------------------------ fraud score ------------------------------ */
// Heuristic, not a verdict: velocity + duplicate pattern + high value + new
// account. Score >= 3 flags the job for ops review; it is never auto-cancelled
// here, because a false positive would strand a real parcel.
async function scoreJobFraud(
  env: Env, phone: string, jobId: number, ref: string,
  recipientPhone: string, pickupAddress: string, total: number,
): Promise<{ score: number; reasons: string[] }> {
  const reasons: string[] = [];
  let score = 0;
  const n1h = (await env.DB.prepare(
    `SELECT COUNT(*) AS n FROM jobs WHERE sender_phone = ?1 AND created_at > datetime('now', '-1 hour')`,
  ).bind(phone).first<any>())?.n ?? 0;
  if (n1h >= 5) { score += 2; reasons.push('velocity_1h'); }
  const n24h = (await env.DB.prepare(
    `SELECT COUNT(*) AS n FROM jobs WHERE sender_phone = ?1 AND created_at > datetime('now', '-1 day')`,
  ).bind(phone).first<any>())?.n ?? 0;
  if (n24h >= 20) { score += 2; reasons.push('velocity_24h'); }
  const dup = (await env.DB.prepare(
    `SELECT COUNT(*) AS n FROM jobs
      WHERE sender_phone = ?1 AND recipient_phone = ?2 AND pickup_address = ?3
        AND id <> ?4 AND created_at > datetime('now', '-6 hours')`,
  ).bind(phone, recipientPhone, pickupAddress, jobId).first<any>())?.n ?? 0;
  if (dup >= 1) { score += 3; reasons.push('duplicate_pattern'); }
  const acct = await env.DB.prepare('SELECT created_at FROM auth_users WHERE phone = ?1')
    .bind(phone).first<any>();
  const joined = acct?.created_at ? Date.parse(`${acct.created_at}Z`) : NaN;
  if (Number.isFinite(joined) && Date.now() - joined < 3_600_000) { score += 1; reasons.push('new_account'); }
  if (total >= 2000) { score += 2; reasons.push('high_value'); }
  if (recipientPhone === phone) { score += 1; reasons.push('self_delivery'); }
  if (score >= 3) {
    await env.DB.batch([
      env.DB.prepare('UPDATE jobs SET review_required = 1, fraud_score = ?2 WHERE id = ?1')
        .bind(jobId, score),
      env.DB.prepare(
        'INSERT INTO fraud_flags (job_id, job_ref, phone, score, reasons) VALUES (?1, ?2, ?3, ?4, ?5)',
      ).bind(jobId, ref, phone, score, reasons.join(',')),
    ]);
  }
  return { score, reasons };
}

/* ------------------------------ tracking links ---------------------------- */
// Recipients get a no-account public link (SMS/WhatsApp). Tokens are random and
// scoped to one job; the public page exposes status/live location only.
function secureToken(bytes = 18): string {
  const b = new Uint8Array(bytes);
  crypto.getRandomValues(b);
  return [...b].map((x) => x.toString(16).padStart(2, '0')).join('');
}

async function issueTrackingToken(env: Env, jobId: number, jobRef: string, phone: string | null): Promise<string> {
  const token = secureToken(12);
  // 180-day ceiling on every newly minted link: parcels deliver in days to a
  // few weeks, so a long-lived shareable URL is pure risk with no upside.
  // 12 chars keeps SMS tracking links short enough that the recipient
  // tracking SMS still fits ONE Africa's Talking segment (K0.24).
  await env.DB.prepare(
    `INSERT INTO tracking_tokens (token, job_id, job_ref, phone, expires_at)
     VALUES (?1, ?2, ?3, ?4, datetime('now', '+180 days'))`,
  ).bind(token, jobId, jobRef, phone).run();
  return token;
}

const trackingUrl = (env: Env, token: string) =>
  `${(env.APP_URL ?? '').replace(/\/$/, '')}/track/${token}`;

/** Payment-HELD job (owner directive 2026-11-15 — "no tracking while payment
 *  is held"): the prepayment never settled at booking (paid = 0) and the job
 *  still carries the advance/prepayment-pending event written at booking time.
 *  Settlement flips paid = 1, so this test self-clears the moment payment
 *  lands — no manual un-holding, ever. */
async function jobPaymentHeld(db: D1Database, jobId: number): Promise<boolean> {
  const row = await db.prepare(
    `SELECT 1 AS held FROM jobs j
      WHERE j.id = ?1 AND j.paid = 0
        AND EXISTS (SELECT 1 FROM job_events e
                     WHERE e.job_id = j.id AND e.status IN ('advance_pending', 'prepayment_pending'))`,
  ).bind(jobId).first<{ held: number }>();
  return !!row;
}

/** The signed-in user's profile name (for NOT NULL job sender columns). Falls
 *  back to null; callers always layer a final 'DropOff customer' default. */
async function senderProfileName(db: D1Database, phone: string): Promise<string | null> {
  const row = await db.prepare(
    'SELECT full_name FROM auth_users WHERE phone = ?1 LIMIT 1',
  ).bind(phone).first<{ full_name: string | null }>().catch(() => null);
  return row?.full_name?.trim() || null;
}

/* ------------------------ tracking access control ------------------------- */
// ACCOUNTS REQUIRED (owner directive — "no one without account"): a parcel can
// ONLY be tracked by a signed-in user whose phone is the sender's or the
// recipient's, or by staff keys. No phone-OTP grants, no anonymous link
// access: the link itself proves nothing. Anyone else learns only the last 4
// digits of the participant phone — never parcel data, rider location or
// events — plus a pointer to the account flow.
type TrackAccess = {
  granted: boolean;
  jobId: number | null;          // null => token unknown/expired (404)
  senderPhone: string | null;
  recipientPhone: string | null;
  recipientName: string | null;
  whoAmI?: 'sender' | 'recipient' | 'staff' | null;
};

async function trackAccess(c: any, token: string): Promise<TrackAccess> {
  const db: D1Database = (c as { env: { DB: D1Database } }).env.DB;
  const job = await db.prepare(
    `SELECT t.job_id, j.sender_phone, j.recipient_phone, j.recipient_name
       FROM tracking_tokens t JOIN jobs j ON j.id = t.job_id
      WHERE t.token = ?1
        AND COALESCE(j.status, '') != 'deleted'
        AND (t.expires_at IS NULL OR t.expires_at > datetime('now'))`,
  ).bind(token).first<any>();
  const base = {
    jobId: job ? (job.job_id as number) : null,
    senderPhone: job?.sender_phone ?? null,
    recipientPhone: job?.recipient_phone ?? null,
    recipientName: job?.recipient_name ?? null,
  };
  if (!job) return { granted: false, ...base };
  // Staff keys (ops console / admin console / rider devices).
  if (c.req.header('X-Admin-Key') === c.env.ADMIN_AUTH_KEY || c.req.header('X-Api-Key') === c.env.API_AUTH_KEY) {
    return { granted: true, ...base, whoAmI: 'staff' };
  }
  // Signed-in participant: the app always attaches its JWT when present.
  const bearer = (c.req.header('Authorization') ?? '').replace(/^Bearer\s+/, '');
  if (bearer) {
    const claims = await verifyJwtClaims(bearer, c.env.JWT_SECRET);
    if (claims && (claims.phone === job.sender_phone || claims.phone === job.recipient_phone)) {
      return { granted: true, ...base, whoAmI: claims.phone === job.recipient_phone ? 'recipient' : 'sender' };
    }
  }
  return { granted: false, ...base }; // token valid, but no account → no data
}

const maskPhone = (p: string | null) => (p && p.length >= 4 ? `————${p.slice(-4)}` : null);

/* ------------------------------ idempotency ------------------------------- */
// Clients retry on flaky networks; the same Idempotency-Key must replay the
// first response instead of creating a second job / mobile-money collect.
const idemKeyOf = (c: any, body: any): string | null => {
  const raw = c.req.header('Idempotency-Key') ?? body?.idempotency_key ?? '';
  const key = String(raw).trim();
  return key ? key.slice(0, 160) : null;
};

async function replayIdempotent(c: any, key: string | null, scope: string, phone?: string | null) {
  if (!key) return null;
  const row: any = await c.env.DB.prepare(
    'SELECT scope, status, response, phone FROM idempotency_keys WHERE key = ?1',
  ).bind(key).first();
  if (!row || row.scope !== scope) return null;
  // Ownership: only the phone that created the key may replay it.
  if (phone != null && row.phone != null && row.phone !== phone) return null;
  try { return c.json(JSON.parse(row.response), row.status); } catch { return null; }
}

async function saveIdempotent(
  env: Env, key: string | null, scope: string, phone: string | null, status: number, payload: unknown,
): Promise<void> {
  if (!key) return;
  await env.DB.prepare(
    `INSERT OR IGNORE INTO idempotency_keys (key, scope, phone, status, response)
     VALUES (?1, ?2, ?3, ?4, ?5)`,
  ).bind(key, scope, phone, status, JSON.stringify(payload)).run().catch(() => {});
}

/* --------------------------------- cors ----------------------------------- */
// Narrow CORS: only origins listed in the CORS_ORIGINS var (comma-separated) may
// call the API cross-origin — lets the Flutter-web admin build work without
// opening the API to every website. Same-origin calls (the HTML consoles) need
// no CORS at all. Set CORS_ORIGINS="" (default) to disable cross-origin entirely.
const corsOrigins = (raw: string | undefined): string[] =>
  (raw ?? '').split(',').map((s) => s.trim()).filter(Boolean);
app.use('*', (c, next) => {
  const allow = corsOrigins(c.env.CORS_ORIGINS);
  if (!allow.length) return next();
  return cors({
    origin: (o) => (allow.includes(o) ? o : null),
    allowHeaders: ['Content-Type', 'Authorization', 'X-Api-Key', 'X-Admin-Key', 'X-Device-Id', 'X-Device-Name'],
    allowMethods: ['GET', 'POST', 'DELETE', 'OPTIONS'],
    maxAge: 86400,
  })(c, next);
});

/* --------------------------------- edge cache ------------------------------ */
// Quasi-static read endpoints get browser/CDN cache so Zambian users never
// re-fetch the same couriers/quotes/cities/plans on every app open.
const cacheFor = (seconds: number) => async (c: any, next: any) => {
  await next();
  if (c.res.status >= 400) return;
  c.header('Cache-Control', `public, max-age=${seconds}, s-maxage=${seconds}, stale-while-revalidate=0`);
  c.header('Vary', 'Accept-Encoding');
};

// Only genuinely shared, non-personal data is cacheable. Everything else —
// jobs, float, partner keys, referrals, ratings, rider routes — is private and
// must never be stored by a browser or proxy (stale + privacy risk).
const PUBLIC_CACHEABLE = /^\/(health|cities|couriers(\/[^/]+(\/profile)?)?|quotes|plans)$/;
app.use('*', async (c, next) => {
  await next();
  if (c.req.method !== 'GET') return;
  if (!PUBLIC_CACHEABLE.test(c.req.path)) c.header('Cache-Control', 'private, no-store');
});

app.use('GET /health', cacheFor(15));
app.use('GET /cities', cacheFor(300));
app.use('GET /couriers', cacheFor(30));
app.use('GET /couriers/*', cacheFor(30));
app.use('GET /quotes', cacheFor(30));
app.use('GET /plans', cacheFor(30));

/* --------------------------------- health --------------------------------- */
app.get('/health', (c) => c.json({ ok: true, ts: Date.now() }));

// Road routing for the in-app navigator (riders). Signed-in accounts only;
// results are cached by 5dp coordinate pair for 15 minutes. The ORS key lives
// server-side — no routing key ever ships inside the app binary. Set it with:
//   wrangler secret put ORS_API_KEY   (free key: https://openrouteservice.org, 2,000 directions/day)
// Until it is set the endpoint answers 503 router_not_configured and the app
// falls back to a labelled straight line.
app.get('/maps/route', async (c) => {
  const parsePair = (raw: string | undefined) => String(raw ?? '').split(',').map(Number);
  const validPair = (n: number[]) => n.length === 2 && n.every((x) => Number.isFinite(x)) && Math.abs(n[0]) <= 180 && Math.abs(n[1]) <= 90;
  const from = parsePair(c.req.query('from')); // lng,lat
  const to = parsePair(c.req.query('to'));
  if (!validPair(from) || !validPair(to)) return c.json({ error: 'bad_coords', detail: 'from/to must be "lng,lat".' }, 400);
  const fmt = (n: number[]) => n.map((x) => x.toFixed(5)).join(',');
  const f = fmt(from), t = fmt(to);
  const cacheKey = new Request(`https://route.internal/${f};${t}`);
  try {
    const hit = await caches.default.match(cacheKey);
    if (hit) {
      const cached = await hit.text();
      return new Response(cached, { headers: { 'content-type': 'application/json', 'x-route-cache': 'hit' } });
    }
  } catch { /* cache unavailable — fall through */ }
  const upstream = ((c.env as any).ROUTER_UPSTREAM as string | undefined)?.replace(/\/+$/, '');
  try {
    if (upstream) {
      // Self-hosted OSRM (open-source, ours — see infra/router/README.md).
      const res = await fetch(
        `${upstream}/route/v1/driving/${f};${t}?overview=full&geometries=geojson&steps=true&continue_straight=true`,
        { headers: { 'User-Agent': 'DropOff/1.0' }, signal: AbortSignal.timeout(9000) },
      );
      if (!res.ok) return c.json({ error: 'router_upstream_failed', status: res.status }, 502);
      const data: any = await res.json();
      const route = data?.routes?.[0];
      if (!route) return c.json({ error: 'router_empty' }, 502);
      const coords: [number, number][] = route.geometry?.coordinates ?? [];
      if (coords.length < 2) return c.json({ error: 'router_empty' }, 502);
      const steps = (route.legs ?? []).flatMap((leg: any) =>
        (leg.steps ?? []).map((s: any) => {
          const man = s?.maneuver ?? {};
          const instruction = typeof man.instruction === 'string' && man.instruction
            ? man.instruction
            : osrmInstruction(String(man.type ?? ''), String(man.modifier ?? ''), String(s?.name ?? ''));
          return {
            instruction,
            distance_m: Number(s?.distance ?? 0),
            duration_s: Number(s?.duration ?? 0),
            road: s?.name ? String(s.name) : null,
            type: man.type ?? null,
          };
        }),
      );
      const body = JSON.stringify({
        points: coords.map(([lng, lat]) => [lat, lng]), // app expects [lat,lng]
        distance_m: Number(route.distance ?? 0),
        duration_s: Number(route.duration ?? 0),
        steps,
      });
      const out = new Response(body, { headers: { 'content-type': 'application/json', 'cache-control': 'public, max-age=900' } });
      try { c.executionCtx.waitUntil(caches.default.put(cacheKey, out.clone())); } catch { /* best-effort */ }
      return out;
    }
    const key = (c.env as any).ORS_API_KEY as string | undefined;
    if (!key) return c.json({ error: 'router_not_configured' }, 503);
    const res = await fetch(
      `https://api.openrouteservice.org/v2/directions/driving-car/geojson?start=${f}&end=${t}`,
      { headers: { Authorization: key, 'User-Agent': 'DropOff/1.0' }, signal: AbortSignal.timeout(9000) },
    );
    if (!res.ok) return c.json({ error: 'router_upstream_failed', status: res.status }, 502);
    const data: any = await res.json();
    const feat = data?.features?.[0];
    if (!feat) return c.json({ error: 'router_empty' }, 502);
    const props = feat.properties ?? {};
    const summary = props.summary ?? {};
    const coords: [number, number][] = feat.geometry?.coordinates ?? [];
    if (coords.length < 2) return c.json({ error: 'router_empty' }, 502);
    const steps = (props.segments ?? []).flatMap((seg: any) =>
      (seg.steps ?? []).map((s: any) => ({
        instruction: String(s.instruction ?? ''),
        distance_m: Number(s.distance ?? 0),
        duration_s: Number(s.duration ?? 0),
        road: s.name ? String(s.name) : null,
        type: s.type ?? null,
      })),
    );
    const body = JSON.stringify({
      points: coords.map(([lng, lat]) => [lat, lng]), // app expects [lat,lng]
      distance_m: Number(summary.distance ?? 0),
      duration_s: Number(summary.duration ?? 0),
      steps,
    });
    const out = new Response(body, { headers: { 'content-type': 'application/json', 'cache-control': 'public, max-age=900' } });
    try { c.executionCtx.waitUntil(caches.default.put(cacheKey, out.clone())); } catch { /* best-effort */ }
    return out;
  } catch {
    return c.json({ error: 'router_upstream_failed' }, 502);
  }
});

/** OSRM maneuver → human instruction, used when OSRM ships no text step. */
function osrmInstruction(type: string, modifier: string, street: string): string {
  const dir = (() => {
    switch (modifier) {
      case 'left': return 'left';
      case 'right': return 'right';
      case 'slight left': return 'slightly left';
      case 'slight right': return 'slightly right';
      case 'sharp left': return 'sharp left';
      case 'sharp right': return 'sharp right';
      case 'straight': return 'straight';
      case 'uturn': return 'u-turn';
      default: return '';
    }
  })();
  const onto = street ? ` onto ${street}` : '';
  switch (type) {
    case 'depart': return 'Head out';
    case 'arrive': return 'Arrive at the destination';
    case 'turn': return dir ? `Turn ${dir}${onto}` : `Make the turn${onto}`;
    case 'end of road': return dir ? `Turn ${dir} at the end of the road${onto}` : `Turn at the end of the road${onto}`;
    case 'fork': return dir ? `Bear ${dir} at the fork${onto}` : `Keep at the fork${onto}`;
    case 'merge': return `Merge${onto}`;
    case 'ramp': return `Take the ramp${onto}`;
    case 'on ramp': return `Take the on-ramp${onto}`;
    case 'off ramp': return `Take the exit${onto}`;
    case 'new name': return `Continue${onto}`;
    case 'continue': return `Continue straight${onto}`;
    case 'roundabout': case 'rotary': return modifier ? `Enter the roundabout (exit ${modifier})${onto}` : `Enter the roundabout${onto}`;
    case 'exit roundabout': return `Exit the roundabout${onto}`;
    case 'roundabout turn': return dir ? `Take the ${dir} exit at the roundabout${onto}` : `Turn at the roundabout${onto}`;
    case 'notification': return `Continue${onto}`;
    default: return dir ? `Turn ${dir}${onto}` : `Continue${onto}`;
  }
}

// Client crash report — unauthenticated (crashes may occur pre-sign-in),
// length-capped and rate-limited by device to 20/hour. The admin console reads
// these; a growing count on the latest build = stop the rollout.
app.post('/client/error', async (c) => {
  let body: any = {};
  try { body = await c.req.json(); } catch { return c.json({ error: 'json_required' }, 400); }
  const message = String(body?.message ?? '').slice(0, 240).trim();
  if (!message) return c.json({ ok: true }); // nothing useful to store
  const stack = String(body?.stack ?? '').slice(0, 2000);
  const platform = String(body?.platform ?? 'unknown').slice(0, 16);
  const appVersion = String(body?.app_version ?? '').slice(0, 32);
  const deviceId = String(body?.device_id ?? c.req.header('x-device-id') ?? 'unknown').slice(0, 128);
  const userPhone = (c.get as any)?.('phone') ? String((c.get as any)('phone')).slice(0, 20) : null;
  const dedupeKey = `${deviceId}|${message.slice(0, 64)}|${stack.slice(0, 64)}`;
  try {
    const recent = await c.env.DB.prepare(
      `SELECT COUNT(*) AS n FROM client_crashes WHERE device_id = ?1 AND last_seen_at > datetime('now', '-1 hour')`,
    ).bind(deviceId).first<any>();
    if (Number(recent?.n ?? 0) >= 20) return c.json({ ok: true, throttled: true });
    await c.env.DB.prepare(
      `INSERT INTO client_crashes (message, stack, platform, app_version, user_phone, device_id, dedupe_key)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
       ON CONFLICT(dedupe_key) DO UPDATE SET count = count + 1, last_seen_at = datetime('now')`,
    ).bind(message, stack, platform, appVersion, userPhone, deviceId, dedupeKey).run();
  } catch { /* best-effort — never 5xx the reporter */ }
  return c.json({ ok: true });
});

// Admin view of recent crashes for the console card.
app.get('/admin/client-crashes', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'admin_required' }, 403);
  const [rows, total] = await Promise.all([
    c.env.DB.prepare(
      `SELECT message, platform, app_version, count, first_seen_at, last_seen_at
         FROM client_crashes ORDER BY last_seen_at DESC LIMIT 15`,
    ).all<any>(),
    c.env.DB.prepare(
      `SELECT COALESCE(SUM(count), 0) AS n FROM client_crashes WHERE last_seen_at > datetime('now', '-1 day')`,
    ).first<any>(),
  ]);
  return c.json({ crashes: rows.results ?? [], crashes_last_24h: Number(total?.n ?? 0) });
});

// Africa's Talking inbound SMS — STOP unsubscribes marketing; START resubscribes.
// (Transactional SMS — OTP, payment codes — is never blocked either way.)
app.post('/webhooks/at-sms', async (c) => {
  let body: any = {};
  const raw = await c.req.text().catch(() => '');
  try { body = JSON.parse(raw); } catch {
    try { body = Object.fromEntries(new URLSearchParams(raw)); } catch { /* ignore */ }
  }
  const text = String(body?.text ?? body?.message ?? body?.body ?? '').trim().toUpperCase();
  const fromRaw = String(body?.from ?? body?.senderId ?? body?.phone ?? '');
  const digits = fromRaw.replace(/\D/g, '');
  const phone = digits.startsWith('260') ? digits : digits.replace(/^0/, '260');
  if (!/^260\d{9}$/.test(phone)) return c.json({ ok: true }); // unparseable — ack anyway
  const stopWords = new Set(['STOP', 'UNSUBSCRIBE', 'END', 'CANCEL', 'QUIT']);
  const startWords = new Set(['START', 'UNSTOP', 'YES', 'SUBSCRIBE']);
  const optOut = stopWords.has(text) ? 1 : (startWords.has(text) ? 0 : null);
  if (optOut === null) return c.json({ ok: true });
  try {
    await c.env.DB.prepare('UPDATE auth_users SET sms_opt_out = ?1 WHERE phone = ?2').bind(optOut, phone).run();
  } catch { /* best-effort */ }
  return c.json({ ok: true });
});

/* ----------------------------- legal (Play needs a live privacy URL) ------- */
// Public, no auth. The middleware skips '/legal' (regex below includes it).
const PRIVACY_HTML =
`<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${PRIVACY_TITLE}</title>
<style>body{font:16px/1.6 system-ui,-apple-system,sans-serif;color:#1c2530;max-width:720px;margin:2rem auto;padding:0 1.25rem}h1{font-size:1.5rem}h2{font-size:1.15rem;margin-top:1.75rem}li{margin:0.35rem 0}</style>
</head><body>
${mdToHtml(PRIVACY_MD)}
</body></html>`;

app.get('/legal/privacy', (c) => c.html(PRIVACY_HTML));

const TERMS_HTML =
`<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${TERMS_TITLE}</title>
<style>body{font:16px/1.6 system-ui,-apple-system,sans-serif;color:#1c2530;max-width:720px;margin:2rem auto;padding:0 1.25rem}h1{font-size:1.5rem}h2{font-size:1.15rem;margin-top:1.75rem}li{margin:0.35rem 0}</style>
</head><body>
${mdToHtml(TERMS_MD)}
</body></html>`;

app.get('/legal/terms', (c) => c.html(TERMS_HTML));

/* ------------------------------ delete my data ----------------------------- */
// Play data-safety requires a link where any user can request that their
// account and associated data be deleted. This is a real self-serve flow:
// the phone proves itself via the same hashed OTP pipe the sign-in uses, then
// the account row is anonymized (email/name/photo/password gone, token_version
// bumped so every JWT dies) and personal tables scrubbed. Financial records
// stay, per the privacy policy (audit law) — but stripped of identity.

const DELETE_DATA_HTML = `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Delete your DropOff data</title>
<style>body{font:16px/1.6 system-ui,-apple-system,sans-serif;color:#1c2530;max-width:720px;margin:2rem auto;padding:0 1.25rem}
h1{font-size:1.5rem}h2{font-size:1.15rem;margin-top:1.5rem}li{margin:.35rem 0}
input{padding:.65rem .75rem;border:1px solid #c9d2dc;border-radius:10px;font-size:1rem;width:min(320px,90%)}
button{margin-left:.5rem;padding:.65rem 1rem;border:0;border-radius:10px;background:#14532d;color:#fff;font-weight:700;font-size:1rem;cursor:pointer}
button:disabled{opacity:.5}
#msg{margin-top:1rem;white-space:pre-line}
.warn{color:#8a2e2e}
</style></head><body>
<h1>Delete your DropOff data</h1>
<p>This deletes your DropOff <b>account and personal data</b>. Sign-in (email, password), your name, profile photo, saved recipient addresses, push tokens and active sessions are erased immediately and cannot be undone.</p>
<p class="warn">Record copies needed by law for financial audit (delivery/payment records) are kept, but stripped of personal identity, as described in our <a href="/legal/privacy">privacy policy</a>.</p>
<hr>
<div id="step1">
  <h2>Step 1 — verify your phone number</h2>
  <input id="phone" inputmode="tel" placeholder="+26 0 96 ..."></input>
  <button id="sendBtn" onclick="sendCode()">Send a code</button>
</div>
<div id="step2" style="display:none">
  <h2>Step 2 — enter the code we texted you</h2>
  <p>It is valid for 10 minutes.</p>
  <input id="code" inputmode="numeric" maxlength="6" placeholder="6-digit code"></input>
  <button id="goBtn" onclick="confirmDelete()">Delete my data permanently</button>
</div>
<div id="msg"></div>
<p>Questions? No DropOff account on this number? Something not working?</p>
<p>Email <a href="mailto:support@dropoff.africa">support@dropoff.africa</a> and we will process the request for you.</p>
<script>
const msg=(t,ok)=>{const e=document.getElementById('msg');e.textContent=t;e.style.color=ok?'#14532d':'#8a2e2e'};
async function post(u,body){const r=await fetch(u,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
let j={};try{j=await r.json()}catch(_){}
return {status:r.status,ok:r.ok,json:j};}
async function sendCode(){
  const b=document.getElementById('sendBtn');const phone=document.getElementById('phone').value.trim();
  if(!phone)return msg('Enter the phone number your DropOff account uses.',false);
  b.disabled=true;msg('Sending…',true);
  const r=await post('/delete-data/request',{phone});
  b.disabled=false;
  if(!r.ok)return msg(r.json.error||'Could not send the code right now. Try again shortly.',false);
  document.getElementById('step1').style.display='none';
  document.getElementById('step2').style.display='';
  msg('A 6-digit code was sent to '+phone+'.',true);
}
async function confirmDelete(){
  const b=document.getElementById('goBtn');const phone=document.getElementById('phone').value.trim();
  const code=document.getElementById('code').value.trim();
  if(!code)return msg('Enter the 6-digit code you received.',false);
  b.disabled=true;
  const r=await post('/delete-data/confirm',{phone,code});
  if(r.ok&&r.json.deleted){document.getElementById('step2').style.display='none';
    return msg('Done. Your account and personal data have been deleted. Financial record copies retained for audit carry no personal identity.',true);}
  const e=r.json.error==='wrong_code'?'Wrong code — try again.':(r.json.error==='account_not_found'?'There is no DropOff account on this number.':(r.json.error||'Deletion failed. Try again shortly.'));
  b.disabled=false;
  msg(e,false);
}
</script></body></html>`;

app.get('/delete-data', (c) => {
  const html = DELETE_DATA_HTML.replaceAll('+26 0 96', '+260 96');
  return c.html(html);
});

// Request step: send the deletion code. Honest error when the number has no
// account (a deletion tool that says ok for strangers just misleads).
app.post('/delete-data/request', async (c) => {
  if (await rateLimited(c, 'delete_otp', 5, 3600)) return c.json({ error: 'too_many_requests' }, 429);
  const b: any = await c.req.json().catch(() => null);
  let phone: string;
  try { phone = normalizeZmPhone(b?.phone); } catch (e: any) { return c.json({ error: e.message }, 400); }
  const account = await c.env.DB.prepare('SELECT phone FROM auth_users WHERE phone = ?1').bind(phone).first();
  if (!account) return c.json({ error: 'account_not_found' }, 404);
  const recent = await c.env.DB.prepare(
    `SELECT COUNT(*) AS n FROM otp_codes WHERE phone = ?1 AND created_at > datetime('now', '-1 hour')`,
  ).bind(phone).first<any>();
  if ((recent?.n ?? 0) >= 5) return c.json({ error: 'too_many_codes_wait_an_hour' }, 429);
  const code = generateOtp();
  const hash = await hashOtp(code, c.env.JWT_SECRET);
  await c.env.DB.batch([
    c.env.DB.prepare('UPDATE otp_codes SET used = 1 WHERE phone = ?1 AND used = 0').bind(phone),
    c.env.DB.prepare(
      `INSERT INTO otp_codes (phone, code_hash, expires_at) VALUES (?1, ?2, datetime('now', '+10 minutes'))`,
    ).bind(phone, hash),
  ]);
  const sms = await sendSms(c.env, phone,
    `DropOff data deletion: your confirmation code is ${code}. It expires in 10 minutes. Never share this code.`, { transactional: true });
  return c.json({ sent: sms.sent, ...(sms.error ? { sms_error: sms.error } : {}) });
});

// Confirm step: OTP-gated anonymization + session/token revocation.
app.post('/delete-data/confirm', async (c) => {
  if (await rateLimited(c, 'delete_confirm', 10)) return c.json({ error: 'too_many_requests' }, 429);
  const b: any = await c.req.json().catch(() => null);
  let phone: string;
  try { phone = normalizeZmPhone(b?.phone); } catch (e: any) { return c.json({ error: e.message }, 400); }
  const code = String(b?.code ?? '').replace(/\D/g, '');
  if (!code) return c.json({ error: 'wrong_code' }, 400);
  const row = await c.env.DB.prepare(
    `SELECT id, code_hash, attempts FROM otp_codes
      WHERE phone = ?1 AND used = 0 AND expires_at > datetime('now')
      ORDER BY id DESC LIMIT 1`,
  ).bind(phone).first<any>();
  if (!row) return c.json({ error: 'code_expired_or_missing' }, 401);
  if (Number(row.attempts ?? 0) >= 5) {
    await c.env.DB.prepare('UPDATE otp_codes SET used = 1 WHERE id = ?1').bind(row.id).run();
    return c.json({ error: 'code_expired_or_missing' }, 401);
  }
  const hash = await hashOtp(code, c.env.JWT_SECRET);
  if (hash !== row.code_hash) {
    await c.env.DB.prepare('UPDATE otp_codes SET attempts = attempts + 1 WHERE id = ?1').bind(row.id).run();
    return c.json({ error: 'wrong_code' }, 401);
  }
  const account = await c.env.DB.prepare('SELECT phone FROM auth_users WHERE phone = ?1').bind(phone).first();
  if (!account) return c.json({ error: 'account_not_found' }, 404);
  await c.env.DB.batch([
    // Burn the code.
    c.env.DB.prepare('UPDATE otp_codes SET used = 1 WHERE id = ?1').bind(row.id),
    // Anonymize the account: PII gone, sign-in dead, every JWT revoked.
    c.env.DB.prepare(
      `UPDATE auth_users SET
         email = 'deleted+' || phone || '@deleted.dropoff.invalid',
         password_hash = 'deleted', email_verified = 0, full_name = NULL,
         photo_url = NULL, locale_pref = NULL, referral_code = NULL,
         token_version = COALESCE(token_version, 0) + 1
       WHERE phone = ?1`,
    ).bind(phone),
    // Personal data + device bindings.
    c.env.DB.prepare('DELETE FROM saved_recipients WHERE owner_phone = ?1').bind(phone),
    c.env.DB.prepare('DELETE FROM push_tokens WHERE phone = ?1').bind(phone),
    c.env.DB.prepare('DELETE FROM device_sessions WHERE phone = ?1').bind(phone),
    c.env.DB.prepare('DELETE FROM chat_reads WHERE phone = ?1').bind(phone),
    c.env.DB.prepare('DELETE FROM user_blocks WHERE blocker = ?1 OR blocked = ?1').bind(phone),
    c.env.DB.prepare('DELETE FROM chat_strikes WHERE phone = ?1').bind(phone),
    // Clean out ALL of this account's open OTP codes.
    c.env.DB.prepare('UPDATE otp_codes SET used = 1 WHERE phone = ?1 AND used = 0').bind(phone),
  ]);
  await sendSms(c.env, phone, 'DropOff: your account and personal data have been deleted as requested. Financial audit records are retained without personal identifiers.', { transactional: true }).catch(() => null);
  return c.json({ ok: true, deleted: true });
});

// Deep-link well-known assets: let Android/iOS open DropOff links instead of
// a bare browser tab. Served on the shared API host — the apex
// carpsosolutions.store belongs to the company site and is untouched.
const APP_LINK_HOST = 'api.carpsosolutions.store';
const DROPOFF_PACKAGE = 'zm.dropoff.dropoff';
const UPLOAD_CERT_SHA256 = 'D0:DB:11:37:43:29:51:04:02:8F:42:3B:AB:B7:89:06:67:68:F0:48:D2:F1:AB:BF:76:21:A4:B8:5A:B0:E9:37';
app.get('/.well-known/assetlinks.json', (c) => c.json([{
  relation: ['delegate_permission/common.handle_all_urls'],
  target: { namespace: 'android_app', package_name: DROPOFF_PACKAGE, sha256_cert_fingerprints: [UPLOAD_CERT_SHA256] },
}], 200, { 'Cache-Control': 'public, max-age=3600' }));
app.get('/.well-known/apple-app-site-association', (c) => {
  const appleTeam = String(c.env.APPLE_TEAM_ID ?? '').trim();
  if (!appleTeam) return c.json({ error: 'apple_app_site_association_not_configured' }, 404);
  return new Response(JSON.stringify({
    applinks: { details: [{ appID: `${appleTeam}.zm.dropoff.dropoff`, paths: ['/track/*', '/t/*', '/r/*', '/promo/*', '/rate/*', '/bookings/*', '/claim', '/plans', '/couriers/*'] }] },
  }), { headers: { 'Content-Type': 'application/json', 'Cache-Control': 'public, max-age=3600' } });
});



// Identity for the signed-in caller — the app uses this to reveal admin/ops
// surfaces (the owner's phone is admin via OWNER_PHONE middleware grant) and
// the superadmin flag to unlock role management (promote admins).
app.get('/me', async (c) => {
  const phone = c.get('phone');
  let rider: { id: number; name: string } | null = null;
  let photoUrl: string | null = null;
  let fullName: string | null = null;
  let email: string | null = null;
  if (phone) {
    const r = await c.env.DB.prepare('SELECT id, full_name, photo_url FROM riders WHERE phone = ?1 AND active = 1')
      .bind(phone).first<{ id: number; full_name: string; photo_url: string | null }>();
    if (r) { rider = { id: r.id, name: r.full_name }; photoUrl = r.photo_url; fullName = r.full_name; }
    const u = await c.env.DB.prepare('SELECT email, full_name, photo_url, locale_pref FROM auth_users WHERE phone = ?1')
      .bind(phone).first<{ email: string | null; full_name: string | null; photo_url: string | null; locale_pref: string | null }>();
    if (u?.full_name) fullName = u.full_name;
    // Account photo (incl. seller uploads) wins for display; rider photo is the tracking identity.
    if (u?.photo_url) photoUrl = u.photo_url;
    email = u?.email ?? null;
    (c as any)._localePref = u?.locale_pref ?? null;
  }
  return c.json({
    phone: phone ?? null,
    role: c.get('role') ?? null,
    superadmin: isSuperAdmin(c),
    rider,
    photo_url: photoUrl,
    full_name: fullName,
    locale_pref: (c as any)._localePref ?? null,
    ...(email ? { email } : {}),
  });
});

// Set profile preferences (e.g. locale). English SMS remain default until locale is used.
app.patch('/me', async (c) => {
  const phone = c.get('phone');
  if (!phone) return c.json({ error: 'sign_in_required' }, 401);
  const b: any = await c.req.json().catch(() => null);
  const allowed = new Set(['en', 'ny', 'bem', 'toi', 'loz', 'lun', 'kqn', 'lue']);
  if (b?.locale_pref != null) {
    const loc = String(b.locale_pref).trim().toLowerCase();
    if (loc && !allowed.has(loc)) return c.json({ error: 'unsupported_locale', allowed: [...allowed] }, 400);
    await c.env.DB.prepare('UPDATE auth_users SET locale_pref = ?2 WHERE phone = ?1').bind(phone, loc || null).run();
  }
  return c.json({ ok: true });
});

// Saved recipients / address book (quick rebook)
app.get('/recipients', async (c) => {
  const phone = c.get('phone');
  if (!phone) return c.json({ error: 'sign_in_required' }, 401);
  const { results } = await c.env.DB.prepare(
    `SELECT id, name, phone, address, city, notes, updated_at FROM saved_recipients
      WHERE owner_phone = ?1 ORDER BY updated_at DESC LIMIT 100`,
  ).bind(phone).all<any>();
  return c.json({ recipients: results ?? [] });
});
app.post('/recipients', async (c) => {
  const phone = c.get('phone');
  if (!phone) return c.json({ error: 'sign_in_required' }, 401);
  const b: any = await c.req.json().catch(() => null);
  const name = String(b?.name ?? '').trim().slice(0, 120);
  let rphone = '';
  try { rphone = normalizeZmPhone(String(b?.phone ?? '').trim() || ''); } catch {}
  if (!name || !rphone) return c.json({ error: 'name_and_phone_required' }, 400);
  await c.env.DB.prepare(
    `INSERT INTO saved_recipients (owner_phone, name, phone, address, city, notes, updated_at)
     VALUES (?1,?2,?3,?4,?5,?6,datetime('now'))
     ON CONFLICT(owner_phone, phone, name) DO UPDATE SET address=excluded.address, city=excluded.city, notes=excluded.notes, updated_at=datetime('now')`,
  ).bind(phone, name, rphone, b?.address ? String(b.address).slice(0, 200) : null, b?.city ? String(b.city).slice(0, 80) : null, b?.notes ? String(b.notes).slice(0, 200) : null).run();
  return c.json({ ok: true });
});
app.delete('/recipients/:id', async (c) => {
  const phone = c.get('phone');
  if (!phone) return c.json({ error: 'sign_in_required' }, 401);
  await c.env.DB.prepare('DELETE FROM saved_recipients WHERE id = ?1 AND owner_phone = ?2').bind(Number(c.req.param('id')), phone).run();
  return c.json({ ok: true });
});

// Density/slot optimization: suggest the least-loaded open slot (simple heuristic).
app.get('/slots/suggest', async (c) => {
  const fromCity = String(c.req.query('from_city') ?? c.req.query('city') ?? '').trim() || null;
  const now = new Date();
  const counts: Record<string, number> = {};
  for (const w of ['06:00', '10:00', '14:00']) counts[w] = 0;
  try {
    const q = fromCity
      ? c.env.DB.prepare(`SELECT pickup_window, COUNT(*) n FROM jobs WHERE status IN ('created','rider_assigned','picked_up') AND pickup_window IN ('06:00','10:00','14:00') AND from_city = ?1 AND created_at > datetime('now','-1 day') GROUP BY pickup_window`).bind(fromCity)
      : c.env.DB.prepare(`SELECT pickup_window, COUNT(*) n FROM jobs WHERE status IN ('created','rider_assigned','picked_up') AND pickup_window IN ('06:00','10:00','14:00') AND created_at > datetime('now','-1 day') GROUP BY pickup_window`);
    const { results } = await q.all<any>();
    for (const r of results ?? []) counts[String(r.pickup_window)] = Number(r.n ?? 0);
  } catch {}
  const ranked = ['06:00', '10:00', '14:00'].sort((a, b) => (counts[a] ?? 0) - (counts[b] ?? 0));
  return c.json({
    suggested_window: ranked[0],
    loads: counts,
    reason: 'Least-loaded slot in the recent window improves batching and pickup speed.',
    windows: ranked,
  });
});

/* ---------------------------------- devices -------------------------------- */
// Every signed-in device this account knows about: identity of the session,
// last seen, and the ability to revoke an individual device. JWT validation
// in middleware re-checks the row on every request, so a revoke here kills
// that device's sessions immediately (other devices unaffected).
app.get('/me/devices', async (c) => {
  const phone = c.get('phone') as string | null | undefined;
  if (!phone) return c.json({ error: 'identity_required' }, 401);
  const selfDev = deviceId(c);
  const { results } = await c.env.DB.prepare(
    `SELECT ds.id, ds.device_id, ds.ip, ds.ua, ds.device_name, ds.location, ds.first_seen, ds.last_seen, ds.trusted
       FROM device_sessions ds
      WHERE ds.phone = ?1
      ORDER BY ds.last_seen DESC
      LIMIT 100`,
  ).bind(phone).all<any>();
  const list = (results ?? []).map((r) => ({
    id: r.id,
    device_id: r.device_id,
    ip: r.ip,
    first_seen: r.first_seen,
    last_seen: r.last_seen,
    trusted: Number(r.trusted ?? 1) === 1,
    user_agent: r.ua ?? null,
    device_name: r.device_name ?? null,
    location: r.location ?? null,
    is_current_session: selfDev && r.device_id === selfDev,
  }));
  return c.json({ devices: list, current_device_id: selfDev || null });
});

app.post('/me/devices/revoke-others', async (c) => {
  const phone = c.get('phone') as string | null | undefined;
  if (!phone) return c.json({ error: 'identity_required' }, 401);
  const selfDev = deviceId(c);
  // 'unknown' is not a real device identity (web/legacy clients) — never let it
  // revoke every genuine device from the account.
  if (!selfDev || selfDev === 'unknown') return c.json({ error: 'device_id_required' }, 400);
  await c.env.DB.prepare('UPDATE device_sessions SET trusted = 0 WHERE phone = ?1 AND device_id <> ?2')
    .bind(phone, selfDev).run();
  return c.json({ ok: true });
});

app.post('/me/devices/:id/revoke', async (c) => {
  const phone = c.get('phone') as string | null | undefined;
  if (!phone) return c.json({ error: 'identity_required' }, 401);
  const id = Number(c.req.param('id'));
  if (!Number.isFinite(id)) return c.json({ error: 'invalid id' }, 400);
  const dev = await c.env.DB.prepare(
    'SELECT id, device_id FROM device_sessions WHERE id = ?1 AND phone = ?2',
  ).bind(id, phone).first<{ id: number; device_id: string }>();
  if (!dev) return c.json({ error: 'not found' }, 404);
  // Revoking is deliberate: mark as untrusted so future requests carrying
  // this device_id are rejected. Re-signing with a fresh code creates a new row.
  await c.env.DB.prepare('UPDATE device_sessions SET trusted = 0 WHERE id = ?1').bind(id).run();
  return c.json({ ok: true, revoked_device_id: dev.device_id });
});

/* ------------------------------ session refresh --------------------------- */
// Exchange any live-or-recent JWT for a fresh 30-day one. Unused sessions still
// die on schedule (30 days + 30-day grace); used ones roll forward silently.
// The remember-me flag on the client simply always lets the app do this. A
// password reset still kills everything (token_version check).
app.post('/auth/refresh', async (c) => {
  if (await rateLimited(c, 'refresh', 30)) return c.json({ error: 'too_many_requests' }, 429);
  const bearer = (c.req.header('Authorization') ?? '').replace(/^Bearer\s+/, '');
  if (!bearer) return c.json({ error: 'unauthorized' }, 401);
  const claims = await verifyJwtClaims(bearer, c.env.JWT_SECRET, { allowExpiredWithinSeconds: 30 * 24 * 3600 });
  if (!claims) return c.json({ error: 'unauthorized' }, 401);
  const user = await c.env.DB.prepare(
    'SELECT COALESCE(token_version, 0) AS ver FROM auth_users WHERE phone = ?1',
  ).bind(claims.phone).first<{ ver: number }>();
  const ver = Number(user?.ver ?? 0);
  if (user && Number(claims.ver ?? 0) !== ver) return c.json({ error: 'session_revoked' }, 401);
  const token = await signJwt(claims.phone, c.env.JWT_SECRET, 60 * 60 * 24 * 30, ver, claims.did);
  return c.json({ ok: true, token, phone: claims.phone });
});

/* ------------------------------ phone OTP auth ---------------------------- */
// POST /auth/request {phone}   -> { sent: true, dev_code? }
// POST /auth/verify {phone, code} -> { token }  (JWT, 30 days)
app.post('/auth/request', async (c) => {
  if (await rateLimited(c, 'otp_request', 20)) return c.json({ error: 'too_many_requests' }, 429);
  const b: any = await c.req.json().catch(() => null);
  if (!b) return c.json({ error: 'invalid JSON body' }, 400);
  let phone: string;
  try { phone = normalizeZmPhone(b.phone); } catch (e: any) { return c.json({ error: e.message }, 400); }

  // naive throttle: max 5 codes per phone per hour
  const recent = await c.env.DB.prepare(
    `SELECT COUNT(*) AS n FROM otp_codes WHERE phone = ?1 AND created_at > datetime('now', '-1 hour')`,
  ).bind(phone).first<any>();
  if ((recent?.n ?? 0) >= 5) return c.json({ error: 'too_many_codes_wait_an_hour' }, 429);

  const code = generateOtp();
  const hash = await hashOtp(code, c.env.JWT_SECRET);
  await c.env.DB.batch([
    c.env.DB.prepare('UPDATE otp_codes SET used = 1 WHERE phone = ?1 AND used = 0').bind(phone),
    c.env.DB.prepare(
      `INSERT INTO otp_codes (phone, code_hash, expires_at) VALUES (?1, ?2, datetime('now', '+10 minutes'))`,
    ).bind(phone, hash),
  ]);
  // deliver via Africa's Talking (Carpso account) when AT_* secrets are set;
  // dev mode returns the code in the response
  const sms = await sendSms(c.env, phone,
    `DropOff: your one-time code is ${code}. It expires in 10 minutes. For your security, never share this code with anyone — DropOff staff will never ask for it.`, { transactional: true });
  const devMode = devModeOn(c.env);
  return c.json({
    sent: sms.sent, ...(sms.error ? { sms_error: sms.error } : {}),
    ...(devMode ? { dev_code: code } : {}),
  });
});

app.post('/auth/verify', async (c) => {
  if (await rateLimited(c, 'otp_verify', 30)) return c.json({ error: 'too_many_requests' }, 429);
  const b: any = await c.req.json().catch(() => null);
  if (!b) return c.json({ error: 'invalid JSON body' }, 400);
  let phone: string;
  try { phone = normalizeZmPhone(b.phone); } catch (e: any) { return c.json({ error: e.message }, 400); }
  const row = await c.env.DB.prepare(
    `SELECT id, code_hash, attempts FROM otp_codes
      WHERE phone = ?1 AND used = 0 AND expires_at > datetime('now')
      ORDER BY id DESC LIMIT 1`,
  ).bind(phone).first<any>();
  if (!row) return c.json({ error: 'code_expired_or_missing' }, 401);
  // brute-force guard: 5 wrong attempts burn the code (6-digit space is finite)
  if (Number(row.attempts ?? 0) >= 5) {
    await c.env.DB.prepare('UPDATE otp_codes SET used = 1 WHERE id = ?1').bind(row.id).run();
    return c.json({ error: 'code_expired_or_missing' }, 401);
  }
  const hash = await hashOtp(String(b.code ?? ''), c.env.JWT_SECRET);
  if (hash !== row.code_hash) {
    await c.env.DB.prepare('UPDATE otp_codes SET attempts = attempts + 1 WHERE id = ?1').bind(row.id).run();
    return c.json({ error: 'wrong_code' }, 401);
  }
  await c.env.DB.prepare('UPDATE otp_codes SET used = 1 WHERE id = ?1').bind(row.id).run();
  // A FRESH OTP proves possession of the phone again — if this device was
  // previously revoked, re-trust THIS device id only (owner 2026-11-19: a
  // revoked generic 'unknown' web device locked every new login out).
  const did = deviceId(c);
  if (did && did !== 'unknown') {
    await c.env.DB.prepare(
      'UPDATE device_sessions SET trusted = 1, last_seen = datetime("now") WHERE phone = ?1 AND device_id = ?2',
    ).bind(phone, did).run().catch(() => {});
  }
  // JWT carries the account's current token_version — a password reset bumps it
  // and forces a fresh OTP sign-in; minting ver=0 here used to leave every
  // OTP session instantly revoked (session_revoked on the first request).
  try { await noteDevice(c.env.DB, phone, deviceId(c), clientIp(c), userAgent(c), { deviceName: deviceName(c), location: c.req.header('CF-IPCountry') }); } catch { /* best-effort */ }
  const acct = await c.env.DB.prepare(
    'SELECT COALESCE(token_version, 0) AS ver FROM auth_users WHERE phone = ?1',
  ).bind(phone).first<{ ver: number }>();
  const token = await signJwt(phone, c.env.JWT_SECRET, 60 * 60 * 24 * 30, Number(acct?.ver ?? 0), deviceId(c));
  return c.json({ ok: true, token, phone });
});

/* --------------------------- email + password auth ------------------------ */
// POST /auth/register {email, password, phone, full_name?} -> { token, ... }
// POST /auth/login    {email, password}                    -> { token, ... }
// JWT identity stays the phone so jobs/payments/wallets need no changes.
// Add a debug error surface: when the admin key matches, the raw exception is
// returned so we can see WHAT broke instead of a bare 500. Surfaced only with
// X-Admin-Key — production users see nothing new.
app.onError((err, c) => {
  if (c.req.header('X-Admin-Key') === c.env.ADMIN_AUTH_KEY) {
    return c.json({ error: 'internal_error', debug: String(err?.message ?? err).slice(0, 500) }, 500);
  }
  return c.json({ error: 'internal_error' }, 500);
});

app.post('/auth/register', async (c) => {
  if (await rateLimited(c, 'register', 10)) return c.json({ error: 'too_many_requests' }, 429);
  const b: any = await c.req.json().catch(() => null);
  if (!b) return c.json({ error: 'invalid JSON body' }, 400);

  const email = String(b.email ?? '').trim().toLowerCase();
  const password = String(b.password ?? '');
  const fullName = b.full_name != null ? String(b.full_name).trim() : null;
  if (!isValidEmail(email)) return c.json({ error: 'invalid_email' }, 400);
  if (password.length < 8) return c.json({ error: 'password_too_short_min_8' }, 400);
  let phone: string;
  try { phone = normalizeZmPhone(b.phone); } catch (e: any) { return c.json({ error: e.message }, 400); }

  const clash = await c.env.DB.prepare(
    `SELECT email, phone FROM auth_users WHERE email = ?1 OR phone = ?2 LIMIT 1`,
  ).bind(email, phone).first<any>();
  if (clash) {
    return c.json({ error: 'account_already_exists' }, 409);
  }

  const passwordHash = await hashPassword(password);
  // NOTE: no stored-value row is created for customers — prepayment is per
  // parcel (booking_deposit → job). Only rider/ops COD float rows exist.
  await c.env.DB.prepare(
    `INSERT INTO auth_users (email, password_hash, phone, full_name) VALUES (?1, ?2, ?3, ?4)`,
  ).bind(email, passwordHash, phone, fullName).run();

  try { await noteDevice(c.env.DB, phone, deviceId(c), clientIp(c), userAgent(c), { deviceName: deviceName(c), location: c.req.header('CF-IPCountry') }); } catch { /* best-effort */ }

  // verification email (non-blocking: the account works immediately)
  const verifyLink = await createEmailLink(c, email, 'verify_email');
  const mail = verifyLink ? await sendMail(c.env, {
    to: email, subject: 'Confirm your DropOff email',
    html: verifyEmailHtml(verifyLink), text: `Confirm your DropOff email: ${verifyLink}`,
  }) : { sent: false, error: 'no_link' };

  const token = await signJwt(phone, c.env.JWT_SECRET, 60 * 60 * 24 * 30, 0, deviceId(c));
  const devMode = devModeOn(c.env);
  return c.json({
    ok: true, token, email, phone, full_name: fullName,
    verification_sent: mail.sent, ...(mail.error ? { mail_error: mail.error } : {}),
    ...(devMode && verifyLink ? { dev_verify_link: verifyLink } : {}),
  }, 201);
});

/* -------- email links: verify + reset (token is passed through email) ------ */
async function createEmailLink(
  c: { env: Env; req: { url: string } },
  email: string, kind: 'verify_email' | 'reset_password',
): Promise<string | null> {
  const token = generateEmailToken();
  const hash = await hashOtp(token, c.env.JWT_SECRET);
  const ttl = kind === 'verify_email' ? '+24 hours' : '+1 hour';
  await c.env.DB.batch([
    c.env.DB.prepare('UPDATE email_tokens SET used = 1 WHERE email = ?1 AND kind = ?2 AND used = 0')
      .bind(email, kind),
    c.env.DB.prepare(
      `INSERT INTO email_tokens (email, token_hash, kind, expires_at) VALUES (?1, ?2, ?3, datetime('now', ?4))`,
    ).bind(email, hash, kind, ttl),
  ]);
  // Hono exposes `c.req.url` as a property (Request.url), NOT a function —
  // calling it threw TypeError and 500'd register/forgot/resend.
  const origin = new URL(c.req.url).origin;
  const base = String(c.env.APP_URL ?? '').replace(/\/$/, '') || origin;
  return `${base}/auth/link?k=${kind}&t=${encodeURIComponent(token)}`;
}

/** HTML confirm pages (public GET; the token is the only secret). */
app.get('/auth/link', async (c) => {
  const kind = c.req.query('k');
  const token = c.req.query('t') ?? '';
  const fail = (msg: string) => c.html(`<div style="font-family:sans-serif;max-width:420px;margin:80px auto;text-align:center">
    <h2>DropOff</h2><p>${msg}</p></div>`, 400);
  if (!token || (kind !== 'verify_email' && kind !== 'reset_password')) return fail('Invalid link.');
  const hash = await hashOtp(token, c.env.JWT_SECRET);
  const row = await c.env.DB.prepare(
    `SELECT id, email FROM email_tokens WHERE token_hash = ?1 AND kind = ?2 AND used = 0 AND expires_at > datetime('now')`,
  ).bind(hash, kind).first<any>();
  if (!row) return fail('This link expired or was already used.');

  if (kind === 'verify_email') {
    await c.env.DB.batch([
      c.env.DB.prepare('UPDATE email_tokens SET used = 1 WHERE id = ?1').bind(row.id),
      c.env.DB.prepare('UPDATE auth_users SET email_verified = 1 WHERE email = ?1').bind(row.email),
    ]);
    return c.html(`<div style="font-family:sans-serif;max-width:420px;margin:80px auto;text-align:center">
      <h2>✅ Email confirmed</h2><p>${row.email} is now verified. You can close this page.</p></div>`);
  }

  // reset_password: serve the choose-new-password form
  return c.html(`<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
    <title>DropOff — new password</title>
    <style>body{font-family:sans-serif;max-width:420px;margin:60px auto;padding:0 16px}
    input,button{display:block;width:100%;padding:12px;margin:8px 0;border-radius:10px;border:1px solid #cfd8d4;font-size:15px}
    button{background:#17855f;color:#fff;border:0;font-weight:700}</style></head><body>
    <h2>Choose a new password</h2><p id="msg"></p>
    <form id="f"><input id="p" type="password" minlength="8" placeholder="New password (8+ chars)" required><button>Save password</button></form>
    <script>
    const t = ${JSON.stringify(token)};
    document.getElementById('f').onsubmit = async (e) => {
      e.preventDefault();
      const r = await fetch('/auth/reset', { method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-Api-Key': 'webform' },
        body: JSON.stringify({ token: t, password: document.getElementById('p').value }) });
      const m = document.getElementById('msg');
      m.textContent = r.ok ? 'Password saved — you can sign in in the app now.' : 'Link expired. Request a new one in the app.';
      m.style.color = r.ok ? '#17855f' : '#b3261e';
    };</script></body></html>`);
});

/** The reset form posts here; guarded by the token itself (sent by email). */
app.post('/auth/reset', async (c) => {
  if (await rateLimited(c, 'reset', 10)) return c.json({ error: 'too_many_requests' }, 429);
  const b: any = await c.req.json().catch(() => null);
  const token = String(b?.token ?? '');
  const password = String(b?.password ?? '');
  if (password.length < 8) return c.json({ error: 'password_too_short_min_8' }, 400);
  const hash = await hashOtp(token, c.env.JWT_SECRET);
  const row = await c.env.DB.prepare(
    `SELECT id, email FROM email_tokens WHERE token_hash = ?1 AND kind = 'reset_password'
      AND used = 0 AND expires_at > datetime('now')`,
  ).bind(hash).first<any>();
  if (!row) return c.json({ error: 'link_expired_or_used' }, 401);
  const passwordHash = await hashPassword(password);
  await c.env.DB.batch([
    c.env.DB.prepare('UPDATE email_tokens SET used = 1 WHERE id = ?1').bind(row.id),
    // token_version++ revokes every outstanding JWT for this account (middleware re-checks it)
    c.env.DB.prepare(
      'UPDATE auth_users SET password_hash = ?2, token_version = COALESCE(token_version, 0) + 1 WHERE email = ?1',
    ).bind(row.email, passwordHash),
  ]);
  return c.json({ ok: true });
});

app.post('/auth/forgot', async (c) => {
  if (await rateLimited(c, 'forgot', 10)) return c.json({ error: 'too_many_requests' }, 429);
  const b: any = await c.req.json().catch(() => null);
  const email = String(b?.email ?? '').trim().toLowerCase();
  if (!isValidEmail(email)) return c.json({ error: 'invalid_email' }, 400);
  const user = await c.env.DB.prepare(
    'SELECT email FROM auth_users WHERE email = ?1',
  ).bind(email).first<any>();
  // never leak whether the email exists
  if (!user) return c.json({ ok: true, sent: true });
  const link = await createEmailLink(c, email, 'reset_password');
  if (!link) return c.json({ ok: true, sent: true });
  const mail = await sendMail(c.env, {
    to: email, subject: 'Reset your DropOff password',
    html: resetEmailHtml(link), text: `Reset your DropOff password: ${link} (valid 1 hour)`,
  });
  const devMode = devModeOn(c.env);
  return c.json({ ok: true, sent: mail.sent, ...(mail.error ? { mail_error: mail.error } : {}),
    ...(devMode ? { dev_reset_link: link } : {}) });
});

app.post('/auth/resend-verification', async (c) => {
  if (await rateLimited(c, 'verify', 10)) return c.json({ error: 'too_many_requests' }, 429);
  const b: any = await c.req.json().catch(() => null);
  const email = String(b?.email ?? '').trim().toLowerCase();
  if (!isValidEmail(email)) return c.json({ error: 'invalid_email' }, 400);
  const user = await c.env.DB.prepare(
    'SELECT email_verified FROM auth_users WHERE email = ?1',
  ).bind(email).first<any>();
  if (!user) return c.json({ ok: true, sent: true });
  if (user.email_verified) return c.json({ ok: true, sent: true, already_verified: true });
  const recent = await c.env.DB.prepare(
    `SELECT created_at FROM email_tokens WHERE email = ?1 AND kind = 'verify_email' ORDER BY id DESC LIMIT 1`,
  ).bind(email).first<{ created_at: string }>();
  if (recent) {
    const t = Date.parse(String(recent.created_at).replace(' ', 'T') + 'Z');
    if (!Number.isNaN(t) && Date.now() - t < 60 * 60 * 1000) {
      return c.json({ ok: true, sent: true, already_sent: true,
        resend_allowed_after_minutes: Math.max(1, Math.ceil((60 * 60 * 1000 - (Date.now() - t)) / 60000)) });
    }
  }
  const link = await createEmailLink(c, email, 'verify_email');
  if (!link) return c.json({ ok: true, sent: true });
  const mail = await sendMail(c.env, {
    to: email, subject: 'Confirm your DropOff email',
    html: verifyEmailHtml(link), text: `Confirm your DropOff email: ${link}`,
  });
  const devMode = devModeOn(c.env);
  return c.json({ ok: true, sent: mail.sent, ...(mail.error ? { mail_error: mail.error } : {}),
    ...(devMode ? { dev_verify_link: link } : {}) });
});

app.post('/auth/login', async (c) => {
  if (await rateLimited(c, 'login', 20)) return c.json({ error: 'too_many_requests' }, 429);
  const b: any = await c.req.json().catch(() => null);
  if (!b) return c.json({ error: 'invalid JSON body' }, 400);
  const email = String(b.email ?? '').trim().toLowerCase();
  const password = String(b.password ?? '');
  if (!isValidEmail(email) || !password) return c.json({ error: 'invalid_credentials' }, 401);

  const ip = clientIp(c);
  const ua = userAgent(c);
  const devId = deviceId(c);

  const locked = await lockoutStatus(c.env.DB, email);
  if (locked.lockedUntil) {
    await recordAttempt(c.env.DB, email, false, ip, ua, devId);
    return c.json({ error: 'account_locked', locked_until: locked.lockedUntil }, 429);
  }

  const user = await c.env.DB.prepare(
    `SELECT password_hash, phone, full_name, token_version FROM auth_users WHERE email = ?1`,
  ).bind(email).first<any>();
  const ok = user ? await verifyPassword(password, user.password_hash) : false;
  if (!user) {
    const res = await recordAttempt(c.env.DB, email, false, ip, ua, devId);
    if (res.lockUntilMinutes) {
      await alertOwner(c.env, email, 'brute_force', 'high',
        `${res.lockUntilMinutes}-minute lockout after repeated failed logins for ${email} from ${ip}.`,
        { ip, device: devId, deviceName: deviceName(c), userAgent: ua, email });
    }
    return c.json({ error: 'unknown_email', hint: 'No DropOff account with that email — create one, or sign in with your phone code instead.' }, 401);
  }
  if (!ok) {
    const res = await recordAttempt(c.env.DB, email, false, ip, ua, devId);
    if (res.lockUntilMinutes) {
      await alertOwner(c.env, email, 'brute_force', 'high',
        `${res.lockUntilMinutes}-minute lockout after repeated failed logins for ${email} from ${ip}.`,
        { ip, device: devId, deviceName: deviceName(c), userAgent: ua, email });
    }
    return c.json({ error: 'wrong_password', hint: 'Wrong password for that email — try again.' }, 401);
  }

  // transparent hash upgrade: legacy (lower-iteration) hashes re-mint to the
  // current policy on login, so old accounts self-heal over time
  if (passwordNeedsRehash(user.password_hash)) {
    const upgraded = await hashPassword(password);
    await c.env.DB.prepare('UPDATE auth_users SET password_hash = ?2 WHERE email = ?1')
      .bind(email, upgraded).run();
  }

  // successful login — fingerprint the device and alert the owner on a new device
  await recordAttempt(c.env.DB, email, true, ip, ua, devId);
  const phone = user.phone;
  const dev = await noteDevice(c.env.DB, phone, deviceId(c), ip, userAgent(c), { deviceName: deviceName(c), location: c.req.header('CF-IPCountry') });
  if (dev.isNew) {
    await alertOwner(c.env, phone, 'new_device', 'medium',
      `New device signed in to ${email}.`,
      { ip, device: deviceId(c), deviceName: deviceName(c), userAgent: ua, email });
  }

  const token = await signJwt(phone, c.env.JWT_SECRET, 60 * 60 * 24 * 30, Number(user.token_version ?? 0), deviceId(c));
  return c.json({ ok: true, token, email, phone, full_name: user.full_name });
});

/* -------------------------- security / owner alerts ------------------------ */
app.get('/security/alerts', async (c) => {
  if (!isAdmin(c) && !isOwner(c)) return c.json({ error: 'forbidden' }, 403);
  const onlyUnacked = c.req.query('unacknowledged') === '1';
  const { results } = await c.env.DB.prepare(
    `SELECT id, phone, type, severity, detail, acknowledged, created_at
       FROM security_alerts
       ${onlyUnacked ? 'WHERE acknowledged = 0' : ''}
      ORDER BY created_at DESC LIMIT 100`,
  ).all();
  return c.json({ alerts: results });
});

app.post('/security/alerts/:id/ack', async (c) => {
  if (!isAdmin(c) && !isOwner(c)) return c.json({ error: 'forbidden' }, 403);
  const id = Number(c.req.param('id'));
  if (!Number.isFinite(id)) return c.json({ error: 'invalid id' }, 400);
  const ok = await acknowledgeAlert(c.env.DB, id);
  return c.json({ ok });
});

app.get('/security/sessions', async (c) => {
  if (!isAdmin(c) && !isOwner(c)) return c.json({ error: 'forbidden' }, 403);
  const phone = c.get('phone') as string | undefined;
  const target = phone ?? ownerPhone(c.env);
  if (!target) return c.json({ error: 'owner_phone_not_configured' }, 400);
  const { results } = await c.env.DB.prepare(
    `SELECT id, device_id, ip, first_seen, last_seen, trusted FROM device_sessions
      WHERE phone = ?1 ORDER BY last_seen DESC`,
  ).bind(target).all();
  return c.json({ phone: target, sessions: results });
});

/* -------------------------------- couriers -------------------------------- */
app.get('/couriers', async (c) => {
  const { results } = await c.env.DB.prepare(
    `SELECT co.id, co.name, co.city, co.depot_name, co.lat, co.lng, co.website, co.price_status, co.note, co.logo_url,
            pp.rail AS payment_rail, pp.merchant_id AS payment_merchant, pp.instructions AS payment_instructions,
            (SELECT COUNT(*) FROM quotes q WHERE q.courier_id = co.id) AS quotes_on_file,
            (SELECT COUNT(DISTINCT q.from_city || '→' || q.to_city)
               FROM quotes q WHERE q.courier_id = co.id) AS quote_routes,
            (SELECT MAX(q.updated_at) FROM quotes q WHERE q.courier_id = co.id) AS quotes_updated_at,
            (SELECT ROUND(AVG(stars), 1) FROM ratings r
              WHERE r.target_type = 'courier' AND r.target_key = 'courier:' || co.id AND r.hidden = 0) AS rating_average,
            (SELECT COUNT(*) FROM ratings r
              WHERE r.target_type = 'courier' AND r.target_key = 'courier:' || co.id AND r.hidden = 0) AS rating_count
           FROM couriers co
           LEFT JOIN partner_pos pp ON pp.courier_id = co.id AND pp.active = 1
          WHERE co.active = 1 ORDER BY co.id`,
  ).all();
  return c.json({ couriers: results }, 200, cacheSeconds(300));
});

// Public partner profile: verified rates come straight from the quotes chargebook
app.get('/couriers/:id/profile', async (c) => {
  const id = Number(c.req.param('id'));
  const courier = await c.env.DB.prepare(
    `SELECT id, name, city, depot_name, lat, lng, website, price_status, note
       FROM couriers WHERE id = ?1 AND active = 1`,
  ).bind(id).first();
  if (!courier) return c.json({ error: 'not found' }, 404);
  // NO-QUOTING POLICY (owner directive): the chargebook is internal. The
  // seller-facing profile carries coverage counts and freshness only — never a
  // counter fare. Ops/admin keys may still read the rates for reconciliation.
  const staff = isAdmin(c) || c.get('role') === 'ops';
  let rates: any[] = [];
  if (staff) {
    ({ results: rates } = await c.env.DB.prepare(
      `SELECT from_city, to_city, weight_class, service, counter_price_zmw, updated_at
         FROM quotes WHERE courier_id = ?1 ORDER BY from_city, to_city, service`,
    ).bind(id).all());
  } else {
    ({ results: rates } = await c.env.DB.prepare(
      `SELECT from_city, to_city, weight_class, service, updated_at,
              CASE WHEN updated_at >= datetime('now', '-90 days') THEN 1 ELSE 0 END AS fresh
         FROM quotes WHERE courier_id = ?1 ORDER BY from_city, to_city, service`,
    ).bind(id).all());
  }
  const rating = await c.env.DB.prepare(
    `SELECT COUNT(*) AS count, ROUND(AVG(stars), 2) AS average
       FROM ratings WHERE target_type = 'courier' AND target_key = ?1`,
  ).bind(`courier:${id}`).first<any>();
  const { results: reviews } = await c.env.DB.prepare(
    `SELECT stars, comment, verified, created_at FROM ratings
      WHERE target_type = 'courier' AND target_key = ?1 AND hidden = 0 AND comment IS NOT NULL AND comment <> ''
      ORDER BY id DESC LIMIT 10`,
  ).bind(`courier:${id}`).all();
  const { results: branches } = await c.env.DB.prepare(
    `SELECT name, city, address, lat, lng, phone FROM courier_branches
      WHERE courier_id = ?1 AND active = 1 ORDER BY name`,
  ).bind(id).all();
  return c.json({
    courier, rates,
    rating: { count: rating?.count ?? 0, average: rating?.average ?? null, reviews },
    branches,
  });
});

/* Chargebook — user-typed localities: distinct area names extracted from
 * jobs.pickup_address / jobs.dest_address (letters only, no street numbers or
 * plot digits, stopword-filtered), most-used first. Staff-only; returns
 * area-level fragments (e.g. "Kabulonga") — never street addresses. */
app.get('/admin/localities', async (c) => {
  if (!isAdmin(c) && c.get('role') !== 'ops') return c.json({ error: 'admin_key_required' }, 403);
  const rows = await c.env.DB.prepare(
    `SELECT pickup_address AS a, dest_address AS b FROM jobs
      WHERE (pickup_address IS NOT NULL AND trim(pickup_address) <> '')
         OR (dest_address IS NOT NULL AND trim(dest_address) <> '')
      ORDER BY id DESC LIMIT 300`,
  ).all<any>();
  const counts = new Map<string, number>();
  const STOP = new Set(['plot', 'flat', 'house', 'street', 'road', 'avenue', 'ave', 'st', 'lane', 'no', 'unit', 'suite', 'place', 'estate', 'lusaka', 'zambia', 'city', 'roadside', 'roadoff', 'corner', 'opposite']);
  const add = (words: string[]) => {
    if (words.length === 0) return;
    const f = words.join(' ').replace(/\s+/g, ' ').trim();
    if (f.length < 4 || f.length > 36) return;
    if (!/^[A-Za-z][A-Za-z ]*$/.test(f)) return;
    const key = f.replace(/\b([A-Za-z])/g, (m) => m.toUpperCase());
    counts.set(key, (counts.get(key) ?? 0) + 1);
  };
  for (const r of (rows.results ?? []) as any[]) {
    for (const addr of [r.a, r.b]) {
      if (!addr) continue;
      for (const seg of String(addr).split(',')) {
        const words = String(seg).split(/[^A-Za-z]+/)
          .filter((w) => w.length > 2 && !STOP.has(w.toLowerCase()));
        if (words.length) add(words);
      }
    }
  }
  const localities = [...counts.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, 60)
    .map(([name, n]) => ({ name, n }));
  return c.json({ localities });
});

/* --------------------------------- quotes --------------------------------- */
app.get('/quotes', async (c) => {
  const fromCity = c.req.query('from') ?? 'Lusaka';
  const toCity = c.req.query('to') ?? '';
  const service = c.req.query('service') ?? 'standard';
  const destLat = Number(c.req.query('dest_lat') ?? '0');
  const destLng = Number(c.req.query('dest_lng') ?? '0');
  if (!toCity) return c.json({ error: 'missing "to"' }, 400);

  // Stale-quote decay: rows not reconfirmed in 90+ days no longer count as
  // on-file coverage (depots change tariffs; a rotted rate must never surface).
  const { results } = await c.env.DB.prepare(
    `SELECT q.*, co.id AS courier_id, co.name AS courier_name, co.depot_name
       FROM quotes q JOIN couriers co ON co.id = q.courier_id
      WHERE q.from_city = ?1 AND q.to_city = ?2 AND q.service = ?3
        AND q.updated_at >= datetime('now', '-90 days')`,
  ).bind(fromCity, toCity, service).all();

  // No pickup coords (e.g. the home fare-checker): anchor Lusaka to the depot
  // (0 km → K55 first-mile) instead of falling through to the K70 non-Lusaka
  // default, which under-quoted Lusaka bookings.
  const la = Number.isFinite(destLat) && destLat !== 0 ? destLat : (fromCity === 'Lusaka' ? -15.4255 : 0);
  const ln = Number.isFinite(destLng) && destLng !== 0 ? destLng : (fromCity === 'Lusaka' ? 28.2805 : 0);
  const riderFee = baseRiderFee(fromCity, la, ln);
  const leg2 = c.req.query('leg2') === '1';
  // Last-mile door delivery is priced like first-mile PAYG in the recipient
  // city (distance bands + vehicle multiplier), never a flat fee.
  const leg2Fee = leg2 ? baseRiderFee(toCity, 0, 0, 'motorcycle') : 0;
  const leg2Processing = leg2 ? platformFee(leg2Fee) : 0;
  // NO-QUOTING POLICY (owner directive): sellers are NEVER shown a counter
  // fare — not a number, not a "published rate". Every courier, Platinum
  // included, is "heard at the counter". Only ops/admin keys may read the
  // internal counter price (reconciliation); seller payloads carry our leg
  // pricing only.
  const staff = isAdmin(c) || c.get('role') === 'ops';
    const quotes = (results as any[]).map((r) => {
    const base = r.counter_price_zmw + riderFee;
    const fees = collectionFees(base, riderFee);
    const shared = {
      courier_id: r.courier_id,
      courier_name: r.courier_name,
      depot_name: r.depot_name,
      service: r.service,
      weight_class: r.weight_class,
      counter_fare: 'heard at the courier counter',
      rider_fee_zmw: riderFee,
      // rider payout stays between DropOff and the driver — never quoted to sellers
      leg2_fee_zmw: leg2Fee,
      leg2_processing_fee_zmw: leg2Processing,
      // DropOff NEVER holds partner money — the partner fare is theirs, at the counter.
      dropoff_leg_zmw: round2(riderFee + leg2Fee + leg2Processing), // ours
      dropoff_due_zmw: collectionFees(
        round2(riderFee + leg2Fee + leg2Processing),
        riderFee,
      ).prompt_total_zmw,
      // ONE customer-visible fee line: "processing fee" (platform + momo collect).
      processing_fee_zmw: fees.processing_fee_zmw,
    };
    if (!staff) return shared;
    return {
      ...shared,
      counter_price_zmw: r.counter_price_zmw,
      total_pickup_zmw: base,
      total_pickup_fees_zmw: fees.processing_fee_zmw,
      total_pickup_prompt_zmw: fees.prompt_total_zmw,
      total_with_leg2_zmw: round2(r.counter_price_zmw + riderFee + leg2Fee + leg2Processing),
    };
  });
  return c.json({ quotes });
});

app.get('/cities', async (c) => {
  const { results } = await c.env.DB.prepare(
    `SELECT to_city AS city FROM quotes
      UNION SELECT from_city FROM quotes
      UNION SELECT city FROM couriers WHERE city IS NOT NULL
      ORDER BY city`,
  ).all();
  return c.json({ cities: (results as { city: string }[]).map((r) => r.city) });
});

/* ---------------------------------- jobs ---------------------------------- */
// Identity: a customer JWT ALWAYS books as its own phone — the client cannot
// spoof a sender number. Ops key may specify any phone (rider device/ops console).
app.post('/jobs', async (c) => {
  if (await rateLimited(c, 'job_create', 60)) return c.json({ error: 'too_many_requests' }, 429);
  const b: any = await c.req.json().catch(() => null);
  if (!b) return c.json({ error: 'invalid JSON body' }, 400);
  const idemKey = idemKeyOf(c, b);
  const replay = await replayIdempotent(c, idemKey, 'job', c.get('phone') ?? null);
  if (replay) return replay;
  // promo bookkeeping lives outside the try so the refund in catch can see it
  let promoConsumed = false;
  let promoCode: string | null = null;
  try {
    const senderPhone = c.get('role') === 'ops' && b.sender_phone
      ? normalizeZmPhone(b.sender_phone) : normalizeZmPhone(c.get('phone') ?? b.sender_phone ?? '');
    const recipientPhone = normalizeZmPhone(b.recipient_phone);
    if (!senderPhone) return c.json({ error: 'missing sender identity' }, 401);
    if (c.get('role') !== 'ops') {
      const n24h = (await c.env.DB.prepare(
        `SELECT COUNT(*) AS n FROM jobs WHERE sender_phone = ?1 AND created_at > datetime('now', '-1 day')`,
      ).bind(senderPhone).first<any>())?.n ?? 0;
      if (n24h >= 40) {
        return c.json({ error: 'daily_limit', message: 'Daily booking limit reached — contact support.' }, 429);
      }
    }
    if (!b.courier_id || !b.dest_city) return c.json({ error: 'courier_id and dest_city required' }, 400);

    // No no-show: senders with 3+ pickup strikes in 14 days are parked for
    // ops — ghost bookings (false parcels) are the platform's #1 fraud pattern.
    if (c.get('role') !== 'ops') {
      const strikes = (await c.env.DB.prepare(
        `SELECT COUNT(*) AS n FROM booking_strikes
          WHERE phone = ?1 AND created_at > datetime('now', '-14 days')`,
      ).bind(senderPhone).first<any>())?.n ?? 0;
      if (strikes >= 3) {
        return c.json({
          error: 'booking_on_hold',
          detail: 'Recent missed pickups put booking on hold — contact DropOff support (or have ops clear the strikes).',
        }, 403);
      }
    }

    // PREPAID POLICY (owner directive): every parcel is paid IN ADVANCE at
    // booking — no cash option, no pay-at-pickup. Momo senders get the full
    // prompt at booking; plans are prepaid by their subscription. Riders
    // never handle ride money.
    const staffEyes = c.get('role') === 'ops' || isAdmin(c);
    // Counter-fare gate: the rider fronts the depot fare, the sender repays
    // it through DropOff. A sender with an UNPAID depot receipt settles it
    // before booking again (prepay, no exceptions — the rider is owed).
    if (!staffEyes) {
      const dueCfare = await c.env.DB.prepare(
        `SELECT ref FROM jobs WHERE sender_phone = ?1 AND counter_receipt_zmw IS NOT NULL AND counter_receipt_paid = 0 ORDER BY id DESC LIMIT 1`,
      ).bind(c.get('phone') ?? '').first<any>();
      if (dueCfare) {
        return c.json({
          error: 'counter_fare_due',
          detail: `You have an unpaid depot counter fare on ${dueCfare.ref}. Open Bookings and pay it first — your rider fronted that money and is reimbursed when you do.`,
        }, 409);
      }
    }
    if (b.pay_method === 'cash' && !staffEyes) {
      return c.json({
        error: 'prepaid_required',
        detail: 'DropOff collects every parcel in advance at booking — a prepayment for your parcel delivery (trip price + processing fee), paid by mobile money. The rider never handles your cash. No cash option, no stored credit: you only ever pay what this delivery costs.',
      }, 400);
    }
    const payMethod: string = ['mobile_money', 'cash'].includes(b.pay_method)
      ? b.pay_method : 'mobile_money';
    // Every parcel rides on a SLOT — no untimed jobs. 'now' (instant) is a
    // slot too; the sender must still declare which one they mean.
    if (b.pickup_window == null || String(b.pickup_window).trim() === '') {
      return c.json({
        error: 'pickup_window_required',
        required: ['now', '06:00', '10:00', '14:00', 'tomorrow:06:00'],
        detail: 'Every DropOff parcel is booked onto a Sweep slot — take one from the chips before booking.',
      }, 400);
    }
    let pickupWindow: string = String(b.pickup_window);
    if (!PICKUP_WINDOWS.includes(pickupWindow)) {
      return c.json({ error: `pickup_window must be one of ${PICKUP_WINDOWS.join(', ')}` }, 400);
    }
    // Explicit next-day booking: "tomorrow:06:00" books the FIRST sweep of
    // tomorrow (6:00 — 7:30 AM CAT) even when today's slots are already past.
    // We normalize to the 06:00 sweep for rider bucketing and stamp pickup_at
    // to tomorrow 06:00 CAT so the scheduler and the queue agree.
    const pickupTomorrow = pickupWindow === 'tomorrow:06:00';
    if (pickupTomorrow) pickupWindow = '06:00';
    // Sweep windows have booking cutoffs (06:00?05:30, 10:00?09:30, 14:00?13:30
    // CAT). A late booking never dies — it rolls forward to the next open
    // window (or instant) and the sender is told exactly what happened.
    // TOMORROW BOOKINGS NEVER ROLL (owner bug 2026-11-17: "the 6am is not
    // showing"): 'tomorrow:06:00' was normalized to '06:00' and then rolled
    // against TODAY's 05:30 cutoff — a tomorrow-6am booking made any time
    // after 05:30 (or after 13:30: "instant") got pickup_window='now' while
    // pickup_at stayed tomorrow 06:00, so the rider queue never bucketed it
    // into the 06:00 card (jobs 16 + 19). Tomorrow's cutoff is tomorrow.
    let windowRolledFrom: string | null = null;
    if (pickupWindow !== 'now' && !pickupTomorrow) {
      const cutoffs: Record<string, string> = { '06:00': '05:30', '10:00': '09:30', '14:00': '13:30' };
      const cat = new Date(Date.now() + 2 * 3600_000); // CAT = UTC+2
      const nowHM = `${String(cat.getUTCHours()).padStart(2, '0')}:${String(cat.getUTCMinutes()).padStart(2, '0')}`;
      if (nowHM > cutoffs[pickupWindow]) {
        windowRolledFrom = pickupWindow;
        const next = (['10:00', '14:00'] as const).find((w) => nowHM <= cutoffs[w]);
        pickupWindow = next ?? 'now';
      }
    }
    const fromCity = b.from_city ?? 'Lusaka';
    const weightClass = b.weight_class ?? '0-5kg';
    const service = b.service ?? 'standard';

    // Server-side pricing: quotes table = preferred source of truth — but a
    // quote no one reconfirmed in 90+ days is STALE (depots change tariffs) and
    // is ignored: the first-mile leg books anyway and the fare is heard at the
    // counter. NEVER fabricate or serve a stale intercity fare.
    const quote = await c.env.DB.prepare(
      `SELECT counter_price_zmw FROM quotes
        WHERE courier_id = ?1 AND from_city = ?2 AND to_city = ?3
          AND weight_class = ?4 AND service = ?5
          AND updated_at >= datetime('now', '-90 days')`,
    ).bind(b.courier_id, fromCity, b.dest_city, weightClass, service).first<any>();
    const counterPrice = quote ? Number(quote.counter_price_zmw) : 0;

    // Pack inclusion: EVERY PARCEL counts as one plan slot — two parcels in
    // one trip to the same receiver = two parcels. Cycle = 30 days from
    // activation. A trip is bundled (K0 rider fee) only if all of its parcels
    // still fit under the cap; otherwise the whole trip pays the tier overage.
    const vehicleClass: VehicleClass = VEHICLE_CLASSES.includes(b.vehicle_class)
      ? b.vehicle_class : 'motorcycle';
    const parcels = Math.max(1, Math.min(Number(b.parcels ?? 1) || 1, parcelCapFor(vehicleClass, (b.parcel_size ?? b.weight_class) as string | undefined)));
    // ROUND TRIP = TWO BILLABLE RIDES (owner 2026-11-18): out to the depot and
    // back to the sender. Physical `parcels` count stays 1.
    const isRoundTrip = b.round_trip === 1 || b.round_trip === true;
    const billableRides = parcels * (isRoundTrip ? 2 : 1);
    let riderFee = baseRiderFee(fromCity, Number(b.pickup_lat ?? 0), Number(b.pickup_lng ?? 0), vehicleClass);
    let packInclusion: 'pack' | 'payg' | 'none' = 'none';
    let planUsed = 0;
    let planCap = 0;
    const activeSub = await c.env.DB.prepare(
      `SELECT tier, period_start, period_end FROM subscriptions WHERE phone = ?1 AND status = 'active'
        AND period_end IS NOT NULL AND period_end > datetime('now')`,
    ).bind(senderPhone).first<any>();
    if (activeSub) {
      const packs = await plans(c.env.DB, { forExistingSubscribers: true });
      // Tier overage discount is OFF platform-wide unless the owner re-enables
      // it in the admin console (migration 0061 — the model is already lean).
      const overageOn = flagOn(await getSetting(c.env.DB, 'overage_discount_enabled'));
      const plan = packs[activeSub.tier as PlanTier];
      if (plan && activeSub.period_start && activeSub.period_end) {
        const used = await c.env.DB.prepare(
          `SELECT COALESCE(SUM(parcels * COALESCE(billable_rides, 1)), 0) AS n FROM jobs j
            WHERE sender_phone = ?1
            AND created_at >= ?2 AND created_at < ?3
            AND status NOT IN ('cancelled', 'canceled')
            AND NOT EXISTS (SELECT 1 FROM job_events e WHERE e.job_id = j.id AND e.status IN ('advance_pending', 'prepayment_pending'))
            AND NOT EXISTS (SELECT 1 FROM payments p WHERE p.job_id = j.id AND p.kind IN ('booking_deposit', 'job'))`,
        ).bind(senderPhone, activeSub.period_start, activeSub.period_end).first<any>();
        planUsed = used?.n ?? 0;
        // No rollover: unused parcels expire with the cycle.
        // CAP SEMANTICS (fix 2026-11-15): a DAY-cycle plan (24h pass) caps per
        // day; multi-day plans (weekly/monthly packs) cap per CYCLE — the
        // seller-facing contract in docs/PLANS_BENEFITS.md ("10 parcels / 30
        // days"). The old `parcels_per_day > 0 ? day : cycle` compared
        // cycle-long usage against the day cap and overage-charged monthly
        // subscribers (Silver 1/day column) from their SECOND parcel of the
        // whole month. The day column now governs day-cycles only.
        const cycleDays = Number(plan.cycle_days ?? 30) || 30;
        planCap = cycleDays <= 1
          ? (plan.parcels_per_day || plan.parcels_per_month)
          : (plan.parcels_per_month || plan.parcels_per_day);
        if (planUsed + billableRides <= planCap) {
          riderFee = plan.rider_fee_zmw;
          packInclusion = 'pack';
        } else {
          packInclusion = 'payg';
          riderFee = tierOverageFee(activeSub.tier,
            baseRiderFee(fromCity, Number(b.pickup_lat ?? 0), Number(b.pickup_lng ?? 0), vehicleClass), overageOn ? plan.overage_discount_pct : 0);
        }
      }
    }

    // Last-mile door delivery: same PAYG location pricing as the first mile —
    // recipient-city distance bands — vehicle multiplier (coords when supplied).
    const leg2Fee = b.dest_leg2
      ? baseRiderFee(String(b.dest_city ?? ''), Number(b.dest_lat ?? 0), Number(b.dest_lng ?? 0), vehicleClass)
      : 0;
    const leg2Processing = b.dest_leg2 ? platformFee(leg2Fee) : 0;

    // Optional seller promo — applies only to the DropOff leg, never the
    // partner's counter fare. Pack members already pay nothing per parcel.
    let promoDiscount = 0;
    if (b.promo_code && packInclusion !== 'pack') {
      const code = String(b.promo_code).trim().toUpperCase();
      const promo = await c.env.DB.prepare(
        'SELECT * FROM promo_codes WHERE code = ?1 AND active = 1',
      ).bind(code).first<any>();
      if (!promo) return c.json({ error: 'promo_not_found' }, 400);
      if (promo.expires_at && promo.expires_at <= new Date().toISOString().slice(0, 10)) {
        return c.json({ error: 'promo_expired' }, 400);
      }
      if (promo.applies_tier && promo.applies_tier !== activeSub?.tier) {
        return c.json({ error: `promo_only_for_${promo.applies_tier}` }, 400);
      }
      // Atomically consume a use FIRST (guard on remaining uses) so concurrent
      // bookings with uses_left = 1 cannot both burn it — then book the job.
      const consume = await c.env.DB.prepare(
        `UPDATE promo_codes SET uses_left = uses_left - 1
          WHERE code = ?1 AND active = 1 AND (uses_left IS NULL OR uses_left > 0)`,
      ).bind(code).run();
      if (consume.meta.changes === 0) return c.json({ error: 'promo_exhausted' }, 409);
      promoConsumed = true;
      const leg = riderFee + leg2Fee + leg2Processing;
      promoDiscount = round2((leg * Number(promo.discount_pct)) / 100);
      promoCode = code;
    }

    // partner counter fare is never touched; discount lives on the DropOff leg
    const totals = computeJobTotals({
      counterPriceZmw: counterPrice,
      riderFeeZmw: riderFee,
      leg2FeeZmw: leg2Fee,
      leg2ProcessingFeeZmw: leg2Processing,
      promoDiscountZmw: promoDiscount,
    });

    // Round trip: if the parcel can't travel on, the rider returns it from the
    // depot back to the seller/sender's door (second priced leg, no re-booking).
    let returnLegFee = 0;
    if (isRoundTrip) {
      // Plan packs cover BOTH rides (2 slots deducted); PAYG pays twice -
      // when the client sends no return price, it costs the outbound leg.
      returnLegFee = packInclusion === 'pack' ? 0 : Math.max(0, Number(b.return_leg_fee_zmw ?? 0));
      if (returnLegFee <= 0 && packInclusion !== 'pack') returnLegFee = riderFee;
      if (!b.return_city) return c.json({ error: 'return_city required for round trips' }, 400);
    }

    // Last mile: explicit flag (mirrors dest_leg2 so the UI can toggle it on
    // both pay-as-you-go and tier bookings without guessing).
    const lastMile = b.last_mile != null ? (b.last_mile === 1 || b.last_mile === true ? 1 : 0)
      : (b.dest_leg2 ? 1 : 0);

    // Timed pickup: optional ISO-8601 slot (CAT). Stored as-is; the cron
    // scheduler notifies sender + rider at T-30 / T-10 and flags misses.
    let pickupAt: string | null = null;
    if (b.pickup_at) {
      const ts = new Date(b.pickup_at).toISOString();
      if (ts === 'Invalid Date' || isNaN(new Date(ts).getTime())) {
        return c.json({ error: 'pickup_at must be ISO-8601' }, 400);
      }
      pickupAt = ts;
    }
    if (!pickupAt && pickupTomorrow) {
      // Tomorrow 06:00 CAT (CAT = UTC+2, so tomorrow's date at 04:00 UTC).
      const n = new Date();
      pickupAt = new Date(Date.UTC(n.getUTCFullYear(), n.getUTCMonth(), n.getUTCDate() + 1, 4, 0)).toISOString();
    }

    // Defensive: never 500 on a NOT NULL job column. The app enforces these,
    // but a hand-rolled API call shouldn't either crash or get silent nulls.
    const pickupAddress = b.pickup_address ? String(b.pickup_address).trim() : '';
    const recName = b.recipient_name ? String(b.recipient_name).trim() : '';
    const destCity = b.dest_city ? String(b.dest_city).trim() : '';
    if (!pickupAddress || !recName || !destCity) {
      return c.json({
        error: 'missing_required_fields',
        required: ['pickup_address', 'recipient_name', 'recipient_phone', 'dest_city'].filter((k) => !String(b[k] ?? '').trim()),
      }, 400);
    }
    // Parcel contents are MANDATORY (owner 2026-11-19): we cannot carry illegal
    // or hazardous items, and a blank description hides them from the rider.
    if (String(b.description ?? '').trim().length < 3) {
      return c.json({ error: 'description_required', detail: 'Declare what is inside the parcel (at least 3 characters).' }, 400);
    }
    const forbidden = forbiddenParcelReason(String(b.description ?? ''));
    if (forbidden) {
      return c.json({
        error: 'prohibited_item',
        detail: `DropOff cannot carry ${forbidden}. Book a specialist courier for this parcel.`,
      }, 400);
    }

    const total = round2(totals.total_zmw + returnLegFee);
    const dropOffLeg = totals.dropoff_leg_zmw;
    // COVER REMOVED (owner directive 2026-11-17): DropOff ships NO parcel
    // cover — "we don't want to be held responsible for now". Incoming
    // opt-ins are ignored; the legacy columns are zeroed so old bookings'
    // audit trail keeps its shape.
    const declaredValueZmw = Math.max(0, Number(b.declared_value_zmw ?? 0) || 0);
    const coverOptIn = false;
    const coverTosAccepted = false;
    const coverTosVersion = null;
    const coverTosAcceptedAt = null;
    const cover = { fee_zmw: 0, cap_zmw: 0 };
    const coverStatus = 'none';

    // Wider entropy: date + 5 random chars (the old 2-digit suffix was guessable)
    const ref = `DRO-${new Date().toISOString().slice(2, 10).replace(/-/g, '')}-${randomCode(5)}`;
    // Seller parcel capture: the photo the SELLER takes of the parcel at
    // booking (uploaded via /uploads kind kyc first). The rider mirrors it at
    // the depot drop and /jobs/:ref/parcel-check compares the two.
    const parCell = String(b.parcel_photo_url ?? '').trim();
    const parcelUrl = parCell ? parCell.slice(0, 300) : null;
    if (parCell && !/^\/media\/uploads\/(kyc|selfie)\/[^/]+\/[0-9a-f-]{36}\.(jpg|jpeg|png|webp)$/i.test(parCell)) {
      return c.json({ error: 'bad_parcel_photo_url', detail: 'Upload the parcel photo via /uploads first, then pass its url.' }, 400);
    }
    const senderName = String(b.sender_name ?? '').trim()
      || await senderProfileName(c.env.DB, senderPhone)
      || 'DropOff customer';

    // ONE PARCEL, ONE CHAT (owner directive 2026-11-17: "the chat of the same
    // parcel having many chats instead of one chat for each parcel"): booking
    // the same trip again while the earlier booking is still UNPAID returns
    // the EXISTING job instead of minting a duplicate. This is the rebooking
    // pattern that flooded the inbox with near-identical chats for one
    // physical parcel (the payment looked stuck, so the sender rebooked — the
    // held-payment auto-watch now fixes that at the source). A dedupe hit
    // requires ALL of: same sender + destination city + courier, pickup at
    // the same spot (≤150 m or identical address text), created within 24 h,
    // never paid, NO rider ever assigned, and not canceled/delivered. Paid or
    // dispatched bookings NEVER dedupe — a second real parcel books freely.
    let dedupedJob: any = null;
    {
      const { results: recent } = await c.env.DB.prepare(
        `SELECT id, ref, pickup_address, pickup_lat, pickup_lng, dest_city,
                total_zmw, rider_fee_zmw, parcels, vehicle_class, pickup_window, pickup_at, branch,
                promo_code, promo_discount_zmw
           FROM jobs
          WHERE sender_phone = ?1 AND dest_city = ?2 AND courier_id = ?3
            AND paid = 0 AND rider_id IS NULL
            AND status NOT IN ('canceled', 'delivered', 'ready_for_collection')
            AND created_at > datetime('now', '-24 hours')
          ORDER BY id DESC LIMIT 8`,
      ).bind(senderPhone, b.dest_city, b.courier_id).all<any>();
      const addrNorm = (s: unknown) => String(s ?? '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
      const newAddr = addrNorm(b.pickup_address);
      for (const cand of recent ?? []) {
        if (cand.pickup_lat != null && b.pickup_lat != null) {
          const km = haversine(Number(b.pickup_lat), Number(b.pickup_lng), Number(cand.pickup_lat), Number(cand.pickup_lng));
          if (km <= 0.15) { dedupedJob = cand; break; }
        } else if (newAddr && addrNorm(cand.pickup_address) === newAddr) {
          dedupedJob = cand;
          break;
        }
      }
    }
    if (dedupedJob) {
      const dupTotal = Number(dedupedJob.total_zmw ?? 0);
      const dupPrompt = round2(dupTotal + MOMO_COLLECTION_FEE);
      const payload = {
        ok: true, ref: dedupedJob.ref, job_id: dedupedJob.id,
        total_zmw: dupTotal, dropoff_leg_zmw: Number(dedupedJob.rider_fee_zmw ?? 0),
        promo_code: dedupedJob.promo_code, promo_discount_zmw: dedupedJob.promo_discount_zmw,
        fees: {} as Record<string, never>, // display-only; the held screen prices from prompt_total
        prompt_total_zmw: dupPrompt,
        deposit_required: true, deposit_amount_zmw: dupPrompt,
        deposit_reference: `adv-${dedupedJob.ref}`,
        deposit_init_failed: false,
        pack_inclusion: 'payg', pay_method: 'mobile_money',
        auto_assigned: null, tracking_token: null, tracking_url: null,
        parcels: Number(dedupedJob.parcels ?? 1), vehicle_class: dedupedJob.vehicle_class,
        plan_used: null, plan_cap: null, plan_inclusion: 'payg',
        pickup_window: dedupedJob.pickup_window, window_rolled_from: null,
        pickup_tomorrow: false, pickup_at: dedupedJob.pickup_at,
        branch: dedupedJob.branch,
        deduped: true,
      };
      if (idemKey) await saveIdempotent(c.env, idemKey, 'job', senderPhone, 200, payload);
      return c.json(payload, 200);
    }

    const { meta } = await c.env.DB.prepare(
      `INSERT INTO jobs (ref, sender_phone, sender_name, pickup_address, pickup_lat, pickup_lng,
         courier_id, recipient_name, recipient_phone, dest_city, dest_city_to_depot,
         description, weight_class, service, counter_price_zmw, rider_fee_zmw, leg2_fee_zmw,
         leg2_processing_fee_zmw, total_zmw,
         promo_code, promo_discount_zmw,
         pickup_time, pickup_window, pay_method,
         round_trip, return_city, return_address, return_leg_fee_zmw, pickup_at, last_mile, billable_rides,
         parcels, vehicle_class, branch, from_city, parcel_photo_url,
         declared_value_zmw, cover_opt_in, cover_fee_zmw, cover_status, cover_tos_accepted, cover_tos_version, cover_tos_accepted_at)
       VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16,?17,?18,?19,?20,?21,?22,?23,?24,?25,?26,?27,?28,?29,?30,?31,?32,?33,?34,?35,?36,?37,?38,?39,?40,?41,?42,?43)`,
    ).bind(
      ref, senderPhone, senderName, pickupAddress, b.pickup_lat ?? null, b.pickup_lng ?? null,
      b.courier_id, b.recipient_name, recipientPhone, b.dest_city, b.dest_leg2 ? 1 : 0,
      b.description ?? '', weightClass, service, counterPrice, riderFee, leg2Fee, leg2Processing, total,
      promoCode, promoDiscount,
      b.pickup_time ?? pickupWindow, pickupWindow, payMethod,
      isRoundTrip ? 1 : 0, b.return_city ?? null, b.return_address ?? null, returnLegFee,
      pickupAt, lastMile,
      parcels, vehicleClass,
      b.branch ? String(b.branch).trim().slice(0, 80) : null,
      fromCity,
      parcelUrl,
      declaredValueZmw > 0 ? declaredValueZmw : null, coverOptIn ? 1 : 0, cover.fee_zmw, coverStatus,
      coverTosAccepted ? 1 : 0, coverTosVersion, coverTosAcceptedAt,
    ).run();

    if (promoCode) {
      // promo_uses bookkeeping (the use itself was already consumed atomically)
      await c.env.DB.prepare(
        'INSERT INTO promo_uses (code, phone, job_id) VALUES (?1, ?2, ?3)',
      ).bind(promoCode, senderPhone, meta.last_row_id).run();
    }

    await c.env.DB.prepare(
      'INSERT INTO job_events (job_id, status, note) VALUES (?1, ?2, ?3)',
    ).bind(meta.last_row_id, 'created', 'Job created').run();
    if (windowRolledFrom) {
      const fromLabel = windowRolledFrom === 'now' ? 'instant' : (SWEEP_SLOTS[windowRolledFrom]?.range ?? windowRolledFrom);
      const toLabel = pickupWindow === 'now' ? 'instant' : (SWEEP_SLOTS[pickupWindow]?.range ?? pickupWindow);
      await c.env.DB.prepare(
        'INSERT INTO job_events (job_id, status, note) VALUES (?1, ?2, ?3)',
      ).bind(meta.last_row_id, 'window_rolled',
        `The ${fromLabel} window had closed — moved to the ${toLabel} slot automatically`).run();
    }

    if (pickupTomorrow) {
      await c.env.DB.prepare(
        'INSERT INTO job_events (job_id, status, note) VALUES (?1, ?2, ?3)',
      ).bind(meta.last_row_id, 'pickup_tomorrow',
        'Slot booked for tomorrow 6:00 — 7:30 AM sweep (after today\'s last window)').run();
    }

    c.executionCtx.waitUntil(
      scoreJobFraud(c.env, senderPhone, meta.last_row_id, ref, recipientPhone, b.pickup_address, total)
        .catch(() => {}),
    );

    // Recipient tracking link: NOT minted here anymore (owner directive
    // 2026-11-15) — the mint moved below the deposit decision so a
    // payment-held booking never holds a live tracking token at all.

    if (pickupAt) {
      await c.env.DB.prepare(
        `INSERT INTO scheduled_pickups (job_ref, phone, rider_phone, pickup_at, status)
          VALUES (?1, ?2, ?3, ?4, 'pending')`,
      ).bind(ref, senderPhone, recipientPhone, pickupAt).run();
    }

    // Referral reward: deferred to rewardReferralOnBooking below / at
    // settlement (owner directive 2026-11-15) — a payment-held booking that
    // never pays must never mint the referrer's promo.

    // Fees ride on the payer leg only: pack parcels carry no per-parcel fees
    // (the pack renewal prompt charges the processing fee on the pack price),
    // ride-float top-ups carry them once per deposit. The customer NEVER pays
    // for the rider's payout — that lives inside the rider's 10% take. Pack
    // and promo math happens on the DropOff leg ONLY — the partner fare is theirs.
    const feeBase = collectionFees(dropOffLeg, packInclusion === 'pack' ? null : riderFee);

    // ADVANCE-PAYMENT GATE (owner directive): pay-as-you-go momo senders pay
    // the FULL DropOff leg prompt at booking — rider dispatch waits for the
    // approval. Plan members already paid via their subscription (skip);
    // legacy 'wallet' pay-method rows are no longer issued (customers hold no
    // stored value), and ops/superadmin bookings ride free.
    let depositRequired = false;
    let depositAmount = 0;
    let depositRef: string | null = null;
    let depositInitFailed = false;
    // PREPAID CAP (compliance): the customer prompt is the server-computed
    // quote for THIS parcel only — trip price + processing + momo legs. It can
    // never exceed what the delivery costs, there is no free-form top-up for
    // customers, and these balances pay for DropOff's own service only — never
    // cash-out, never third-party acceptance. See docs/PAYMENT_COMPLIANCE.md.
    if (!staffEyes && packInclusion !== 'pack' && payMethod === 'mobile_money') {
      depositRequired = true;
      depositAmount = feeBase.prompt_total_zmw; // full DropOff leg + processing + momo leg
      depositRef = `adv-${ref}`;
      const init = await lipilaCollect(c.env, senderPhone, depositAmount, depositRef,
        `DropOff advance ${ref}`.replace(/[^A-Za-z0-9 ]/g, ' ')).catch(() => ({ ok: false } as any));
      if (init.ok) {
        await c.env.DB.prepare(
          `INSERT INTO payments (job_id, phone, provider, amount_zmw, credit_zmw, platform_fee_zmw,
             lipila_fee_zmw, lipila_reference, status, channel, kind)
           VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, 'pending', 'merchant', 'booking_deposit')`,
        ).bind(meta.last_row_id, senderPhone, providerFromPhone(senderPhone), depositAmount,
          depositAmount, round2(platformFee(dropOffLeg)), MOMO_COLLECTION_FEE,
          init.lipilaReference ?? depositRef).run();
      } else {
        // PREPAY, NO EXCEPTIONS (owner directive): if the provider is down the
        // booking is HELD, never dispatched on credit. No prompt went out, so
        // there is nothing to approve — the job waits unassigned with a
        // prepayment_pending event; the sender taps Pay now (POST /payments
        // kind=job) which issues a fresh prompt and dispatches on approval.
        depositRequired = false;
        depositInitFailed = true;
        await c.env.DB.prepare(
          `INSERT INTO job_events (job_id, status, note) VALUES (?1, 'prepayment_pending', ?2)`,
        ).bind(meta.last_row_id,
          'Prepayment could not start (mobile-money provider unreachable). Booking HELD — no rider is assigned until the DropOff leg is prepaid. Retry payment to dispatch.').run();
        c.executionCtx.waitUntil(
          sendSms(c.env, senderPhone,
          `DropOff: booking ${ref} is HELD. The momo prompt failed. Open Bookings and tap Pay now to dispatch your rider.`, { transactional: true }).catch(() => {}),
        );
      }
    }
    if (depositRequired) {
      await c.env.DB.prepare(
        'INSERT INTO job_events (job_id, status, note) VALUES (?1, ?2, ?3)',
      ).bind(meta.last_row_id, 'advance_pending',
        'Advance payment prompt sent at booking — the FULL DropOff leg. The rider is dispatched the moment it is approved; no pay-at-pickup, no rider cash handling.').run();
      c.executionCtx.waitUntil(
        sendSms(c.env, senderPhone,
        `DropOff: approve the K${depositAmount.toFixed(2)} prepayment for ${ref} (trip price + processing fee). Your rider dispatches the moment you approve and never handles cash.`, { transactional: true }).catch(() => {}),
      );
    }

    // Referral reward only for bookings that are actually going live — held
    // bookings earn theirs at settlement (settlePaymentSuccess calls the same
    // helper). At most one reward per referred booking, guarded atomically.
    if (!depositRequired && !depositInitFailed) {
      try { await rewardReferralOnBooking(c.env, meta.last_row_id, senderPhone); } catch { /* referral logging must never block a booking */ }
    }

    // Recipient tracking link (no account): minted ONLY when the parcel is
    // actually moving (owner directive 2026-11-15) — pack-covered and staff
    // bookings dispatch immediately, so they mint here; a payment-held
    // booking mints NOTHING until settlement (sendRecipientTrackingSms), so
    // no held parcel ever carries a live tracking link (waybill/share).
    let trackingToken: string | null = null;
    if (!depositRequired && !depositInitFailed) {
      trackingToken = await issueTrackingToken(c.env, meta.last_row_id, ref, recipientPhone);
    }
    const trackUrl = trackingToken ? trackingUrl(c.env, trackingToken) : '';

    // Handover proof + recipient tracking SMS (owner directive 2026-11-15):
    // sent ONLY when the parcel is actually moving. Pack-covered and staff
    // bookings dispatch immediately, so the recipient gets the tracking link
    // + handover code right here. A payment-held booking (prompt waiting, or
    // the provider was down) gets BOTH at settlement — settlePaymentSuccess
    // → sendRecipientTrackingSms — never before the money lands. The OTP is
    // generated at that moment too (only its hash is stored, so it cannot be
    // re-sent from booking time).
    if (!depositRequired && !depositInitFailed) {
      // SPLIT + CITY-GATED CODES (owner decisions 2026-11-18): the sender's
      // PICKUP code is independent of the recipient's DOOR code, and the
      // recipient's code is minted ONLY for intercity collections (Ndola) —
      // Lusaka recipients track live in-app and confirm receipt instead.
      const intercity = isIntercity(b.from_city, b.dest_city);
      const pickupOtp = String(Math.floor(1000 + Math.random() * 9000));
      const doorOtp = intercity ? String(Math.floor(1000 + Math.random() * 9000)) : null;
      await c.env.DB.prepare(
        'UPDATE jobs SET delivery_otp_hash = ?2, pickup_otp_hash = ?3 WHERE ref = ?1',
      ).bind(ref,
        doorOtp ? await handoverOtpHash(c.env, ref, doorOtp) : null,
        await handoverOtpHash(c.env, ref, pickupOtp)).run();
      c.executionCtx.waitUntil(
        sendSms(c.env, recipientPhone, intercity
          ? `DropOff: parcel ${ref}. Track: ${trackUrl}. Code ${doorOtp} - never share before handover.`
          : `DropOff: parcel ${ref}. Track: ${trackUrl} - follow it live in the DropOff app and confirm receipt when it lands.`,
          { transactional: true }).catch(() => {}),
      );
      // PICKUP CODE FOR THE SENDER (owner directive 2026-11-17): the rider
      // confirms the collection with the SENDER's own code.
      c.executionCtx.waitUntil(
        sendSms(c.env, senderPhone,
        `DropOff: parcel ${ref}. Pickup code ${pickupOtp} - show it to your rider when they collect.`, { transactional: true }).catch(() => {}),
      );
    }

    // Smart auto-assign: bookings get a rider immediately unless a deposit is
    // waiting (momo) or the caller opts out. Coords are optional — dispatch
    // falls back to the Lusaka centre when the sender typed an address only.
    let autoAssigned: { rider_id: number; rider: string; photo_url: string | null; eta_minutes: number; km: number } | null = null;
    if (!depositRequired && !depositInitFailed && b.auto_assign !== false) {
      const pick = await dispatchToNearestRider(c.env, ref);
      if (pick) {
        autoAssigned = { rider_id: pick.rider.id, rider: pick.rider.full_name, photo_url: pick.rider.photo_url ?? null, eta_minutes: pick.eta_minutes, km: pick.km };
      }
    }

    const payload = {
      ok: true, ref, job_id: meta.last_row_id, total_zmw: total,
      dropoff_leg_zmw: dropOffLeg,
      promo_code: promoCode, promo_discount_zmw: promoDiscount,
      // Strip rider payout — driver earnings are never shown to sellers.
      fees: (() => {
        const { rider_payout_zmw: _omit, ...customerFees } = feeBase as any;
        return customerFees;
      })(),
      prompt_total_zmw: feeBase.prompt_total_zmw,
      deposit_required: depositRequired,
      deposit_amount_zmw: depositRequired ? depositAmount : 0,
      deposit_reference: depositRef,
      deposit_init_failed: depositInitFailed,
      pack_inclusion: packInclusion, pay_method: payMethod,
      auto_assigned: autoAssigned,
      tracking_token: trackingToken, tracking_url: trackingToken ? trackUrl : null,
      parcels, vehicle_class: vehicleClass,
      plan_used: activeSub ? planUsed + (packInclusion === 'pack' ? parcels : 0) : null,
      plan_cap: activeSub ? planCap : null,
      plan_inclusion: packInclusion,
      pickup_window: pickupWindow,
      window_rolled_from: windowRolledFrom,
      pickup_tomorrow: pickupTomorrow,
      pickup_at: pickupAt,
      branch: b.branch ? String(b.branch).trim().slice(0, 80) : null,
    };
    await saveIdempotent(c.env, idemKey, 'job', senderPhone, 201, payload);
    return c.json(payload, 201);
  } catch (e: any) {
    // refund a promo use we happened to consume before the booking failed
    if (promoConsumed && promoCode) {
      await c.env.DB.prepare(
        `UPDATE promo_codes SET uses_left = COALESCE(uses_left, 0) + 1 WHERE code = ?1`,
      ).bind(promoCode).run().catch(() => {});
    }
    return c.json({ error: e.message ?? 'bad request' }, 400);
  }
});

// Collection from a courier point ? recipient's door (Lusaka only).
// The parcel already arrived at the courier depot; a rider picks it up there
// and runs the last mile. No counter fare and no branch choice — the rider
// collects from the nominated point. Pricing = last-mile zone fare + its
// processing fee (same model as the door-delivery add-on).
app.post('/collections', async (c) => {
  const phone = c.get('phone');
  const role = c.get('role');
  if (!phone) return c.json({ error: 'sign_in_required' }, 401);
  if (role === 'rider') return c.json({ error: 'forbidden' }, 403);
  const b: any = await c.req.json().catch(() => null);
  if (!b) return c.json({ error: 'invalid JSON body' }, 400);
  const courierId = Number(b.courier_id);
  if (!courierId) return c.json({ error: 'courier_id required' }, 400);
  const courier = await c.env.DB.prepare('SELECT id, name FROM couriers WHERE id = ?1').bind(courierId).first<any>();
  if (!courier) return c.json({ error: 'courier_not_found' }, 404);
  const phoneName = await senderProfileName(c.env.DB, phone);
  const point = String(b.point ?? '').trim();
  if (point.length < 2) return c.json({ error: 'collection_point_required' }, 400);
  const recipientName = String(b.recipient_name ?? '').trim();
  const recipientPhone = normalizeZmPhone(String(b.recipient_phone ?? ''));
  if (recipientName.length < 2) return c.json({ error: 'recipient_name_required' }, 400);
  if (!recipientPhone) return c.json({ error: 'invalid_recipient_phone' }, 400);
  const destAddress = String(b.dest_address ?? '').trim();
  if (destAddress.length < 4) return c.json({ error: 'dest_address_required' }, 400);
  const windowReq = String(b.pickup_window ?? '10:00');
  // "tomorrow:06:00" books the first sweep of the NEXT day even though today's
  // windows are already past — normalized to the 06:00 sweep + tomorrow 06:00 CAT pickup_at.
  const pickupTomorrow = windowReq === 'tomorrow:06:00';
  const window = pickupTomorrow ? '06:00' : windowReq;
  if (!['06:00', '10:00', '14:00'].includes(window)) return c.json({ error: 'pickup_window must be 06:00, 10:00 or 14:00' }, 400);
  let pickupAt: string | null = null;
  if (pickupTomorrow) {
    const n = new Date();
    pickupAt = new Date(Date.UTC(n.getUTCFullYear(), n.getUTCMonth(), n.getUTCDate() + 1, 4, 0)).toISOString();
  }
  const vehicleClass: VehicleClass = VEHICLE_CLASSES.includes(b.vehicle_class) ? b.vehicle_class : 'motorcycle';
  const parcels = Math.max(1, Math.min(Number(b.parcels ?? 1) || 1, parcelCapFor(vehicleClass, (b.parcel_size ?? b.weight_class) as string | undefined)));
  // PREPAID POLICY (owner directive): no cash — everything is paid in advance
  // at booking by momo; plans ride prepaid via their subscription.
  const payMethod = b.pay_method === 'cash' ? 'cash' : 'mobile_money';
  const staffEyes = c.get('role') === 'ops' || isAdmin(c);
  if (payMethod === 'cash' && !staffEyes) {
    return c.json({
      error: 'prepaid_required',
      detail: 'DropOff collects every parcel in advance at booking. Pay by mobile money — the rider never handles your cash.',
    }, 400);
  }

  // Plan inclusion: every parcel counts as one plan slot (two parcels in one
  // trip = two slots). A trip rides free (rider fee K0) while it fits the cap.
  // Cycle = the plan's cycle (rider_daily = 1 day, weekly = 7, monthly = 30).
  // Any normal in-app delivery - door pickup, courier-depot collection, the
  // optional last mile - draws from the same allowance.
  const activeSub = await c.env.DB.prepare(
    `SELECT tier, period_start, period_end FROM subscriptions WHERE phone = ?1 AND status = 'active'
       AND period_end IS NOT NULL AND period_end > datetime('now')`,
  ).bind(phone).first<any>();
  let riderFee = baseRiderFee('Lusaka', 0, 0, vehicleClass);
  let planInclusion: 'pack' | 'payg' | 'none' = 'none';
  let planUsed = 0;
  let planCap = 0;
  const billableRides = parcels; // collections are single-leg
  if (activeSub) {
    const planCatalogue = await plans(c.env.DB, { forExistingSubscribers: true });
    const overageOn = flagOn(await getSetting(c.env.DB, 'overage_discount_enabled'));
    const plan = planCatalogue[activeSub.tier as PlanTier];
    if (plan && activeSub.period_start && activeSub.period_end) {
      const used = await c.env.DB.prepare(
        `SELECT COALESCE(SUM(parcels * COALESCE(billable_rides, 1)), 0) AS n FROM jobs j
            WHERE sender_phone = ?1
            AND created_at >= ?2 AND created_at < ?3
            AND status NOT IN ('cancelled', 'canceled')
            AND NOT EXISTS (SELECT 1 FROM job_events e WHERE e.job_id = j.id AND e.status IN ('advance_pending', 'prepayment_pending'))
            AND NOT EXISTS (SELECT 1 FROM payments p WHERE p.job_id = j.id AND p.kind IN ('booking_deposit', 'job'))`,
      ).bind(phone, activeSub.period_start, activeSub.period_end).first<any>();
      planUsed = used?.n ?? 0;
      // CAP SEMANTICS (fix 2026-11-15): day-cycles cap per day, multi-day
      // plans cap per cycle (see the /jobs booking note — the old daily-cap
      // comparison overage-charged monthly subscribers from parcel 2).
      const cycleDays = Number(plan.cycle_days ?? 30) || 30;
      planCap = cycleDays <= 1
        ? (plan.parcels_per_day || plan.parcels_per_month)
        : (plan.parcels_per_month || plan.parcels_per_day);
      if (planUsed + billableRides <= planCap) {
        riderFee = plan.rider_fee_zmw;
        planInclusion = 'pack';
      } else {
        planInclusion = 'payg';
        riderFee = tierOverageFee(activeSub.tier, baseRiderFee('Lusaka', 0, 0, vehicleClass), overageOn ? plan.overage_discount_pct : 0);
      }
    }
  }
  const processing = round2(platformFee(riderFee));
  const total = round2(riderFee + processing);
  const ref = `DRO-${new Date().toISOString().slice(2, 10).replace(/-/g, '')}-${randomCode(5)}`;
  const senderName = String(b.sender_name ?? '').trim() || phoneName || 'DropOff customer';
  // Seller parcel capture at booking (same evidence chain as /jobs bookings).
  const parCell = String(b.parcel_photo_url ?? '').trim();
  const parcelUrl = parCell ? parCell.slice(0, 300) : null;
  if (parCell && !/^\/media\/uploads\/(kyc|selfie)\/[^/]+\/[0-9a-f-]{36}\.(jpg|jpeg|png|webp)$/i.test(parCell)) {
    return c.json({ error: 'bad_parcel_photo_url', detail: 'Upload the parcel photo via /uploads first, then pass its url.' }, 400);
  }
  const declaredValueZmw = Math.max(0, Number(b.declared_value_zmw ?? 0) || 0);
  // COVER REMOVED (owner directive 2026-11-17) — see POST /jobs. No cover is
  // quoted or charged anywhere; legacy columns stay zeroed.
  const coverOptIn = false;
  const coverTosAccepted = false;
  const coverTosVersion = null;
  const coverTosAcceptedAt = null;
  const cover = { fee_zmw: 0, cap_zmw: 0 };
  const coverStatus = 'none';
  // ADVANCE-PAYMENT GATE (owner directive): every momo collection is paid IN
  // ADVANCE at booking — full rider leg + processing + momo leg. Plan members
  // (in-cap, rider fee K0) ride their prepaid subscription. Deposit settles
  // the parcel's prepayment directly (job marked paid on approval) and
  // dispatches the rider.
  const depositRequired = !staffEyes && planInclusion !== 'pack' && riderFee > 0;
  const depositAmount = round2(riderFee + round2(platformFee(riderFee)) + MOMO_COLLECTION_FEE);
  let depositRef: string | null = null;
  let depositInitFailed = false;
  // Handover proof (anti-false-parcel): minted at booking for trips that move
  // immediately (plan-covered / staff). A prepayment-held collection gets its
  // code + tracking SMS at settlement instead (owner directive 2026-11-15) —
  // the recipient must never hold tracking for a booking whose prepayment is
  // still pending, so the hash stays NULL until the money lands.
  const deliveryOtp = depositRequired ? null : String(Math.floor(1000 + Math.random() * 9000)); // handover proof (anti-false-parcel)
  const deliveryOtpHash = deliveryOtp ? await handoverOtpHash(c.env, ref, deliveryOtp) : null;
  const { meta } = await c.env.DB.prepare(
    `INSERT INTO jobs (ref, sender_phone, sender_name, pickup_address, courier_id,
       recipient_name, recipient_phone, dest_city, dest_address, description, weight_class,
       counter_price_zmw, rider_fee_zmw, leg2_processing_fee_zmw, total_zmw,
       pickup_time, pickup_window, pickup_at, pay_method, last_mile, parcels, vehicle_class, from_city, delivery_otp_hash, parcel_photo_url,
       declared_value_zmw, cover_opt_in, cover_fee_zmw, cover_status, cover_tos_accepted, cover_tos_version, cover_tos_accepted_at)
     VALUES (?1,?2,?3,?4,?5,?6,?7,'Lusaka',?8,?9,?10,0,?11,?12,?13,?14,?14,?15,?16,1,?17,?18,'Lusaka',?19,?20,?21,?22,?23,?24,?25,?26,?27)`,
  ).bind(
    ref, phone, senderName, point, courierId,
    recipientName, recipientPhone, destAddress,
    String(b.description ?? 'Collection').trim().slice(0, 200), String(b.weight_class ?? '0-5kg'),
    riderFee, processing, total, window, pickupAt, payMethod, parcels, vehicleClass,
    deliveryOtpHash, parcelUrl,
    declaredValueZmw > 0 ? declaredValueZmw : null, coverOptIn ? 1 : 0, cover.fee_zmw, coverStatus,
    coverTosAccepted ? 1 : 0, coverTosVersion, coverTosAcceptedAt,
  ).run();

  await c.env.DB.prepare(
    `INSERT INTO job_events (job_id, status, note) VALUES (?1, 'created', ?2)`,
  ).bind(meta.last_row_id, `Collection booked from ${courier.name} (${point}) - rider delivers to ${recipientName}'s door`).run();

  if (pickupTomorrow) {
    await c.env.DB.prepare(
      `INSERT INTO job_events (job_id, status, note) VALUES (?1, 'pickup_tomorrow', ?2)`,
    ).bind(meta.last_row_id, 'Slot booked for tomorrow 6:00 — 7:30 AM sweep (after today\'s last window)').run();
  }

  // Handover proof SMS — the recipient (never the sender) holds the code.
  // PAYMENT-HELD collections send nothing to the recipient yet (owner
  // directive 2026-11-15): the code + tracking link go out at settlement,
  // once the prepayment is approved.
  if (!depositRequired) {
    c.executionCtx.waitUntil(
      sendSms(c.env, recipientPhone,
      `DropOff: collection booked at ${courier.name}. Show code ${deliveryOtp} to your rider at handover - never share it before the parcel is in your hands.`, { transactional: true }).catch(() => {}),
    );
  }

  // Ghost-booking deposit for first ride collections (same as /jobs bookings)
  if (depositRequired) {
    const depInit = await lipilaCollect(c.env, phone, depositAmount,
      `dep-${ref}`, `DropOff deposit ${ref}`.replace(/[^A-Za-z0-9 ]/g, ' ')).catch(() => ({ ok: false } as any));
    if (depInit.ok) {
      depositRef = `dep-${ref}`;
      await c.env.DB.prepare(
        `INSERT INTO payments (job_id, phone, provider, amount_zmw, credit_zmw, platform_fee_zmw,
           lipila_fee_zmw, lipila_reference, status, channel, kind)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, 'pending', 'merchant', 'booking_deposit')`,
      ).bind(meta.last_row_id, phone, providerFromPhone(phone), depositAmount, depositAmount,
        round2(platformFee(riderFee)), MOMO_COLLECTION_FEE, depInit.lipilaReference ?? depositRef).run();
      await c.env.DB.prepare(
        'INSERT INTO job_events (job_id, status, note) VALUES (?1, ?2, ?3)',
      ).bind(meta.last_row_id, 'advance_pending',
        'Advance payment prompt sent at booking — the FULL DropOff leg for this collection. The rider is dispatched the moment it is approved.').run();
      await sendSms(c.env, phone,
        `DropOff: approve the K${depositAmount.toFixed(2)} prepayment for ${ref} (trip price + processing fee). Your rider dispatches the moment you approve and never handles cash.`, { transactional: true }).catch(() => {});
    } else {
      // PREPAY, NO EXCEPTIONS: provider down → the collection is HELD, never
      // dispatched on credit. Sender retries payment to dispatch.
      depositInitFailed = true;
      await c.env.DB.prepare(
        `INSERT INTO job_events (job_id, status, note) VALUES (?1, 'prepayment_pending', ?2)`,
      ).bind(meta.last_row_id,
        'Prepayment could not start (mobile-money provider unreachable). Collection HELD — no rider is assigned until the DropOff leg is prepaid. Retry payment to dispatch.').run();
      c.executionCtx.waitUntil(
        sendSms(c.env, phone,
        `DropOff: collection ${ref} is HELD. The momo prompt failed. Open Bookings and tap Pay now to dispatch your rider.`, { transactional: true }).catch(() => {}),
      );
    }
  }

  return c.json({
    ok: true,
    ref,
    courier_id: courierId,
    courier_name: courier.name,
    pickup_window: window,
    rider_fee_zmw: riderFee,
    processing_fee_zmw: processing,
    total_zmw: total,
    deposit_required: depositRequired,
    deposit_amount_zmw: depositRequired ? depositAmount : 0,
    deposit_reference: depositRef,
    deposit_init_failed: depositInitFailed,
    parcels,
    vehicle_class: vehicleClass,
    pay_method: payMethod,
    plan_inclusion: planInclusion,
    plan_used: activeSub ? planUsed + (planInclusion === 'pack' ? parcels : 0) : null,
    plan_cap: activeSub ? planCap : null,
  }, 201);
});

// Sellers can test a promo code before booking (public, read-only)
app.get('/promo/check', async (c) => {
  const code = String(c.req.query('code') ?? '').trim().toUpperCase();
  if (!code) return c.json({ error: 'missing code' }, 400);
  const promo = await c.env.DB.prepare('SELECT code, discount_pct, note, applies_tier, uses_left, expires_at, active FROM promo_codes WHERE code = ?1').bind(code).first<any>();
  if (!promo || !promo.active) return c.json({ error: 'promo_not_found' }, 404);
  if (promo.expires_at && promo.expires_at <= new Date().toISOString().slice(0, 10)) return c.json({ error: 'promo_expired' }, 410);
  if (promo.uses_left != null && Number(promo.uses_left) <= 0) return c.json({ error: 'promo_exhausted' }, 409);
  return c.json({ ok: true, code: promo.code, discount_pct: promo.discount_pct, note: promo.note, applies_tier: promo.applies_tier });
});

app.get('/jobs', async (c) => {
  const role = c.get('role');
  let phone: string | null = null;
  if (role === 'customer' || role === 'partner' || role === 'rider') {
    // Partners list only their own jobs; riders have no reason to browse the
    // whole book — everyone non-staff is pinned to their OWN phone.
    phone = c.get('phone') ?? '';
  } else if (role === 'ops' || role === 'admin' || role === 'cfo' || isAdmin(c)) {
    // ops/admin/cfo: must specify whose jobs
    try { phone = normalizeZmPhone(c.req.query('phone') ?? ''); } catch { phone = ''; }
  } else {
    phone = ''; // everyone else: no listing at all
  }
  if (!phone) return c.json({ error: 'missing phone' }, 400);
  const limit = pageLimit(c.req.query('limit'));
  const after = c.req.query('after') ? Number(c.req.query('after')) : null;
  const afterBind = after != null && Number.isFinite(after) ? after : 9007199254740991;
  const { results } = await c.env.DB.prepare(
    `SELECT j.*, co.name AS courier_name, co.depot_name, r.full_name AS rider_name, r.phone AS rider_phone,
            (SELECT status FROM job_events ev WHERE ev.job_id = j.id ORDER BY ev.id DESC LIMIT 1) AS last_event,
            (SELECT paused_at IS NOT NULL FROM payments p WHERE p.job_id = j.id AND p.kind = 'booking_deposit' AND p.status = 'pending' ORDER BY p.id DESC LIMIT 1) AS reprompt_paused
       FROM jobs j JOIN couriers co ON co.id = j.courier_id
        LEFT JOIN riders r ON r.id = j.rider_id
      WHERE j.sender_phone = ?1 AND j.id < ?2
         AND COALESCE(j.status, '') != 'deleted'
      ORDER BY j.id DESC LIMIT ?3`,
  ).bind(phone, afterBind, limit + 1).all();
  const hasMore = results.length > limit;
  const page = hasMore ? results.slice(0, -1) : results;
  // NO-QUOTING POLICY: never ship counter-fare or full-total numbers to the
  // job list — counter fare stays at the counter; total includes it.
  // Counter RECEIPT flow (owner directive 2026-11-12): the sender sees the
  // actual written receipt amount AND the real rider-submitted receipt photo
  // on their OWN job (that is what they owe) — the app keeps it blurred/
  // locked until they pay. Partners never see any of it.
  const role2 = c.get('role');
  if (role2 === 'customer' || role2 === 'partner' || role2 === 'rider') {
    for (const j of page as any[]) {
      // Multi-receipt depot drops: ship the parsed array to sender/rider;
      // partners never see any counter-receipt data.
      const receipts = j.counter_receipts_json ? JSON.parse(j.counter_receipts_json) : null;
      delete j.counter_receipts_json;
      delete j.counter_price_zmw;
      delete j.total_zmw;
      delete j.rider_payout_zmw;
      if (role2 === 'partner') {
        delete j.counter_receipt_zmw;
        delete j.counter_receipt_paid;
        delete j.counter_receipt_url;
      } else if (receipts) {
        j.counter_receipts = receipts;
      }
    }
  }
  return c.json({
    jobs: page,
    next_after: hasMore ? Number(page[page.length - 1]?.id ?? 0) : undefined,
    has_more: hasMore,
  }, 200, cacheSeconds(30));
});

app.get('/jobs/:ref', async (c) => {
  const job = await c.env.DB.prepare(
    `SELECT j.*, co.name AS courier_name, co.depot_name, r.phone AS rider_phone FROM jobs j
       JOIN couriers co ON co.id = j.courier_id
       LEFT JOIN riders r ON r.id = j.rider_id WHERE j.ref = ?1`,
  ).bind(c.req.param('ref')).first() as any;
  if (!job) return c.json({ error: 'not found' }, 404);
  const phone = c.get('phone');
  const role = c.get('role');
  // Customers AND partners are participants-or-strangers: only the job's own
  // sender/recipient (or staff) may read it. Partners must not read other
  // sellers' money fields or internal event notes.
  const isStaff = role === 'ops' || isAdmin(c);
  const isParticipant = phone === job.sender_phone || phone === job.recipient_phone;
  if (!isStaff && !isParticipant) {
    return c.json({ error: 'not found' }, 404); // no existence leak
  }

  let payload: any = { ...job };
  if (!isStaff) {
    // internal fields no seller or recipient should ever read
    for (const k of ['fraud_score', 'review_required']) delete payload[k];
    // NO-QUOTING POLICY (owner directive): the counter fare is the depot's
    // business, transacted at the counter — a seller never reads any number
    // for it, and `total_zmw` includes it, so both stay staff-only.
    // Counter RECEIPT exception (owner directive 2026-11-12): the sender of
    // the job reads the actual written receipt amount AND the real
    // rider-submitted receipt photo (the app locks it visually until they
    // pay); partners and strangers read none of it.
    for (const k of ['counter_price_zmw', 'total_zmw']) delete payload[k];
    if (phone !== job.sender_phone) {
      for (const k of ['counter_receipt_zmw', 'counter_receipt_paid', 'counter_receipt_url']) delete payload[k];
      delete payload.counter_receipts_json;
    } else {
      // Multi-receipt depot drops: the parsed receipt list rides with the job.
      payload.counter_receipts = job.counter_receipts_json ? JSON.parse(job.counter_receipts_json) : null;
      delete payload.counter_receipts_json;
    }
    if (phone === job.recipient_phone && phone !== job.sender_phone) {
      // recipient sees delivery status only — never the sender's money side
      for (const k of ['rider_fee_zmw', 'leg2_fee_zmw',
        'leg2_processing_fee_zmw', 'promo_code', 'promo_discount_zmw',
        'paid', 'pay_method', 'sender_name', 'sender_phone', 'pickup_address']) {
        delete payload[k];
      }
    }
    // Never leak driver payout language to sellers either.
    for (const k of ['rider_payout_zmw']) delete payload[k];
  }

  // Timeline: public statuses only; notes stay internal for non-participants.
  const { results: events } = await c.env.DB.prepare(
    'SELECT status, note, created_at FROM job_events WHERE job_id = ?1 ORDER BY id',
  ).bind(job.id).all();
  const safeEvents = (events as any[])
    .filter((e) => ['created', 'rider_assigned', 'picked_up', 'at_depot', 'departed',
      'arrived', 'delivered', 'ready_for_collection', 'partner_confirmed'].includes(e.status))
    .map((e) => (!isStaff ? { status: e.status, created_at: e.created_at } : e));
  return c.json({ job: payload, events: safeEvents });
});

// Live location for a participant (sender/recipient) or ops/admin (fleet view)
app.get('/jobs/:ref/live', async (c) => {
  const job = await c.env.DB.prepare(
    `SELECT j.*, r.phone AS rider_phone, r.last_lat, r.last_lng, r.last_seen_at,
            co.lat AS depot_lat, co.lng AS depot_lng, co.depot_name
       FROM jobs j
       LEFT JOIN riders r ON r.id = j.rider_id
       LEFT JOIN couriers co ON co.id = j.courier_id
      WHERE j.ref = ?1`,
  ).bind(c.req.param('ref')).first() as any;
  if (!job) return c.json({ error: 'not found' }, 404);
  const liveRole = c.get('role');
  const liveStaff = liveRole === 'ops' || isAdmin(c);
  const livePhone = c.get('phone');
  if (!liveStaff && livePhone !== job.sender_phone && livePhone !== job.recipient_phone) {
    return c.json({ error: 'not found' }, 404);
  }
  if (!job.rider_phone) return c.json({ has_rider: false });
  // TRACKING WINDOW (owner directive 2026-11-17): live rider tracking runs
  // from dispatch — on the way to the pickup — through the collected leg,
  // and ENDS at the depot drop ('delivered') or when the parcel waits at the
  // destination depot for collection ('ready_for_collection').
  if (['delivered', 'ready_for_collection'].includes(String(job.status ?? ''))) {
    return c.json({ has_rider: true, location: null, ended: true, note: 'Tracking ended — the parcel is at the depot.' });
  }
  if (job.last_lat == null) {
    return c.json({ has_rider: true, location: null, note: 'rider has not shared location yet' });
  }
  return c.json({
    has_rider: true,
    lat: job.last_lat,
    lng: job.last_lng,
    seen_at: job.last_seen_at,
    pickup_lat: job.pickup_lat ?? null,
    pickup_lng: job.pickup_lng ?? null,
    // END of the visible leg: the courier's depot branch — real stored
    // coordinates (jobs carry no destination GPS, only an address string),
    // so the tracking map can draw where the journey ends (owner 2026-11-18).
    depot_lat: job.depot_lat ?? null,
    depot_lng: job.depot_lng ?? null,
    depot_name: job.depot_name ?? null,
    maps_link: `https://maps.google.com/?q=${job.last_lat},${job.last_lng}`,
  });
});

/* ------------------- rider: order waybill + resend PIN --------------------- */
// Both serve the ASSIGNED rider (the stop-sheet owner) plus ops/admin. The
// rider gets the full order sheet (waybill) with every money field stripped,
// and can re-fire the 4-digit pickup-code SMS when the sender's booking SMS
// never landed — otherwise the pickup can never be verified at all
// (owner directive 2026-11-18).

// The rider's waybill: everything needed to act (contacts, both addresses,
// depot/branch, parcels) — never any money field.
app.get('/jobs/:ref/waybill', async (c) => {
  const job = await c.env.DB.prepare(
    `SELECT j.ref, j.created_at, j.pickup_at, j.pickup_window, j.eta_minutes, j.status,
            j.parcels, j.last_mile, j.description, j.weight_class, j.rider_id,
            j.pickup_address, j.dest_address, j.from_city, j.dest_city, j.branch,
            j.sender_name, j.sender_phone, j.recipient_name, j.recipient_phone,
            co.name AS courier_name, co.depot_name
       FROM jobs j JOIN couriers co ON co.id = j.courier_id
      WHERE j.ref = ?1`,
  ).bind(c.req.param('ref')).first() as any;
  if (!job) return c.json({ error: 'not found' }, 404);
  const wbStaff = c.get('role') === 'ops' || isAdmin(c);
  if (!wbStaff) {
    const phone = c.get('phone') ?? '';
    if (!phone) return c.json({ error: 'identity_required' }, 401);
    const rider = await c.env.DB.prepare(
      'SELECT id FROM riders WHERE phone = ?1 AND active = 1',
    ).bind(phone).first<any>();
    // Only the ASSIGNED rider reads the sheet — strangers get the same 404 as
    // a missing job, so there is no existence leak either way.
    if (!rider || job.rider_id !== rider.id) return c.json({ error: 'not found' }, 404);
  }
  return c.json({ waybill: {
    ref: job.ref,
    created_at: job.created_at,
    pickup_at: job.pickup_at,
    pickup_window: job.pickup_window,
    eta_minutes: job.eta_minutes,
    status: job.status,
    parcels: job.parcels,
    last_mile: job.last_mile,
    description: job.description,
    weight_class: job.weight_class,
    pickup_address: job.pickup_address,
    dest_address: job.dest_address,
    from_city: job.from_city,
    dest_city: job.dest_city,
    branch: job.branch,
    sender_name: job.sender_name,
    sender_phone: job.sender_phone,
    recipient_name: job.recipient_name,
    recipient_phone: job.recipient_phone,
    courier_name: job.courier_name,
    depot_name: job.depot_name,
  } });
});

// RESEND THE 4-DIGIT PICKUP CODE (owner 2026-11-18): the code is stored
// HASHED, so "resend" generates a FRESH code, overwrites the hash and re-fires
// BOTH copies — sender's pickup code and recipient's handover code — so the
// chain stays consistent (the recipient's tracking SMS carried the old one).
// Max 3 resends per job per day; the attempt is logged as a job event either
// way so a dead gateway shows up in ops.
app.post('/jobs/:ref/resend-pin', async (c) => {
  const job = await c.env.DB.prepare(
    `SELECT id, ref, status, sender_phone, recipient_phone, rider_id, from_city, dest_city, delivery_otp_hash
       FROM jobs WHERE ref = ?1`,
  ).bind(c.req.param('ref')).first() as any;
  if (!job) return c.json({ error: 'not found' }, 404);
  const rpStaff = c.get('role') === 'ops' || isAdmin(c);
  if (!rpStaff) {
    const phone = c.get('phone') ?? '';
    if (!phone) return c.json({ error: 'identity_required' }, 401);
    const rider = await c.env.DB.prepare(
      'SELECT id FROM riders WHERE phone = ?1 AND active = 1',
    ).bind(phone).first<any>();
    if (!rider || job.rider_id !== rider.id) return c.json({ error: 'not found' }, 404);
  }
  const st = String(job.status ?? '');
  if (['picked_up', 'at_depot', 'departed', 'arrived', 'delivered',
    'ready_for_collection', 'canceled', 'cancelled'].includes(st)) {
    return c.json({ error: 'not_needed',
      detail: 'This job no longer needs a pickup code — the pickup already moved.' }, 409);
  }
  const cnt = await c.env.DB.prepare(
    `SELECT COUNT(*) AS n FROM job_events
      WHERE job_id = ?1 AND status = 'resend_pin'
        AND created_at > datetime('now', '-1 day')`,
  ).bind(job.id).first<any>();
  if (Number(cnt?.n ?? 0) >= 3) {
    return c.json({ error: 'rate_limited',
      detail: 'Resend limit reached for today (3). DropOff support has been flagged — call ops.' }, 429);
  }
  // Fresh codes (the old ones die with the hash overwrites) + zero both
  // attempt locks, so a rider locked out by wrong codes gets a clean chance.
  // SPLIT CODES (2026-11-18): sender and recipient each get their OWN fresh
  // secret — the pickup code never opens the door.
  const pickupOtp = String(Math.floor(1000 + Math.random() * 9000));
  // Door code only for intercity collections (owner 2026-11-18): same-city
  // recipients have no PIN — the resend simply clears any stale door hash.
  const intercity = isIntercity(job.from_city, job.dest_city);
  const doorOtp = intercity ? String(Math.floor(1000 + Math.random() * 9000)) : null;
  await c.env.DB.prepare(
    `UPDATE jobs SET pickup_otp_hash = ?2, delivery_otp_hash = ?3,
            pickup_otp_attempts = 0, delivery_otp_attempts = 0 WHERE id = ?1`,
  ).bind(job.id,
    await handoverOtpHash(c.env, job.ref, pickupOtp),
    doorOtp ? await handoverOtpHash(c.env, job.ref, doorOtp) : null).run();
  const sends: Promise<{ sent: boolean }>[] = [];
  if (job.sender_phone) {
    sends.push(sendSms(c.env, job.sender_phone,
      `DropOff: parcel ${job.ref}. Pickup code ${pickupOtp} - show it to your rider when they collect.`,
      { transactional: true }));
  }
  if (doorOtp && job.recipient_phone && job.recipient_phone !== job.sender_phone) {
    sends.push(sendSms(c.env, job.recipient_phone,
      `DropOff: parcel ${job.ref}. Code ${doorOtp} - never share before handover.`,
      { transactional: true }));
  }
  const results = await Promise.allSettled(sends);
  const sentAny = results.some((r) => r.status === 'fulfilled' && r.value?.sent === true);
  await c.env.DB.prepare(
    `INSERT INTO job_events (job_id, status, note) VALUES (?1, 'resend_pin', ?2)`,
  ).bind(job.id, sentAny
    ? `Pickup code re-sent at the rider's request — sender ${job.sender_phone ?? 'n/a'}, recipient ${job.recipient_phone ?? 'n/a'}.`
    : `Pickup code RESEND FAILED at the SMS gateway — sender ${job.sender_phone ?? 'n/a'}. Ops: check the AT account / sms logs.`)
    .run().catch(() => {});
  return c.json({
    ok: true,
    resent: true,
    sent: sentAny,
    sender_sent: results[0]?.status === 'fulfilled' ? results[0].value?.sent === true : false,
    detail: sentAny
      ? 'New 4-digit code sent — ask the sender to read their FRESH SMS (older codes no longer work).'
      : 'The SMS gateway rejected the resend — the attempt is logged; call DropOff support.',
  });
});

/* ------------------------ admin: live-order seed sweep ---------------------- */
// SEED SWEEP (owner directive 2026-11-18): old test-era orders miss details
// the new flows depend on — pickup pins, codes, tracking links, sweep times.
// One admin tap completes every LIVE job with mechanically-derivable data
// (never invented fares or addresses): geocodes the REAL typed pickup
// address, sets a missing sweep time to the booking time, REGENERATES both
// split codes (attempt locks reset), mints a tracking token, and texts each
// phone its OWN fresh code so the whole chain can be tested end to end.
// Canceled and terminal jobs are never touched. ?dry=1 previews only.
// PROHIBITED PARCEL CONTENT (owner 2026-11-18): DHL/UPS/FedEx publish the same
// restricted categories; online lookup was unavailable in this environment on
// 2026-11-19, so this uses the industry-standard published list: illegal drugs,
// weapons/firearms, explosives, flammables/fuel, corrosives/poisons,
// radioactive material, live animals and human remains. Sender MUST declare
// contents so these never enter a rider's bag.
const FORBIDDEN_PARCEL: Array<[RegExp, string]> = [
  [/\b(cocaine|heroin|meth(amphetamine)?|marijuana|cannabis|weed|ecstasy|narcotics?|illegal drugs?)\b/i, 'illegal drugs'],
  [/\b(firearm|firearms|guns?|rifles?|pistols?|ammunition|bullets?|grenades?)\b/i, 'firearms/ammunition'],
  [/\b(explosives?|dynamite|fireworks|bombs?)\b/i, 'explosives'],
  [/\b(petrol|gasoline|diesel|fuel|kerosene|lighter fluid|flammable)\b/i, 'flammable fuel'],
  [/\b(poison|cyanide|arsenic|acid|corrosive|toxic chemicals?)\b/i, 'poisons/corrosives'],
  [/\b(radioactive|uranium|plutonium)\b/i, 'radioactive material'],
  [/\b(live animals?|snakes?|birds?|puppies|kittens)\b/i, 'live animals'],
  [/\b(human remains?|corpse|body parts?)\b/i, 'human remains'],
];
function forbiddenParcelReason(description: string): string | null {
  for (const [pattern, label] of FORBIDDEN_PARCEL) if (pattern.test(description)) return label;
  return null;
}

async function geocodePickup(address: string, city: string): Promise<{ lat: number; lng: number } | null> {
  const q = [address, city, 'Zambia'].map((s) => `${s ?? ''}`.trim()).filter(Boolean).join(', ');
  if (q.replace(/[,\s]/g, '').length < 6) return null;
  try {
    const res = await fetch(
      `https://nominatim.openstreetmap.org/search?format=json&limit=1&countrycodes=zm&q=${encodeURIComponent(q)}`,
      { headers: { 'User-Agent': 'DropOff seed sweep (ops)', 'Accept-Language': 'en' } });
    if (!res.ok) return null;
    const rows = await res.json() as Array<{ lat: string; lon: string }>;
    const hit = rows?.[0];
    const lat = Number(hit?.lat);
    const lng = Number(hit?.lon);
    return Number.isFinite(lat) && Number.isFinite(lng) && (lat !== 0 || lng !== 0) ? { lat, lng } : null;
  } catch {
    return null;
  }
}

app.post('/admin/jobs/seed-sweep', async (c) => {
  if (!isAdmin(c) && c.get('role') !== 'ops') return c.json({ error: 'forbidden' }, 403);
  const dry = c.req.query('dry') === '1';
  const { results: jobs } = await c.env.DB.prepare(
    `SELECT id, ref, status, last_mile, sender_phone, recipient_phone,
            pickup_address, from_city, dest_city, pickup_lat, pickup_lng, pickup_at, created_at
       FROM jobs
      WHERE COALESCE(status,'') NOT IN ('canceled','cancelled','deleted','delivered','ready_for_collection')
      ORDER BY id LIMIT 50`,
  ).all<any>();
  const report: any[] = [];
  for (const job of jobs ?? []) {
    const out: any = { ref: job.ref, status: job.status };
    // 1) Missing pickup pin — geocode the REAL typed address (never invent).
    if (job.pickup_lat == null && `${job.pickup_address ?? ''}`.trim()) {
      const hit = await geocodePickup(`${job.pickup_address}`, `${job.from_city ?? ''}`);
      if (hit) {
        out.geocoded = { lat: hit.lat, lng: hit.lng };
        if (!dry) {
          await c.env.DB.prepare(
            'UPDATE jobs SET pickup_lat = ?2, pickup_lng = ?3 WHERE id = ?1',
          ).bind(job.id, hit.lat, hit.lng).run();
        }
      } else out.geocode_failed = true;
      await new Promise((r) => setTimeout(r, 1200)); // Nominatim 1 req/s policy
    }
    // 2) Missing sweep time — the booking time is the truthful floor (keeps
    //    the TODAY card and sweep bucketing sane for old test rows).
    if (job.pickup_at == null && job.created_at) {
      out.pickup_at_set = job.created_at;
      if (!dry) {
        await c.env.DB.prepare(
          'UPDATE jobs SET pickup_at = ?2 WHERE id = ?1',
        ).bind(job.id, job.created_at).run();
      }
    }
    // 3) Fresh SPLIT + CITY-GATED codes: sender pickup code always; the
    //    recipient door code only for intercity collections — same-city rows
    //    get any stale door hash CLEARED (Lusaka recipients have no PIN).
    const intercity = isIntercity(job.from_city, job.dest_city);
    const pickupOtp = String(Math.floor(1000 + Math.random() * 9000));
    const doorOtp = intercity ? String(Math.floor(1000 + Math.random() * 9000)) : null;
    if (!dry) {
      await c.env.DB.prepare(
        `UPDATE jobs SET pickup_otp_hash = ?2, delivery_otp_hash = ?3,
                pickup_otp_attempts = 0, delivery_otp_attempts = 0 WHERE id = ?1`,
      ).bind(job.id,
        await handoverOtpHash(c.env, job.ref, pickupOtp),
        doorOtp ? await handoverOtpHash(c.env, job.ref, doorOtp) : null).run();
    }
    // 4) Tracking link for the recipient's SMS.
    let token: string | null = null;
    if (!dry) {
      const t = await c.env.DB.prepare(
        'SELECT token FROM tracking_tokens WHERE job_id = ?1 ORDER BY created_at DESC LIMIT 1',
      ).bind(job.id).first<any>();
      token = t?.token ?? await issueTrackingToken(c.env, job.id, job.ref,
        job.recipient_phone ?? job.sender_phone ?? job.ref);
    }
    const trackUrl = token ? trackingUrl(c.env, token) : null;
    // 5) SMS each phone its OWN code. In-hand jobs skip the sender (the
    //    pickup already happened); their recipient still gets the door code.
    const inHand = ['picked_up', 'at_depot', 'departed', 'arrived'].includes(String(job.status ?? ''));
    if (!dry) {
      if (!inHand && job.sender_phone) {
        const r = await sendSms(c.env, job.sender_phone,
          `DropOff: parcel ${job.ref}. Pickup code ${pickupOtp} - show it to your rider when they collect.`,
          { transactional: true });
        out.sender_sms = r.sent ? 'sent' : `failed:${r.error ?? '?'}`;
      }
      if (job.recipient_phone) {
        const r = await sendSms(c.env, job.recipient_phone,
          intercity
            ? `DropOff: parcel ${job.ref}.${trackUrl ? ` Track: ${trackUrl}.` : ''} Code ${doorOtp} - never share before handover.`
            : `DropOff: parcel ${job.ref}.${trackUrl ? ` Track: ${trackUrl}.` : ''} Follow it live in the DropOff app and confirm receipt when it lands.`,
          { transactional: true });
        out.recipient_sms = r.sent ? 'sent' : `failed:${r.error ?? '?'}`;
      }
      await c.env.DB.prepare(
        `INSERT INTO job_events (job_id, status, note) VALUES (?1, 'seed_sweep', ?2)`,
      ).bind(job.id, 'Seed sweep: pins/codes/links refreshed for testing — fresh codes texted to each phone.')
        .run().catch(() => {});
    } else {
      out.would_send = { sender: !inHand && !!job.sender_phone, recipient: !!job.recipient_phone };
    }
    report.push(out);
  }
  return c.json({ ok: true, dry, jobs: report.length, report });
});

/* ------------------------- rider app: act on a job ------------------------- */
// Auth: ops key, admin key, or the ASSIGNED rider's own JWT. Statuses move
// pickup -> picked_up -> at_depot -> departed -> arrived -> delivered/ready.
// Also logs waiting minutes (billed) and COD collections (credited to rider float).
app.post('/jobs/:ref/events', async (c) => {
  const b: any = await c.req.json().catch(() => null);
  if (!b) return c.json({ error: 'invalid JSON body' }, 400);
  const status = b.status as string | undefined;
  const allowed = ['rider_assigned', 'picked_up', 'at_depot', 'departed', 'arrived', 'delivered', 'ready_for_collection'];
  if (status !== undefined && !allowed.includes(status)) return c.json({ error: 'bad status' }, 400);

  const job = await c.env.DB.prepare(
    `SELECT j.id, j.ref, j.sender_phone, j.recipient_phone, j.rider_id, j.counter_price_zmw, j.rider_fee_zmw, j.leg2_fee_zmw,
            j.leg2_processing_fee_zmw, j.promo_discount_zmw,
            j.counter_receipt_zmw, j.counter_receipt_paid,
            j.total_zmw, j.wait_minutes, j.wait_fee_zmw, j.pay_method, j.paid,
            j.courier_id, j.from_city, j.dest_city, j.weight_class, j.service,
            j.dropoff_photo_url, j.pod_pickup_url, j.pod_delivery_url,
            r.phone AS rider_phone
       FROM jobs j LEFT JOIN riders r ON r.id = j.rider_id
      WHERE j.ref = ?1`,
  ).bind(c.req.param('ref')).first() as any;
  if (!job) return c.json({ error: 'not found' }, 404);

  // authorization: ops/admin keys, or the assigned rider's own JWT.
  // Applies to every authenticated role — not just 'customer' — so a rider,
  // partner or ops-key device cannot tamper with another rider's job.
  const phone = c.get('phone') ?? null;
  const isAdminKey = isAdmin(c);
  const isOpsKey = c.get('role') === 'ops';
  if (!isAdminKey && !isOpsKey) {
    const isAssigned = job.rider_phone && phone === job.rider_phone;
    if (!isAssigned) return c.json({ error: 'only the assigned rider can act on this job' }, 403);
  }

  const dbStatements: D1PreparedStatement[] = [];
  // True when a door delivery's recipient code was just verified — depot
  // drops (the counter flow) never carry a recipient code.
  let doorVerified = false;
  // Set when the rider just submitted a depot receipt — drives the sender's
  // pay-your-counter-fare notification after the batch lands.
  let counterReceiptDue: number | null = null;

  // HANDOVER PROOF (anti-false-parcel): marking a job 'delivered' requires the
  // recipient's 4-digit DropOff code (SMSed to them at booking). Ops/admin keys
  // bypass it for depot-side reconciliation; legacy jobs without a hash pass
  // through (their booking predates the gate).
  if (status === 'delivered' && !isAdminKey && !isOpsKey) {
    const otpRow = await c.env.DB.prepare(
      'SELECT delivery_otp_hash, delivery_otp_attempts, last_mile FROM jobs WHERE id = ?1',
    ).bind(job.id).first<any>();
    // Only DOOR deliveries (last mile to the recipient) need the code — depot
    // drops already carry AI-checked depot photo evidence.
    doorVerified = false;
    if (otpRow?.delivery_otp_hash && Number(otpRow.last_mile) === 1) {
      if ((otpRow.delivery_otp_attempts ?? 0) >= 8) {
        await addStrike(c.env, phone ?? '', job.id, 'otp_abuse'); // the wrong-code device earns a strike
        return c.json({ error: 'otp_locked', detail: 'Too many wrong codes — contact DropOff support to unlock this delivery.' }, 429);
      }
      const otp = String(b.otp ?? '').replace(/\D/g, '');
      const want = String(otpRow.delivery_otp_hash);
      const got = otp.length === 4 ? await handoverOtpHash(c.env, c.req.param('ref'), otp) : '';
      const match = got.length === want.length && got.split('').every((ch, i) => ch === want[i]);
      if (!match) {
        await c.env.DB.prepare(
          'UPDATE jobs SET delivery_otp_attempts = COALESCE(delivery_otp_attempts, 0) + 1 WHERE id = ?1',
        ).bind(job.id).run();
        return c.json({
          error: 'otp_required',
          detail: 'Ask the recipient for their 4-digit DropOff code — it is in the handover SMS. It protects both of you against false parcels.',
        }, 403);
      }
      doorVerified = true;
      dbStatements.push(c.env.DB.prepare('UPDATE jobs SET delivery_otp_attempts = 0 WHERE id = ?1').bind(job.id));
    } else if (Number(otpRow?.last_mile) === 1) {
      // Lusaka-first: no SMS door code was minted. A registered recipient may
      // set their OWN 4-digit door PIN — the rider verifies it at the door.
      const rec = await c.env.DB.prepare(
        'SELECT door_pin_hash FROM auth_users WHERE phone = ?1',
      ).bind(job.recipient_phone).first<any>();
      if (rec?.door_pin_hash) {
        if ((otpRow?.delivery_otp_attempts ?? 0) >= 8) {
          await addStrike(c.env, phone ?? '', job.id, 'otp_abuse');
          return c.json({ error: 'otp_locked', detail: 'Too many wrong door PINs — contact DropOff support.' }, 429);
        }
        const pin = String(b.otp ?? '').replace(/\D/g, '');
        const got = pin.length === 4 ? await hashOtp(pin, c.env.JWT_SECRET) : '';
        if (got !== rec.door_pin_hash) {
          await c.env.DB.prepare(
            'UPDATE jobs SET delivery_otp_attempts = COALESCE(delivery_otp_attempts, 0) + 1 WHERE id = ?1',
          ).bind(job.id).run();
          return c.json({
            error: 'otp_required',
            detail: 'Ask the recipient for their 4-digit DropOff door PIN (set in their account).',
          }, 403);
        }
        doorVerified = true;
        dbStatements.push(c.env.DB.prepare('UPDATE jobs SET delivery_otp_attempts = 0 WHERE id = ?1').bind(job.id));
      }
    }
  }

  // PICKUP PROOF (owner directive 2026-11-17): the SENDER holds the 4-digit
  // code for the first leg (seller → depot). The rider confirms it at
  // collection — same attempt gate as the door handover. Ops/admin keys
  // bypass; jobs minted before the code existed pass through.
  if (status === 'picked_up' && !isAdminKey && !isOpsKey) {
    const pickupOtp = await c.env.DB.prepare(
      'SELECT pickup_otp_hash, delivery_otp_hash, pickup_otp_attempts FROM jobs WHERE id = ?1',
    ).bind(job.id).first<any>();
    // SPLIT CODES (2026-11-18): verify against the SENDER's own
    // pickup_otp_hash. Legacy rows were backfilled pickup = delivery; rows
    // from before codes existed have neither and pass through.
    const pickupHash = pickupOtp?.pickup_otp_hash ?? pickupOtp?.delivery_otp_hash;
    if (pickupHash) {
      if ((pickupOtp.pickup_otp_attempts ?? 0) >= 8) {
        await addStrike(c.env, phone ?? '', job.id, 'otp_abuse');
        return c.json({ error: 'otp_locked', detail: 'Too many wrong codes — contact DropOff support to unlock this pickup.' }, 429);
      }
      const otp = String(b.otp ?? '').replace(/\D/g, '');
      const want = String(pickupHash);
      const got = otp.length === 4 ? await handoverOtpHash(c.env, c.req.param('ref'), otp) : '';
      const match = got.length === want.length && got.split('').every((ch, i) => ch === want[i]);
      if (!match) {
        await c.env.DB.prepare(
          'UPDATE jobs SET pickup_otp_attempts = COALESCE(pickup_otp_attempts, 0) + 1 WHERE id = ?1',
        ).bind(job.id).run();
        return c.json({
          error: 'otp_required',
          detail: 'Ask the SENDER for their 4-digit pickup code — it is in the booking SMS. It protects both of you against false parcels.',
        }, 403);
      }
      dbStatements.push(c.env.DB.prepare('UPDATE jobs SET pickup_otp_attempts = 0 WHERE id = ?1').bind(job.id));
    }
  }

  // waiting-time billing (event kept as dispute evidence). Canonical recompute —
  // promo discount is honoured here too so totals never drift from /payments.
  if (b.wait_minutes !== undefined) {
    const minutes = Math.max(0, Math.min(240, Math.round(Number(b.wait_minutes) || 0)));
    const waitFee = waitFeeFor(minutes);
    const totals = computeJobTotals({
      counterPriceZmw: job.counter_price_zmw,
      riderFeeZmw: job.rider_fee_zmw,
      leg2FeeZmw: job.leg2_fee_zmw,
      leg2ProcessingFeeZmw: job.leg2_processing_fee_zmw,
      promoDiscountZmw: job.promo_discount_zmw,
      waitFeeZmw: waitFee,
    });
    dbStatements.push(c.env.DB.prepare(
      `UPDATE jobs SET wait_minutes = ?2, wait_fee_zmw = ?3, total_zmw = ?4 WHERE id = ?1`,
    ).bind(job.id, minutes, waitFee, totals.total_zmw));
    dbStatements.push(c.env.DB.prepare(
      `INSERT INTO job_events (job_id, status, note, lat, lng) VALUES (?1,'waiting',?2,?3,?4)`,
    ).bind(job.id, b.note ?? `Waited ${minutes} min. K${waitFee} waiting fee billed to the sender — DropOff revenue, never the rider`, b.lat ?? null, b.lng ?? null));
    // The waiting bill belongs to DropOff, not the rider: no per-job credit
    // to any rider. The wait-fee accrues in the job total (DropOff funds
    // include it) and flows into TOT turnover via the ledger.
  }

  // CASH POLICY (owner directive): no COD, no cash at the door — the rider
  // NEVER takes cash from a recipient. Any caller that still logs a COD amount
  // gets the event stripped from the ledger instead of being booked.
  if (b.cod_collected_zmw !== undefined) {
    dbStatements.push(c.env.DB.prepare(
      `INSERT INTO job_events (job_id, status, note) VALUES (?1, 'prepaid_required', ?2)`,
    ).bind(job.id, 'COD at the door is rejected — recipients pay via momo at booking or nothing is due. Riders never carry cash.'));
  }

  // NO-QUOTING POLICY (owner directive): the counter fare lives at the depot
  // counter — RIDERS NEVER RECORD OR REPORT PRICES. Only ops/admin keys may
  // record a counter price (internal reconciliation), and doing so upserts
  // the chargebook as a verified rate. DropOff never INVENTS a fare; ops
  // records only what the counter actually charged.
  if (b.counter_price_zmw !== undefined && (status === 'at_depot' || status === 'delivered')) {
    if (!isAdminKey && !isOpsKey) {
      delete b.counter_price_zmw; // riders cannot touch money they never collect
    } else {
      const recorded = Math.round(Number(b.counter_price_zmw) * 100) / 100;
      if (Number.isFinite(recorded) && recorded > 0 && recorded <= 20000) {
        dbStatements.push(c.env.DB.prepare(
          `UPDATE jobs SET counter_price_zmw = ?2 WHERE id = ?1`,
        ).bind(job.id, recorded));
        if (job.courier_id && job.from_city && job.dest_city && job.weight_class) {
          const svc = job.service || 'standard';
          const q = await c.env.DB.prepare(
            `SELECT id FROM quotes WHERE courier_id = ?1 AND from_city = ?2 AND to_city = ?3
               AND weight_class = ?4 AND service = ?5`,
          ).bind(job.courier_id, job.from_city, job.dest_city, job.weight_class, svc).first<any>();
          if (q) {
            dbStatements.push(c.env.DB.prepare(
              `UPDATE quotes SET counter_price_zmw = ?2, source = 'recorded', updated_at = datetime('now') WHERE id = ?1`,
            ).bind(q.id, recorded));
          } else {
            dbStatements.push(c.env.DB.prepare(
              `INSERT INTO quotes (courier_id, from_city, to_city, weight_class, service, counter_price_zmw, source)
               VALUES (?1,?2,?3,?4,?5,?6,'recorded')`,
            ).bind(job.courier_id, job.from_city, job.dest_city, job.weight_class, svc, recorded));
          }
          dbStatements.push(c.env.DB.prepare(
            `INSERT INTO job_events (job_id, status, note) VALUES (?1, 'counter_recorded', ?2)`,
          ).bind(job.id, `Counter fare K${recorded} recorded at the depot — chargebook updated for ${job.from_city} → ${job.dest_city} (${job.weight_class}, ${svc}).`));
        }
      }
    }
  }

  // CAMERA-CAPTURE INTEGRITY (owner directive): a parcel is marked delivered
  // by camera capture, never by price entry. The assigned rider MUST attach a
  // proof photo to any 'delivered' event — depot handoff or door delivery.
  // Ops/admin bypasses only for depot-side reconciliation, and even then the
  // photoless drop is flagged for review.
  if (status === 'delivered' && !b.photo_url) {
    if (!isAdminKey && !isOpsKey) {
      return c.json({ error: 'photo_required', detail: 'Mark the delivery with a camera photo of the parcel — a delivery without proof is not a delivery.' }, 400);
    }
    dbStatements.push(c.env.DB.prepare(
      `INSERT INTO job_events (job_id, status, note) VALUES (?1, 'photo_missing', ?2)`,
    ).bind(job.id, 'Delivered by ops without a proof photo — flagged for review. Delivery is marked by camera capture.'));
    try {
      await raiseAlert(c.env.DB, ownerPhone(c.env) ?? job.sender_phone, 'delivery_photo_missing', 'medium',
        `${job.ref} was marked delivered without a camera photo (ops/admin reconciliation drop) — review the handoff.`);
    } catch { /* alerting must never block the event */ }
  }

  // DEPOT COUNTER FLOW (owner directive 2026-11-12): the rider FRONTS the
  // depot's counter fare with their own money, then photographs BOTH the
  // parcel and the depot's written receipt and transcribes the EXACT amount
  // on the receipt (transcription of a written document — the rider never
  // QUOTES a fare). The sender pays that amount + processing fee to DropOff
  // by momo; the receipt photo unlocks only after payment; the rider is then
  // reimbursed the exact counter amount, fee-free. Riders still never take
  // cash from senders. Door deliveries (code-verified) skip this — no
  // counter is involved.
  if (status === 'delivered' && !doorVerified && !isAdminKey && !isOpsKey) {
    // RECEIPT IMMUTABILITY (audit fix): once the sender has PAID the counter
    // fare, the submitted receipt is money-movement evidence — a rider (or a
    // dropped network retry) must never be able to rewrite it. Unpaid
    // resubmissions stay allowed: a network drop must be self-healing.
    if (Number(job.counter_receipt_paid ?? 0) === 1) {
      return c.json({
        error: 'counter_receipt_locked',
        detail: 'This depot receipt is already paid — its amount and photos are locked. Contact DropOff support if something is wrong.',
      }, 409);
    }
    const amount = Math.round(Number(b.receipt_amount_zmw) * 100) / 100;
    const receiptUrl = String(b.receipt_url ?? '').trim();
    // MULTI-RECEIPT DEPOT DROPS (owner request 2026-11-12): a depot may split
    // one batch across several written receipts. The rider files EACH one —
    // photographed with its own exact amount. A submitted receipt is a
    // single, exact, photographed document, never a rider-computed sum; the
    // SERVER sums the documents. The legacy single fields
    // (receipt_amount_zmw/receipt_url) are honoured as a one-receipt list.
    const filed: { amount_zmw: number; url: string }[] = [];
    if (Array.isArray(b.receipts)) {
      for (const r of b.receipts as any[]) {
        filed.push({
          amount_zmw: Math.round(Number(r?.amount_zmw) * 100) / 100,
          url: String(r?.url ?? '').trim(),
        });
      }
    } else if (Number.isFinite(amount) && amount > 0 && receiptUrl) {
      filed.push({ amount_zmw: amount, url: receiptUrl });
    }
    const badReceipt = filed.find((r) => !Number.isFinite(r.amount_zmw) || r.amount_zmw <= 0 || r.amount_zmw > 20000 || !r.url);
    if (filed.length === 0 || badReceipt) {
      return c.json({
        error: 'receipt_required',
        detail: 'Every depot receipt needs its photo AND the exact amount written on it (each receipt is a separate photographed document).',
      }, 400);
    }
    // Parcel photos: the legacy photo_url is the primary; extra parcel
    // photos ride on parcel_photos[] (batches of different parcels).
    const parcelPhotos = [String(b.photo_url ?? '').trim(), ...(Array.isArray(b.parcel_photos) ? (b.parcel_photos as any[]).map((u) => String(u ?? '').trim()) : [])]
      .filter((u) => u.length > 0);
    if (parcelPhotos.length === 0) {
      return c.json({ error: 'photo_required', detail: 'A camera photo of the parcel is required — delivery is marked by capture, never by price entry.' }, 400);
    }
    if (parcelPhotos.some((u) => filed.some((r) => r.url === u))) {
      return c.json({
        error: 'two_photos_required',
        detail: 'Parcel photos and depot receipt photos must be separate images.',
      }, 400);
    }
    const receiptTotal = round2(filed.reduce((s, r) => s + r.amount_zmw, 0));
    dbStatements.push(c.env.DB.prepare(
      `UPDATE jobs SET counter_receipt_url = ?2, counter_receipt_zmw = ?3, counter_receipts_json = ?4, counter_receipt_paid = 0 WHERE id = ?1`,
    ).bind(job.id, filed[0].url, receiptTotal, JSON.stringify(filed)));
    const receiptList = filed.map((r, i) => `#${i + 1} K${r.amount_zmw.toFixed(2)}`).join(', ');
    dbStatements.push(c.env.DB.prepare(
      `INSERT INTO job_events (job_id, status, note) VALUES (?1, 'counter_receipt_submitted', ?2)`,
    ).bind(job.id, `Depot receipt${filed.length > 1 ? `s (${filed.length})` : ''} submitted: ${receiptList} as written on the photographed document${filed.length > 1 ? 's' : ''} (${parcelPhotos.length} parcel photo${parcelPhotos.length > 1 ? 's' : ''} + ${filed.length} receipt photo${filed.length > 1 ? 's' : ''} filed). Sender repays the K${receiptTotal.toFixed(2)} total through DropOff (plan members: no processing fee) — the depot receipt photos are revealed on payment.`));
    counterReceiptDue = receiptTotal;
  }

  // DropOff NEVER holds partner money: the customer pays us only the DropOff
  // leg — rider fee + last-mile door leg (+ its processing), minus any promo.
  const dropoffLegZmw = round2(
    Math.max(0, job.rider_fee_zmw + (job.leg2_fee_zmw || 0) + (job.leg2_processing_fee_zmw || 0) - (job.promo_discount_zmw || 0)),
  );

  // Wallet jobs settle the same DropOff leg, minus the Lipila momo leg —
  // the platform processing fee still applies (no free rides on the fee).
  // LEGACY: pay_method 'wallet' rows are no longer issued — customers hold no
  // stored value; this debit only fires for pre-refactor rows with a balance.
  const walletProcessing = platformFee(dropoffLegZmw);
  const walletDue = round2(dropoffLegZmw + walletProcessing);

  // wallet-method jobs are charged at pickup. The debit is guarded by balance;
  // the ledger + paid flag are written ONLY when the debit actually moved money
  // (a failed guard used to leave a ledger row and a paid job with no deduction).
  if (status === 'picked_up' && job.pay_method === 'wallet' && !job.paid) {
    const debit = await c.env.DB.prepare(
      `UPDATE wallets SET balance_zmw = balance_zmw - ?2 WHERE phone = ?1 AND balance_zmw >= ?2`,
    ).bind(job.sender_phone, walletDue).run();
    if (debit.meta.changes > 0) {
      await c.env.DB.batch([
        c.env.DB.prepare(
          `INSERT INTO wallet_ledger (phone, amount_zmw, kind, job_id) VALUES (?1, -?2, 'job_charge', ?3)`,
        ).bind(job.sender_phone, walletDue, job.id),
        c.env.DB.prepare('UPDATE jobs SET paid = 1 WHERE id = ?1').bind(job.id),
      ]);
    } else {
      return c.json({ error: 'insufficient_wallet_balance', due_zmw: walletDue }, 402);
    }
  }

  if (status) {
    dbStatements.push(c.env.DB.prepare(
      'INSERT INTO job_events (job_id, status, note, lat, lng) VALUES (?1,?2,?3,?4,?5)',
    ).bind(job.id, status, b.note ?? null, b.lat ?? null, b.lng ?? null));
    const sets = ['status = ?2'];
    const vals: unknown[] = [job.id, status];
    const nextParam = () => '?' + (vals.length + 1);
    if (b.waybill) { sets.push('courier_waybill = ' + nextParam()); vals.push(b.waybill); }
    // Rider records the depot branch AT THE DEPOT — not in advance. Before
    // lodgement the parcel route is "to PLATINUM" (or the quoted courier);
    // the specific branch is only known when the rider hands it in. Any event
    // that files a depot receipt IS the lodgement moment.
    if ((status === 'at_depot' || counterReceiptDue != null) && typeof b.branch === 'string' && b.branch.trim()) {
      sets.push('branch = ' + nextParam());
      vals.push(b.branch.trim().slice(0, 80));
    }
    if (b.photo_url) {
      const photo = String(b.photo_url).trim();
      const stage = String(b.stage ?? '');
      const override = isAdminKey || isOpsKey;
      // FIRST-WRITE-WINS evidence lock (owner directive 2026-11-15): once a
      // lodgement / pickup / handover photo is on file, neither the rider nor
      // a dropped network retry can swap it for a different one — evidence of
      // a bad delivery freezes the moment it exists. Staff keys keep an
      // override for genuine mis-submissions.
      if (!override) {
        const locked = (cur: unknown) => typeof cur === 'string' && cur.trim().length > 0 && cur.trim() !== photo;
        // Stage-specific: a pickup photo lives in dropoff_photo_url, so it
        // must NOT block the later depot drop (different photo/stage).
        if (stage !== 'pickup' && stage !== 'delivery' && locked(job.dropoff_photo_url)) return c.json({
          error: 'photo_locked',
          detail: 'Lodgement photo already on file - ops can correct a genuine mis-submission.',
        }, 409);
        if (stage === 'pickup' && status === 'picked_up' && locked(job.pod_pickup_url)) return c.json({
          error: 'photo_locked',
          detail: 'Pickup photo already on file — evidence frozen. Ops can correct it.',
        }, 409);
        if (stage === 'delivery' && status === 'delivered' && locked(job.pod_delivery_url)) return c.json({
          error: 'photo_locked',
          detail: 'Handover photo already on file — evidence frozen. Ops can correct it.',
        }, 409);
      }
      if (override) {
        sets.push('dropoff_photo_url = ' + nextParam()); vals.push(photo);
        if (stage === 'pickup' && status === 'picked_up') { sets.push('pod_pickup_url = ' + nextParam()); vals.push(photo); }
        else if (stage === 'delivery' && status === 'delivered') { sets.push('pod_delivery_url = ' + nextParam()); vals.push(photo); }
      } else {
        if (!job.dropoff_photo_url) { sets.push('dropoff_photo_url = ' + nextParam()); vals.push(photo); }
        if (stage === 'pickup' && status === 'picked_up' && !job.pod_pickup_url) { sets.push('pod_pickup_url = ' + nextParam()); vals.push(photo); }
        else if (stage === 'delivery' && status === 'delivered' && !job.pod_delivery_url) { sets.push('pod_delivery_url = ' + nextParam()); vals.push(photo); }
      }
    }
    dbStatements.push(c.env.DB.prepare(
      `UPDATE jobs SET ${sets.join(', ')} WHERE id = ?1`).bind(...vals));
  }
  // PICKUP PHOTO BATCH (owner directive 2026-11-17): a stop with N parcels
  // files N photos — one per parcel, no repeats. The first photo is the
  // locked pod_pickup_url evidence; the whole batch is recorded on the job's
  // event log so ops can compare every collected parcel against the seller's
  // booking photo at the depot drop.
  if (status === 'picked_up' && Array.isArray(b.parcel_photos)) {
    const pickupPhotos = (b.parcel_photos as any[]).map((u) => String(u ?? '').trim()).filter((u) => u.length > 0);
    if (pickupPhotos.length > 0) {
      dbStatements.push(c.env.DB.prepare(
        `INSERT INTO job_events (job_id, status, note) VALUES (?1, 'pickup_photos_filed', ?2)`,
      ).bind(job.id, `Pickup evidence: ${pickupPhotos.length} parcel photo${pickupPhotos.length > 1 ? 's' : ''} filed at collection (${pickupPhotos.join(' ')}).`));
    }
  }
  if (dbStatements.length) await c.env.DB.batch(dbStatements);

  // Auto-mark in the parcel chat on every major milestone (everyone watches,
  // no typing required). Executes only after the canonical events commit has
  // landed — these are derived from `status` set by the authorized caller,
  // and the message is always labelled SYSTEM (no fake user).
  // Route-aware SYSTEM messages — never claim a hard-coded city when the job
  // is happening anywhere else. Branch beats city beats generic.
  const routeCity = (job.branch?.trim() ? job.branch : null) ?? job.dest_city?.trim() ?? job.to_city?.trim() ?? job.from_city?.trim() ?? null;
  const originCity = job.from_city?.trim() || null;
  const destCity = job.dest_city?.trim() || job.to_city?.trim() || null;
  const chatEvent = (() => {
    switch (status) {
      case 'rider_assigned': return `SYSTEM: Rider is on the way to the pickup${originCity ? ` in ${originCity}` : ''} — parcel handoff in progress.`;
      case 'picked_up':
        return `SYSTEM: Picked up by the rider — en route to ${(job.branch?.trim()) || 'the depot'}.`;
      case 'at_depot':
        return `SYSTEM: Parcel dropped at ${(job.branch?.trim()) || 'the courier depot'} — awaiting lodgement.`;
      case 'departed':
        return `SYSTEM: Parcel dispatched from ${originCity ?? 'the depot'} to ${destCity ?? 'the destination'}.`;
      case 'arrived':
        return `SYSTEM: Parcel arrived at ${destCity ?? routeCity ?? 'the destination'} — awaiting collection.`;
      case 'delivered':      return `SYSTEM: Parcel delivered — journey complete.`;
      case 'ready_for_collection':
        return `SYSTEM: Parcel ready for collection at ${(job.branch?.trim()) || 'the depot'}.`;
      default: return '';
    }
  })();
  if (chatEvent) {
    try {
      const threadId = await getOrCreateJobThread(c.env, job.id);
      await c.env.DB.prepare(
        `INSERT INTO chat_messages (thread_id, sender_phone, sender_role, body) VALUES (?1, ?2, ?3, ?4)`,
      ).bind(threadId, 'dropoff', 'ops', chatEvent).run();
      c.executionCtx.waitUntil(notifyChatParticipants(c.env, { id: threadId }, job, '', chatEvent).catch(() => {}));
      // Recipient confirmed by handing over their OTP — that IS the confirmation.
      // The parcel is with the recipient, so the chat closes itself and archives;
      // every participant keeps the full history forever, read-only.
      if (status === 'delivered' && doorVerified) {
        try {
          const closedMsg = `SYSTEM: Delivery confirmed — chat closed & archived. Everyone keeps the full history, read-only.`;
          await c.env.DB.prepare(
            `INSERT INTO chat_messages (thread_id, sender_phone, sender_role, body) VALUES (?1, 'dropoff', 'ops', ?2)`,
          ).bind(threadId, closedMsg).run();
          await c.env.DB.prepare(
            `UPDATE chat_threads SET closed_by = 'system', closed_at = datetime('now') WHERE id = ?1 AND closed_at IS NULL`,
          ).bind(threadId).run();
          await c.env.DB.prepare(
            `INSERT INTO job_events (job_id, status, note) VALUES (?1, 'chat_closed', ?2)`,
          ).bind(job.id, 'Chat auto-archived on delivery confirmation — history kept for all participants.').run();
        } catch { /* auto-archive is best-effort; delivery already persisted */ }
      }
    } catch { /* chat is best-effort; core milestone already persisted */ }
  }

  // Counter fare is now owed by the sender — tell them exactly what to pay
  // and that the receipt photo unlocks when they do. (Rider fronted the
  // money; reimbursement fires on payment approval.)
  if (counterReceiptDue != null) {
    // Same fee math the /payments endpoint will apply — plan-active senders
    // see the waived total in the SMS, not a number that later changes.
    const cfare = await counterFareFees(c.env, job.sender_phone, counterReceiptDue);
    const fee = round2(cfare.total - counterReceiptDue);
    try {
      await sendSms(c.env, job.sender_phone,
        cfare.planWaived
          ? `DropOff: parcel ${job.ref} is at the depot counter. Pay K${cfare.total.toFixed(2)} in Bookings to reveal your depot receipt photo (no processing - plan active).`
          : `DropOff: parcel ${job.ref} is at the depot. Counter fare K${counterReceiptDue.toFixed(2)} + K${fee.toFixed(2)} processing = K${cfare.total.toFixed(2)}. Pay in Bookings to reveal the depot receipt photo.`, { transactional: true });
    } catch { /* notification must never break the event */ }
    c.executionCtx.waitUntil(sendToPhone(c.env, job.sender_phone, {
      title: 'Counter fare due',
      body: `Parcel ${job.ref} reached the depot. Pay K${cfare.total.toFixed(2)} in Bookings to reveal your depot receipt photo and release the rider's reimbursement.`,
      data: { job_ref: job.ref ?? '', kind: 'counter_fare_due' },
    }));
  }

  // Free the rider's load slot and flip them back to available — without this,
  // riders stay 'on_route' and accumulate current_load forever, eventually
  // reaching capacity and never receiving another dispatch.
  if (status === 'delivered' || status === 'ready_for_collection' || status === 'collected') {
    await c.env.DB.prepare(
      `UPDATE riders SET current_load = MAX(0, current_load - 1), status = 'available', route_updated_at = datetime('now')
       WHERE id = (SELECT rider_id FROM jobs WHERE id = ?1)`,
    ).bind(job.id).run().catch(() => { /* dispatch hygiene must never break delivery events */ });
  }

  const updated = await c.env.DB.prepare(
    `SELECT ref, status, paid, counter_price_zmw, rider_fee_zmw, leg2_fee_zmw,
            wait_minutes, wait_fee_zmw, cod_collected_zmw, total_zmw FROM jobs WHERE id = ?1`,
  ).bind(job.id).first();
  // FCM push to the sender — status transitions are the parcel's whole story.
  if (status && updated) {
    const stagePush: Record<string, { title: string; body: string }> = {
      rider_assigned: { title: 'Rider assigned', body: 'Your DropOff rider is on it — track them live in Bookings.' },
      picked_up: { title: 'Parcel picked up', body: 'Collected from the sender — heading to the depot.' },
      at_depot: { title: 'At the depot', body: 'Your parcel reached the depot. You can follow the journey live.' },
      departed: { title: 'On the way', body: 'Left the depot on the DropOff leg.' },
      arrived: { title: 'Arrived', body: 'Your parcel arrived at the destination city.' },
      ready_for_collection: { title: 'Ready for collection', body: 'The parcel is waiting at your depot for pickup.' },
      delivered: { title: 'Delivered', body: 'Success — the parcel is signed in at the depot. Kigoda.' },
    };
    const push = stagePush[status];
    if (push) {
      await sendToPhone(c.env, job.sender_phone, { ...push, data: { job_ref: String(updated.ref), kind: 'status' } });
    }
    // SMS milestones to both parties — proactive updates are the #1 trust signal
    // in first-mile delivery. Best-effort: never fails the job if SMS is off.
    const smsMilestones = new Set(['picked_up', 'at_depot', 'delivered', 'ready_for_collection']);
    if (status && smsMilestones.has(status) && job.sender_phone && job.recipient_phone) {
      const ref = String(updated.ref);
      const body = status === 'delivered'
        ? `DropOff: your parcel ${ref} is delivered at the depot. Track it in the DropOff app.`
        : status === 'ready_for_collection'
          ? `DropOff: your parcel ${ref} is ready for collection at the depot.`
          : status === 'at_depot'
            ? `DropOff: your parcel ${ref} reached the depot.`
            : `DropOff: your parcel ${ref} was picked up and is heading to the depot.`;
      await Promise.allSettled([
        sendSms(c.env, job.sender_phone, body, { transactional: true }),
        sendSms(c.env, job.recipient_phone, body, { transactional: true }),
      ]);
    }
  }
  return c.json({ ok: true, job: updated });
});

/* --------------------------------- ratings -------------------------------- */
// Rate the three sides of a delivery — the seller, the driver (rider) and the
// courier. Only the job's participants (sender / recipient) or ops can rate;
// sellers can't rate themselves; ratings open once the parcel is delivered or
// ready for collection. One score per reviewer per target — resubmits update.
const RATING_TARGETS = new Set(['seller', 'driver', 'courier']);
const RATING_OPEN = new Set(['delivered', 'ready_for_collection']);

// Lightweight comment guard — enough to keep abuse out of a public feed without
// Lightweight comment guard — the shared containsAbuse() matcher lives in
// moderation.ts (normalization + Zambian-language terms) so chat and comments
// enforce identical rules. Hidden-by-admin and strikes are the real levers.
function containsProfanity(text: string): boolean {
  return containsAbuse(text);
}

async function ratingTargetKey(job: any, targetType: string): Promise<string | null> {
  if (targetType === 'seller') return `phone:${job.sender_phone}`;
  if (targetType === 'driver') return job.rider_id ? `rider:${job.rider_id}` : null;
  return `courier:${job.courier_id}`;
}

app.post('/jobs/:ref/rate', async (c) => {
  if (await rateLimited(c, 'rating', 40)) return c.json({ error: 'too_many_requests' }, 429);
  const b: any = await c.req.json().catch(() => null);
  const targetType = String(b?.target_type ?? '').toLowerCase();
  if (!RATING_TARGETS.has(targetType)) return c.json({ error: 'bad target_type' }, 400);
  const stars = Math.round(Number(b?.stars));
  if (!Number.isFinite(stars) || stars < 1 || stars > 5) return c.json({ error: 'stars must be 1-5' }, 400);
  const comment = typeof b?.comment === 'string' ? b.comment.trim().slice(0, 500) : '';
  if (comment && containsProfanity(comment)) {
    return c.json({ error: 'comment_blocked', message: 'Please keep comments respectful.' }, 400);
  }

  const job = await c.env.DB.prepare(
    `SELECT id, ref, sender_phone, recipient_phone, rider_id, courier_id, status FROM jobs WHERE ref = ?1`,
  ).bind(c.req.param('ref')).first<any>();
  if (!job) return c.json({ error: 'not found' }, 404);

  const role = c.get('role');
  const reviewer = role === 'ops'
    ? normalizeZmPhone(String(b?.reviewer_phone ?? job.sender_phone))
    : (c.get('phone') as string);
  if (role === 'customer' && reviewer !== job.sender_phone && reviewer !== job.recipient_phone) {
    return c.json({ error: 'not found' }, 404); // no existence leak
  }
  if (targetType === 'seller' && reviewer === job.sender_phone) {
    return c.json({ error: 'cannot_rate_self' }, 403);
  }
  if (role === 'customer' && !RATING_OPEN.has(String(job.status))) {
    return c.json({ error: 'not_complete', message: 'Rate once the parcel is delivered or ready for collection.' }, 409);
  }
  const targetKey = await ratingTargetKey(job, targetType);
  if (!targetKey) return c.json({ error: 'no_driver_assigned' }, 409);

  await c.env.DB.prepare(
    `INSERT INTO ratings (job_ref, job_id, target_type, target_key, reviewer_phone, reviewer_role, stars, comment)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
     ON CONFLICT(job_ref, target_type, reviewer_phone)
     DO UPDATE SET stars = excluded.stars, comment = excluded.comment, updated_at = datetime('now')`,
  ).bind(job.ref, job.id, targetType, targetKey, reviewer, role ?? 'customer', stars, comment || null).run();
  await c.env.DB.prepare(
    `INSERT INTO job_events (job_id, status, note) VALUES (?1, 'rated', ?2)`,
  ).bind(job.id, `${targetType} rated ${stars}/5`).run();

  return c.json({ ok: true, target_type: targetType, stars });
});

// OPTIONAL RECEIPT CONFIRMATION (owner 2026-11-18, Lusaka-first): same-city
// recipients carry no PIN — they track live in-app and CONFIRM RECEIPT
// instead. The confirmation is a real job event from the recipient's own
// signed session (real account holders only), idempotent per job, and the
// sender gets a push nudge (no SMS cost for good news).
app.post('/jobs/:ref/confirm-receipt', async (c) => {
  const job = await c.env.DB.prepare(
    'SELECT id, ref, sender_phone, recipient_phone, status FROM jobs WHERE ref = ?1',
  ).bind(c.req.param('ref')).first() as any;
  if (!job) return c.json({ error: 'not found' }, 404);
  const phone = c.get('phone') ?? '';
  const staff = c.get('role') === 'ops' || isAdmin(c);
  if (!staff && phone !== job.recipient_phone) {
    return c.json({ error: 'not found' }, 404); // no existence leak
  }
  const already = await c.env.DB.prepare(
    `SELECT id FROM job_events WHERE job_id = ?1 AND status = 'receipt_confirmed' LIMIT 1`,
  ).bind(job.id).first<any>();
  if (!already) {
    await c.env.DB.prepare(
      `INSERT INTO job_events (job_id, status, note) VALUES (?1, 'receipt_confirmed', ?2)`,
    ).bind(job.id, staff
      ? 'Receipt confirmed by ops on the recipient\'s behalf.'
      : 'Recipient confirmed receipt in-app — from their own DropOff account.')
      .run();
    if (job.sender_phone) {
      await sendToPhone(c.env, job.sender_phone, {
        title: 'Parcel received ✓',
        body: `The recipient confirmed receipt of ${job.ref}.`,
        data: { kind: 'receipt_confirmed', ref: job.ref },
      }).catch(() => {});
    }
  }
  return c.json({ ok: true, ref: job.ref, confirmed: true });
});

app.get('/jobs/:ref/ratings', async (c) => {
  const job = await c.env.DB.prepare(
    `SELECT id, ref, sender_phone, recipient_phone, rider_id, courier_id FROM jobs WHERE ref = ?1`,
  ).bind(c.req.param('ref')).first<any>();
  if (!job) return c.json({ error: 'not found' }, 404);
  if (c.get('role') === 'customer' && c.get('phone') !== job.sender_phone && c.get('phone') !== job.recipient_phone) {
    return c.json({ error: 'not found' }, 404);
  }
  const { results } = await c.env.DB.prepare(
    `SELECT target_type, stars, comment, reviewer_phone, verified, hidden, created_at, updated_at
       FROM ratings WHERE job_ref = ?1 ORDER BY id`,
  ).bind(job.ref).all<any>();

  const viewer = c.get('phone');
  const mine: Record<string, number> = {};
  const masked = (results as any[]).map((r) => {
    const isMine = viewer != null && r.reviewer_phone === viewer;
    if (isMine) mine[r.target_type] = r.stars;
    // reviewers stay anonymous — only the viewer recognises their own entry
    return { ...r, reviewer_phone: isMine ? r.reviewer_phone : '***' };
  });
  const summary: Record<string, { count: number; average: number | null }> = {};
  for (const t of RATING_TARGETS) {
    const key = await ratingTargetKey(job, t);
    if (!key) continue;
    const agg = await c.env.DB.prepare(
      `SELECT COUNT(*) AS count, ROUND(AVG(stars), 2) AS average
         FROM ratings WHERE target_type = ?1 AND target_key = ?2`,
    ).bind(t, key).first<any>();
    summary[t] = { count: agg?.count ?? 0, average: agg?.average ?? null };
  }
  return c.json({ ratings: masked, my_ratings: mine, summary });
});

app.get('/ratings/summary', async (c) => {
  const targetType = String(c.req.query('target_type') ?? '');
  const targetKey = String(c.req.query('target_key') ?? '');
  if (!RATING_TARGETS.has(targetType) || !targetKey) return c.json({ error: 'bad target' }, 400);
  const agg = await c.env.DB.prepare(
    `SELECT COUNT(*) AS count, ROUND(AVG(stars), 2) AS average
       FROM ratings WHERE target_type = ?1 AND target_key = ?2`,
  ).bind(targetType, targetKey).first<any>();
  const { results: recent } = await c.env.DB.prepare(
    `SELECT stars, comment, verified, created_at FROM ratings
      WHERE target_type = ?1 AND target_key = ?2 AND hidden = 0 AND comment IS NOT NULL AND comment <> ''
      ORDER BY id DESC LIMIT 20`,
  ).bind(targetType, targetKey).all();
  return c.json({
    target_type: targetType, target_key: targetKey,
    count: agg?.count ?? 0, average: agg?.average ?? null, recent,
  });
});

/* --------------------------- rating reports ------------------------------- */
// Flagging a comment is limited to parties of the rated job (sender,
// recipient, assigned rider) or staff — arbitrary signed-in users cannot
// mass-report ratings they have nothing to do with.
app.post('/ratings/:id/report', async (c) => {
  const id = Number(c.req.param('id'));
  const b: any = await c.req.json().catch(() => null);
  const rating = await c.env.DB.prepare(
    `SELECT r.id, r.job_id, j.sender_phone, j.recipient_phone, j.rider_id
       FROM ratings r LEFT JOIN jobs j ON j.id = r.job_id
      WHERE r.id = ?1`,
  ).bind(id).first<any>();
  if (!rating) return c.json({ error: 'not found' }, 404);
  const role = c.get('role');
  const staff = role === 'ops' || isAdmin(c);
  const phone = c.get('phone') ?? '';
  if (!staff) {
    if (!phone || !rating.job_id) return c.json({ error: 'forbidden' }, 403);
    let riderPhone: string | null = null;
    if (rating.rider_id) {
      riderPhone = ((await c.env.DB.prepare('SELECT phone FROM riders WHERE id = ?1')
        .bind(rating.rider_id).first<any>())?.phone) ?? null;
    }
    const tied = phone === rating.sender_phone || phone === rating.recipient_phone || phone === riderPhone;
    if (!tied) return c.json({ error: 'forbidden' }, 403);
  }
  const reason = String(b?.reason ?? '').trim().slice(0, 300);
  await c.env.DB.batch([
    c.env.DB.prepare('INSERT INTO rating_reports (rating_id, reporter_phone, reason) VALUES (?1, ?2, ?3)')
      .bind(id, phone || null, reason || null),
    c.env.DB.prepare(`UPDATE ratings SET report_reason = ?2, reported_at = datetime('now') WHERE id = ?1`)
      .bind(id, reason || null),
  ]);
  return c.json({ ok: true });
});

app.get('/admin/ratings', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'forbidden' }, 403);
  const reportedOnly = c.req.query('reported') === '1';
  const { results } = await c.env.DB.prepare(
    `SELECT r.*, (SELECT COUNT(*) FROM rating_reports rr WHERE rr.rating_id = r.id) AS reports
       FROM ratings r ${reportedOnly ? 'WHERE r.reported_at IS NOT NULL' : ''}
      ORDER BY r.id DESC LIMIT 200`,
  ).all();
  return c.json({ ratings: results });
});

app.post('/admin/ratings/:id/moderate', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'forbidden' }, 403);
  const b: any = await c.req.json().catch(() => null);
  const hidden = b?.hidden === true || b?.hidden === 1 ? 1 : 0;
  const res = await c.env.DB.prepare('UPDATE ratings SET hidden = ?2 WHERE id = ?1')
    .bind(Number(c.req.param('id')), hidden).run();
  return c.json({ ok: true, updated: res.meta.changes });
});

/* ----------------------------- fraud review ------------------------------- */
app.get('/admin/fraud', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'forbidden' }, 403);
  const status = c.req.query('status') ?? 'open';
  const { results } = await c.env.DB.prepare(
    `SELECT f.*, j.status AS job_status, j.total_zmw
       FROM fraud_flags f JOIN jobs j ON j.id = f.job_id
      WHERE f.status = ?1 ORDER BY f.id DESC LIMIT 200`,
  ).bind(status).all();
  return c.json({ flags: results });
});

app.post('/admin/fraud/:id/review', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'forbidden' }, 403);
  const b: any = await c.req.json().catch(() => null);
  const status = b?.status === 'confirmed' ? 'confirmed' : 'cleared';
  const flag = await c.env.DB.prepare('SELECT job_id FROM fraud_flags WHERE id = ?1')
    .bind(Number(c.req.param('id'))).first<any>();
  if (!flag) return c.json({ error: 'not found' }, 404);
  await c.env.DB.batch([
    c.env.DB.prepare(
      `UPDATE fraud_flags SET status = ?2, reviewed_at = datetime('now'), reviewer = ?3 WHERE id = ?1`,
    ).bind(Number(c.req.param('id')), status, c.get('phone') ?? null),
    c.env.DB.prepare('UPDATE jobs SET review_required = ?2 WHERE id = ?1')
      .bind(flag.job_id, status === 'confirmed' ? 1 : 0),
  ]);
  return c.json({ ok: true, status });
});

/* ------------------------- account-gated tracking page ----------------------- */
// GET /track/:token — the link NEVER opens a parcel by itself. Only a signed-in
// account whose phone is the sender's or recipient's (or staff) gets data;
// anyone else gets requires_account + a last-4 hint. See trackAccess().
// Granted viewers get status + live rider location; never prices, sender
// phone or payment data.
app.get('/track/:token', async (c) => {
  const token = c.req.param('token');
  const wantsHtml = c.req.header('accept')?.includes('text/html') ?? false;
  if (wantsHtml) {
    return c.html(`<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>DropOff</title></head>
<body style="font-family:system-ui;margin:0;background:#123C32;color:#fff;display:flex;align-items:center;justify-content:center;min-height:100vh;text-align:center;padding:24px">
<div style="max-width:420px"><h1 style="margin:0 0 8px">Open in DropOff</h1>
<p style="opacity:.9">Tap below to open this link in the DropOff app. Tracking requires an account: sign in (or create one) with the phone this parcel was addressed to.</p>
<a href="dropoff://track/${encodeURIComponent(token)}" style="display:inline-block;margin-top:18px;background:#F6B73C;color:#123C32;font-weight:800;text-decoration:none;padding:14px 28px;border-radius:12px">Open in DropOff</a>
<p style="margin-top:16px;font-size:12px;opacity:.7">No account, no parcel details — the link only works signed-in with the sender's or recipient's number.</p>
</div></body></html>`);
  }
  const access = await trackAccess(c, token);
  if (!access.jobId) return c.json({ error: 'not found' }, 404);
  if (!access.granted) {
    return c.json({
      requires_account: true,
      hint_phone: maskPhone(access.recipientPhone),
      hint: 'Tracking opens only in a DropOff account signed in with the phone this parcel was addressed to (or the sender\'s phone). Create your account or sign in, then open the link again.',
    });
  }
  const row = await c.env.DB.prepare(
    `SELECT t.job_id, t.job_ref,
            j.ref, j.status, j.created_at, j.pickup_address, j.dest_city, j.branch,
            j.recipient_name, j.eta_minutes, j.courier_id,
            co.name AS courier_name, co.depot_name AS courier_depot,
            r.full_name AS rider_name, r.vehicle AS rider_vehicle,
            r.last_lat, r.last_lng, r.last_seen_at,
            r.photo_url AS rider_photo_url, r.verification_status AS rider_verification,
       FROM tracking_tokens t
       JOIN jobs j ON j.id = t.job_id
       LEFT JOIN couriers co ON co.id = j.courier_id
       LEFT JOIN riders r ON r.id = j.rider_id
      WHERE t.token = ?1
         AND COALESCE(j.status, '') != 'deleted'
         AND (t.expires_at IS NULL OR t.expires_at > datetime('now'))`,
  ).bind(c.req.param('token')).first<any>();
  if (!row) return c.json({ error: 'not found' }, 404);
  // Payment-held parcels show a held notice instead of live status (owner
  // directive 2026-11-15) — even a token minted before payment can't carry
  // live tracking until the prepayment settles.
  if (await jobPaymentHeld(c.env.DB, row.job_id)) {
    return c.json({
      payment_held: true,
      ref: row.ref,
      hint: 'Prepayment pending — tracking opens once the sender\'s payment is approved.',
    });
  }
  // Public page: timeline statuses only — NEVER internal notes (referral,
  // fraud, payment) and never prices or sender details.
  const { results: events } = await c.env.DB.prepare(
    `SELECT status, created_at FROM job_events
      WHERE job_id = ?1 AND status IN ('created','rider_assigned','picked_up','at_depot','departed','arrived','delivered','ready_for_collection','partner_confirmed')
      ORDER BY id`,
  ).bind(row.job_id).all();
  // Smart ETA: p50 of this courier's recent legs applied to where the parcel is.
  const predicted = await predictEtaForJob(c.env.DB, row, events as any[]).catch(() => null);
  return c.json({
    ref: row.ref,
    status: row.status,
    created_at: row.created_at,
    predicted,
    pickup_city: (row.pickup_address ?? '').split(',').slice(-1)[0].trim() || null,
    dest_city: row.dest_city,
    // First mile ends at the depot branch the seller nominated — that is what
    // DropOff is paid for; the final city is only the optional last mile.
    dropoff: {
      branch: row.branch ?? row.courier_depot ?? null,
      courier: row.courier_name ?? null,
    },
    recipient_name: row.recipient_name,
    courier: row.courier_name,
    eta_minutes: row.eta_minutes ?? null,
    rider: row.rider_name
      ? { name: row.rider_name, vehicle: row.rider_vehicle, photo_url: row.rider_photo_url ?? null, verified: row.rider_verification === 'verified' }
      : null,
    location: row.last_lat != null
      ? { lat: row.last_lat, lng: row.last_lng, seen_at: row.last_seen_at }
      : null,
    events,
    // "belongs to" proof — shown only after the account gate passes.
    verified: true,
    you_are: access.whoAmI ?? null,
    verified_for: access.recipientName ?? null,
  });
});

// Vanity short path for SMS/shares — redirects to /track/:token, which is
// account-gated like everything else.
app.get('/t/:token', (c) => c.redirect(`/track/${c.req.param('token')}`, 302));

// (Removed: POST /track/:token/verify — the phone-OTP "grant" that let
// non-account holders track with a link. Accounts are required now.)

// Recipient inbox: every live parcel addressed to the signed-in caller's phone,
// newest first - a recipient who creates a DropOff account gets their parcels
// automatically, no link-pasting needed. Cancelled/delivered jobs are still
// listed (the app shows the terminal status rather than hiding it).
app.get('/track/incoming', async (c) => {
  const phone = c.get('phone');
  if (!phone) return c.json({ error: 'identity_required' }, 401);
  const limit = pageLimit(c.req.query('limit'));
  const { results } = await c.env.DB.prepare(
    `SELECT j.ref, j.status, j.created_at, j.dest_city, j.recipient_name,
            (j.paid = 0 AND EXISTS (
               SELECT 1 FROM job_events e
                WHERE e.job_id = j.id AND e.status IN ('advance_pending', 'prepayment_pending'))) AS payment_held,
            co.name AS courier_name, co.depot_name AS courier_depot,
            t.token AS tracking_token
       FROM jobs j
       LEFT JOIN couriers co ON co.id = j.courier_id
       LEFT JOIN tracking_tokens t ON t.job_id = j.id
      WHERE j.recipient_phone = ?1
         AND COALESCE(j.status, '') NOT IN ('deleted', 'canceled', 'cancelled')
      ORDER BY j.id DESC LIMIT ?2`,
  ).bind(phone, limit).all();
  const APP_URL = (c.env.APP_URL ?? '').replace(/\/$/, '');
  const parcels = [] as any[];
  for (const row of results as any[]) {
    let token: string | null = row.tracking_token ?? null;
    if (!token && !row.payment_held) {
      // Parcel predates tracking-token issuance - mint one on first read.
      // Held parcels mint nothing: tracking is locked until payment settles.
      const jobRow = await c.env.DB.prepare('SELECT id, ref FROM jobs WHERE ref = ?1')
        .bind(row.ref).first<any>();
      if (jobRow) token = await issueTrackingToken(c.env, jobRow.id, jobRow.ref, phone);
    }
    parcels.push({
      ref: row.ref, status: row.status, created_at: row.created_at,
      dest_city: row.dest_city, recipient_name: row.recipient_name,
      courier: row.courier_name, depot: row.courier_depot,
      tracking_url: token && !row.payment_held ? `${APP_URL}/track/${token}` : null,
    });
  }
  return c.json({ parcels });
});

// Participants/ops can fetch (or mint) their job's share link.
app.post('/jobs/:ref/tracking-link', async (c) => {
  const job = await c.env.DB.prepare(
    'SELECT id, ref, sender_phone, recipient_phone FROM jobs WHERE ref = ?1',
  ).bind(c.req.param('ref')).first<any>();
  if (!job) return c.json({ error: 'not found' }, 404);
  if (c.get('role') === 'customer' && c.get('phone') !== job.sender_phone && c.get('phone') !== job.recipient_phone) {
    return c.json({ error: 'not found' }, 404);
  }
  // PAYMENT-HELD JOBS NEVER MINT OR SERVE TRACKING (owner directive
  // 2026-11-15): "Track this delivery" / "Share" against a booking whose
  // prepayment is still pending gets 402, not a live link. It unlocks
  // itself at settlement (paid = 1) — no manual step.
  if (await jobPaymentHeld(c.env.DB, job.id)) {
    return c.json({ error: 'payment_required', hint: 'Prepayment pending — tracking opens once payment is approved.' }, 402);
  }
  const existing = await c.env.DB.prepare(
    'SELECT token FROM tracking_tokens WHERE job_id = ?1 ORDER BY created_at DESC LIMIT 1',
  ).bind(job.id).first<{ token: string }>();
  const token = existing?.token ?? await issueTrackingToken(c.env, job.id, job.ref, job.recipient_phone);
  return c.json({ token, url: trackingUrl(c.env, token) });
});

/* ------------------------------- Delivery IQ ------------------------------ */
// GET /iq/eta?courier_id=&window= — how fast does this courier actually reach
// the depot? Computed from real job_events (picked_up ? at_depot) over the
// last 90 days (max 300 jobs), optionally filtered to one pickup window.
// Signed-in callers only (booking screen shows it next to the window picker).
app.get('/iq/eta', async (c) => {
  if (!c.get('phone')) return c.json({ error: 'identity_required' }, 401);
  const courierId = Number(c.req.query('courier_id') ?? '');
  const window = c.req.query('window') ?? '';
  if (!courierId) return c.json({ error: 'courier_id required' }, 400);
  const rows = await c.env.DB.prepare(
    `SELECT j.pickup_window,
            MIN(CASE WHEN e.status = 'picked_up' THEN e.created_at END) AS picked_at,
            MIN(CASE WHEN e.status = 'at_depot' THEN e.created_at END) AS depot_at
       FROM jobs j JOIN job_events e ON e.job_id = j.id
      WHERE j.courier_id = ?1 AND j.created_at >= datetime('now', '-90 days')
      GROUP BY j.id LIMIT 300`,
  ).bind(courierId).all<any>();
  const mins: number[] = [];
  for (const r of rows.results ?? []) {
    if (window && r.pickup_window !== window) continue;
    if (!r.picked_at || !r.depot_at) continue;
    const t1 = Date.parse(String(r.picked_at).replace(' ', 'T') + 'Z');
    const t2 = Date.parse(String(r.depot_at).replace(' ', 'T') + 'Z');
    if (Number.isNaN(t1) || Number.isNaN(t2)) continue;
    const m = Math.round((t2 - t1) / 60000);
    if (m >= 0 && m < 24 * 60) mins.push(m); // drop bogus/negative gaps
  }
  if (mins.length === 0) {
    // Cold start: no 90-day history yet. Fall back to the advertised window
    // bands so the estimate is still useful (labelled, never passed off as IQ).
    const bands: Record<string, number> = { '06:00': 50, '10:00': 45, '14:00': 45 };
    const p50 = bands[window] ?? 50;
    return c.json({
      courier_id: courierId,
      window: window || null,
      sample_count: 0,
      fallback: true,
      minutes_p50: p50,
      minutes_p90: p50 + 25,
      minutes_avg: p50 + 5,
      basis: 'advertised window bands (no measured history yet)',
    });
  }
  mins.sort((a, b) => a - b);
  const p = (q: number) => mins[Math.min(mins.length - 1, Math.floor(q * mins.length))];
  const avg = Math.round(mins.reduce((s, m) => s + m, 0) / mins.length);
  return c.json({
    courier_id: courierId,
    window: window || null,
    sample_count: mins.length,
    minutes_p50: p(0.5),
    minutes_p90: p(0.9),
    minutes_avg: avg,
    basis: 'actual pickup?depot times, last 90 days',
  });
});

/* --------------------------- DropOff Predict ------------------------------- */
// Explainable heuristics over real job data - deliberately no opaque ML and no
// fake certainty. Every number ships with its basis and sample size so the UI
// can show confidence honestly. Three surfaces:
//   predictEtaForJob()  - per-parcel "when will it arrive" on the tracking page
//   GET /predict/seller - the seller's next-30-day forecast + plan pick
//   GET /admin/demand-forecast - ops heatmap (branch x window x weekday)
const toMs = (s: unknown): number | null => {
  const raw = String(s ?? '').trim();
  if (!raw) return null;
  const t = raw.replace(' ', 'T');
  const naive = !/(Z|[+-]\d{2}:?\d{2})$/i.test(t);
  const ms = Date.parse(naive ? `${t}Z` : t);
  return Number.isNaN(ms) ? null : ms;
};
const CAT_MS = 2 * 3600 * 1000; // Central Africa Time (UTC+2, no DST)
const percentile = (sorted: number[], q: number) =>
  sorted[Math.min(sorted.length - 1, Math.floor(q * sorted.length))];
const catToday = () => new Date(Date.now() + CAT_MS);

type EtaPrediction = {
  eta_minutes: number | null;
  arrival_by: string | null;
  confidence: 'high' | 'medium' | 'low';
  sample_count: number;
  basis: string;
};

/** Per-parcel arrival prediction from this courier's measured history. The
 *  parcel flow is created -> picked_up -> at_depot -> (last mile) -> delivered.
 *  We predict the remaining legs with p50s and never claim more than the data
 *  supports (low sample -> 'low' confidence + plain-language basis). */
async function predictEtaForJob(db: D1Database, job: any, events: any[]): Promise<EtaPrediction> {
  const evList: any[] = Array.isArray(events) ? events : [];
  const evTime = (s: string) => toMs(evList.find((e: any) => e.status === s)?.created_at);
  const delivered = evTime('delivered') ?? evTime('ready_for_collection') ?? evTime('partner_confirmed');
  if (delivered != null) {
    return {
      eta_minutes: 0,
      arrival_by: new Date(delivered).toISOString(),
      confidence: 'high',
      sample_count: 0,
      basis: 'parcel already delivered / ready for collection',
    };
  }
  const { results: hist } = await db.prepare(
    `SELECT MIN(CASE WHEN e.status = 'picked_up' THEN e.created_at END) AS picked_at,
            MIN(CASE WHEN e.status = 'at_depot' THEN e.created_at END) AS depot_at,
            MIN(CASE WHEN e.status = 'delivered' THEN e.created_at END) AS delivered_at
       FROM jobs j JOIN job_events e ON e.job_id = j.id
      WHERE j.courier_id = ?1 AND j.id != ?2 AND j.created_at >= datetime('now', '-180 days')
      GROUP BY j.id LIMIT 200`,
  ).bind(job.courier_id ?? 0, job.job_id ?? 0).all<any>();
  const firstMile: number[] = [];
  const lastMile: number[] = [];
  for (const h of hist ?? []) {
    const p = toMs(h.picked_at), d = toMs(h.depot_at), del = toMs(h.delivered_at);
    if (p != null && d != null && d >= p && d - p < 24 * 3600 * 1000) firstMile.push(Math.round((d - p) / 60000));
    if (d != null && del != null && del >= d && del - d < 24 * 3600 * 1000) lastMile.push(Math.round((del - d) / 60000));
  }
  firstMile.sort((a, b) => a - b);
  lastMile.sort((a, b) => a - b);
  const p50fm = firstMile.length ? percentile(firstMile, 0.5) : null;
  const p50lm = lastMile.length ? percentile(lastMile, 0.5) : null;
  const sample = Math.max(firstMile.length, lastMile.length);
  const confidence = sample >= 30 ? 'high' : sample >= 8 ? 'medium' : 'low';
  const basis = sample === 0
    ? 'no measured history for this courier yet - shown as a rough estimate'
    : `courier's last ${sample} parcels (180d): pickup?depot ~${p50fm ?? '?'} min` +
      (p50lm != null ? `, depot?door ~${p50lm} min` : '');
  const fm = p50fm ?? 45;
  const lm = p50lm ?? 45;
  const now = Date.now();
  const depot = evTime('at_depot');
  const picked = evTime('picked_up');
  let eta: number;
  if (depot != null) {
    eta = Math.max(10, lm - Math.round((now - depot) / 60000));
  } else if (picked != null) {
    // First mile in flight: remainder of it, then the last mile.
    eta = Math.max(10, (fm - Math.round((now - picked) / 60000)) + lm);
  } else {
    // Not collected yet - full estimate from now.
    eta = fm + lm;
  }
  return {
    eta_minutes: eta,
    arrival_by: new Date(now + eta * 60000).toISOString(),
    confidence,
    sample_count: sample,
    basis,
  };
}

app.get('/predict/seller', async (c) => {
  const phone = c.get('phone');
  if (!phone) return c.json({ error: 'identity_required' }, 401);
  const db = c.env.DB;
  const { results: monthRows } = await db.prepare(
    `SELECT strftime('%Y-%m', datetime(created_at, '+2 hours')) AS ym,
            COALESCE(SUM(parcels), COUNT(*)) AS n
       FROM jobs
      WHERE sender_phone = ?1 AND created_at >= datetime('now', '-183 days') AND status NOT IN ('cancelled', 'canceled')
      GROUP BY ym`,
  ).bind(phone).all<any>();
  const byMonth = new Map<string, number>();
  for (const r of monthRows ?? []) byMonth.set(String(r.ym), Number(r.n) || 0);
  const now = catToday();
  const slots: { ym: string; n: number }[] = [];
  for (let i = 5; i >= 0; i--) {
    const d = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - i, 1));
    const key = `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`;
    slots.push({ ym: key, n: byMonth.get(key) ?? 0 });
  }
  // Least-squares over the six monthly totals, blended with the trailing
  // 3-month average (6 points make the raw slope noisy on its own).
  const ys = slots.map((s) => s.n);
  const xs = ys.map((_, i) => i);
  const nPts = xs.length;
  const sx = xs.reduce((a, b) => a + b, 0);
  const sy = ys.reduce((a, b) => a + b, 0);
  const sxx = xs.reduce((a, x) => a + x * x, 0);
  const sxy = xs.reduce((a, x, i) => a + x * ys[i], 0);
  const slope = nPts * sxx - sx * sx !== 0 ? (nPts * sxy - sx * sy) / (nPts * sxx - sx * sx) : 0;
  const intercept = (sy - slope * sx) / nPts;
  const trendForecast = intercept + slope * 6;
  const last3 = ys.slice(-3).reduce((a, b) => a + b, 0) / 3;
  const blended = Math.max(0, Math.round(0.5 * trendForecast + 0.5 * last3));

  const active = await db.prepare(
    `SELECT COUNT(*) AS k, AVG(rider_fee_zmw) AS avg_fee
       FROM jobs WHERE sender_phone = ?1 AND created_at >= datetime('now', '-90 days') AND status NOT IN ('cancelled', 'canceled')`,
  ).bind(phone).first<any>();
  const sample = Number(active?.k ?? 0);
  const avgFee = Number(active?.avg_fee ?? 45) || 45;
  const peakWindow = (await db.prepare(
    `SELECT pickup_window, COUNT(*) AS n FROM jobs
      WHERE sender_phone = ?1 AND created_at >= datetime('now', '-90 days') AND pickup_window IS NOT NULL
      GROUP BY pickup_window ORDER BY n DESC LIMIT 1`,
  ).bind(phone).first<any>())?.pickup_window ?? null;
  const peakWeekday = (await db.prepare(
    `SELECT strftime('%w', datetime(created_at, '+2 hours')) AS wd, COUNT(*) AS n FROM jobs
      WHERE sender_phone = ?1 AND created_at >= datetime('now', '-90 days')
      GROUP BY wd ORDER BY n DESC LIMIT 1`,
  ).bind(phone).first<any>())?.wd ?? null;

  // Plan pick: economic comparison across every paid tier — pick the plan with
  // the MAXIMUM estimated savings (tie-break: cheaper fee), never a first-match
  // scan. The old loop always pitched the first plan in the list (Weekly
  // Sprint K399), so a seller with a 1-parcel forecast was shown "save K-315".
  // A plan that costs more than pay-as-you-go is NOT a recommendation.
  const catalogue = await plans(db);
  const paid = ['weekly', 'silver', 'gold', 'platinum'] as const;
  const tierLabel: Record<string, string> = { weekly: 'Weekly Sprint', silver: 'Silver', gold: 'Gold', platinum: 'Platinum' };
  let best: any = null;
  if (blended > 0) {
    for (const tier of paid) {
      const p = catalogue[tier];
      const est = Math.round(Math.min(blended, p.parcels_per_month) * avgFee - p.fee_zmw);
      if (est < 0) continue; // losing deal — never recommend
      if (!best || est > best.est_savings_zmw || (est === best.est_savings_zmw && p.fee_zmw < best.fee_zmw)) {
        best = { tier, tag: p.tag ?? tierLabel[tier], fee_zmw: p.fee_zmw, parcels_per_month: p.parcels_per_month, est_savings_zmw: est };
      }
    }
  }
  // Break-even teaser (honest ladder): the cheapest plan that can actually pay
  // for itself at this seller's average fee, and the parcel count where it
  // flips positive. Injected into daily_option.note so it renders on every
  // installed app without a client update.
  let planTeaser: string | null = null;
  if (blended > 0 && !best) {
    let teaser: { tier: PlanTier; label: string; parcels: number } | null = null;
    for (const tier of paid) {
      const p = catalogue[tier];
      const need = Math.ceil(p.fee_zmw / Math.max(1, avgFee));
      if (need <= p.parcels_per_month && (!teaser || need < teaser.parcels || (need === teaser.parcels && p.fee_zmw < catalogue[teaser.tier].fee_zmw))) {
        teaser = { tier, label: tierLabel[tier], parcels: need };
      }
    }
    if (teaser) planTeaser = `Ship ~${teaser.parcels} parcels this month and ${teaser.label} (K${catalogue[teaser.tier].fee_zmw}) pays for itself.`;
  }
  // Daily Rider covers ONE parcel per active day — a 30-parcel month needs
  // 30 activations (that's why the pass only wins for genuinely bursty senders).
  const dailyDays = Math.min(30, Math.ceil(blended));
  const paygCost = Math.round(blended * avgFee);
  const dailyCost = dailyDays * catalogue.rider_daily.fee_zmw;
  let dailyNote = 'On-demand days - activate only the days you ship. 24h validity, 1 parcel included per day.';
  if (blended > 0 && dailyDays > 0) {
    dailyNote += ` Each active day beats one pay-as-you-go trip on price.`;
    dailyNote += ` At your volume: ~${dailyDays} active days × K${catalogue.rider_daily.fee_zmw} ≈ K${dailyCost} vs ≈ K${paygCost} pay-as-you-go.`;
    if (planTeaser) dailyNote += ` ${planTeaser}`;
  }
  const dailyOption = blended > 0 && dailyDays <= 30
    ? {
      days_needed: dailyDays,
      cost_zmw: dailyCost,
      note: dailyNote,
    }
    : null;
  const confidence = sample >= 60 ? 'high' : sample >= 15 ? 'medium' : 'low';
  return c.json({
    generated_at: new Date().toISOString(),
    months: slots,
    parcels_90d: sample,
    peak_window: peakWindow,
    peak_weekday: peakWeekday == null ? null : Number(peakWeekday),
    forecast_next_30d: blended,
    trend_parcels_per_month: Math.round(slope * 10) / 10,
    avg_rider_fee_zmw: Math.round(avgFee * 100) / 100,
    recommended_plan: best,
    plan_teaser: planTeaser,
    daily_option: dailyOption,
    confidence,
    basis: 'least-squares over the last 6 CAT months, blended 50/50 with the trailing 3-month average',
  });
});

const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
app.get('/admin/demand-forecast', async (c) => {
  if (!isAdmin(c) && c.get('role') !== 'ops') return c.json({ error: 'forbidden' }, 403);
  const db = c.env.DB;
  const { results: rows } = await db.prepare(
    `SELECT COALESCE(NULLIF(TRIM(branch), ''), 'Unspecified') AS branch,
            COALESCE(NULLIF(pickup_window, ''), 'unscheduled') AS window,
            CAST(strftime('%w', datetime(created_at, '+2 hours')) AS INTEGER) AS weekday,
            COUNT(*) AS trips,
            COALESCE(SUM(parcels), COUNT(*)) AS parcels
       FROM jobs
      WHERE created_at >= datetime('now', '-56 days') AND status NOT IN ('cancelled', 'canceled')
      GROUP BY 1, 2, 3`,
  ).all<any>();
  // Trailing 56 days = exactly 8 occurrences of each weekday -> divide by 8.
  const windows = ['06:00', '10:00', '14:00', 'now', 'unscheduled'];
  type Cell = { [w: string]: number[] }; // window -> 7 weekday means
  const branches = new Map<string, Cell>();
  let sampleTrips = 0;
  let sampleParcels = 0;
  for (const r of rows ?? []) {
    const key = String(r.branch);
    const w = String(r.window);
    const wd = Number(r.weekday);
    const parcels = Number(r.parcels) || 0;
    sampleTrips += Number(r.trips) || 0;
    sampleParcels += parcels;
    if (!branches.has(key)) {
      const cell: Cell = {};
      for (const win of windows) cell[win] = [0, 0, 0, 0, 0, 0, 0];
      branches.set(key, cell);
    }
    const cell = branches.get(key)!;
    if (!cell[w]) cell[w] = [0, 0, 0, 0, 0, 0, 0];
    if (wd >= 0 && wd <= 6) cell[w][wd] += parcels / 8;
  }
  const today = catToday();
  const dayWindowKeys = new Set<string>();
  for (const cell of branches.values()) for (const w of Object.keys(cell)) dayWindowKeys.add(w);
  const orderedWindows = [...dayWindowKeys];
  const days: any[] = [];
  for (let i = 0; i < 7; i++) {
    const d = new Date(today.getTime() + i * 86400000);
    const wd = d.getUTCDay();
    const perWindow: Record<string, number> = {};
    let total = 0;
    for (const w of orderedWindows) {
      let sum = 0;
      for (const cell of branches.values()) sum += cell[w]?.[wd] ?? 0;
      perWindow[w] = Math.round(sum * 10) / 10;
      total += perWindow[w];
    }
    days.push({
      date: d.toISOString().slice(0, 10),
      weekday: WEEKDAYS[wd],
      windows: perWindow,
      total: Math.round(total * 10) / 10,
    });
  }
  const branchList = [...branches.entries()]
    .map(([branch, cell]) => {
      const byWindow: Record<string, number> = {};
      let sevenDay = 0;
      for (const w of Object.keys(cell)) {
        const windowTotal = cell[w].reduce((a, b) => a + b, 0);
        byWindow[w] = Math.round(windowTotal * 10) / 10;
        sevenDay += windowTotal; // every weekday occurs exactly once in 7 days
      }
      return { branch, predicted_7d_parcels: Math.round(sevenDay * 10) / 10, by_window: byWindow };
    })
    .sort((a, b) => b.predicted_7d_parcels - a.predicted_7d_parcels)
    .slice(0, 12);
  const sevenDayTotal = branchList.reduce((a, b) => a + b.predicted_7d_parcels, 0);
  const busiestBranch = branchList[0]?.branch ?? null;
  const busiestWindow = (() => {
    const sums: Record<string, number> = {};
    for (const b of branchList) for (const [w, v] of Object.entries(b.by_window)) sums[w] = (sums[w] ?? 0) + v;
    const top = Object.entries(sums).sort((a, b) => b[1] - a[1])[0];
    return top ? top[0] : null;
  })();
  return c.json({
    generated_at: new Date().toISOString(),
    basis: 'same weekday+window parcel average of the trailing 8 weeks (CAT)',
    sample_trips_56d: sampleTrips,
    sample_parcels_56d: sampleParcels,
    days,
    branches: branchList,
    totals: {
      predicted_7d_parcels: Math.round(sevenDayTotal * 10) / 10,
      busiest_branch: busiestBranch,
      busiest_window: busiestWindow,
    },
  });
});

/* ---------------------------------- chat ---------------------------------- */
// One thread per job: seller, recipient (token), assigned rider, depot partner
// and ops share it. Support threads (kind='support') connect a phone to ops.

type ChatRole = 'seller' | 'recipient' | 'rider' | 'courier' | 'ops' | 'partner';

async function jobChatRole(c: any, job: any): Promise<ChatRole | null> {
  const phone: string | null = c.get('phone') ?? null;
  const role: string | null = c.get('role') ?? null;
  if (phone && phone === job.sender_phone) return 'seller';
  if (phone && phone === job.recipient_phone) return 'recipient';
  if (phone && role === 'partner' && c.get('courierId') != null && Number(c.get('courierId')) === Number(job.courier_id)) {
    // Explicit join required: linked depots observe a delivery's chat only
    // after tapping Join (0060_chat_partner_joins). No join row → 404, same
    // as any outsider — the join door is surfaced via /join-status.
    const joined = await c.env.DB.prepare(
      `SELECT 1 AS x FROM chat_partner_joins p
         JOIN chat_threads t ON t.id = p.thread_id
        WHERE t.job_id = ?1 AND p.phone = ?2`,
    ).bind(job.id, phone).first();
    if (joined) return 'partner';
    return null;
  }
  if (phone && job.rider_id) {
    const rider: any = await c.env.DB.prepare('SELECT phone FROM riders WHERE id = ?1').bind(job.rider_id).first();
    if (rider?.phone === phone) return 'rider';
  }
  return null;
}

async function getOrCreateJobThread(env: Env, jobId: number): Promise<number> {
  const existing = await env.DB.prepare('SELECT id FROM chat_threads WHERE job_id = ?1').bind(jobId).first<{ id: number }>();
  if (existing) return existing.id;
  const { meta } = await env.DB.prepare(
    'INSERT INTO chat_threads (kind, job_id) VALUES (\'job\', ?1)',
  ).bind(jobId).run();
  return meta.last_row_id as number;
}

// Viewers never see: messages hidden by admin review, or messages from
// participants *they* have blocked (unblocks restore them instantly).
// Returns the filtered list; the caller also gets the phones this viewer
// blocks among the thread's senders, so clients can show an unblock banner.
async function chatMessages(env: Env, threadId: number, viewerPhone: string | null = null) {
  const { results } = await env.DB.prepare(
    `SELECT m.id, m.sender_phone, m.sender_role, m.body, m.created_at,
            COALESCE(au.photo_url, r.photo_url) AS sender_photo_url,
            COALESCE(NULLIF(au.full_name, ''), NULLIF(r.full_name, '')) AS sender_name
       FROM chat_messages m
       LEFT JOIN auth_users au ON au.phone = m.sender_phone
       LEFT JOIN riders r ON r.phone = m.sender_phone
      WHERE m.thread_id = ?1 AND m.hidden = 0 ORDER BY m.id ASC LIMIT 200`,
  ).bind(threadId).all();
  if (!viewerPhone) return { messages: results, blocked_senders: [] as string[] };
  const blockedRows = await env.DB.prepare('SELECT blocked FROM user_blocks WHERE blocker = ?1')
    .bind(viewerPhone).all<{ blocked: string }>();
  const blocked = new Set(blockedRows.results.map((r) => r.blocked));
  const messages = blocked.size ? results.filter((m) => !blocked.has(String(m.sender_phone))) : results;
  const senders = await env.DB.prepare(
    'SELECT DISTINCT sender_phone FROM chat_messages WHERE thread_id = ?1 AND hidden = 0',
  ).bind(threadId).all<{ sender_phone: string }>();
  return {
    messages,
    blocked_senders: [...senders.results.map((r) => r.sender_phone)].filter((p) => blocked.has(p) && p !== 'ops'),
  };
}

// One gate for every REST chat send: suspensions first (403), then abuse
// (400 + an automatic strike toward the 3-strike suspension).
async function chatSendGate(c: any, body: string, senderPhone: string | null): Promise<Response | null> {
  if (senderPhone) {
    const until = await chatSuspendedUntil(c.env, senderPhone);
    if (until) return c.json({ error: 'chat_suspended', until }, 403);
  }
  if (containsAbuse(body)) {
    if (senderPhone) await recordAbuseStrike(c.env, senderPhone);
    return c.json({ error: 'message_blocked', message: 'Keep messages respectful.' }, 400);
  }
  return null;
}

async function markThreadRead(env: Env, threadId: number, phone: string): Promise<void> {
  const last = await env.DB.prepare(
    'SELECT MAX(id) AS m FROM chat_messages WHERE thread_id = ?1',
  ).bind(threadId).first<{ m: number | null }>();
  await env.DB.prepare(
    `INSERT INTO chat_reads (thread_id, phone, last_read_id) VALUES (?1, ?2, ?3)
      ON CONFLICT(thread_id, phone) DO UPDATE SET last_read_id = MAX(chat_reads.last_read_id, excluded.last_read_id),
        updated_at = datetime('now')`,
  ).bind(threadId, phone, last?.m ?? 0).run();
}

async function notifyChatParticipants(env: Env, thread: any, job: any, fromPhone: string, preview: string): Promise<void> {
  const targets = new Set<string>();
  if (job) {
    if (job.sender_phone) targets.add(job.sender_phone);
    if (job.recipient_phone) targets.add(job.recipient_phone);
    if (job.rider_id) {
      const rider = await env.DB.prepare('SELECT phone FROM riders WHERE id = ?1').bind(job.rider_id).first<{ phone: string }>();
      if (rider?.phone) targets.add(rider.phone);
    }
  } else if (thread?.phone) {
    targets.add(thread.phone);
    const op = ownerPhone(env);
    if (op) targets.add(op);
  }
  targets.delete(fromPhone);
  for (const t of targets) {
    await sendToPhone(env, t, { title: 'New DropOff message', body: preview, data: { kind: 'chat', thread_id: String(thread?.id ?? '') } });
  }
}

// Job thread — sellers/riders/partners/ops (JWT or key)
app.get('/jobs/:ref/chat', async (c) => {
  const job = await c.env.DB.prepare(
    'SELECT id, ref, sender_phone, recipient_phone, courier_id, rider_id FROM jobs WHERE ref = ?1',
  ).bind(c.req.param('ref')).first<any>();
  if (!job) return c.json({ error: 'not found' }, 404);
  const chatRole = await jobChatRole(c, job);
  if (!chatRole) return c.json({ error: 'not found' }, 404); // no existence leak
  const threadId = await getOrCreateJobThread(c.env, job.id);
  const thread = await c.env.DB.prepare('SELECT closed_by, closed_at FROM chat_threads WHERE id = ?1').bind(threadId).first<{ closed_by: string | null; closed_at: string | null }>();
  const viewerPhone = c.get('phone');
  if (viewerPhone) await markThreadRead(c.env, threadId, viewerPhone);
  const chat = await chatMessages(c.env, threadId, viewerPhone);
  return c.json({ thread_id: threadId, role: chatRole, closed_by: thread?.closed_by ?? null, closed_at: thread?.closed_at ?? null, ...chat });
});

// Suspended or abusive senders are stopped before insertion; a profanity-hit
// counts as an automatic strike (3 strikes = 7-day chat suspension).

app.post('/jobs/:ref/chat', async (c) => {
  if (await rateLimited(c, 'chat_send', 30, 10)) return c.json({ error: 'too_many_requests' }, 429);
  const b: any = await c.req.json().catch(() => null);
  const body = String(b?.body ?? '').trim().slice(0, 500);
  if (!body) return c.json({ error: 'body required' }, 400);
  const job = await c.env.DB.prepare(
    'SELECT id, ref, sender_phone, recipient_phone, courier_id, rider_id FROM jobs WHERE ref = ?1',
  ).bind(c.req.param('ref')).first<any>();
  if (!job) return c.json({ error: 'not found' }, 404);
  const chatRole = await jobChatRole(c, job);
  if (!chatRole) return c.json({ error: 'not found' }, 404);
  const gate = await chatSendGate(c, body, c.get('phone') ?? null);
  if (gate) return gate;
  const threadId = await getOrCreateJobThread(c.env, job.id);
  const thread = await c.env.DB.prepare('SELECT closed_at FROM chat_threads WHERE id = ?1').bind(threadId).first<{ closed_at: string | null }>();
  if (thread?.closed_at) return c.json({ error: 'chat_closed', detail: 'This conversation has been closed. Read-only history remains for everyone.' }, 409);
  const senderPhone = c.get('phone') ?? 'ops';
  const { meta } = await c.env.DB.prepare(
    `INSERT INTO chat_messages (thread_id, sender_phone, sender_role, body) VALUES (?1, ?2, ?3, ?4)`,
  ).bind(threadId, senderPhone, chatRole, body).run();
  await markThreadRead(c.env, threadId, senderPhone);
  c.executionCtx.waitUntil(
    notifyChatParticipants(c.env, { id: threadId }, job, senderPhone, body.slice(0, 60)).catch(() => {}),
  );
  return c.json({ ok: true, id: meta.last_row_id });
});

// Recipient chat via the tracking token — same ACCOUNT gate as GET /track/:token.
// Signed-in participant phone only; the link alone never opens a thread.
app.get('/track/:token/chat', async (c) => {
  const access = await trackAccess(c, c.req.param('token'));
  if (!access.jobId) return c.json({ error: 'not found' }, 404);
  if (!access.granted) return c.json({ error: 'verification_required' }, 401);
  const threadId = await getOrCreateJobThread(c.env, access.jobId);
  const chat = await chatMessages(c.env, threadId, access.recipientPhone);
  if (access.recipientPhone) await markThreadRead(c.env, threadId, access.recipientPhone);
  const thread = await c.env.DB.prepare('SELECT closed_by, closed_at FROM chat_threads WHERE id = ?1').bind(threadId).first<{ closed_by: string | null; closed_at: string | null }>();
  return c.json({ thread_id: threadId, role: 'recipient', closed_by: thread?.closed_by ?? null, closed_at: thread?.closed_at ?? null, ...chat });
});

app.post('/track/:token/chat', async (c) => {
  if (await rateLimited(c, 'chat_send', 30, 10)) return c.json({ error: 'too_many_requests' }, 429);
  // Per-TOKEN throttle on top of the per-IP bucket: one leaked grant must not
  // be able to flood the thread from rotating IPs.
  if (await rateLimited(c, `track_chat:${c.req.param('token')}`, 20, 10)) {
    return c.json({ error: 'too_many_requests' }, 429);
  }
  const b: any = await c.req.json().catch(() => null);
  const body = String(b?.body ?? '').trim().slice(0, 500);
  if (!body) return c.json({ error: 'body required' }, 400);
  const access = await trackAccess(c, c.req.param('token'));
  if (!access.jobId) return c.json({ error: 'not found' }, 404);
  if (!access.granted) return c.json({ error: 'verification_required' }, 401);
  const gate = await chatSendGate(c, body, access.recipientPhone);
  if (gate) return gate;
  const job = await c.env.DB.prepare(
    'SELECT id, ref, sender_phone, recipient_phone, courier_id, rider_id FROM jobs WHERE id = ?1',
  ).bind(access.jobId).first<any>();
  if (!job) return c.json({ error: 'not found' }, 404);
  const threadId = await getOrCreateJobThread(c.env, job.id);
  const thread = await c.env.DB.prepare('SELECT closed_at FROM chat_threads WHERE id = ?1').bind(threadId).first<{ closed_at: string | null }>();
  if (thread?.closed_at) return c.json({ error: 'chat_closed', detail: 'This conversation has been closed. Read-only history remains for everyone.' }, 409);
  const { meta } = await c.env.DB.prepare(
    `INSERT INTO chat_messages (thread_id, sender_phone, sender_role, body) VALUES (?1, ?2, 'recipient', ?3)`,
  ).bind(threadId, job.recipient_phone, body).run();
  await markThreadRead(c.env, threadId, job.recipient_phone);
  c.executionCtx.waitUntil(
    notifyChatParticipants(c.env, { id: threadId }, job, job.recipient_phone, body.slice(0, 60)).catch(() => {}),
  );
  return c.json({ ok: true, id: meta.last_row_id });
});

// Support thread (seller/anyone signed in <-> ops)
app.post('/chat/support', async (c) => {
  if (await rateLimited(c, 'chat_send', 20, 10)) return c.json({ error: 'too_many_requests' }, 429);
  const b: any = await c.req.json().catch(() => null);
  const body = String(b?.body ?? '').trim().slice(0, 500);
  const phone = c.get('phone');
  if (!phone) return c.json({ error: 'identity_required' }, 401);
  const existing = await c.env.DB.prepare(
    `SELECT id FROM chat_threads WHERE kind = 'support' AND phone = ?1`,
  ).bind(phone).first<{ id: number }>();
  let threadId: number;
  if (existing) threadId = existing.id;
  else {
    const { meta } = await c.env.DB.prepare(
      `INSERT INTO chat_threads (kind, phone) VALUES ('support', ?1)`,
    ).bind(phone).run();
    threadId = meta.last_row_id as number;
  }
  if (body) {
    const gate = await chatSendGate(c, body, phone);
    if (gate) return gate;
    await c.env.DB.prepare(
      `INSERT INTO chat_messages (thread_id, sender_phone, sender_role, body) VALUES (?1, ?2, 'seller', ?3)`,
    ).bind(threadId, phone, body).run();
    const thread = { id: threadId, phone };
    c.executionCtx.waitUntil(notifyChatParticipants(c.env, thread, null, phone, body.slice(0, 60)).catch(() => {}));
  }
  await markThreadRead(c.env, threadId, phone);
  const chat = await chatMessages(c.env, threadId, phone);
  return c.json({ thread_id: threadId, role: 'seller', ...chat });
});

// Ops replies on a support thread
app.post('/chat/support/:id/reply', async (c) => {
  if (c.get('role') !== 'ops' && !isAdmin(c)) return c.json({ error: 'forbidden' }, 403);
  const b: any = await c.req.json().catch(() => null);
  const body = String(b?.body ?? '').trim().slice(0, 500);
  if (!body) return c.json({ error: 'body required' }, 400);
  const threadId = Number(c.req.param('id'));
  const thread = await c.env.DB.prepare(`SELECT id, phone FROM chat_threads WHERE id = ?1 AND kind = 'support'`).bind(threadId).first<any>();
  if (!thread) return c.json({ error: 'not found' }, 404);
  await c.env.DB.prepare(
    `INSERT INTO chat_messages (thread_id, sender_phone, sender_role, body) VALUES (?1, ?2, 'ops', ?3)`,
  ).bind(threadId, c.get('phone') ?? 'ops', body).run();
  c.executionCtx.waitUntil(notifyChatParticipants(c.env, thread, null, c.get('phone') ?? 'ops', body.slice(0, 60)).catch(() => {}));
  return c.json({ ok: true });
});

/* ----------------------- UGC safety: report & block ------------------------ */
// Play-required user-reporting and user-blocking for chat content.

// Rate-limited report of a single chat message by a participant of the thread.
app.post('/chat/messages/:id/report', async (c) => {
  if (await rateLimited(c, 'chat_report', 10, 3600)) return c.json({ error: 'too_many_requests' }, 429);
  const reporter = c.get('phone');
  if (!reporter) return c.json({ error: 'identity_required' }, 401);
  const messageId = Number(c.req.param('id'));
  if (!Number.isFinite(messageId)) return c.json({ error: 'bad id' }, 400);
  const b: any = await c.req.json().catch(() => ({}));
  const cat = ['harassment', 'spam', 'other'].includes(String(b?.reason)) ? String(b.reason) : 'other';
  const note = typeof b?.note === 'string' ? String(b.note).trim().slice(0, 200) : '';

  const msg = await c.env.DB.prepare('SELECT id, thread_id, sender_phone FROM chat_messages WHERE id = ?1')
    .bind(messageId).first<any>();
  // No existence leak: an unknown id, your own or an ops message is a 404.
  if (!msg || msg.sender_phone === reporter || msg.sender_phone === 'ops') return c.json({ error: 'not found' }, 404);
  const thread = await c.env.DB.prepare('SELECT id, kind, phone, job_id FROM chat_threads WHERE id = ?1')
    .bind(msg.thread_id).first<any>();
  if (!thread) return c.json({ error: 'not found' }, 404);
  if (thread.kind === 'support') {
    if (thread.phone !== reporter) return c.json({ error: 'forbidden' }, 403);
  } else if (thread.job_id) {
    const job = await c.env.DB.prepare(
      'SELECT id, sender_phone, recipient_phone, courier_id, rider_id FROM jobs WHERE id = ?1',
    ).bind(thread.job_id).first<any>();
    const chatRole = job ? await jobChatRole(c, job) : null;
    if (!chatRole) return c.json({ error: 'forbidden' }, 403);
  }
  const dup = await c.env.DB.prepare(
    'SELECT id FROM chat_reports WHERE message_id = ?1 AND reported_by = ?2',
  ).bind(messageId, reporter).first<{ id: number }>();
  if (dup) return c.json({ ok: true, already_reported: true });
  const reason = note ? `${cat}: ${note}` : cat;
  const { meta } = await c.env.DB.prepare(
    `INSERT INTO chat_reports (message_id, thread_id, reported_by, reason) VALUES (?1, ?2, ?3, ?4)`,
  ).bind(messageId, msg.thread_id, reporter, reason).run();
  return c.json({ ok: true, id: meta.last_row_id });
});

// Block / unblock a user. Their messages disappear from my chat views only.
app.get('/users/blocks', async (c) => {
  const me = c.get('phone');
  if (!me) return c.json({ error: 'identity_required' }, 401);
  const { results } = await c.env.DB.prepare(
    'SELECT blocked, created_at FROM user_blocks WHERE blocker = ?1 ORDER BY created_at DESC LIMIT 200',
  ).bind(me).all();
  return c.json({ blocks: results });
});

app.post('/users/blocks', async (c) => {
  const me = c.get('phone');
  if (!me) return c.json({ error: 'identity_required' }, 401);
  const b: any = await c.req.json().catch(() => ({}));
  const target = normalizeZmPhone(String(b?.phone ?? ''));
  // Never blockable: yourself and system/ops.
  if (!target || target === me || target === 'ops') return c.json({ error: 'bad user' }, 400);
  await c.env.DB.prepare(
    'INSERT INTO user_blocks (blocker, blocked) VALUES (?1, ?2) ON CONFLICT(blocker, blocked) DO NOTHING',
  ).bind(me, target).run();
  return c.json({ ok: true });
});

app.delete('/users/blocks/:phone', async (c) => {
  const me = c.get('phone');
  if (!me) return c.json({ error: 'identity_required' }, 401);
  const target = normalizeZmPhone(String(c.req.param('phone')));
  if (!target) return c.json({ error: 'bad user' }, 400);
  await c.env.DB.prepare('DELETE FROM user_blocks WHERE blocker = ?1 AND blocked = ?2').bind(me, target).run();
  return c.json({ ok: true });
});

/* ---------------------------- chat moderation queue ------------------------- */
// Admin review of user chat reports. "Confirm" hides the message from every
// participant and auto-strikes the sender (3 strikes = 7-day suspension).

app.get('/admin/chat/reports', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'forbidden' }, 403);
  const status = ['open', 'actioned', 'dismissed'].includes(c.req.query('status') ?? '')
    ? c.req.query('status') : 'open';
  const { results } = await c.env.DB.prepare(
    `SELECT r.*, m.body AS message_body, m.sender_phone, m.sender_role, m.hidden AS msg_hidden,
            t.kind AS thread_kind, t.job_id, j.ref AS job_ref
       FROM chat_reports r
       JOIN chat_messages m ON m.id = r.message_id
       JOIN chat_threads t ON t.id = r.thread_id
       LEFT JOIN jobs j ON j.id = t.job_id
      WHERE r.status = ?1 ORDER BY r.id DESC LIMIT 200`,
  ).bind(status).all();
  const strikes = await c.env.DB.prepare(
    `SELECT s.phone, s.strikes, s.suspended_until, s.updated_at FROM chat_strikes s
      WHERE s.strikes > 0 OR s.suspended_until IS NOT NULL
      ORDER BY s.updated_at DESC LIMIT 100`,
  ).all();
  return c.json({ reports: results, strikes: strikes.results });
});

app.post('/admin/chat/reports/:id/review', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'forbidden' }, 403);
  const b: any = await c.req.json().catch(() => ({}));
  const action = String(b?.action ?? '');
  if (action !== 'confirm' && action !== 'dismiss') return c.json({ error: 'bad action' }, 400);
  const { results } = await c.env.DB.prepare(
    `SELECT r.id, r.status, r.message_id, m.sender_phone, m.hidden AS msg_hidden
       FROM chat_reports r JOIN chat_messages m ON m.id = r.message_id
      WHERE r.id = ?1 AND r.status = 'open' LIMIT 1`,
  ).bind(Number(c.req.param('id'))).all();
  const report = results[0];
  if (!report) return c.json({ error: 'not found' }, 404);
  if (action === 'confirm' && report.msg_hidden !== 1) {
    await c.env.DB.prepare('UPDATE chat_messages SET hidden = 1 WHERE id = ?1')
      .bind(report.message_id).run();
    await recordAbuseStrike(c.env, String(report.sender_phone ?? ''));
  }
  await c.env.DB.prepare('UPDATE chat_reports SET status = ?2 WHERE id = ?1')
    .bind(report.id, action === 'confirm' ? 'actioned' : 'dismissed').run();
  return c.json({ ok: true });
});

// Forgiveness lever — clear a user's strikes and lift any chat suspension.
app.post('/admin/chat/strikes/:phone/clear', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'forbidden' }, 403);
  const cleared = await clearChatStrikes(c.env, String(c.req.param('phone')));
  return c.json({ ok: true, cleared });
});

// ── Booking strikes (no-show / ghost bookings) — the No-contact guard ─────
// A sender with 3+ strikes in 14 days is parked from new bookings (see the
// /bookings gate). This endpoint lists everyone parked/on-notice, with the
// job ids behind each strike so ops can eyeball the pattern before clearing.
app.get('/admin/booking-strikes', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'forbidden' }, 403);
  const { results } = await c.env.DB.prepare(
    `SELECT s.phone,
            u.full_name AS sender_name,
            COUNT(*) AS strikes,
            SUM(CASE WHEN s.created_at > datetime('now', '-14 days') THEN 1 ELSE 0 END) AS strikes_14d,
            MAX(s.created_at) AS last_strike,
            MIN(s.created_at) AS first_strike,
            GROUP_CONCAT(DISTINCT j.ref) AS job_refs
       FROM booking_strikes s
       LEFT JOIN auth_users u ON u.phone = s.phone
       LEFT JOIN jobs j ON j.id = s.job_id
      WHERE s.created_at > datetime('now', '-90 days')
      GROUP BY s.phone
      ORDER BY strikes_14d DESC, strikes DESC LIMIT 100`,
  ).all();
  const rows = (results ?? []) as any[];
  return c.json({
    strikes: rows.map((r) => ({
      phone: r.phone,
      sender_name: r.sender_name ?? null,
      strikes: Number(r.strikes ?? 0),
      strikes_14d: Number(r.strikes_14d ?? 0),
      on_hold: Number(r.strikes_14d ?? 0) >= 3,
      last_strike: r.last_strike ?? null,
      job_refs: r.job_refs ?? null,
    })),
  });
});

// Clear the booking strikes for one sender (the unblock button). Deleting the
// rows is all the gate needs — there is no other state to lift.
app.post('/admin/booking-strikes/:phone/clear', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'forbidden' }, 403);
  const phone = String(c.req.param('phone'));
  // One job_event per struck job — audit trail BEFORE the rows vanish.
  try {
    await c.env.DB.prepare(
      `INSERT INTO job_events (job_id, status, note)
       SELECT s.job_id, 'strikes_cleared', 'Booking strikes cleared by ops — sender unparked.'
       FROM booking_strikes s WHERE s.phone = ?1`,
    ).bind(phone).run();
  } catch { /* audit copy must never block the clear */ }
  const cleared = await c.env.DB.prepare('DELETE FROM booking_strikes WHERE phone = ?1').bind(phone).run();
  return c.json({ ok: true, cleared: cleared.meta.changes });
});

// Inbox: my threads with unread counts (seller + recipient-with-JWT + rider view)
app.get('/chat/threads', async (c) => {
  const phone = c.get('phone');
  if (!phone) return c.json({ error: 'identity_required' }, 401);
  const rider = await c.env.DB.prepare('SELECT id FROM riders WHERE phone = ?1').bind(phone).first<{ id: number }>();
  const { results } = await c.env.DB.prepare(
    `SELECT t.id, t.kind, t.job_id, t.closed_by, t.closed_at, j.ref AS job_ref, j.dest_city,
            j.status AS job_status, j.pickup_address,
            (SELECT body FROM chat_messages m WHERE m.thread_id = t.id ORDER BY m.id DESC LIMIT 1) AS last_message,
            (SELECT created_at FROM chat_messages m WHERE m.thread_id = t.id ORDER BY m.id DESC LIMIT 1) AS last_at,
            (SELECT COUNT(*) FROM chat_messages m WHERE m.thread_id = t.id AND m.id > COALESCE((SELECT last_read_id FROM chat_reads r WHERE r.thread_id = t.id AND r.phone = ?1), 0) AND m.sender_phone <> ?1) AS unread
       FROM chat_threads t
       LEFT JOIN jobs j ON j.id = t.job_id
      WHERE (t.kind = 'support' AND t.phone = ?1)
         OR (t.job_id IS NOT NULL AND EXISTS (
              SELECT 1 FROM jobs jj WHERE jj.id = t.job_id
                AND jj.status <> 'canceled'
                AND (jj.sender_phone = ?1 OR jj.recipient_phone = ?1
                     OR (?2 IS NOT NULL AND jj.rider_id = ?2)
                     OR EXISTS (SELECT 1 FROM chat_partner_joins p JOIN chat_threads t2 ON t2.id = p.thread_id WHERE t2.job_id = jj.id AND p.phone = ?1))))`,
  ).bind(phone, rider?.id ?? null).all();
  return c.json({ threads: results });
});

// A linked partner joins the parcel chat for THEIR courier's delivery —
// explicit one-tap opt-in recorded per thread. Before joining, the depot
// sees nothing (the chat 404s like for any outsider); after joining they
// read and write alongside sender, recipient and rider. A closed chat stays
// read-only for everyone, joiners included.
app.post('/jobs/:ref/chat/join', async (c) => {
  const phone = c.get('phone');
  const role = c.get('role');
  if (!phone) return c.json({ error: 'identity_required' }, 401);
  const job = await c.env.DB.prepare('SELECT id, courier_id FROM jobs WHERE ref = ?1').bind(c.req.param('ref')).first<any>();
  if (!job) return c.json({ error: 'not found' }, 404);
  const linked = role === 'partner' && job.courier_id != null && c.get('courierId') != null
    && Number(c.get('courierId')) === Number(job.courier_id);
  if (!linked && !isAdmin(c)) return c.json({ error: 'not found' }, 404);
  const threadId = await getOrCreateJobThread(c.env, job.id);
  await c.env.DB.prepare(
    `INSERT INTO chat_partner_joins (thread_id, phone) VALUES (?1, ?2)
     ON CONFLICT(thread_id, phone) DO NOTHING`,
  ).bind(threadId, phone).run();
  return c.json({ ok: true, thread_id: threadId });
});

// Door probe for the Join button — reveals only whether the linked partner
// has joined this thread; no chat content leaks before the tap.
app.get('/jobs/:ref/chat/join-status', async (c) => {
  const phone = c.get('phone');
  const role = c.get('role');
  if (!phone) return c.json({ error: 'identity_required' }, 401);
  const job = await c.env.DB.prepare('SELECT id, courier_id FROM jobs WHERE ref = ?1').bind(c.req.param('ref')).first<any>();
  if (!job) return c.json({ error: 'not found' }, 404);
  const linked = role === 'partner' && job.courier_id != null && c.get('courierId') != null
    && Number(c.get('courierId')) === Number(job.courier_id);
  if (!linked) return c.json({ error: 'not found' }, 404);
  const joined = await c.env.DB.prepare(
    `SELECT 1 AS x FROM chat_partner_joins p
     JOIN chat_threads t ON t.id = p.thread_id
    WHERE t.job_id = ?1 AND p.phone = ?2`,
  ).bind(job.id, phone).first();
  return c.json({ state: joined ? 'joined' : 'join_required' });
});

// Close a parcel chat — sends the archive state to ALL participants; the
// history stays available to everyone forever, nobody can post any more.
// The sender / recipient / assigned rider / linked partner may close it.
app.post('/chat/threads/:id/close', async (c) => {
  const phone = c.get('phone');
  if (!phone) return c.json({ error: 'identity_required' }, 401);
  const id = Number(c.req.param('id'));
  if (!Number.isFinite(id) || id <= 0) return c.json({ error: 'bad_thread' }, 400);
  const thread = await c.env.DB.prepare(
    `SELECT t.id, t.kind, t.phone, t.job_id, t.closed_at, t.closed_by,
            j.sender_phone, j.recipient_phone, j.courier_id, j.rider_id, j.ref
       FROM chat_threads t LEFT JOIN jobs j ON j.id = t.job_id
      WHERE t.id = ?1`,
  ).bind(id).first<any>();
  if (!thread) return c.json({ error: 'not found' }, 404);
  if (thread.closed_at) return c.json({ ok: true, already_closed: true });
  if (thread.kind === 'support') {
    if (phone !== thread.phone && !isAdmin(c)) return c.json({ error: 'not found' }, 404);
  }
  // WHO may close: sender, recipient, the ASSIGNED rider, a linked partner who
  // has joined the thread, and staff — no one else.
  if (thread.kind === 'job' && thread.job_id) {
    const isStaff = isAdmin(c) || c.get('role') === 'ops' || (c.get('role') as any) === 'cfo';
    let isAssignedRider = false;
    if (thread.rider_id) {
      const riderRow = await c.env.DB.prepare('SELECT phone FROM riders WHERE id = ?1').bind(thread.rider_id).first<{ phone: string }>();
      isAssignedRider = riderRow?.phone === phone;
    }
    let isPartner = false;
    if (thread.courier_id) {
      const partnerRow = await c.env.DB.prepare(
        `SELECT 1 AS x FROM chat_partner_joins p
          WHERE p.thread_id = ?1 AND p.phone = ?2`,
      ).bind(id, phone).first();
      isPartner = !!partnerRow;
    }
    if (!isStaff && phone !== thread.sender_phone && phone !== thread.recipient_phone && !isAssignedRider && !isPartner) {
      return c.json({ error: 'forbidden' }, 403);
    }
  }
  await c.env.DB.prepare(
    `UPDATE chat_threads SET closed_by = ?2, closed_at = datetime('now') WHERE id = ?1 AND closed_at IS NULL`,
  ).bind(id, phone).run();
  // Announce the closure to all participants — they'll see the archive ribbon.
  const job = thread.job_id ? { id: thread.job_id, ref: thread.ref, sender_phone: thread.sender_phone, recipient_phone: thread.recipient_phone, rider_id: thread.rider_id } : null;
  void job; // (not used — kept for future realtime broadcast)
  try {
    if (thread.job_id) {
      await c.env.DB.prepare(
        `INSERT INTO job_events (job_id, status, note) VALUES (?1, 'chat_closed', ?2)`,
      ).bind(thread.job_id, `Chat closed by ${phone} — all history preserved, read-only from here.`).run();
    }
  } catch { /* audit must never block the close */ }
  return c.json({ ok: true });
});

/* --------------------------- support inbox (admin) ------------------------- */
// Staff view of every support ticket (kind='support' threads). Reply with the
// existing POST /chat/support/:id/reply. "Unread" = messages from the seller
// that arrived after the last ops reply.
app.get('/admin/support/threads', async (c) => {
  if (!isAdmin(c) && c.get('role') !== 'ops') return c.json({ error: 'forbidden' }, 403);
  const { results } = await c.env.DB.prepare(
    `SELECT t.id, t.phone, t.created_at, u.photo_url AS customer_photo_url, u.full_name AS customer_name,
            (SELECT m.body FROM chat_messages m WHERE m.thread_id = t.id ORDER BY m.id DESC LIMIT 1) AS last_message,
            (SELECT m.created_at FROM chat_messages m WHERE m.thread_id = t.id ORDER BY m.id DESC LIMIT 1) AS last_at,
            (SELECT COUNT(*) FROM chat_messages m WHERE m.thread_id = t.id) AS message_count,
            (SELECT COUNT(*) FROM chat_messages m WHERE m.thread_id = t.id AND m.sender_role <> 'ops'
               AND m.id > COALESCE((SELECT MAX(m2.id) FROM chat_messages m2 WHERE m2.thread_id = t.id AND m2.sender_role = 'ops'), 0)) AS unread
       FROM chat_threads t
       LEFT JOIN auth_users u ON u.phone = t.phone
      WHERE t.kind = 'support'
      ORDER BY COALESCE((SELECT m.created_at FROM chat_messages m WHERE m.thread_id = t.id ORDER BY m.id DESC LIMIT 1), t.created_at) DESC
      LIMIT 100`,
  ).all();
  return c.json({ threads: results });
});

app.get('/admin/support/threads/:id', async (c) => {
  if (!isAdmin(c) && c.get('role') !== 'ops') return c.json({ error: 'forbidden' }, 403);
  const id = Number(c.req.param('id'));
  const thread = await c.env.DB.prepare(
    `SELECT t.id, t.kind, t.phone, t.created_at, u.photo_url AS customer_photo_url, u.full_name AS customer_name
       FROM chat_threads t LEFT JOIN auth_users u ON u.phone = t.phone
      WHERE t.id = ?1 AND t.kind = 'support'`,
  ).bind(id).first();
  if (!thread) return c.json({ error: 'not found' }, 404);
  const messages = await chatMessages(c.env, id);
  return c.json({ thread, messages });
});

/* ------------------------------ users & roles ----------------------------- */
// GET: any staff can review accounts. Role writes: SUPERADMIN only (owner or
// admin key) — the owner can promote an assistant to admin; admins cannot
// mint more admins, and the owner row can never be demoted (no self-lockout).
app.get('/admin/users', async (c) => {
  if (!isAdmin(c) && c.get('role') !== 'ops') return c.json({ error: 'forbidden' }, 403);
  const { results } = await c.env.DB.prepare(
    `SELECT email, phone, full_name, role, email_verified, created_at, photo_url
       FROM auth_users ORDER BY created_at DESC LIMIT 200`,
  ).all();
  const owner = ownerPhone(c.env);
  const ownerMail = ownerEmail(c.env);
  const users = ((results ?? []) as any[]).map((u) => ({ ...u, superadmin: (owner != null && u.phone === owner) || (ownerMail != null && u.email === ownerMail) }));
  return c.json({ users });
});

app.post('/admin/users/role', async (c) => {
  if (!isSuperAdmin(c)) return c.json({ error: 'superadmin_required' }, 403);
  const b: any = await c.req.json().catch(() => null);
  const email = String(b?.email ?? '').trim().toLowerCase();
  const role = String(b?.role ?? '');
  if (!email || !['customer', 'admin', 'partner', 'rider', 'ops', 'cfo'].includes(role)) {
    return c.json({ error: 'email and role (customer|admin|partner|rider|ops|cfo) required' }, 400);
  }
  const user = await c.env.DB.prepare(
    'SELECT email, phone, role FROM auth_users WHERE email = ?1',
  ).bind(email).first<any>();
  if (!user) return c.json({ error: 'not found' }, 404);
  // The owner account can never be demoted — you cannot lock yourself out.
  const isOwnerRow = (user.phone && user.phone === ownerPhone(c.env))
    || (user.email && ownerEmail(c.env) != null && user.email === ownerEmail(c.env));
  if (role !== 'admin' && isOwnerRow) {
    return c.json({ error: 'owner_cannot_be_demoted' }, 400);
  }
  const res = await c.env.DB.prepare('UPDATE auth_users SET role = ?2 WHERE email = ?1')
    .bind(email, role).run();
  return c.json({ ok: true, email, role, updated: res.meta.changes ?? 0 });
});

/* -------- admin/superadmin SMS communication + marketing ------------------- */
// Single send or audience broadcast (marketing + operational notices). Every
// send lands in sms_broadcasts for the audit trail.

const SMS_AUDIENCES = ['all', 'accounts', 'sellers', 'subscribers'] as const;
const SMS_BROADCAST_CAP = 500;

app.post('/admin/sms', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'admin_key_required' }, 403);
  const b: any = await c.req.json().catch(() => null);
  const message = String(b?.message ?? '').trim();
  const phone = normalizeZmPhone(String(b?.phone ?? ''));
  if (!message) return c.json({ error: 'message required' }, 400);
  if (message.length > 600) return c.json({ error: 'message too long (max 600 chars)' }, 400);
  const sender = c.get('phone') ?? 'admin-key';
  const res = await sendSms(c.env, phone, message, { transactional: true });
  await c.env.DB.prepare(
    `INSERT INTO sms_broadcasts (sender, audience, recipient_count, sent_count, body) VALUES (?1, 'single', 1, ?2, ?3)`,
  ).bind(sender, res.sent ? 1 : 0, message).run();
  return c.json({ ok: res.sent, phone, error: res.error ?? null });
});

app.post('/admin/sms/broadcast', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'admin_key_required' }, 403);
  const b: any = await c.req.json().catch(() => null);
  const message = String(b?.message ?? '').trim();
  const audience = String(b?.audience ?? '').toLowerCase();
  const extraPhones = Array.isArray(b?.phones) ? b.phones.map((p: unknown) => String(p)) : [];
  if (!message) return c.json({ error: 'message required' }, 400);
  if (message.length > 600) return c.json({ error: 'message too long (max 600 chars)' }, 400);
  if (!SMS_AUDIENCES.includes(audience as any)) {
    return c.json({ error: `audience must be one of: ${SMS_AUDIENCES.join(', ')}` }, 400);
  }

  const phones = new Set<string>();
  if (audience === 'all' || audience === 'accounts') {
    const { results } = await c.env.DB.prepare('SELECT phone FROM auth_users WHERE phone IS NOT NULL').all();
    for (const r of results as any[]) if (r.phone) phones.add(r.phone);
  }
  if (audience === 'all' || audience === 'sellers') {
    const { results } = await c.env.DB.prepare('SELECT DISTINCT sender_phone AS phone FROM jobs').all();
    for (const r of results as any[]) if (r.phone) phones.add(r.phone);
  }
  if (audience === 'all' || audience === 'subscribers') {
    const { results } = await c.env.DB.prepare(`SELECT phone FROM subscriptions WHERE status = 'active'`).all();
    for (const r of results as any[]) if (r.phone) phones.add(r.phone);
  }
  for (const raw of extraPhones) {
    try { phones.add(normalizeZmPhone(raw)); } catch { /* skip invalid */ }
  }
  // never message the ops/test service identity
  phones.delete('ops');

  const recipients = [...phones].slice(0, SMS_BROADCAST_CAP);
  const sender = c.get('phone') ?? 'admin-key';
  const { meta } = await c.env.DB.prepare(
    `INSERT INTO sms_broadcasts (sender, audience, recipient_count, body) VALUES (?1, ?2, ?3, ?4)`,
  ).bind(sender, audience, recipients.length, message).run();
  const broadcastId = meta.last_row_id as number;

  c.executionCtx.waitUntil((async () => {
    let sent = 0;
    const results = await Promise.allSettled(recipients.map((p) => sendSms(c.env, p, message)));
    for (const r of results) if (r.status === 'fulfilled' && r.value.sent) sent++;
    await c.env.DB.prepare('UPDATE sms_broadcasts SET sent_count = ?2 WHERE id = ?1')
      .bind(broadcastId, sent).run().catch(() => {});
  })());

  return c.json({ ok: true, broadcast_id: broadcastId, audience, recipients: recipients.length, capped: phones.size > SMS_BROADCAST_CAP });
});

app.get('/admin/sms/log', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'admin_key_required' }, 403);
  const { results } = await c.env.DB.prepare(
    `SELECT id, sender, audience, recipient_count, sent_count, body, created_at
       FROM sms_broadcasts ORDER BY id DESC LIMIT 50`,
  ).all();
  return c.json({ broadcasts: results });
});

/* ------------------- admin/superadmin notification broadcasts ------------------ */
// Audience push — mirrors /admin/sms/broadcast and is recorded the same way.
// Admin and superadmin can both send marketing pushes; isAdmin covers the owner.
const PUSH_AUDIENCES = ['all', 'accounts', 'sellers', 'subscribers', 'riders'] as const;
const PUSH_CAP = 500;

app.post('/admin/push/broadcast', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'admin_key_required' }, 403);
  const b: any = await c.req.json().catch(() => null);
  const title = String(b?.title ?? '').trim().slice(0, 80);
  const message = String(b?.message ?? '').trim().slice(0, 140);
  const audience = String(b?.audience ?? '').toLowerCase();
  const extraPhones = Array.isArray(b?.phones) ? b.phones.map((p: unknown) => String(p)) : [];
  if (!title || !message) return c.json({ error: 'title and message required' }, 400);
  if (!PUSH_AUDIENCES.includes(audience as any)) {
    return c.json({ error: `audience must be one of: ${PUSH_AUDIENCES.join(', ')}` }, 400);
  }
  const phones = new Set<string>();
  if (audience === 'all' || audience === 'accounts') {
    const { results } = await c.env.DB.prepare('SELECT phone FROM auth_users WHERE phone IS NOT NULL').all();
    for (const r of results as any[]) if (r.phone) phones.add(r.phone);
  }
  if (audience === 'all' || audience === 'sellers') {
    const { results } = await c.env.DB.prepare('SELECT DISTINCT sender_phone AS phone FROM jobs').all();
    for (const r of results as any[]) if (r.phone) phones.add(r.phone);
  }
  if (audience === 'all' || audience === 'subscribers') {
    const { results } = await c.env.DB.prepare(`SELECT phone FROM subscriptions WHERE status = 'active'`).all();
    for (const r of results as any[]) if (r.phone) phones.add(r.phone);
  }
  if (audience === 'all' || audience === 'riders') {
    const { results } = await c.env.DB.prepare(`SELECT phone FROM riders WHERE active = 1`).all();
    for (const r of results as any[]) if (r.phone) phones.add(r.phone);
  }
  for (const raw of extraPhones) {
    try { phones.add(normalizeZmPhone(raw)); } catch { /* skip */ }
  }
  phones.delete('ops');

  // Only send to phones with at least one registered push token.
  const candidates = [...phones].slice(0, PUSH_CAP * 4);
  const withTokens: string[] = [];
  for (const q of candidates) {
    const t = await c.env.DB.prepare('SELECT 1 FROM push_tokens WHERE phone = ?1').bind(q).first();
    if (t) withTokens.push(q);
    if (withTokens.length >= PUSH_CAP) break;
  }

  const sender = c.get('phone') ?? 'admin-key';
  const { meta } = await c.env.DB.prepare(
    `INSERT INTO push_broadcasts (sender, audience, title, body, recipient_count) VALUES (?1, ?2, ?3, ?4, ?5)`,
  ).bind(sender, audience, title, message, withTokens.length).run();
  const broadcastId = meta.last_row_id as number;

  c.executionCtx.waitUntil((async () => {
    let sent = 0;
    await Promise.allSettled(withTokens.map((p) =>
      sendToPhone(c.env, p, { title, body: message, data: { kind: 'marketing', broadcast_id: String(broadcastId) } }),
    ));
    sent = withTokens.length;
    await c.env.DB.prepare('UPDATE push_broadcasts SET sent_count = ?2 WHERE id = ?1')
      .bind(broadcastId, sent).run().catch(() => {});
  })());

  return c.json({ ok: true, broadcast_id: broadcastId, audience, recipients: withTokens.length, targeted: candidates.length });
});

app.get('/admin/push/log', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'admin_key_required' }, 403);
  const { results } = await c.env.DB.prepare(
    `SELECT id, sender, audience, title, body, recipient_count, sent_count, created_at
       FROM push_broadcasts ORDER BY id DESC LIMIT 50`,
  ).all();
  return c.json({ broadcasts: results });
});

/* ------------------------- courier branches (admin) ------------------------ */
app.get('/admin/branches', async (c) => {
  if (!isAdmin(c) && c.get('role') !== 'ops') return c.json({ error: 'admin_key_required' }, 403);
  const courierId = Number(c.req.query('courier_id') ?? 0);
  const { results } = await c.env.DB.prepare(
    `SELECT b.*, co.name AS courier_name FROM courier_branches b
       JOIN couriers co ON co.id = b.courier_id
      WHERE b.active = 1 ${courierId ? 'AND b.courier_id = ?1' : ''}
      ORDER BY co.name, b.name`,
  ).bind(...(courierId ? [courierId] : [])).all();
  return c.json({ branches: results });
});

app.post('/admin/branches', async (c) => {
  if (!isAdmin(c) && c.get('role') !== 'ops') return c.json({ error: 'admin_key_required' }, 403);
  const b: any = await c.req.json().catch(() => null);
  const courierId = Number(b?.courier_id ?? 0);
  const name = String(b?.name ?? '').trim();
  if (!courierId || !name) return c.json({ error: 'courier_id and name required' }, 400);
  const lat = b?.lat == null || b?.lat === '' ? null : Number(b.lat);
  const lng = b?.lng == null || b?.lng === '' ? null : Number(b.lng);
  const { meta } = await c.env.DB.prepare(
    `INSERT INTO courier_branches (courier_id, name, city, address, lat, lng, phone)
      VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)`,
  ).bind(courierId, name.slice(0, 80), String(b?.city ?? 'Lusaka').trim() || 'Lusaka',
    b?.address ? String(b.address).trim().slice(0, 200) : null,
    Number.isFinite(lat) ? lat : null, Number.isFinite(lng) ? lng : null,
    b?.phone ? String(b.phone).trim().slice(0, 20) : null).run();
  return c.json({ ok: true, id: meta.last_row_id });
});

app.delete('/admin/branches/:id', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'admin_key_required' }, 403);
  const res = await c.env.DB.prepare('UPDATE courier_branches SET active = 0 WHERE id = ?1')
    .bind(Number(c.req.param('id'))).run();
  return c.json({ ok: true, removed: res.meta.changes ?? 0 });
});

/* ------------------------------ FCM push reg ------------------------------ */
// POST /admin/push-test {phone, title?, body?} — one-tap verification that the
// FCM chain (Worker secret → Google → device token) is alive. Admin/ops only.
app.post('/admin/push-test', async (c) => {
  if (!isAdmin(c) && c.get('role') !== 'ops') return c.json({ error: 'forbidden' }, 403);
  const b: any = await c.req.json().catch(() => null);
  const phone = normalizeZmPhone(String(b?.phone ?? ''));
  if (!phone) return c.json({ error: 'phone required (260XXXXXXXXX)' }, 400);
  const title = String(b?.title ?? 'DropOff — push test').slice(0, 80);
  const body = String(b?.body ?? 'FCM is live and reaching this phone.').slice(0, 140);
  const before = await c.env.DB.prepare(
    'SELECT COUNT(*) AS n FROM push_tokens WHERE phone = ?1',
  ).bind(phone).first<any>();
  await sendToPhone(c.env, phone, { title, body, data: { kind: 'push_test' } });
  return c.json({ ok: true, phone, tokens: Number(before?.n ?? 0) });
});

// POST /push/register {token, platform} — upserts this device under the JWT's
// phone so the Worker can reach it on job/payment events. DELETE removes it.
app.post('/push/register', async (c) => {
  const phone = c.get('phone');
  if (!phone) return c.json({ error: 'sign in with your account' }, 403);
  const b: any = await c.req.json().catch(() => null);
  const token = b?.token ? String(b.token).trim() : '';
  const platform = b?.platform ? String(b.platform).slice(0, 20) : 'android';
  if (!token) return c.json({ error: 'missing token' }, 400);
  await c.env.DB.prepare(
    `INSERT INTO push_tokens (token, phone, platform) VALUES (?1, ?2, ?3)
      ON CONFLICT(token) DO UPDATE SET phone = ?2, platform = ?3, last_seen = datetime('now')`,
  ).bind(token, c.get('phone') as string, platform).run();
  return c.json({ ok: true });
});

app.delete('/push/register', async (c) => {
  const b: any = await c.req.json().catch(() => null);
  const token = b?.token ? String(b.token).trim() : c.req.header('X-Push-Token') ?? '';
  if (!token) return c.json({ error: 'missing token' }, 400);
  // Ownership: a signed-in user may only remove their OWN device token;
  // staff (ops/admin key) may remove any. Prevents IDOR token-hijack.
  const role = c.get('role');
  const staff = role === 'ops' || isAdmin(c);
  const phone = c.get('phone') ?? '';
  if (!staff && !phone) return c.json({ error: 'sign in with your account' }, 403);
  const res = staff
    ? await c.env.DB.prepare('DELETE FROM push_tokens WHERE token = ?1').bind(token).run()
    : await c.env.DB.prepare('DELETE FROM push_tokens WHERE token = ?1 AND phone = ?2')
        .bind(token, phone).run();
  return c.json({ ok: true, removed: res.meta.changes ?? 0 });
});

// Pause/resume DropOff's payment reminders for a job — the sender realised
// the money is not there right now, so we stop sending anything new. USSD
// pushes already on the handset are out of app control (we never pretend
// otherwise). Paused rows are excluded from the advance-prompt reuse check,
// so resuming re-arms a fresh prompt on the next deliberate tap.
app.post('/jobs/:ref/payment/pause-reprompt', async (c) => {
  const phone = c.get('phone');
  if (!phone) return c.json({ error: 'identity_required' }, 401);
  const job = await c.env.DB.prepare(
    `SELECT j.id, j.sender_phone,
            (SELECT paused_at IS NOT NULL FROM payments p
              WHERE p.job_id = j.id AND p.kind = 'booking_deposit' AND p.status = 'pending'
              ORDER BY p.id DESC LIMIT 1) AS paused
       FROM jobs j WHERE ref = ?1`,
  ).bind(c.req.param('ref')).first<any>();
  if (!job) return c.json({ error: 'not found' }, 404);
  const isStaff = isAdmin(c) || c.get('role') === 'ops';
  if (!isStaff && job.sender_phone !== phone) return c.json({ error: 'not found' }, 404);
  const body = await c.req.json().catch(() => ({} as any));
  const paused = body?.paused !== false; // default = pause
  await c.env.DB.prepare(
    `UPDATE payments SET paused_at = ${paused ? "datetime('now')" : 'NULL'}
     WHERE job_id = ?1 AND kind = 'booking_deposit' AND status = 'pending'`,
  ).bind(job.id).run();
  try {
    await c.env.DB.prepare(
      `INSERT INTO job_events (job_id, status, note) VALUES (?1, ?2, ?3)`,
    ).bind(job.id, paused ? 'reprompt_paused' : 'reprompt_resumed',
      paused ? 'Payment reminders paused by the sender — booking stays HELD.' : 'Payment reminders resumed by the sender.').run();
  } catch { /* audit must never block the toggle */ }
  return c.json({ ok: true, paused });
});

/* ------------------- ride float (rider/ops COD float) ---------------------- */
// NOT A WALLET: customers never hold stored value — prepayment is per parcel.
// This ledger only tracks rider/ops COD float: topup +, job charge -,
// COD receipt +, rider earning +, rider payout -. Money moves through
// wallet_ledger rows (audit trail).
async function walletCreditStatements(
  c: { env: { DB: D1Database } },
  phone: string, amount: number, kind: string, jobId?: number,
): Promise<D1PreparedStatement[]> {
  return [
    c.env.DB.prepare('INSERT OR IGNORE INTO wallets (phone, balance_zmw) VALUES (?1, 0)').bind(phone),
    c.env.DB.prepare(
      `INSERT INTO wallet_ledger (phone, amount_zmw, kind, job_id) VALUES (?1, ?2, ?3, ?4)`,
    ).bind(phone, amount, kind, jobId ?? null),
    c.env.DB.prepare('UPDATE wallets SET balance_zmw = balance_zmw + ?2 WHERE phone = ?1').bind(phone, amount),
  ];
}

app.get('/wallet', async (c) => {
  if (!['ops', 'admin'].includes(c.get('role') as string)) {
    return c.json({ error: 'customers hold no stored value — prepayment is per parcel; riders check float via ops' }, 403);
  }
  const phone = c.get('phone');
  if (!phone) return c.json({ error: 'identity_required' }, 401);
  const wallet = await c.env.DB.prepare(
    'SELECT balance_zmw FROM wallets WHERE phone = ?1').bind(phone).first<any>();
  const { results: ledger } = await c.env.DB.prepare(
    `SELECT amount_zmw, kind, job_id, created_at FROM wallet_ledger
      WHERE phone = ?1 ORDER BY id DESC LIMIT 25`,
  ).bind(phone).all();
  return c.json({ phone, balance_zmw: wallet?.balance_zmw ?? 0, ledger });
});

/* ------------------------------- payments --------------------------------- */
// Lipila collect for: kind=job (settle a job), kind=topup (ride float),
// kind=subscription (auto-renewal). All settle idempotently below.
app.post('/payments', async (c) => {
  if (await rateLimited(c, 'payment_create', 30)) return c.json({ error: 'too_many_requests' }, 429);
  const b: any = await c.req.json().catch(() => null);
  if (!b) return c.json({ error: 'invalid JSON body' }, 400);
  const idemKey = idemKeyOf(c, b);
  const replay = await replayIdempotent(c, idemKey, 'payment', c.get('phone') ?? null);
  if (replay) return replay;
  const kind: string = ['job', 'topup', 'subscription', 'counter_fare'].includes(b.kind) ? b.kind : 'job';

  let phone: string;
  let amount = 0;        // the full prompt: base + our platform fee + Lipila legs
  let creditZmw = 0;     // what lands in the wallet on success (top-ups)
  let platformFeeZmw = 0; // DropOff's cut, recorded for the dashboard
  let lipilaFeeZmw = 0;  // Lipila's pass-through legs
  let jobId: number | null = null;
  let subscriptionId: number | null = null;
  let lipilaRef: string;
  const channel = b.channel ?? 'merchant';

  if (kind === 'job') {
    const job = await c.env.DB.prepare(
      'SELECT id, ref, total_zmw, rider_fee_zmw, leg2_fee_zmw, leg2_processing_fee_zmw, promo_discount_zmw, paid, sender_phone FROM jobs WHERE ref = ?1').bind(b.job_ref ?? '').first() as any;
    if (!job) return c.json({ error: 'job not found' }, 404);
    if (job.paid) return c.json({ error: 'job already paid' }, 409);
    // customers pay their OWN job only
    if (c.get('role') === 'customer' && c.get('phone') !== job.sender_phone) {
      return c.json({ error: 'forbidden' }, 403);
    }
    phone = c.get('role') === 'ops' && b.phone ? normalizeZmPhone(b.phone) : c.get('phone')!;
    if (!phone) return c.json({ error: 'missing phone' }, 400);
    // IDEMPOTENCY: the advance-payment gate already sent the sender's momo
    // prompt for this exact parcel at booking. If it is pending OR already
    // settled it IS this job's payment — never issue a second prompt for the
    // same delivery.
    const pendingAdvance = await c.env.DB.prepare(
      `SELECT id, amount_zmw, platform_fee_zmw, lipila_fee_zmw, lipila_reference, status FROM payments
        WHERE job_id = ?1 AND kind = 'booking_deposit' AND status IN ('pending','success') AND paused_at IS NULL
        ORDER BY id DESC LIMIT 1`,
    ).bind(job.id).first<any>();
    if (pendingAdvance) {
      const reused = {
        ok: true,
        payment_id: pendingAdvance.id,
        lipila_reference: pendingAdvance.lipila_reference ?? null,
        amount_zmw: pendingAdvance.amount_zmw,
        platform_fee_zmw: pendingAdvance.platform_fee_zmw ?? 0,
        lipila_fee_zmw: pendingAdvance.lipila_fee_zmw ?? 0,
        reused_advance_prompt: true,
      };
      await saveIdempotent(c.env, idemKey, 'payment', phone, 200, reused);
      return c.json(reused);
    }
    // SAME GUARD for the Pay-now path (owner directive 2026-11-15): a rapid
    // double-tap can only ever leave ONE kind='job' prompt live — the second
    // tap reuses it instead of collecting the sender twice.
    const pendingJobPay = await c.env.DB.prepare(
      `SELECT id, amount_zmw, platform_fee_zmw, lipila_fee_zmw, lipila_reference, status FROM payments
        WHERE job_id = ?1 AND kind = 'job' AND status = 'pending'
        ORDER BY id DESC LIMIT 1`,
    ).bind(job.id).first<any>();
    if (pendingJobPay) {
      const reused = {
        ok: true,
        payment_id: pendingJobPay.id,
        lipila_reference: pendingJobPay.lipila_reference ?? null,
        amount_zmw: pendingJobPay.amount_zmw,
        platform_fee_zmw: pendingJobPay.platform_fee_zmw ?? 0,
        lipila_fee_zmw: pendingJobPay.lipila_fee_zmw ?? 0,
        reused_job_prompt: true,
      };
      await saveIdempotent(c.env, idemKey, 'payment', phone, 200, reused);
      return c.json(reused);
    }
    // DropOff NEVER holds partner money: charge ONLY the DropOff leg
    // (rider fee + door leg + its processing) and platform processing fees.
    // The courier counter fare is paid directly at the depot. Counter fare is
    // irrelevant to the dropoff leg — pass 0 so jobTotals doesn't weight it.
    const dropoffLeg = computeJobTotals({
      counterPriceZmw: 0,
      riderFeeZmw: job.rider_fee_zmw,
      leg2FeeZmw: job.leg2_fee_zmw,
      leg2ProcessingFeeZmw: job.leg2_processing_fee_zmw,
      promoDiscountZmw: job.promo_discount_zmw,
    }).dropoff_leg_zmw;
    // server-computed fees — the client never sets an amount. Recorded on the
    // payment row = the CUSTOMER leg only (processing fee). Rider payout costs
    // are absorbed at payout time out of the rider's 10%.
    const fees = collectionFees(dropoffLeg, job.rider_fee_zmw);
    amount = fees.prompt_total_zmw;
    platformFeeZmw = fees.platform_fee_zmw;
    lipilaFeeZmw = fees.lipila_fee_zmw;
    jobId = job.id;
    lipilaRef = `job-${job.ref}`;
  } else if (kind === 'subscription') {
    // Pack activation/renewal: the signed-in seller pays their OWN subscription.
    const caller = c.get('phone');
    if (!caller) return c.json({ error: 'identity_required' }, 401);
    const sub = b.subscription_id
      ? await c.env.DB.prepare('SELECT id, phone, tier FROM subscriptions WHERE id = ?1')
          .bind(Number(b.subscription_id)).first<any>()
      : await c.env.DB.prepare('SELECT id, phone, tier FROM subscriptions WHERE phone = ?1 ORDER BY id DESC LIMIT 1')
          .bind(caller).first<any>();
    if (!sub) return c.json({ error: 'no_subscription', detail: 'Choose a pack first.' }, 404);
    if (c.get('role') === 'customer' && sub.phone !== caller) return c.json({ error: 'forbidden' }, 403);
    const pending = await c.env.DB.prepare(
      `SELECT id FROM payments WHERE subscription_id = ?1 AND status = 'pending'`,
    ).bind(sub.id).first<any>();
    if (pending) return c.json({ error: 'payment_already_pending' }, 409);
    const plan = (await plans(c.env.DB))[sub.tier as PlanTier];
    if (!plan || plan.fee_zmw <= 0) return c.json({ error: 'invalid_tier' }, 400);
    phone = sub.phone;
    platformFeeZmw = platformFee(plan.fee_zmw);
    lipilaFeeZmw = MOMO_COLLECTION_FEE;
    amount = round2(plan.fee_zmw + platformFeeZmw + lipilaFeeZmw);
    subscriptionId = sub.id;
    lipilaRef = `sub-${sub.id}-${new Date().toISOString().slice(0, 10).replace(/-/g, '')}`;
  } else if (kind === 'counter_fare') {
    // Depot counter fare (owner directive 2026-11-12): the sender pays the
    // EXACT amount the rider transcribed off the depot's written receipt, plus
    // processing — the rider is reimbursed fee-free on approval. The client
    // never sets an amount; the server reads it from the job.
    const job = await c.env.DB.prepare(
      `SELECT id, ref, sender_phone, counter_receipt_zmw, counter_receipt_paid FROM jobs WHERE ref = ?1`,
    ).bind(b.job_ref ?? '').first() as any;
    if (!job) return c.json({ error: 'job not found' }, 404);
    if (c.get('role') === 'customer' && c.get('phone') !== job.sender_phone) {
      return c.json({ error: 'forbidden' }, 403);
    }
    if (!job.counter_receipt_zmw || Number(job.counter_receipt_zmw) <= 0) {
      return c.json({ error: 'no_counter_receipt', detail: 'No depot receipt has been submitted for this parcel yet.' }, 409);
    }
    if (Number(job.counter_receipt_paid) === 1) {
      return c.json({ error: 'counter_fare_already_paid' }, 409);
    }
    // Idempotency: a pending prompt for this job IS this payment.
    const pendingCfare = await c.env.DB.prepare(
      `SELECT id, amount_zmw, platform_fee_zmw, lipila_fee_zmw, lipila_reference, status FROM payments
        WHERE job_id = ?1 AND kind = 'counter_fare' AND status IN ('pending','success')
        ORDER BY id DESC LIMIT 1`,
    ).bind(job.id).first<any>();
    if (pendingCfare) {
      if (pendingCfare.status === 'success') return c.json({ error: 'counter_fare_already_paid' }, 409);
      return c.json({
        ok: true,
        payment_id: pendingCfare.id,
        lipila_reference: pendingCfare.lipila_reference ?? null,
        amount_zmw: pendingCfare.amount_zmw,
        platform_fee_zmw: pendingCfare.platform_fee_zmw ?? 0,
        lipila_fee_zmw: pendingCfare.lipila_fee_zmw ?? 0,
        reused_prompt: true,
      });
    }
    const receipt = round2(Number(job.counter_receipt_zmw));
    phone = c.get('role') === 'ops' && b.phone ? normalizeZmPhone(b.phone) : c.get('phone')!;
    if (!phone) return c.json({ error: 'missing phone' }, 400);
    // PLAN-ACTIVE senders only pay for the receipt reveal (owner directive
    // 2026-11-12) — processing waived, momo pass-through stays.
    const cfareFees = await counterFareFees(c.env, phone, receipt);
    platformFeeZmw = cfareFees.platformFeeZmw;
    lipilaFeeZmw = cfareFees.lipilaFeeZmw;
    amount = cfareFees.total;
    jobId = job.id;
    // Retry-safe Lipila reference: a FAILED attempt's reference cannot be
    // reused at the telco, so retries after a failure get a fresh unique ref.
    // Pending/success prompts are reused via the idempotency check above.
    const failedCfare = await c.env.DB.prepare(
      `SELECT COUNT(*) AS n FROM payments WHERE job_id = ?1 AND kind = 'counter_fare' AND status = 'failed'`,
    ).bind(job.id).first<any>();
    lipilaRef = failedCfare && failedCfare.n > 0 ? `cfare-${job.ref}-${Number(failedCfare.n) + 1}` : `cfare-${job.ref}`;
  } else {
    // Top-ups exist ONLY for rider/ops float (COD handling) — customers/sellers have no wallet.
    if (!['ops', 'admin'].includes(c.get('role') as string)) {
      return c.json({ error: 'ride float is rider/ops only — customers prepay per parcel' }, 403);
    }
    phone = c.get('role') === 'ops' && b.phone ? normalizeZmPhone(b.phone) : c.get('phone')!;
    if (!phone) return c.json({ error: 'missing phone' }, 400);
    creditZmw = Math.round(Number(b.amount_zmw) || 0);
    if (creditZmw < 10 || creditZmw > WALLET_TOPUP_CAP_ZMW) {
      return c.json({ error: `ride float top-up must be between K10 and K${WALLET_TOPUP_CAP_ZMW}` }, 400);
    }
    // fees collected once per deposit then amortised across many parcels
    platformFeeZmw = platformFee(creditZmw);
    lipilaFeeZmw = MOMO_COLLECTION_FEE;
    amount = round2(creditZmw + platformFeeZmw + lipilaFeeZmw);
    lipilaRef = `topup-${phone}-${Date.now().toString(36)}`;
  }

  const init = await lipilaCollect(c.env, phone, amount, lipilaRef,
    kind === 'job' ? `DropOff ${lipilaRef}`
      : kind === 'subscription' ? 'DropOff pack activation/renewal'
      : kind === 'counter_fare' ? 'DropOff depot counter fare'
      : 'DropOff ride float top-up');
  if (!init.ok) return c.json({ error: 'lipila_init_failed', detail: init.raw }, 502);

  const provider: Provider = b.provider ?? providerFromPhone(phone);
  const { meta } = await c.env.DB.prepare(
    `INSERT INTO payments (job_id, subscription_id, phone, provider, amount_zmw, credit_zmw, platform_fee_zmw,
       lipila_fee_zmw, lipila_reference, status, channel, kind)
     VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,'pending',?10,?11)`,
  ).bind(jobId, subscriptionId, phone, provider, amount, creditZmw, platformFeeZmw, lipilaFeeZmw,
    init.lipilaReference ?? null, channel, kind).run();

  const payload = {
    ok: true, payment_id: meta.last_row_id, lipila_reference: init.lipilaReference,
    amount_zmw: amount, platform_fee_zmw: platformFeeZmw, lipila_fee_zmw: lipilaFeeZmw,
  };
  await saveIdempotent(c.env, idemKey, 'payment', phone, 200, payload);
  return c.json(payload);
});

/* --------------------- K1 payment rails test (owner) ----------------------- */
// Fires a REAL Lipila collect for a tiny amount to prove the whole money
// path — prompt → approval → webhook → settlement — without touching any
// booking, plan or wallet (owner directive 2026-11-17: "test payment k1").
// kind='test' matches NO settle branch in settlePaymentSuccess: the row just
// flips to 'success' and stays as an audit trail. Gated to the superadmin key.
app.post('/admin/test-collect', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'admin_key_required' }, 403);
  const b: any = await c.req.json().catch(() => ({}));
  const phone = normalizeZmPhone(String(b?.phone ?? ''));
  if (!phone) return c.json({ error: 'valid Zambian phone required' }, 400);
  const amount = round2(Math.max(1, Math.min(Number(b?.amount_zmw ?? 1) || 1, 20)));
  const flavor = b?.kind === 'subscription' ? 'subscription' : 'payg';
  const ref = `test-${flavor}-${randomCode(6)}`;
  const init = await lipilaCollect(c.env, phone, amount, ref,
    flavor === 'subscription' ? 'DropOff TEST plan subscription' : 'DropOff TEST prepayment (pay-as-you-go)')
    .catch(() => ({ ok: false } as any));
  if (!init.ok) return c.json({ error: 'lipila_init_failed', detail: (init as any).raw }, 502);
  const { meta } = await c.env.DB.prepare(
    `INSERT INTO payments (job_id, subscription_id, phone, provider, amount_zmw, credit_zmw, platform_fee_zmw,
       lipila_fee_zmw, lipila_reference, status, channel, kind)
     VALUES (NULL, NULL, ?1, ?2, ?3, 0, 0, 0, ?4, 'pending', 'merchant', 'test')`,
  ).bind(phone, providerFromPhone(phone), amount, init.lipilaReference ?? ref).run();
  return c.json({ ok: true, payment_id: meta.last_row_id, lipila_reference: init.lipilaReference, amount_zmw: amount, flavor });
});

// Depot counter fare owed by a sender (owner directive 2026-11-12).
// PLAN-ACTIVE SENDERS (owner directive) pay ONLY for the receipt reveal:
// the processing fee is waived because their plan already funds the DropOff
// leg — they still repay the exact depot receipt amount, plus the real momo
// collection pass-through (that is a telco cost, not a DropOff fee). Everyone
// else pays receipt + processing + momo fee. The rider is reimbursed the
// receipt amount fee-free either way.
async function counterFareFees(env: Env, phone: string, receipt: number) {
  const active = await env.DB.prepare(
    `SELECT 1 FROM subscriptions WHERE phone = ?1 AND status = 'active'
      AND period_end IS NOT NULL AND period_end > datetime('now') LIMIT 1`,
  ).bind(phone).first();
  const platformFeeZmw = active ? 0 : platformFee(receipt);
  const lipilaFeeZmw = MOMO_COLLECTION_FEE;
  return {
    planWaived: !!active,
    platformFeeZmw,
    lipilaFeeZmw,
    total: round2(receipt + platformFeeZmw + lipilaFeeZmw),
  };
}

// Recipient tracking SMS, deferred edition (owner directive 2026-11-15):
// payment-held bookings mint their handover codes + tracking link ONLY when
// the prepayment actually lands — never "share tracking" a held parcel.
// Called from settlePaymentSuccess for the job's OWN payment approval. The
// no-op guard is the OTP hashes: bookings that dispatched immediately already
// hashed BOTH codes at booking time (and SMSed them), so they are skipped.
// SPLIT CODES (2026-11-18): mints the recipient's DOOR code and the sender's
// PICKUP code independently — each phone gets only its own secret.
async function sendRecipientTrackingSms(env: Env, jobId: number): Promise<void> {
  const job = await env.DB.prepare(
    `SELECT j.ref, j.recipient_phone, j.sender_phone, j.from_city, j.dest_city,
            j.delivery_otp_hash, j.pickup_otp_hash, t.token AS tracking_token
       FROM jobs j LEFT JOIN tracking_tokens t ON t.job_id = j.id
      WHERE j.id = ?1 ORDER BY t.created_at DESC LIMIT 1`,
  ).bind(jobId).first<any>();
  if (!job?.ref || !job.recipient_phone) return;
  // CITY-GATED (owner 2026-11-18): same-city recipients never get a PIN —
  // tracking link only; the door code exists for intercity collections.
  const intercity = isIntercity(job.from_city, job.dest_city);
  const wantDoor = intercity && !job.delivery_otp_hash;
  // Legacy-shape rows (pre-split): the shared code doubles as the pickup code,
  // no new mint, no new SMS — the sender already holds that code.
  let wantPickup = !job.pickup_otp_hash;
  if (wantPickup && !wantDoor && job.delivery_otp_hash) {
    await env.DB.prepare(
      'UPDATE jobs SET pickup_otp_hash = delivery_otp_hash WHERE ref = ?1',
    ).bind(job.ref).run();
    wantPickup = false;
  }
  if (!wantDoor && !wantPickup) return;
  const doorOtp = wantDoor ? String(Math.floor(1000 + Math.random() * 9000)) : null;
  const pickupOtp = wantPickup ? String(Math.floor(1000 + Math.random() * 9000)) : null;
  await env.DB.prepare(
    `UPDATE jobs SET
       delivery_otp_hash = COALESCE(?2, delivery_otp_hash),
       pickup_otp_hash   = COALESCE(?3, pickup_otp_hash)
      WHERE ref = ?1`,
  ).bind(job.ref,
    doorOtp ? await handoverOtpHash(env, job.ref, doorOtp) : null,
    pickupOtp ? await handoverOtpHash(env, job.ref, pickupOtp) : null).run();
  let token: string | null = job.tracking_token ?? null;
  const mintedToken = !token;
  if (!token) {
    // The booking minted nothing (payment was held at booking time) — mint
    // NOW, at settlement, so the paid parcel's first-ever link is a live one.
    token = await issueTrackingToken(env, jobId, job.ref, job.recipient_phone);
  }
  const trackUrl = trackingUrl(env, token);
  if (doorOtp) {
    await sendSms(env, job.recipient_phone,
      `DropOff: parcel ${job.ref} paid. Track: ${trackUrl}. Code ${doorOtp} - never share before handover.`, { transactional: true }).catch(() => {});
  } else if (mintedToken) {
    // Same-city parcel paid: link only — no PIN for Lusaka recipients.
    await sendSms(env, job.recipient_phone,
      `DropOff: parcel ${job.ref} paid. Track: ${trackUrl} - follow it live in the DropOff app and confirm receipt when it lands.`, { transactional: true }).catch(() => {});
  }
  // Sender's pickup-code copy lands here too (held bookings mint the code at
  // settlement — see /jobs booking comment) — their OWN code, not the door's.
  if (pickupOtp && job.sender_phone) {
    await sendSms(env, job.sender_phone,
      `DropOff: parcel ${job.ref} paid. Pickup code ${pickupOtp} - show it to your rider when they collect.`, { transactional: true }).catch(() => {});
  }
}

// Self-heal (2026-11-17): the SMS/OTP mint could die AFTER the money landed
// (bug: ORDER BY t.id on a table with no id column) — a paid, live parcel
// with no handover code, no tracking link, no sender pickup code. Idempotent:
// mints only when a code hash is missing (either one), so it's a safe
// permanent guard in the minute cron, not a one-off patch. Recipient SMS is a
// one-time send per job (the hash becomes set on success).
async function healMissingTrackingSms(env: Env): Promise<void> {
  try {
    const { results } = await env.DB.prepare(
      `SELECT id FROM jobs
        WHERE paid = 1 AND (pickup_otp_hash IS NULL
             OR (LOWER(TRIM(COALESCE(dest_city,''))) != LOWER(TRIM(COALESCE(from_city,'')))
                 AND COALESCE(from_city,'') != '' AND COALESCE(dest_city,'') != ''
                 AND delivery_otp_hash IS NULL))
          AND COALESCE(status, '') != 'canceled'
          AND created_at > datetime('now', '-2 days')
        ORDER BY id LIMIT 25`,
    ).all<any>();
    for (const row of results ?? []) {
      try {
        await sendRecipientTrackingSms(env, row.id);
      } catch (e) {
        await captureError(env, e, { method: 'CRON', url: `https://cron/heal-tracking/${row.id}` }).catch(() => {});
      }
    }
  } catch (e) {
    await captureError(env, e, { method: 'CRON', url: 'https://cron/heal-tracking' }).catch(() => {});
  }
}

// Idempotent settlement: the `settled` flag is flipped in the same batch as the
// ledger rows; webhook + status-poll can race safely. Subscription rows renew.
// Give the money back — NEVER keep a payment the sender should not have made
// (owner directive 2026-11-15, same class as cancel-before-pickup refunds):
// the parcel was already canceled, or a second prompt for the same parcel
// was approved after another payment already paid it. Auto-refunds to the
// sender's momo; on provider failure it leaves a loud job event for manual
// /admin/payments/:id/refund.
async function refundSettledPayment(
  env: Env,
  pay: { id: number; phone: string; amount_zmw: number; job_id: number | null; kind: string },
  jobRef: string | null,
  reason: string,
): Promise<void> {
  const jobId = pay.job_id;
  const refundRef = `refund-${pay.id}-${Date.now().toString(36)}`;
  const disb = await lipilaDisburse(env, pay.phone, pay.amount_zmw, refundRef,
    `DropOff ${reason} ${jobRef ?? ''}`.replace(/[^A-Za-z0-9 ]/g, ' ')).catch(() => ({ ok: false } as any));
  if (disb.ok) {
    await env.DB.batch([
      env.DB.prepare(
        `INSERT INTO payments (job_id, phone, provider, amount_zmw, credit_zmw, platform_fee_zmw,
           lipila_fee_zmw, lipila_reference, status, channel, kind, refund_of_payment_id, refunded_at)
         VALUES (?1,?2,?3,?4,0,0,0,?5,'pending','merchant','refund',?6,datetime('now'))`,
      ).bind(jobId, pay.phone, 'lipila', pay.amount_zmw, refundRef, pay.id),
      ...(jobId ? [env.DB.prepare(
        `INSERT INTO job_events (job_id, status, note) VALUES (?1, 'payment_refunded', ?2)`,
      ).bind(jobId, `${reason} — K${pay.amount_zmw.toFixed(2)} returned to the sender's momo automatically.`)] : []),
    ]);
    await sendSms(env, pay.phone,
      `DropOff: K${pay.amount_zmw.toFixed(2)} was returned to your momo — ${reason}. ${jobRef ? `${jobRef} will not be dispatched.` : ''}`, { transactional: true }).catch(() => {});
    return;
  }
  if (jobId) {
    await env.DB.prepare(
      `INSERT INTO job_events (job_id, status, note) VALUES (?1, 'refund_failed', ?2)`,
    ).bind(jobId, `${reason} — auto-refund of K${pay.amount_zmw.toFixed(2)} FAILED (provider unreachable / insufficient float). Refund manually via /admin/payments/:id/refund.`).run().catch(() => {});
  }
}

// Referral reward (owner directive 2026-11-15): the referrer's single-use
// promo is minted — idempotently, off the same guarded UPDATE — only when the
// booking is real. Held bookings earn theirs at settlement (this helper is
// also called from settlePaymentSuccess); a booking that never pays earns
// nothing.
async function rewardReferralOnBooking(env: Env, jobId: number, senderPhone: string): Promise<void> {
  const claimed = await env.DB.prepare(
    `UPDATE referrals SET status='rewarded', referred_job_id = ?2, rewarded_at = datetime('now')
      WHERE referred_phone = ?1 AND status = 'pending'`,
  ).bind(senderPhone, jobId).run();
  if (claimed.meta.changes === 0) return;
  const refRow = await env.DB.prepare(
    'SELECT id, referrer_phone FROM referrals WHERE referred_phone = ?1',
  ).bind(senderPhone).first<any>();
  if (!refRow) return;
  const rewardCode = `FRIEND${randomCode(5)}`;
  const pct = REF_REWARD_PCT;
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO promo_codes (code, discount_pct, note, uses_left, active)
       VALUES (?1, ?2, ?3, 1, 1)`,
    ).bind(rewardCode, pct, `Referral reward — ${senderPhone} joined via your code`),
    env.DB.prepare(
      `UPDATE referrals SET reward_code = ?2 WHERE id = ?1`,
    ).bind(refRow.id, rewardCode),
    env.DB.prepare(`INSERT INTO job_events (job_id, status, note) VALUES (?1, 'referral_rewarded', ?2)`)
      .bind(jobId, `Referrer ${refRow.referrer_phone} gets ${rewardCode} (${pct}% off, single-use)`),
  ]);
}

/* Failure reasons (owner directive 2026-11-17): when a momo prompt fails the
 * payer must see WHY — "no money", "wrong PIN attempts exhausted", etc. Lipila
 * returns that message on the status check; we store it on the payments row's
 * meta JSON and echo it from the status endpoints the app polls. */
function failReasonOf(metaText: unknown): string | null {
  if (!metaText) return null;
  try {
    const r = (JSON.parse(String(metaText)) as Record<string, unknown>)?.fail_reason;
    return typeof r === 'string' && r.trim() ? r.trim() : null;
  } catch { return null; }
}

// Persist the telco's failure message onto the row (meta JSON, merged — meta
// also carries upgrade bookkeeping like prevTier, so never clobber it).
async function recordFailReason(env: Env, paymentId: number, reason?: string): Promise<void> {
  if (!reason) return;
  try {
    const row = await env.DB.prepare('SELECT meta FROM payments WHERE id = ?1').bind(paymentId).first<any>();
    let meta: Record<string, unknown> = {};
    try { meta = JSON.parse(row?.meta ?? '{}') as Record<string, unknown>; } catch { /* replace bad meta */ }
    meta.fail_reason = reason;
    await env.DB.prepare('UPDATE payments SET meta = ?2 WHERE id = ?1').bind(paymentId, JSON.stringify(meta)).run();
  } catch { /* best-effort — never block settlement on reason bookkeeping */ }
}

async function settlePaymentSuccess(env: Env, paymentId: number, finalStatus: string): Promise<void> {  if (finalStatus !== 'success') return;
  const claim = await env.DB.prepare(
    `UPDATE payments SET status = 'success', settled = 1, paid_at = datetime('now')
      WHERE id = ?1 AND settled = 0`,
  ).bind(paymentId).run();
  if (!claim.meta.changes) return; // someone else (webhook/poll) sank it already

  const pay = await env.DB.prepare(
    'SELECT id, phone, amount_zmw, job_id, subscription_id, kind FROM payments WHERE id = ?1',
  ).bind(paymentId).first<any>();
  if (!pay) return;

  if (pay.kind === 'topup') {
    const db = env.DB;
    // credit the base amount only — the customer already covered the prompt fee
    const base = pay.credit_zmw && pay.credit_zmw > 0 ? pay.credit_zmw : pay.amount_zmw;
    const stmts: D1PreparedStatement[] = [
      db.prepare('INSERT OR IGNORE INTO wallets (phone, balance_zmw) VALUES (?1, 0)').bind(pay.phone),
      db.prepare(`INSERT INTO wallet_ledger (phone, amount_zmw, kind, job_id) VALUES (?1, ?2, 'topup', NULL)`)
        .bind(pay.phone, base),
      db.prepare('UPDATE wallets SET balance_zmw = balance_zmw + ?2 WHERE phone = ?1').bind(pay.phone, base),
    ];
    if (pay.job_id) stmts.push(db.prepare('UPDATE jobs SET paid = 1 WHERE id = ?1').bind(pay.job_id));
    await env.DB.batch(stmts);
  } else if (pay.kind === 'subscription' && pay.subscription_id) {
    // Activate/renew the pack for its own cycle (daily = 1 day, weekly = 7,
    // monthly packs = 30). Unused parcels do NOT roll over — they expire.
    const sub = await env.DB.prepare('SELECT phone, tier, period_start, period_end FROM subscriptions WHERE id = ?1')
      .bind(pay.subscription_id).first<any>();
    const packs = await plans(env.DB);
    const cycleDays = Math.max(1, packs[(sub?.tier ?? 'silver') as PlanTier]?.cycle_days || 30);
    const cycleMod = `+${cycleDays} days`;
    const nowStr = new Date().toISOString().slice(0, 19).replace('T', ' ');
    let newStart = nowStr;
    if (sub && sub.period_start && sub.period_end) {
      newStart = sub.period_end > nowStr ? sub.period_start : nowStr;
    }
    await env.DB.prepare(
      `UPDATE subscriptions SET status = 'active',
         period_start = ?2,
         period_end = datetime(?2, ?3),
         rollover_parcels = 0,
         rollover_period = NULL,
         expires_at = datetime(?2, ?3),
         started_at = datetime('now')
       WHERE id = ?1`,
    ).bind(pay.subscription_id, newStart, cycleMod).run();
    await sendToPhone(env, pay.phone, {
      title: sub?.tier ? `${sub.tier} plan renewed` : 'Plan renewed',
      body: cycleDays === 1
        ? 'Your daily pass is live for today. Book away — unused parcels expire tonight.'
        : `Renewed for another ${cycleDays} days. Unused parcels do not carry over — book away!`,
      data: { kind: 'subscription_active' },
    });
  } else if (pay.kind === 'upgrade' && pay.subscription_id) {
    // Mid-cycle upgrade: tier + cap already bumped at purchase; this just
    // confirms the prorated payment and celebrates.
    const sub = await env.DB.prepare('SELECT tier FROM subscriptions WHERE id = ?1').bind(pay.subscription_id).first<any>();
    await sendToPhone(env, pay.phone, {
      title: 'Plan upgraded',
      body: sub?.tier ? `You are now on ${sub.tier} — bigger cap, live immediately.` : 'Upgrade complete.',
      data: { kind: 'subscription_active' },
    });
  } else if (pay.kind === 'job' && pay.job_id) {
    // direct mobile-money job payment: mark paid (no wallet rows — customers have no wallet)
    const jobRow = await env.DB.prepare('SELECT id, ref, status, promo_code FROM jobs WHERE id = ?1').bind(pay.job_id).first<any>();
    const jobRef = jobRow?.ref ?? null;
    if (jobRow && (jobRow.status === 'canceled' || jobRow.status === 'cancelled')) {
      // The parcel died before the money landed (hold expired / canceled) —
      // never keep the payment: it goes straight back to the sender's momo,
      // and the single-use promo the booking burned is restored.
      await refundSettledPayment(env, pay, jobRef, 'Parcel canceled before payment landed — refund');
      if (jobRow.promo_code) {
        await env.DB.prepare(
          `UPDATE promo_codes SET uses_left = COALESCE(uses_left, 0) + 1 WHERE code = ?1 AND uses_left IS NOT NULL`,
        ).bind(jobRow.promo_code).run().catch(() => {});
      }
      return;
    }
    const paidClaim = await env.DB.prepare(`UPDATE jobs SET paid = 1 WHERE id = ?1 AND paid = 0`).bind(pay.job_id).run();
    if (!paidClaim.meta.changes) {
      // Two live prompts for one parcel (rapid double-tap Pay now): the
      // second approval is a DUPLICATE charge — give the money straight back.
      await refundSettledPayment(env, pay, jobRef, 'Duplicate payment for the same parcel — refund');
      return;
    }
    // The sender retried a HELD booking (Lipila down at booking time, then
    // came back) — dispatch now, on THIS approval. dispatchToNearestRider is
    // idempotent (skips already-assigned jobs), so a duplicate webhook is safe.
    if (jobRow) await dispatchToNearestRider(env, jobRow.ref);
    // Payment-held bookings only NOW earn their tracking link + handover code.
    await sendRecipientTrackingSms(env, pay.job_id);
    if (jobRef) await rewardReferralOnBooking(env, pay.job_id, pay.phone).catch(() => {});
    await sendToPhone(env, pay.phone, {
      title: 'Payment received',
      body: 'Confirmed! Your parcel is booked — follow every step in Bookings.',
      data: { job_ref: jobRef ?? '', kind: 'payment' },
    });
  } else if (pay.kind === 'topup') {
    // Rider/ops COD float only — customers never hold stored value.
    await sendToPhone(env, pay.phone, {
      title: 'Ride float loaded',
      body: `Your ride float balance is updated.`,
    });
  } else if (pay.kind === 'booking_deposit' && pay.job_id) {
    // Prepayment resolved: the momo money (exactly the quote for this parcel —
    // trip price + processing + momo legs, never more) IS this parcel's
    // payment. NOT A WALLET (compliance, PAYMENT_COMPLIANCE.md): the customer
    // balance is never credited — the job is marked paid directly and the
    // ledger row stays only as a job-linked audit trail. Any residue flows
    // back to the sender's momo on cancel-before-pickup. Coords are optional;
    // jobs from typed addresses fall back to the city anchor.
    const job = await env.DB.prepare(
      'SELECT id, ref, sender_phone, status, promo_code FROM jobs WHERE id = ?1',
    ).bind(pay.job_id).first<any>();
    if (job && (job.status === 'canceled' || job.status === 'cancelled')) {
      // Prepayment landed after the parcel was canceled — never keep it:
      // straight back to the sender's momo, promo use restored.
      await refundSettledPayment(env, pay, job.ref ?? null, 'Parcel canceled before prepayment landed — refund');
      if (job.promo_code) {
        await env.DB.prepare(
          `UPDATE promo_codes SET uses_left = COALESCE(uses_left, 0) + 1 WHERE code = ?1 AND uses_left IS NOT NULL`,
        ).bind(job.promo_code).run().catch(() => {});
      }
      return;
    }
    // Duplicate guard: the sender may have already paid via the Pay-now
    // retry (kind='job') while this original at-booking prompt was pending —
    // this approval is then a DUPLICATE, and the money goes straight back.
    const paidClaim = await env.DB.prepare(`UPDATE jobs SET paid = 1 WHERE id = ?1 AND paid = 0`).bind(pay.job_id).run();
    if (!paidClaim.meta.changes) {
      await refundSettledPayment(env, pay, job?.ref ?? null, 'Duplicate prepayment for the same parcel — refund');
      return;
    }
    // DISPATCH FIRST (owner bug 2026-11-17: "booking succeeds, money deducted,
    // screen never flips to success"): the money is claimed and the job is
    // paid — rider assignment, tracking and the sender's success flip must
    // never wait on (or die with) bookkeeping. The old order wrote the
    // wallet-ledger audit row BEFORE dispatch; that row has a FOREIGN KEY to
    // wallets(phone), which customers don't have ("NOT A WALLET"), so the
    // batch threw on EVERY momo settlement — dispatch, the deposit_paid
    // event, the tracking SMS and the OTP never ran, and the polling screen
    // got a 500 right when the money landed (jobs 18 + 19, both stuck
    // paid-but-undispatched). The minute cron's redispatch net also skipped
    // them forever (their advance_pending event never cleared).
    if (job) {
      try {
        await dispatchToNearestRider(env, job.ref);
      } catch (e) {
        // paid + riderless is recoverable: the minute cron retries dispatch.
        await captureError(env, e, { method: 'SETTLE', url: `https://settle/dispatch/${pay.job_id}` }).catch(() => {});
      }
    }
    // Payment-held bookings only NOW earn their tracking link + handover code.
    try {
      await sendRecipientTrackingSms(env, pay.job_id);
    } catch (e) {
      await captureError(env, e, { method: 'SETTLE', url: `https://settle/tracking/${pay.job_id}` }).catch(() => {});
    }
    if (job?.ref) await rewardReferralOnBooking(env, pay.job_id, pay.phone).catch(() => {});
    // Bookkeeping LAST and non-fatal: a failed audit row must never again be
    // able to kill a dispatch or a settlement response. The zero-balance
    // wallets row satisfies the wallet_ledger FK without crediting anything.
    try {
      await env.DB.batch([
        env.DB.prepare('INSERT OR IGNORE INTO wallets (phone, balance_zmw) VALUES (?1, 0)').bind(pay.phone),
        env.DB.prepare(`INSERT INTO wallet_ledger (phone, amount_zmw, kind, job_id) VALUES (?1, ?2, 'deposit', ?3)`)
          .bind(pay.phone, pay.amount_zmw, pay.job_id),
        env.DB.prepare(`INSERT INTO job_events (job_id, status, note) VALUES (?1, 'deposit_paid', ?2)`)
          .bind(pay.job_id, 'Prepayment approved — rider dispatched.'),
      ]);
    } catch (e) {
      await captureError(env, e, { method: 'SETTLE', url: `https://settle/ledger/${pay.job_id}` }).catch(() => {});
    }
  } else if (pay.kind === 'counter_fare' && pay.job_id) {
    // Sender paid the depot counter fare (+ processing) through DropOff.
    // Unlock the receipt photo for them, then reimburse the rider the EXACT
    // counter amount fee-free (the processing fee the sender paid covers
    // DropOff's costs — no payout fee is charged on the reimbursement).
    const job = await env.DB.prepare(
      `SELECT id, ref, sender_phone, counter_receipt_zmw, rider_id FROM jobs WHERE id = ?1`,
    ).bind(pay.job_id).first<any>();
    if (job) {
      const receipt = round2(Number(job.counter_receipt_zmw ?? 0));
      await env.DB.batch([
        env.DB.prepare(`UPDATE jobs SET counter_receipt_paid = 1 WHERE id = ?1 AND counter_receipt_paid = 0`).bind(job.id),
        env.DB.prepare(
          `INSERT INTO wallet_ledger (phone, amount_zmw, kind, job_id) VALUES (?1, ?2, 'counter_fare', ?3)`,
        ).bind(pay.phone, receipt, job.id),
        env.DB.prepare(
          `INSERT INTO job_events (job_id, status, note) VALUES (?1, 'counter_fare_paid', ?2)`,
        ).bind(job.id, `Sender paid the depot counter fare K${receipt.toFixed(2)} (+ processing) — receipt photo unlocked for the sender. Rider reimbursement in flight.`),
      ]);
      await sendToPhone(env, pay.phone, {
        title: 'Receipt unlocked',
        body: `Counter fare for ${job.ref ?? 'your parcel'} paid — the depot receipt photo is now visible in Bookings.`,
        data: { job_ref: job.ref ?? '', kind: 'counter_fare_paid' },
      });
      // Fire-and-forget: the reimbursement does its own error bookkeeping.
      reimburseRider(env, job, receipt).catch(() => { /* flagged on the job if it fails */ });
    }
  } else if (pay.kind === 'cod_remit' && pay.job_id) {
    await env.DB.prepare(
      `INSERT INTO job_events (job_id, status, note) VALUES (?1, 'cod_remit_paid', ?2)`,
    ).bind(pay.job_id, 'COD remit paid to sender momo (webhook)').run();
  }
}

// Reimburse the rider the EXACT depot counter amount they fronted — fee-free
// (the sender's processing fee already covered DropOff's costs). The audit
// trail: a payments row (kind rider_reimbursement, settles by webhook like
// cod_remit) + a job-linked ledger row. Failures raise a job event so ops can
// pay the rider manually via /admin/payments/:id/refund — the money is owed,
// it never disappears.
async function reimburseRider(
  env: Env,
  job: { id: number; ref: string | null; rider_id: number | null },
  amount: number,
): Promise<void> {
  if (amount <= 0) return;
  const rider = job.rider_id
    ? await env.DB.prepare('SELECT phone FROM riders WHERE id = ?1').bind(job.rider_id).first<any>()
    : null;
  if (!rider?.phone) {
    await env.DB.prepare(
      `INSERT INTO job_events (job_id, status, note) VALUES (?1, 'reimbursement_failed', ?2)`,
    ).bind(job.id, `Counter reimbursement K${amount.toFixed(2)} could not be sent — no rider on the job. Pay the rider manually via /admin/payments/:id/refund or payroll adjustment.`).run();
    return;
  }
  const ref = `reimb-${job.id}-${Date.now().toString(36)}`;
  try {
    await env.DB.batch([
      env.DB.prepare(
        `INSERT INTO payments (job_id, phone, provider, amount_zmw, credit_zmw, platform_fee_zmw,
           lipila_fee_zmw, lipila_reference, status, channel, kind)
         VALUES (?1, ?2, ?3, ?4, ?4, 0, 0, ?5, 'pending', 'merchant', 'rider_reimbursement')`,
      ).bind(job.id, rider.phone, providerFromPhone(rider.phone), amount, ref),
      // FK-safe (same bug class as the settle-time wallet_ledger crash): a
      // rider without a wallets row made this batch throw and the payout was
      // marked failed before Lipila was ever called.
      env.DB.prepare('INSERT OR IGNORE INTO wallets (phone, balance_zmw) VALUES (?1, 0)').bind(rider.phone),
      env.DB.prepare(
        `INSERT INTO wallet_ledger (phone, amount_zmw, kind, job_id) VALUES (?1, ?2, 'rider_reimburse', ?3)`,
      ).bind(rider.phone, amount, job.id),
    ]);
    const disb = await lipilaDisburse(env, rider.phone, amount, ref,
      `DropOff counter fare reimbursement ${job.ref ?? job.id}`.replace(/[^A-Za-z0-9 ]/g, ' '));
    if (!disb.ok) {
      await env.DB.batch([
        env.DB.prepare(`UPDATE payments SET status = 'failed' WHERE lipila_reference = ?1 AND status = 'pending'`).bind(ref),
        env.DB.prepare(
          `INSERT INTO job_events (job_id, status, note) VALUES (?1, 'reimbursement_failed', ?2)`,
        ).bind(job.id, `Counter reimbursement K${amount.toFixed(2)} to the rider failed at payout init (Lipila) — retry via /admin/payments/:id/refund. The rider is OWED this money.`),
      ]);
      // Surface Lipila's own error (auth/float/whitelist) on the row's meta so
      // ops screens can show WHY the payout failed, not just "failed".
      try {
        const row = await env.DB.prepare('SELECT id FROM payments WHERE lipila_reference = ?1 ORDER BY id DESC LIMIT 1').bind(ref).first<any>();
        if (row?.id) await recordFailReason(env, row.id, String(disb.raw ?? '').slice(0, 200) || 'payout_init_failed');
      } catch { /* best-effort */ }
    }
  } catch {
    try {
      await env.DB.prepare(
        `INSERT INTO job_events (job_id, status, note) VALUES (?1, 'reimbursement_failed', ?2)`,
      ).bind(job.id, `Counter reimbursement K${amount.toFixed(2)} bookkeeping failed — pay the rider manually. The money is owed.`);
    } catch { /* last resort: never break settlement */ }
  }
}

/* -------- platform revenue sweep (fees → business momo) ----------------- */
// All platform income sits in the Lipila merchant account as we collect it. When the
// undistributed balance reaches PLATFORM_SWEEP_MIN_ZMW, sweep it to the
// business number in one disbursement. Idempotent: the ledger row is written
// BEFORE the disburse call, so a crash-then-rerun can never double-pay
// (the pending row blocks the next sweep until it is marked success/failed).
async function sweepPlatformIncome(env: Env): Promise<void> {
  const businessPhone = env.BUSINESS_PHONE;
  if (!businessPhone) return;
  const earnedRow = await env.DB.prepare(
    `SELECT COALESCE(SUM(platform_fee_zmw), 0) AS total FROM payments WHERE status = 'success'`,
  ).first<any>();
  const sweptRow = await env.DB.prepare(
    `SELECT COALESCE(SUM(amount_zmw), 0) AS total FROM platform_disbursements WHERE status = 'success'`,
  ).first<any>();
  const pending = round2((earnedRow?.total ?? 0) - (sweptRow?.total ?? 0));
  if (pending < PLATFORM_SWEEP_MIN_ZMW) return;
  const open = await env.DB.prepare(
    `SELECT id FROM platform_disbursements WHERE status = 'pending' AND created_at > datetime('now', '-1 hour') LIMIT 1`,
  ).first<any>();
  if (open) return; // a sweep is still in flight — never disburse twice
  const ref = `sweep-${Date.now().toString(36)}`;
  const { meta } = await env.DB.prepare(
    `INSERT INTO platform_disbursements (amount_zmw, business_phone, lipila_reference, status)
       VALUES (?1, ?2, ?3, 'pending')`,
  ).bind(pending, businessPhone, ref).run();
  const disb = await lipilaDisburse(env, businessPhone, pending, ref, 'DropOff platform income sweep');
  if (disb.ok) {
    // pending sweep → success; any other still-'+90d' row resolves through status poll
    await env.DB.prepare(
      `UPDATE platform_disbursements SET status = 'success', lipila_reference = ?2, paid_at = datetime('now')
         WHERE id = ?1`,
    ).bind(meta.last_row_id, disb.lipilaReference ?? ref).run();
  } else {
    await env.DB.prepare(
      `UPDATE platform_disbursements SET status = 'failed' WHERE id = ?1`,
    ).bind(meta.last_row_id).run();
  }
}

/* ---------------------- cron: reconcile stuck payments -------------------- */
// Pending collects can miss their webhook (network, phone off). Sweep every
// pending payment older than 2 minutes, re-check with Lipila and settle what
// actually succeeded. Rows stuck >7 days are closed as failed.
async function reconcilePayments(env: Env): Promise<void> {  try {
    const { results } = await env.DB.prepare(
      `SELECT id, lipila_reference, kind FROM payments
        WHERE status = 'pending' AND lipila_reference IS NOT NULL
          AND created_at < datetime('now', '-2 minutes')
          AND created_at > datetime('now', '-2 days')
        ORDER BY id LIMIT 50`,
    ).all<any>();
    for (const pay of results ?? []) {
      // Payout kinds settle on the DISBURSEMENT status endpoint (a collect
      // check-status would never see their reference). Payout rows are only
      // status-flipped - their ledger/payroll bookkeeping happened at init.
      if (pay.kind === 'rider_reimbursement' || pay.kind === 'cod_remit') {
        const d = await lipilaDisburseStatusDetail(env, pay.lipila_reference);
        if (d.status === 'pending') continue;
        await env.DB.prepare('UPDATE payments SET status = ?2 WHERE id = ?1').bind(pay.id, d.status).run();
        await recordFailReason(env, pay.id, d.reason);
        continue;
      }
      const { status, reason } = await lipilaStatusDetail(env, pay.lipila_reference);
      if (status === 'pending') continue;
      await env.DB.prepare('UPDATE payments SET status = ?2 WHERE id = ?1').bind(pay.id, status).run();
      await recordFailReason(env, pay.id, reason);
      await settlePaymentSuccess(env, pay.id, status);
    }
    const expired = await env.DB.prepare(
      `SELECT id, kind, subscription_id, meta FROM payments
        WHERE status = 'pending' AND created_at < datetime('now', '-7 days')`,
    ).all();
    for (const row of expired.results as any[]) {
      // Abandoned mid-cycle upgrades: hand the seller their old tier back.
      if (row.kind === 'upgrade' || row.meta) {
        try {
          const info = JSON.parse(row.meta ?? '{}') as { prevTier?: string };
          if (info.prevTier && row.subscription_id) {
            await env.DB.prepare('UPDATE subscriptions SET tier = ?2 WHERE id = ?1')
              .bind(row.subscription_id, info.prevTier).run();
          }
        } catch { /* bad meta — skip revert */ }
      }
    }
    await env.DB.prepare(
      `UPDATE payments SET status = 'failed'
        WHERE status = 'pending' AND created_at < datetime('now', '-7 days')`,
    ).run();
  } catch { /* reconciliation is best-effort */ }
}

app.get('/payments/:id/status', async (c) => {
  const id = Number(c.req.param('id'));
  const pay = await c.env.DB.prepare(
    'SELECT id, job_id, phone, provider, amount_zmw, lipila_reference, status, kind, meta FROM payments WHERE id = ?1',
  ).bind(id).first<any>();
  if (!pay) return c.json({ error: 'not found' }, 404);
  const isOwner = c.get('phone') === pay.phone || c.get('role') === 'ops';
  if (!isOwner) return c.json({ error: 'forbidden' }, 403);

  if (pay.status === 'pending' && pay.lipila_reference) {
    const { status, reason } = await lipilaStatusDetail(c.env, pay.lipila_reference);
    if (status !== 'pending') {
      await c.env.DB.prepare('UPDATE payments SET status = ?2 WHERE id = ?1').bind(pay.id, status).run();
      await recordFailReason(c.env, pay.id, reason);
      await settlePaymentSuccess(c.env, pay.id, status);
      return c.json({ status, fail_reason: reason ?? null });
    }
    return c.json({ status, fail_reason: failReasonOf(pay.meta) });
  }
  return c.json({ status: pay.status, fail_reason: failReasonOf(pay.meta) });
});

// HELD-PAYMENT RECONCILE (owner bug 2026-11-17: "I paid but the payment
// screen didn't check or poll"): the held-booking screen polls THIS endpoint
// — the job's latest payment — and every pending row is re-checked against
// Lipila right here. A prompt approved late (or a webhook that never
// arrived) still settles and flips the booking out of HELD. The phone on the
// row is returned so the screen can tell the user WHICH number transacts.
// Gated to the job's sender phone + ops/admin.
app.get('/jobs/:ref/payments', async (c) => {
  const job = await c.env.DB.prepare(
    'SELECT id, sender_phone, paid FROM jobs WHERE ref = ?1',
  ).bind(c.req.param('ref')).first<any>();
  if (!job) return c.json({ error: 'not found' }, 404);
  if (c.get('phone') !== job.sender_phone && c.get('role') !== 'ops' && !isAdmin(c)) {
    return c.json({ error: 'forbidden' }, 403);
  }
  const pay = await c.env.DB.prepare(
    'SELECT id, phone, amount_zmw, status, kind, lipila_reference, meta, created_at FROM payments WHERE job_id = ?1 ORDER BY id DESC LIMIT 1',
  ).bind(job.id).first<any>();
  // JOB-PAID OVERRIDE (owner bug 2026-11-17: "booking succeeds, money
  // deducted, screen never flips"): the JOB being paid is the truth this
  // endpoint sells. A newer PENDING row (a retried "Pay now" prompt) used to
  // shadow an earlier settled payment and keep the held-watch spinning — and
  // a settlement whose side-effects threw (the wallet_ledger FK bug) left
  // the job paid while the screen stayed HELD. If the job is paid, the
  // screen flips — no Lipila round-trip, no shadowing row, no stuck watch.
  if (Number(job.paid) === 1) {
    return c.json({
      payment: pay ? { ...pay, status: 'success' } : null,
      job_paid: true,
    });
  }
  if (!pay) return c.json({ payment: null });
  if (pay.status === 'pending' && pay.kind !== 'cod_remit' && pay.kind !== 'rider_reimbursement' && pay.lipila_reference) {
    const { status, reason } = await lipilaStatusDetail(c.env, pay.lipila_reference);
    if (status !== 'pending') {
      await c.env.DB.prepare('UPDATE payments SET status = ?2 WHERE id = ?1').bind(pay.id, status).run();
      await recordFailReason(c.env, pay.id, reason);
      await settlePaymentSuccess(c.env, pay.id, status);
      pay.status = status;
      if (reason) pay.meta = JSON.stringify({ ...(pay.meta ? safeParse(pay.meta) : {}), fail_reason: reason });
    }
  }
  return c.json({
    payment: {
      payment_id: pay.id,
      status: pay.status,
      amount_zmw: pay.amount_zmw,
      phone: pay.phone,
      kind: pay.kind,
      created_at: pay.created_at,
      fail_reason: failReasonOf(pay.meta),
    },
  });
});

// Tiny parse helper for the fail-reason merge above (never throw from a poll).
function safeParse(s: string): Record<string, unknown> {
  try { return JSON.parse(s) as Record<string, unknown>; } catch { return {}; }
}

app.get('/payments/:id/receipt', async (c) => {
  const id = Number(c.req.param('id'));
  const pay = await c.env.DB.prepare(
    `SELECT p.*, j.ref AS job_ref, j.sender_name, j.pickup_address, j.dest_city,
            co.name AS courier_name
       FROM payments p
       LEFT JOIN jobs j ON j.id = p.job_id
       LEFT JOIN couriers co ON co.id = j.courier_id
      WHERE p.id = ?1`,
  ).bind(id).first<any>();
  if (!pay) return c.json({ error: 'not found' }, 404);
  if (c.get('role') === 'customer' && c.get('phone') !== pay.phone) return c.json({ error: 'forbidden' }, 403);
  return c.json({
    receipt_no: `RCPT-${pay.id}`,
    payment_id: pay.id,
    status: pay.status,
    kind: pay.kind,
    paid_at: pay.paid_at,
    created_at: pay.created_at,
    phone: pay.phone,
    job_ref: pay.job_ref ?? null,
    sender_name: pay.sender_name ?? null,
    pickup_address: pay.pickup_address ?? null,
    dest_city: pay.dest_city ?? null,
    courier: pay.courier_name ?? null,
    amounts: {
      total_zmw: pay.amount_zmw,
      credit_zmw: pay.credit_zmw ?? 0,
      platform_fee_zmw: pay.platform_fee_zmw ?? 0,
      lipila_fee_zmw: pay.lipila_fee_zmw ?? 0,
    },
    refund_of_payment_id: pay.refund_of_payment_id ?? null,
    refunded_at: pay.refunded_at ?? null,
    lipila_reference: pay.lipila_reference ?? null,
  });
});

/* ---------------------------- Lipila webhook ------------------------------ */
// NEVER trust the webhook body: anyone can POST {"reference": …, "status":
// "success"} and get free rides. The reported status is ignored — we look the
// payment up and re-verify the true status with Lipila's API before settling.
// (cod_remit rows are disbursements we initiated ourselves; we only log them.)
app.post('/webhooks/lipila', async (c) => {
  // Optional shared-secret gate (defence in depth — the body is never trusted).
  if (c.env.LIPILA_WEBHOOK_SECRET) {
    const got = c.req.header('X-Lipila-Signature') ?? c.req.header('X-Webhook-Secret')
      ?? new URL(c.req.url).searchParams.get('secret') ?? '';
    const want = c.env.LIPILA_WEBHOOK_SECRET;
    const equal = got.length === want.length && got.split('').every((ch, i) => ch === want[i]);
    if (!equal) return c.json({ error: 'unauthorized' }, 401);
  }
  const b: any = await c.req.json().catch(() => null);
  if (!b) return c.json({ ok: true });
  const ref = b.reference ?? b.data?.reference;
  if (!ref) return c.json({ ok: true });
  const pay = await c.env.DB.prepare(
    'SELECT id, status, kind, lipila_reference FROM payments WHERE lipila_reference = ?1 ORDER BY id DESC LIMIT 1',
  ).bind(String(ref)).first<any>();
  if (!pay) return c.json({ ok: true });

  if (pay.kind === 'cod_remit' || pay.kind === 'rider_reimbursement') {
    // Our own disbursements: the body is UNVERIFIED. Without the shared
    // secret we never flip a payout to success from a bare POST — the
    // disbursement caller already records the final status from Lipila's
    // own response. With the secret configured, the origin check at the
    // top of this handler has passed, so upgrading to success is sound.
    if (c.env.LIPILA_WEBHOOK_SECRET && pay.status !== 'success') {
      await c.env.DB.prepare('UPDATE payments SET status = ?2 WHERE id = ?1').bind(pay.id, 'success').run();
    }
    return c.json({ ok: true });
  }

  if (pay.status === 'pending' && pay.lipila_reference) {
    // authoritative check straight from Lipila — body status is advisory only
    const { status, reason } = await lipilaStatusDetail(c.env, pay.lipila_reference);
    if (status !== 'pending') {
      await c.env.DB.prepare('UPDATE payments SET status = ?2 WHERE id = ?1').bind(pay.id, status).run();
      await recordFailReason(c.env, pay.id, reason);
      await settlePaymentSuccess(c.env, pay.id, status);
      return c.json({ ok: true, status });
    }
  }
  return c.json({ ok: true, status: pay.status });
});

/* ------------------------- seller subscription packs ----------------------- */
/* ---------- server-backed address book (owner 2026-11-18) ------------- */
// Places used in search / booking / GPS pinning are stored against the signed-in
// phone. The app keeps an offline mirror; this is the shared, growing collection
// that seeds the in-app map across sessions and devices.
app.get('/places', async (c) => {
  const phone = c.get('phone');
  if (!phone) return c.json({ error: 'identity_required' }, 401);
  const { results } = await c.env.DB.prepare(
    `SELECT id, label, lat, lng, source, used_at, created_at
       FROM saved_places WHERE phone = ?1
      ORDER BY used_at DESC, id DESC LIMIT 100`,
  ).bind(phone).all();
  return c.json({ places: results });
});
app.post('/places', async (c) => {
  const phone = c.get('phone');
  if (!phone) return c.json({ error: 'identity_required' }, 401);
  const b: any = await c.req.json().catch(() => null);
  const label = String(b?.label ?? '').trim().slice(0, 180);
  if (!label) return c.json({ error: 'label_required' }, 400);
  const lat = Number(b?.lat);
  const lng = Number(b?.lng);
  const hasPin = Number.isFinite(lat) && Number.isFinite(lng) && lat !== 0 && lng !== 0;
  const source = String(b?.source ?? 'app').slice(0, 32);
  await c.env.DB.prepare(
    `INSERT INTO saved_places (phone, label, lat, lng, source, used_at)
     VALUES (?1, ?2, ?3, ?4, ?5, datetime('now'))
     ON CONFLICT(phone, label) DO UPDATE SET
       lat = COALESCE(excluded.lat, saved_places.lat),
       lng = COALESCE(excluded.lng, saved_places.lng),
       source = excluded.source, used_at = datetime('now')`,
  ).bind(phone, label, hasPin ? lat : null, hasPin ? lng : null, source).run();
  return c.json({ ok: true, label });
});

app.get('/plans', async (c) => {
  // Driver economics are for drivers and admins only — sellers/customers get
  // the tier catalogue alone. Flags let the app hide dark features (the
  // owner flips them from /admin/settings without a deploy).
  const privileged = c.get('role') === 'ops' || isAdmin(c);
  return c.json({
    plans: await plans(c.env.DB),
    feature_flags: {
      overage_discount_enabled: flagOn(await getSetting(c.env.DB, 'overage_discount_enabled')),
      door_to_door_enabled: flagOn(await getSetting(c.env.DB, 'door_to_door_enabled')),
    },
    ...(privileged ? { driver_monthly_pay_zmw: DRIVER_MONTHLY_PAY_ZMW, driver_daily_target: DRIVER_DAILY_TARGET, platform_take: PLATFORM_TAKE } : {}),
  });
});

/* ---------------------------- partner shop portal -------------------------- */
// Partner accounts are normal auth_users with role='partner' + courier_id, set
// by the superadmin (POST /admin/partners). They log in like any customer, then:
//   GET  /partner/quotes            → the courier's published counter prices
//   POST /partner/quotes            → upsert/confirm a counter price
//   GET  /partner/rides             → parcels handed to this courier
//   POST /partner/rides/:ref/confirm → acknowledge hand-off at the depot
function partnerCourierId(c: { get: (k: string) => unknown }): number | null {
  if (c.get('role') === 'partner') return c.get('courierId') as number ?? null;
  return null;
}

app.get('/partner/me', async (c) => {
  const courierId = partnerCourierId(c);
  const user = await c.env.DB.prepare(
    'SELECT email, full_name FROM auth_users WHERE phone = ?1 AND role = ?2',
  ).bind(c.get('phone') ?? '', c.get('role') ?? 'partner').first<any>();
  const courier = courierId
    ? await c.env.DB.prepare('SELECT id, name, city, depot_name, price_status FROM couriers WHERE id = ?1')
      .bind(courierId).first()
    : null;
  return c.json({
    email: user?.email ?? null, full_name: user?.full_name ?? null,
    courier, role: c.get('role'),
  });
});

app.get('/partner/quotes', async (c) => {
  const courierId = partnerCourierId(c);
  // Partner JWTs are pinned to their own courier — no `?courier_id=` browsing.
  // Ops/admin keys may inspect any courier explicitly.
  const target = c.get('role') === 'partner'
    ? courierId
    : (isAdmin(c) || c.get('role') === 'ops' ? Number(c.req.query('courier_id') ?? 0) : null);
  if (!target) return c.json({ error: 'partner_not_linked_to_courier' }, 403);
  const { results } = await c.env.DB.prepare(
    `SELECT id, courier_id, from_city, to_city, weight_class, service, counter_price_zmw, updated_at
       FROM quotes WHERE courier_id = ?1 ORDER BY to_city, weight_class`,
  ).bind(target).all();
  return c.json({ quotes: results });
});

app.post('/partner/quotes', async (c) => {
  const b: any = await c.req.json().catch(() => null);
  const courierId = partnerCourierId(c);
  const required = ['courier_id', 'from_city', 'to_city', 'weight_class', 'service', 'counter_price_zmw'];
  for (const k of required) if (b?.[k] === undefined) return c.json({ error: `${k} required` }, 400);
  if (courierId && Number(b.courier_id) !== courierId) return c.json({ error: 'forbidden_courier' }, 403);
  if (Number(b.counter_price_zmw) <= 0) return c.json({ error: 'counter_price_zmw must be > 0' }, 400);
  const exists = await c.env.DB.prepare(
    `SELECT id FROM quotes WHERE courier_id = ?1 AND from_city = ?2 AND to_city = ?3
       AND weight_class = ?4 AND service = ?5`,
  ).bind(b.courier_id, b.from_city, b.to_city, b.weight_class, b.service).first<any>();
  let id: number;
  if (exists) {
    await c.env.DB.prepare(
      `UPDATE quotes SET counter_price_zmw = ?2, updated_at = datetime('now') WHERE id = ?1`,
    ).bind(exists.id, b.counter_price_zmw).run();
    id = exists.id;
  } else {
    const { meta } = await c.env.DB.prepare(
      `INSERT INTO quotes (courier_id, from_city, to_city, weight_class, service, counter_price_zmw)
       VALUES (?1,?2,?3,?4,?5,?6)`,
    ).bind(b.courier_id, b.from_city, b.to_city, b.weight_class, b.service, b.counter_price_zmw).run();
    id = meta.last_row_id;
  }
  await c.env.DB.prepare(
    `UPDATE couriers SET price_status = 'confirmed_by_partner' WHERE id = ?1`,
  ).bind(b.courier_id).run();
  return c.json({ ok: true, id, confirmed: true });
});

app.get('/partner/rides', async (c) => {
  const courierId = partnerCourierId(c);
  // Same pinning as quotes: partners only ever see their own depot's rides.
  const target = c.get('role') === 'partner'
    ? courierId
    : (isAdmin(c) || c.get('role') === 'ops' ? Number(c.req.query('courier_id') ?? 0) : null);
  if (!target) return c.json({ error: 'partner_not_linked_to_courier' }, 403);
  const { results } = await c.env.DB.prepare(
    `SELECT j.ref, j.recipient_name, j.recipient_phone, j.dest_city, j.weight_class,
            j.counter_price_zmw, j.total_zmw, j.status, j.paid, j.created_at,
            (SELECT status FROM job_events ev WHERE ev.job_id = j.id ORDER BY ev.id DESC LIMIT 1) AS last_event
       FROM jobs j WHERE j.courier_id = ?1 ORDER BY j.id DESC LIMIT 50`,
  ).bind(target).all();
  return c.json({ jobs: results });
});

app.post('/partner/rides/:ref/confirm', async (c) => {
  const courierId = partnerCourierId(c);
  const job = await c.env.DB.prepare(
    'SELECT id, courier_id FROM jobs WHERE ref = ?1',
  ).bind(c.req.param('ref')).first<any>();
  if (!job) return c.json({ error: 'job not found' }, 404);
  // A partner JWT can only confirm hand-offs at ITS OWN depot — an unlinked
  // partner account confirms nothing.
  if (c.get('role') === 'partner' && (!courierId || job.courier_id !== courierId)) {
    return c.json({ error: 'not_your_courier_job' }, 403);
  }
  if (c.get('role') !== 'partner' && !isAdmin(c) && c.get('role') !== 'ops') {
    return c.json({ error: 'forbidden' }, 403);
  }
  const b: any = await c.req.json().catch(() => ({}));
  await c.env.DB.prepare(
    'INSERT INTO job_events (job_id, status, note) VALUES (?1, ?2, ?3)',
  ).bind(job.id, 'partner_confirmed',
    b?.note ?? `Depot confirmed hand-off${b?.waybill ? ` — waybill ${b.waybill}` : ''}`).run();
  if (b?.waybill) {
    await c.env.DB.prepare('UPDATE jobs SET courier_waybill = ?2 WHERE id = ?1').bind(job.id, b.waybill).run();
  }
  return c.json({ ok: true, ref: c.req.param('ref') });
});

/* -------- partner webhook ingestion (any POS/dispatch system) ------------- */
// A courier shop plugs THEIR system into ours with one HTTPS call. Status maps
// 1:1 onto the parcel timeline the sender already watches.
const PARTNER_EVENT_MAP: Record<string, string> = {
  at_depot: 'at_depot', departed: 'departed', arrived: 'arrived',
  ready_for_collection: 'ready_for_collection', delivered: 'delivered',
};
app.post('/webhooks/partner-status', async (c) => {
  const key = c.req.header('X-Partner-Key') ?? '';
  const pk = await c.env.DB.prepare('SELECT courier_id FROM partner_keys WHERE api_key = ?1').bind(key).first<any>();
  if (!pk) return c.json({ error: 'bad_partner_key' }, 403);
  const b: any = await c.req.json().catch(() => null);
  if (!b) return c.json({ error: 'invalid JSON body' }, 400);
  const status = String(b.status ?? '').toLowerCase();
  if (!PARTNER_EVENT_MAP[status]) {
    return c.json({ error: 'status must be one of: ' + Object.keys(PARTNER_EVENT_MAP).join(', ') }, 400);
  }
  const waybill = String(b.waybill ?? '').trim();
  const ref = String(b.ref ?? '').trim();
  if (!waybill && !ref) return c.json({ error: 'waybill or ref required' }, 400);
  let job: any = null;
  // A partner key is scoped to ITS depot only — a key for courier A says
  // nothing about courier B's parcels, however they were addressed.
  if (waybill) job = await c.env.DB.prepare('SELECT id, ref FROM jobs WHERE courier_waybill = ?1 AND courier_id = ?2 LIMIT 1').bind(waybill, pk.courier_id).first();
  if (!job && ref) job = await c.env.DB.prepare('SELECT id, ref FROM jobs WHERE ref = ?1 AND courier_id = ?2 LIMIT 1').bind(ref, pk.courier_id).first();
  if (!job) return c.json({ error: 'unknown_waybill' }, 404);
  // Held (unpaid) parcels never arrive at a depot — refuse confirmations.
  if (await jobPaymentHeld(c.env.DB, job.id)) {
    return c.json({ error: 'payment_pending', detail: 'Parcel is held until its prepayment is approved.' }, 409);
  }
  const since = new Date(Date.now() - 5 * 60 * 1000).toISOString().replace('T', ' ').slice(0, 19);
  const dup = await c.env.DB.prepare(
    'SELECT id FROM job_events WHERE job_id = ?1 AND status = ?2 AND created_at > ?3 LIMIT 1',
  ).bind(job.id, PARTNER_EVENT_MAP[status], since).first<any>();
  if (dup) return c.json({ ok: true, deduped: true });
  await c.env.DB.batch([
    c.env.DB.prepare('INSERT INTO job_events (job_id, status, note) VALUES (?1,?2,?3)')
      .bind(job.id, PARTNER_EVENT_MAP[status], `[partner] ${b.note ?? status}${b.at ? ` @ ${b.at}` : ''}`),
    c.env.DB.prepare('UPDATE jobs SET status = ?2, partner_confirmed = 1 WHERE id = ?1')
      .bind(job.id, PARTNER_EVENT_MAP[status]),
  ]);
  return c.json({ ok: true, ref: job.ref, partner_confirmed: true });
});

// Per-partner webhook key. Generate/rotate from the superadmin console.
app.post('/admin/partner-keys', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'admin_key_required' }, 403);
  const b: any = await c.req.json().catch(() => null);
  const cid = Number(b?.courier_id);
  if (!cid) return c.json({ error: 'courier_id required' }, 400);
  const key = crypto.randomUUID().replace(/-/g, '');
  await c.env.DB.prepare(
    `INSERT INTO partner_keys (courier_id, api_key) VALUES (?1, ?2)
     ON CONFLICT(courier_id) DO UPDATE SET api_key = excluded.api_key, created_at = datetime('now')`,
  ).bind(cid, key).run();
  return c.json({
    ok: true, courier_id: cid, api_key: key,
    usage: 'POST /webhooks/partner-status  X-Partner-Key: <key>  {"waybill":"...","status":"departed|arrived|delivered|ready_for_collection|at_depot","note":"optional","at":"ISO"}',
  });
});

/* -------- tiers (seller packs — live editable) + promo codes ------------- */
// List ALL known tiers including toggled-off ones (admin catalogue for the
// console) — the sales catalogue hides inactive rows, the console must not.
app.get('/admin/tiers', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'admin_key_required' }, 403);
  const known = ['rider_daily', 'weekly', 'silver', 'gold', 'platinum'];
  const { results } = await c.env.DB.prepare(
    `SELECT tier, fee_zmw, parcels_per_day, parcels_per_month, rider_fee_zmw,
            overage_discount_pct, cycle_days, tag, active
       FROM tiers WHERE tier IN ('rider_daily','weekly','silver','gold','platinum')`,
  ).all();
  const rows = new Map<string, any>();
  for (const r of results as any[]) rows.set(r.tier, r);
  const activeMap = await plans(c.env.DB, { forExistingSubscribers: true });
  const tiers = known.map((tier) => {
    const row = rows.get(tier);
    const active = row ? Number(row.active) === 1 : true; // no row yet = seed default (on)
    const def = activeMap[tier as PlanTier] ?? PLANS[tier as PlanTier];
    return {
      tier, active,
      fee_zmw: row?.fee_zmw ?? def.fee_zmw,
      parcels_per_day: row?.parcels_per_day ?? def.parcels_per_day,
      parcels_per_month: row?.parcels_per_month ?? def.parcels_per_month,
      rider_fee_zmw: row?.rider_fee_zmw ?? def.rider_fee_zmw,
      overage_discount_pct: row?.overage_discount_pct ?? def.overage_discount_pct,
      cycle_days: row?.cycle_days ?? def.cycle_days,
      tag: row?.tag ?? def.tag ?? null,
      windows: def.windows,
    };
  });
  return c.json({ tiers });
});

// Platform feature flags, owner-flippable WITHOUT a deploy. Keys are
// whitelisted; every value is a '0'/'1' string. Read-only for staff.
const SETTING_KEYS = new Set(['door_to_door_enabled', 'overage_discount_enabled']);
app.get('/admin/settings', async (c) => {
  if (!isFinanceExec(c)) return c.json({ error: 'forbidden' }, 403);
  return c.json({
    settings: {
      door_to_door_enabled: flagOn(await getSetting(c.env.DB, 'door_to_door_enabled')),
      overage_discount_enabled: flagOn(await getSetting(c.env.DB, 'overage_discount_enabled')),
    },
  });
});
app.post('/admin/settings', async (c) => {
  // Owner/superadmin only — these flags gate paid surfaces.
  if (!isSuperAdmin(c)) return c.json({ error: 'superadmin_required' }, 403);
  const b: any = await c.req.json().catch(() => null);
  const key = String(b?.key ?? '').trim().toLowerCase();
  if (!SETTING_KEYS.has(key)) return c.json({ error: `unknown setting (allowed: ${[...SETTING_KEYS].join(', ')})` }, 400);
  const on = b?.enabled === true || String(b?.value ?? '') === '1';
  await setSetting(c.env.DB, key, on ? '1' : '0', c.get('phone') ?? 'admin-key');
  return c.json({ ok: true, key, enabled: on });
});
// Full plan edit OR toggle: every field of a plan is editable here — the
// same endpoint handles "set off" (active: 0) without wiping its config.
app.post('/admin/tiers', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'admin_key_required' }, 403);
  const b: any = await c.req.json().catch(() => null);
  const tier = String(b?.tier ?? '').trim().toLowerCase();
  if (!/^[a-z0-9_]{2,20}$/.test(tier)) return c.json({ error: 'tier id must be 2-20 lowercase letters/digits/_' }, 400);
  const seed = PLANS[tier as PlanTier];
  if (!seed) return c.json({ error: `unknown tier ${tier}` }, 400);
  const fee = Math.max(0, Number(b?.fee_zmw ?? seed.fee_zmw));
  const ppd = Math.max(0, Math.round(Number(b?.parcels_per_day ?? seed.parcels_per_day)));
  const ppm = Math.max(0, Math.round(Number(b?.parcels_per_month ?? seed.parcels_per_month)));
  const disc = Math.max(0, Math.min(100, Number(b?.overage_discount_pct ?? seed.overage_discount_pct)));
  const days = Math.max(1, Math.round(Number(b?.cycle_days ?? seed.cycle_days)));
  const rider = Math.max(0, Number(b?.rider_fee_zmw ?? seed.rider_fee_zmw));
  const tag = b?.tag == null || String(b.tag).trim() === '' ? null : String(b.tag).trim().slice(0, 40);
  // Partial toggle request ({tier, active:0/1}) keeps all other config untouched.
  const toggleOnly = Object.keys(b ?? {}).every((k) => ['tier', 'active'].includes(k));
  if (toggleOnly) {
    await c.env.DB.prepare(
      `INSERT INTO tiers (tier, fee_zmw, parcels_per_day, parcels_per_month, rider_fee_zmw, overage_discount_pct, cycle_days, tag, active)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
       ON CONFLICT(tier) DO UPDATE SET active=excluded.active`,
    ).bind(tier, seed.fee_zmw, seed.parcels_per_day, seed.parcels_per_month, seed.rider_fee_zmw, seed.overage_discount_pct, seed.cycle_days, seed.tag ?? null, b?.active ? 1 : 0).run();
    return c.json({ ok: true, tier, active: b?.active ? 1 : 0 });
  }
  const active = b?.active == null ? 1 : (b.active ? 1 : 0);
  await c.env.DB.prepare(
    `INSERT INTO tiers (tier, fee_zmw, parcels_per_day, parcels_per_month, rider_fee_zmw, overage_discount_pct, cycle_days, tag, active)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
     ON CONFLICT(tier) DO UPDATE SET fee_zmw=excluded.fee_zmw, parcels_per_day=excluded.parcels_per_day,
       parcels_per_month=excluded.parcels_per_month,
       rider_fee_zmw=excluded.rider_fee_zmw, overage_discount_pct=excluded.overage_discount_pct,
       cycle_days=excluded.cycle_days, tag=excluded.tag, active=excluded.active`,
  ).bind(tier, fee, ppd, ppm, rider, disc, days, tag, active).run();
  return c.json({ ok: true, tier, fee_zmw: fee, parcels_per_day: ppd, parcels_per_month: ppm, rider_fee_zmw: rider,
    overage_discount_pct: disc, cycle_days: days, tag, active });
});

app.get('/admin/promos', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'admin_key_required' }, 403);
  const { results } = await c.env.DB.prepare('SELECT * FROM promo_codes ORDER BY created_at DESC LIMIT 200').all();
  return c.json({ promos: results });
});
app.post('/admin/promos', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'admin_key_required' }, 403);
  const b: any = await c.req.json().catch(() => null);
  const code = String(b?.code ?? '').trim().toUpperCase();
  if (!/^[A-Z0-9_-]{3,24}$/.test(code)) return c.json({ error: 'code must be 3-24 A-Z/0-9/_/-' }, 400);
  const pct = Number(b?.discount_pct);
  if (!(pct > 0 && pct <= 100)) return c.json({ error: 'discount_pct must be 0-100' }, 400);
  const tier = b?.applies_tier ? String(b.applies_tier).trim().toLowerCase() : null;
  const uses = b?.uses_left == null ? null : Math.max(0, Math.round(Number(b.uses_left)));
  const exp = b?.expires_at ? String(b.expires_at) : null;
  await c.env.DB.prepare(
    `INSERT INTO promo_codes (code, discount_pct, note, applies_tier, uses_left, expires_at, active)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, 1)
     ON CONFLICT(code) DO UPDATE SET discount_pct=excluded.discount_pct, note=excluded.note,
       applies_tier=excluded.applies_tier, uses_left=excluded.uses_left, expires_at=excluded.expires_at, active=1`,
  ).bind(code, pct, b?.note ?? null, tier, uses, exp).run();
  return c.json({ ok: true, code, discount_pct: pct });
});

/* ----------------- rider incentive programmes (admin-promoted promos) -------- */
// Admin/superadmin creates a promo with a TITLE ("Christmas Bonus", "Weekend
// Sprint") — rider incentives then run through the normal payroll confirmation
// chain, never in-app cash-outs. Per the salaried model, incentives sit ON TOP
// of base pay; this programme simply defines the bonus envelope.
// Only ONE programme is active at a time — activate a different one to replace it.
app.get('/admin/incentives', async (c) => {
  if (!isAdmin(c) && c.get('role') !== 'ops') return c.json({ error: 'admin_key_required' }, 403);
  const { results } = await c.env.DB.prepare(
    `SELECT * FROM incentive_programmes ORDER BY active DESC, id DESC LIMIT 50`,
  ).all();
  // Include currently-active programme for convenience.
  const active = results?.find((r: any) => Number(r.active) === 1) ?? null;
  return c.json({ programmes: results ?? [], active });
});
app.post('/admin/incentives', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'admin_key_required' }, 403);
  const b: any = await c.req.json().catch(() => null);
  const title = String(b?.title ?? '').trim().slice(0, 64);
  if (title.length < 3) return c.json({ error: 'title must be 3+ characters' }, 400);
  const num = (v: any, d: number, min: number, max: number) => {
    const n = Number(v ?? d); return Number.isFinite(n) ? Math.max(min, Math.min(max, n)) : d;
  };
  const startsOn = b?.starts_on ? String(b.starts_on).trim() : null;
  const endsOn = b?.ends_on ? String(b.ends_on).trim() : null;
  const params = [
    title,
    startsOn, endsOn,
    num(b?.completion_bonus_zmw, DRIVER_COMPLETION_BONUS_ZMW, 0, 10000),
    num(b?.per_extra_parcel_zmw, DRIVER_OVER_TARGET_BONUS_ZMW, 0, 500),
    Math.round(num(b?.per_extra_cap, DRIVER_OVER_TARGET_CAP, 0, 5000)),
    num(b?.stretch_ratio, DRIVER_STRETCH_RATIO, 1, 5),
    num(b?.stretch_bonus_zmw, DRIVER_STRETCH_BONUS_ZMW, 0, 10000),
    String(b?.note ?? '').trim().slice(0, 280),
    String(b?.created_by ?? c.get('phone') ?? 'admin').slice(0, 30),
  ];
  const id = Number(b?.id ?? 0);
  if (id > 0) {
    await c.env.DB.prepare(
      `UPDATE incentive_programmes SET title=?1, starts_on=?2, ends_on=?3,
         completion_bonus_zmw=?4, per_extra_parcel_zmw=?5, per_extra_cap=?6,
         stretch_ratio=?7, stretch_bonus_zmw=?8, note=?9, created_by=?10
       WHERE id=?11`,
    ).bind(...params, id).run();
    return c.json({ ok: true, id });
  }
  // Creating a NEW active programme also deactivates the previous one.
  const active = b?.active == null ? 1 : (b.active ? 1 : 0);
  if (active) {
    await c.env.DB.prepare(
      `UPDATE incentive_programmes SET active = 0 WHERE active = 1`,
    ).run();
  }
  const { meta } = await c.env.DB.prepare(
    `INSERT INTO incentive_programmes (title, starts_on, ends_on,
       completion_bonus_zmw, per_extra_parcel_zmw, per_extra_cap,
       stretch_ratio, stretch_bonus_zmw, active, note, created_by)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)`,
  ).bind(...params, active).run();
  return c.json({ ok: true, id: meta.last_row_id });
});
// Toggle on/off without touching amounts.
app.post('/admin/incentives/:id/toggle', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'admin_key_required' }, 403);
  const id = Number(c.req.param('id'));
  if (!Number.isFinite(id) || id <= 0) return c.json({ error: 'bad_id' }, 400);
  const b: any = await c.req.json().catch(() => null);
  const on = b?.active == null ? undefined : (b.active ? 1 : 0);
  if (on === undefined) {
    const row = await c.env.DB.prepare('SELECT active FROM incentive_programmes WHERE id=?1').bind(id).first<any>();
    if (!row) return c.json({ error: 'not found' }, 404);
    const now = Number(row.active) === 1 ? 0 : 1;
    if (now === 1) await c.env.DB.prepare('UPDATE incentive_programmes SET active = 0 WHERE active = 1 AND id != ?1').bind(id).run();
    await c.env.DB.prepare('UPDATE incentive_programmes SET active = ?2 WHERE id = ?1').bind(id, now).run();
    return c.json({ ok: true, id, active: now });
  }
  if (on === 1) await c.env.DB.prepare('UPDATE incentive_programmes SET active = 0 WHERE active = 1 AND id != ?1').bind(id).run();
  await c.env.DB.prepare('UPDATE incentive_programmes SET active = ?2 WHERE id = ?1').bind(id, on).run();
  return c.json({ ok: true, id, active: on });
});

/* -------- partner collection rails (THEIR POS — never DropOff money) ------- */
// Sellers pay the courier directly at the counter/depot using the partner's
// own merchant till (momo / bank / POS terminal / WhatsApp order). DropOff
// bridges the context, not the custody: the money is the partner's, always.
app.post('/partner/pos', async (c) => {
  if (c.get('role') !== 'partner') return c.json({ error: 'partner role required' }, 403);
  const cid = Number(c.get('courierId'));
  if (!cid) return c.json({ error: 'no courier linked to this account' }, 400);
  const b: any = await c.req.json().catch(() => null);
  const rail = String(b?.rail ?? '').trim().toLowerCase();
  if (!['momo', 'bank', 'pos_terminal', 'whatsapp', 'cash'].includes(rail)) {
    return c.json({ error: 'rail must be momo|bank|pos_terminal|whatsapp|cash' }, 400);
  }
  const instructions = String(b?.instructions ?? '').trim() || null;
  const merchant = String(b?.merchant_id ?? '').trim() || null;
  await c.env.DB.prepare(
    `INSERT INTO partner_pos (courier_id, rail, merchant_id, instructions) VALUES (?1,?2,?3,?4)
     ON CONFLICT(courier_id) DO UPDATE SET rail=excluded.rail, merchant_id=excluded.merchant_id,
       instructions=excluded.instructions, updated_at=datetime('now')`,
  ).bind(cid, rail, merchant, instructions).run();
  return c.json({ ok: true, courier_id: cid, rail });
});

async function partnerPosList(db: D1Database) {
  const { results } = await db.prepare(
    `SELECT p.*, co.name AS courier_name FROM partner_pos p JOIN couriers co ON co.id = p.courier_id WHERE p.active = 1 ORDER BY co.name`,
  ).all();
  return results;
}
app.get('/partner/pos', async (c) => {
  const role = c.get('role');
  if (role === 'partner') {
    const cid = Number(c.get('courierId'));
    const row = cid ? await c.env.DB.prepare('SELECT * FROM partner_pos WHERE courier_id = ?1').bind(cid).first() : null;
    const key = cid ? await c.env.DB.prepare('SELECT api_key FROM partner_keys WHERE courier_id = ?1').bind(cid).first() : null;
    return c.json({ pos: row ?? null, webhook_key: (key as any)?.api_key ?? null });
  }
  if (!isAdmin(c)) return c.json({ error: 'admin_key_required' }, 403);
  return c.json({ pos: await partnerPosList(c.env.DB) });
});
app.post('/admin/pos', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'admin_key_required' }, 403);
  const b: any = await c.req.json().catch(() => null);
  const cid = Number(b?.courier_id);
  const rail = String(b?.rail ?? '').trim().toLowerCase();
  if (!cid || !['momo', 'bank', 'pos_terminal', 'whatsapp', 'cash'].includes(rail)) {
    return c.json({ error: 'courier_id and rail (momo|bank|pos_terminal|whatsapp|cash) required' }, 400);
  }
  await c.env.DB.prepare(
    `INSERT INTO partner_pos (courier_id, rail, merchant_id, instructions) VALUES (?1,?2,?3,?4)
     ON CONFLICT(courier_id) DO UPDATE SET rail=excluded.rail, merchant_id=excluded.merchant_id,
       instructions=excluded.instructions, updated_at=datetime('now')`,
  ).bind(cid, rail, String(b?.merchant_id ?? '').trim() || null, String(b?.instructions ?? '').trim() || null).run();
  return c.json({ ok: true, courier_id: cid, rail });
});
app.get('/admin/pos', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'admin_key_required' }, 403);
  return c.json({ pos: await partnerPosList(c.env.DB) });
});

/* -------- rider live pings + smart pickup routing (nearest-neighbor) ------ */
app.post('/rider/ping', async (c) => {
  const b: any = await c.req.json().catch(() => null);
  const lat = Number(b?.lat), lng = Number(b?.lng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return c.json({ error: 'lat/lng required' }, 400);
  const phone = c.get('phone') ?? (c.get('role') === 'ops' ? (b?.phone ?? null) : null);
  if (!phone) return c.json({ error: 'identity_required' }, 401);
  const status = b?.status ? String(b.status) : null;
  if (status && !['available', 'on_route', 'offline'].includes(status)) {
    return c.json({ error: 'status must be available|on_route|offline' }, 400);
  }
  await c.env.DB.prepare(
    `UPDATE riders SET last_lat = ?2, last_lng = ?3, last_seen_at = datetime('now')
       ${status ? ', status = ?4' : ''} WHERE phone = ?1`,
  ).bind(phone, lat, lng, ...(status ? [status] : [])).run();
  return c.json({ ok: true });
});

/** Greedy nearest-neighbor pickup order for a rider's open jobs today. */
function nearestRoute(
  origin: { lat: number; lng: number },
  stops: { ref: string; address: string; lat: number; lng: number }[],
): { ref: string; address: string; lat: number; lng: number; km_from_previous: number }[] {
  const remaining = [...stops];
  const ordered: { ref: string; address: string; lat: number; lng: number; km_from_previous: number }[] = [];
  let cur = origin;
  while (remaining.length) {
    let best = 0, bestKm = Infinity;
    for (let i = 0; i < remaining.length; i++) {
      const km = haversine(cur.lat, cur.lng, remaining[i].lat, remaining[i].lng);
      if (km < bestKm) { bestKm = km; best = i; }
    }
    const [next] = remaining.splice(best, 1);
    ordered.push({ ...next, km_from_previous: round2(bestKm) });
    cur = { lat: next.lat, lng: next.lng };
  }
  return ordered;
}
app.get('/route/pickup', async (c) => {
  if (!['ops', 'admin'].includes(c.get('role') as string)) return c.json({ error: 'ops or admin role required' }, 403);
  let phone = c.req.query('phone');
  if (phone) { try { phone = normalizeZmPhone(phone); } catch { return c.json({ error: 'bad phone' }, 400); } }
  const q = phone
    ? c.env.DB.prepare(
        // jobs assigned to this rider OR still unassigned, today, still open.
        // (fixed: no phantom rider_phone column + parenthesised OR/AND precedence)
        `SELECT j.ref, j.pickup_address, j.pickup_lat, j.pickup_lng, j.pickup_at, j.round_trip
           FROM jobs j
          WHERE (j.rider_id IS NULL OR j.rider_id IN (SELECT id FROM riders WHERE phone = ?1))
            AND date(j.created_at, '${CAT_OFFSET}') = date('now', '${CAT_OFFSET}')
            AND j.status NOT IN ('delivered','ready_for_collection')
            AND j.pickup_lat IS NOT NULL AND j.pickup_lng IS NOT NULL`,
      ).bind(phone).all()
    : c.env.DB.prepare(
        `SELECT ref, pickup_address, pickup_lat, pickup_lng, pickup_at, round_trip FROM jobs
          WHERE date(created_at, '${CAT_OFFSET}') = date('now', '${CAT_OFFSET}')
            AND status NOT IN ('delivered','ready_for_collection')
            AND pickup_lat IS NOT NULL AND pickup_lng IS NOT NULL`,
      ).all();
  const { results } = await q;
  const hub = { lat: -15.4255, lng: 28.2805 }; // Platinum Chibolya depot anchor
  const rows = (results as any[]);
  // Timed pickups first (earliest slot first), then the ASAP run optimized by
  // nearest-neighbor — so a rider never misses a booked window.
  const timed = rows.filter((r) => r.pickup_at).sort((a, b) => String(a.pickup_at).localeCompare(String(b.pickup_at)));
  const asap = rows.filter((r) => !r.pickup_at);
  return c.json({
    origin: hub,
    timed: timed.map((r) => ({ ...r, km_from_previous: null })),
    asap: nearestRoute(hub, asap.map((r) => ({ ref: r.ref, address: r.pickup_address, lat: r.pickup_lat, lng: r.pickup_lng }))),
    count: rows.length,
  });
});

/* -------- batch pickup scheduling (no zigzag) ----------------------------- */
// Sweep algorithm: bucket scattered stops by latitude bands and walk each band
// east-west / west-east alternately ("snake" rasterisation) — provably minimal
// crossings, the classic non-crossing courier path for a city-wide route.
// Band = ~1.3 km; stop cap 25 per rider.
app.get('/batch/pickup', async (c) => {
  if (!['ops', 'admin'].includes(c.get('role') as string)) {
    return c.json({ error: 'ops or admin role required' }, 403);
  }
  const dateParam = c.req.query('date') ?? new Date().toISOString().slice(0, 10);
  const maxStops = Math.max(1, Math.min(60, Number(c.req.query('max_stops') ?? '25') || 25));
  const bandDeg = Number(c.req.query('band_km') ?? '1.3') / 111; // ~1° ≈ 111km
  const { results } = await c.env.DB.prepare(
    `SELECT ref, pickup_address, pickup_lat, pickup_lng, weight_class, description
       FROM jobs
      WHERE date(created_at, '${CAT_OFFSET}') = ?1
        AND status IN ('created', 'rider_assigned')
        AND pickup_lat IS NOT NULL AND pickup_lng IS NOT NULL`,
  ).bind(dateParam).all();

  const stops = (results as any[]).map((r) => ({
    ref: r.ref, address: r.pickup_address, lat: r.pickup_lat, lng: r.pickup_lng,
    weight: r.weight_class, note: r.description ?? '',
  }));

  const bands = new Map<number, typeof stops>();
  for (const s of stops) {
    const key = Math.floor(s.lat / bandDeg);
    const list = bands.get(key) ?? [];
    list.push(s); bands.set(key, list);
  }
  const orderedAll: typeof stops = [];
  [...bands.keys()].sort((a, b) => a - b).forEach((k, i) => {
    const row = bands.get(k) ?? [];
    row.sort((a, b) => (i % 2 === 0 ? a.lng - b.lng : b.lng - a.lng)); // snake
    orderedAll.push(...row);
  });

  const hub = { lat: -15.4255, lng: 28.2805 };
  const routes: ReturnType<typeof buildRoute>[] = [];
  while (orderedAll.length) routes.push(buildRoute(orderedAll.splice(0, maxStops), hub, routes.length + 1));
  return c.json({
    date: dateParam,
    hub: 'Platinum Chibolya',
    stop_count: stops.length,
    routes,
    algorithm: `snake-latbands band=${bandDeg.toFixed(4)}° cap=${maxStops}`,
  });
});

function buildRoute(stops: { ref: string; address: string; lat: number; lng: number; weight: string; note: string }[], hub: { lat: number; lng: number }, idx: number) {
  let prev = hub, km = 0;
  const out = stops.map((s, i) => {
    const d = haversine(prev.lat, prev.lng, s.lat, s.lng);
    km += d;
    prev = { lat: s.lat, lng: s.lng };
    return {
      seq: i + 1, ref: s.ref, address: s.address, weight: s.weight,
      km_from_prev: round2(d), cum_km: round2(km), note: s.note,
    };
  });
  return {
    route: idx,
    stops: out,
    total_km: round2(km),
    est_minutes: Math.round((km / 22) * 60 + stops.length * 4),
    // quick rider workload hint: split evenly-ish across a 3-rider fleet
    rider_hint: `rider-${((idx - 1) % 3) + 1}`,
  };
}

/* ------------------ smart rider auto-assign + dynamic re-optimization ----- */
// Nearest available rider with free capacity gets the job; ties broken by
// current load (emptiest rider first) so work spreads evenly.
/** Dispatch a job to the nearest verified+available rider and notify BOTH
 *  sides. Sender coords win; when they're missing we fall back to the Lusaka
 *  centre anchor (the city's working assumption) — we NEVER skip dispatch
 *  for lack of coordinates, because bookings made from typed addresses have
 *  none. Returns the assignment or null when no verified rider exists. */
async function dispatchToNearestRider(
  env: Env,
  ref: string,
  collectExcluded?: Array<{ name: string; depot: string }>,
): Promise<{ rider: any; eta_minutes: number; km: number; fallback: boolean; excludedAtDepot: Array<{ name: string; depot: string }> } | null> {
  try {
    const job = await env.DB.prepare(
      'SELECT id, ref, sender_phone, pickup_address, pickup_lat, pickup_lng FROM jobs WHERE ref = ?1').bind(ref).first<any>();
    if (!job) return null;
    const fallback = !(Number.isFinite(Number(job.pickup_lat)) && Number.isFinite(Number(job.pickup_lng)));
    const lat = fallback ? -15.4255 : Number(job.pickup_lat);
    const lng = fallback ? 28.2805 : Number(job.pickup_lng);
    const pick = await nearestAvailableRider(env, lat, lng, collectExcluded);
    if (!pick) return null;
    const etaMin = Math.round((pick.km / 22) * 60 + 4);
    // Idempotency guard (webhook double-fire or stale dispatch): only claim
    // the job when it is STILL unassigned and not delivered/canceled — and
    // only then count it against the rider's load.
    const claim = await env.DB.prepare(
      `UPDATE jobs SET rider_id = ?1, status = 'rider_assigned', assigned_at = datetime('now'), eta_minutes = ?2
        WHERE id = ?3 AND rider_id IS NULL AND status != 'delivered' AND status != 'canceled'`,
    ).bind(pick.rider.id, etaMin, job.id).run();
    if (!claim.meta.changes) return null;
    await env.DB.prepare(
      `UPDATE riders SET current_load = current_load + 1, status = 'on_route', route_updated_at = datetime('now') WHERE id = ?1`,
    ).bind(pick.rider.id).run();
    // Algorithmic assignment is AUDITED (owner directive 2026-11-15: the
    // algorithm picks from available riders — never a default owner). The
    // event also drives the tracking page's "Rider assigned" timeline step.
    await env.DB.prepare(
      `INSERT INTO job_events (job_id, status, note) VALUES (?1, 'rider_assigned', ?2)`,
    ).bind(job.id, `SYSTEM: nearest available rider auto-assigned — ${pick.rider.full_name} (${round2(pick.km)} km away, ETA ~${etaMin} min).`).run();
    await sendToPhone(env, job.sender_phone, {
      title: 'Rider assigned',
      body: `Rider ${pick.rider.full_name} (${pick.rider.vehicle}) is heading to your pickup — track live in Bookings.`,
      data: { job_ref: job.ref, kind: 'rider_assigned' },
    });
    await sendToPhone(env, pick.rider.phone, {
      title: 'New delivery assigned',
      body: `Job ${job.ref} — pickup at ${job?.pickup_address ?? 'sender address'}. Open the Team tab for details.`,
      data: { job_ref: job.ref, kind: 'rider_assigned' },
    });
    return { rider: pick.rider, eta_minutes: etaMin, km: pick.km, fallback, excludedAtDepot: collectExcluded ?? [] };
  } catch {
    return null;
  }
}

/**
 * Riders currently at a depot (first-mile leg done, parcel lodged, waiting to
 * advance to 'collected'/'delivered') are NOT assignable — they're physically
 * at the courier counter/depot unloading lodgement paperwork. Returned as a
 * map of rider_id -> depot name so callers can explain a refusal honestly
 * instead of a bare "no riders".
 */
async function ridersAtDepot(env: Env): Promise<Map<number, string>> {
  try {
    const { results } = await env.DB.prepare(
      `SELECT DISTINCT j.rider_id AS id, c.depot_name AS depot
         FROM jobs j JOIN couriers c ON c.id = j.courier_id
        WHERE j.status = 'at_depot' AND j.rider_id IS NOT NULL`,
    ).all<any>();
    const m = new Map<number, string>();
    for (const r of (results ?? []) as any[]) {
      const id = Number(r.id);
      if (Number.isFinite(id) && !m.has(id)) m.set(id, String(r.depot ?? 'the depot'));
    }
    return m;
  } catch {
    return new Map();
  }
}

async function nearestAvailableRider(
  env: Env,
  lat: number,
  lng: number,
  collectExcluded?: Array<{ name: string; depot: string }>,
): Promise<{ rider: any; km: number } | null> {
  const atDepot = await ridersAtDepot(env);
  const riders = await env.DB.prepare(
    `SELECT id, phone, full_name, vehicle, last_lat, last_lng, last_seen_at, status, active, capacity, current_load, photo_url
       FROM riders WHERE active = 1 AND status IN ('available', 'on_route')
         AND verification_status = 'verified'
         AND last_seen_at > datetime('now', '-15 minutes')`
  ).all<any>();
  // Freshness tiers (owner directive: algorithm picks riders actually available
  // NOW — never a rider coasting on a stale CBD default):
  //   tier 0: pinged in <= 10 minutes — scored by true distance
  //   tier 1: pinged in <= 60 minutes — +12-50 km penalty (stale-but-verified
  //           riders still surface when nothing fresher exists)
  //   tier 2: never pinged / null GPS — +40 km penalty (dispatchable last)
  const nowMs = Date.now();
  const freshnessPenalty = (seenAt: string | null): number => {
    if (!seenAt) return 40;
    const mins = (nowMs - Date.parse(String(seenAt).replace(' ', 'T') + 'Z')) / 60_000;
    if (!Number.isFinite(mins)) return 40;
    if (mins <= 10) return 0;
    if (mins <= 60) return Math.min(50, 12 + ((mins - 10) / 50) * 38);
    return 60;
  };
  let best: { rider: any; km: number } | null = null;
  let bestScore = Infinity;
  for (const r of (riders.results ?? [])) {
    const riderId = Number(r.id);
    if (atDepot.has(riderId)) {
      if (collectExcluded) collectExcluded.push({ name: String(r.full_name ?? 'A rider'), depot: atDepot.get(riderId)! });
      continue;
    }
    const load = Number(r.current_load ?? 0), cap = Number(r.capacity ?? 8);
    if (load >= cap) continue;
    const penalty = freshnessPenalty(r.last_seen_at);
    const km = haversine(lat, lng, Number(r.last_lat ?? -15.4255), Number(r.last_lng ?? 28.2805));
    const score = km + penalty + load * 0.5; // near, then fresh, then emptier
    if (!best || score < bestScore) { best = { rider: r, km }; bestScore = score; }
  }
  return best;
}

app.post('/jobs/:ref/auto-assign', async (c) => {
  if (!['ops', 'admin'].includes(c.get('role') as string)) return c.json({ error: 'ops or admin required' }, 403);
  const ref = c.req.param('ref');
  const job = await c.env.DB.prepare(
    `SELECT j.*, c.lat AS depot_lat, c.lng AS depot_lng FROM jobs j
      LEFT JOIN couriers c ON c.id = j.courier_id WHERE j.ref = ?1`,
  ).bind(ref).first<any>();
  if (!job) return c.json({ error: 'not found' }, 404);
  if (job.rider_id) return c.json({ error: 'already assigned', rider_id: job.rider_id }, 409);
  // Payment-held parcels never get a rider — not even via ops (owner directive).
  if (await jobPaymentHeld(c.env.DB, job.id)) {
    return c.json({ error: 'payment_required', hint: 'Prepayment pending — assignment unlocks once payment is approved.' }, 402);
  }
  const excludedDepot: Array<{ name: string; depot: string }> = [];
  const result = await dispatchToNearestRider(c.env, ref, excludedDepot);
  if (!result) {
    if (excludedDepot.length > 0) {
      const names = [...new Set(excludedDepot.map((d) => d.depot))].join(' / ');
      return c.json({
        error: 'rider_at_depot',
        hint: `Rider(s) busy at ${names} — the system auto-assigns the moment a depot job closes.`,
        excluded_at_depot: excludedDepot,
      }, 404);
    }
    return c.json({ error: 'no verified rider available right now' }, 404);
  }
  const pick = result.rider;
  const etaMin = result.eta_minutes;
  const km = result.km;
  return c.json({ ok: true, ref, rider_id: pick.id, rider: pick.full_name, photo_url: pick.photo_url ?? null, eta_minutes: etaMin, km: round2(km) });
});

// Re-optimize ONE rider's route from their live location, optionally inserting
// a brand-new stop at the cheapest position (mid-route top-up). Returns the
// ordered stop list with ETAs so the rider's app can redraw the map.
app.post('/batch/reoptimize', async (c) => {
  if (!['ops', 'admin'].includes(c.get('role') as string)) return c.json({ error: 'ops or admin required' }, 403);
  const b: any = await c.req.json().catch(() => null);
  const phone = b?.rider_phone ? normalizeZmPhone(b.rider_phone) : null;
  if (!phone) return c.json({ error: 'rider_phone required' }, 400);
  const rider = await c.env.DB.prepare(
    `SELECT id, full_name, last_lat, last_lng, capacity, current_load FROM riders WHERE phone = ?1 AND active = 1`,
  ).bind(phone).first<any>();
  if (!rider) return c.json({ error: 'rider not found' }, 404);
  const origin = { lat: Number(rider.last_lat ?? -15.4255), lng: Number(rider.last_lng ?? 28.2805) };
  const stops: { ref: string; address: string; lat: number; lng: number; weight?: string; note?: string }[] = [];
  const rows = await c.env.DB.prepare(
    `SELECT ref, pickup_address, pickup_lat, pickup_lng, weight_class, description FROM jobs
       WHERE rider_id = ?1 AND status IN ('created', 'rider_assigned', 'picked_up')
         AND pickup_lat IS NOT NULL AND pickup_lng IS NOT NULL`,
  ).bind(rider.id).all<any>();
  for (const r of (rows.results ?? [])) stops.push({ ref: r.ref, address: r.pickup_address, lat: r.pickup_lat, lng: r.pickup_lng, weight: r.weight_class, note: r.description ?? '' });
  // optional new stop inserted at the cheapest position (mid-route top-up)
  if (b?.new_stop && Number.isFinite(b.new_stop.lat) && Number.isFinite(b.new_stop.lng)) {
    const ns = { ref: b.new_stop.ref ?? 'new', address: b.new_stop.address ?? '', lat: b.new_stop.lat, lng: b.new_stop.lng, weight: b.new_stop.weight, note: b.new_stop.note ?? '' };
    if (stops.length === 0) stops.push(ns);
    else {
      let bestIdx = 0, bestExtra = Infinity;
      let prev = origin;
      for (let i = 0; i <= stops.length; i++) {
        const next = i < stops.length ? stops[i] : null;
        const a = haversine(prev.lat, prev.lng, ns.lat, ns.lng);
        const bDist = next ? haversine(ns.lat, ns.lng, next.lat, next.lng) : 0;
        const direct = next ? haversine(prev.lat, prev.lng, next.lat, next.lng) : 0;
        const extra = a + bDist - direct;
        if (extra < bestExtra) { bestExtra = extra; bestIdx = i; }
        if (next) prev = { lat: next.lat, lng: next.lng };
      }
      stops.splice(bestIdx, 0, ns);
    }
  }
  const ordered = nearestRoute(origin, stops);
  let elapsedKm = 0;
  const etaStops = ordered.map((s) => {
    const d = haversine(origin.lat, origin.lng, s.lat, s.lng); // approx cum from rider pos
    elapsedKm = d; // nearestRoute already gives km_from_prev; recompute cum simply
    return { ...s, est_minutes_from_now: Math.round((elapsedKm / 22) * 60 + stops.indexOf(s) * 4) };
  });
  await c.env.DB.prepare(
    `UPDATE riders SET route_json = ?2, route_updated_at = datetime('now') WHERE id = ?1`,
  ).bind(rider.id, JSON.stringify(etaStops)).run();
  return c.json({ rider: rider.full_name, origin, stops: etaStops, total_stops: etaStops.length, algorithm: 'nearest-neighbor + cheapest-insert' });
});

// Rider's current optimized route (JWT-authenticated rider phone).
app.get('/rider/route', async (c) => {
  const phone = c.get('phone');
  if (!phone) return c.json({ error: 'identity_required' }, 401);
  const rider = await c.env.DB.prepare(
    `SELECT id, full_name, last_lat, last_lng, route_json, route_updated_at, capacity, current_load FROM riders WHERE phone = ?1 AND active = 1`,
  ).bind(phone).first<any>();
  if (!rider) return c.json({ error: 'rider not found' }, 404);
  const route = rider.route_json ? JSON.parse(rider.route_json) : null;
  const jobs = await c.env.DB.prepare(
    `SELECT ref, pickup_address, status, eta_minutes FROM jobs WHERE rider_id = ?1 AND status NOT IN ('delivered','ready_for_collection') ORDER BY assigned_at`,
  ).bind(rider.id).all<any>();
  return c.json({ rider: rider.full_name, load: `${rider.current_load}/${rider.capacity}`, last_seen_at: rider.route_updated_at, route, jobs: jobs.results ?? [] });
});
/* --------------------- rider task queue (slot batches) -------------------- */
// The rider's day, grouped into sweep windows like a task queue: stop order,
// ETA chain, parcel totals, majority destination branch, target drop-off time.
const SWEEP_SLOTS: Record<string, { label: string; cutoff: string; start: string; target: string; range: string }> = {
  '06:00': { label: '06:00—07:30 slot', cutoff: '05:30', start: '06:00', target: '08:30', range: '6:00—7:30 AM' },
  '10:00': { label: '10:00—11:30 slot', cutoff: '09:30', start: '10:00', target: '12:30', range: '10:00—11:30 AM' },
  '14:00': { label: '14:00—15:30 slot', cutoff: '13:30', start: '14:00', target: '16:30', range: '2:00—3:30 PM' },
};

function catHM(offsetMinutes = 0): string {
  const d = new Date(Date.now() + 2 * 3600_000 + offsetMinutes * 60_000);
  return `${String(d.getUTCHours()).padStart(2, '0')}:${String(d.getUTCMinutes()).padStart(2, '0')}`;
}

function minutesOf(hm: string): number {
  const [h, m] = hm.split(':').map(Number);
  return h * 60 + m;
}

function hmOf(minutes: number): string {
  const m = ((minutes % 1440) + 1440) % 1440;
  return `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;
}

// Daily live stats for the rider's task-queue card (owner 2026-11-18): the
// rider's day runs on CAT (UTC+2), so jobs bucket by the CAT calendar day of
// their scheduled sweep (pickup_at, falling back to created_at). Canceled
// jobs never count; earnings are the rider fees on legs already done.
app.get('/rider/stats', async (c) => {
  let phone = c.get('phone') ?? '';
  if (c.get('role') === 'ops') {
    try { phone = normalizeZmPhone(c.req.query('phone') ?? (phone || '')); }
    catch { return c.json({ error: 'invalid_phone' }, 400); }
  }
  if (!phone) return c.json({ error: 'identity_required' }, 401);
  const rider = await c.env.DB.prepare(
    'SELECT id FROM riders WHERE phone = ?1 AND active = 1',
  ).bind(phone).first<any>();
  if (!rider) return c.json({ error: 'rider not found' }, 404);
  const row = await c.env.DB.prepare(
    `SELECT COUNT(*) AS total,
            COALESCE(SUM(CASE WHEN status = 'rider_assigned' THEN 1 ELSE 0 END), 0) AS waiting,
            COALESCE(SUM(CASE WHEN status IN ('picked_up','at_depot','departed','arrived') THEN 1 ELSE 0 END), 0) AS picked,
            COALESCE(SUM(CASE WHEN status IN ('delivered','ready_for_collection') THEN 1 ELSE 0 END), 0) AS delivered,
            COALESCE(SUM(parcels), 0) AS parcels,
            COALESCE(SUM(CASE WHEN status IN ('delivered','ready_for_collection') THEN rider_fee_zmw ELSE 0 END), 0) AS earned_zmw
       FROM jobs
      WHERE rider_id = ?1
        AND COALESCE(status,'') NOT IN ('canceled','cancelled','deleted')
        AND (
          date(COALESCE(pickup_at, created_at), '+2 hours') = date('now', '+2 hours')
          OR EXISTS (SELECT 1 FROM job_events e WHERE e.job_id = j.id
            AND e.status IN ('rider_assigned','picked_up','at_depot','departed','arrived','delivered','ready_for_collection','counter_receipt_submitted','pickup_photos_filed')
            AND date(e.created_at, '+2 hours') = date('now', '+2 hours'))
        )`,
  ).bind(rider.id).first<any>();
  return c.json({ stats: row ?? {} });
});

app.get('/rider/queue', async (c) => {
  let phone = c.get('phone') ?? '';
  if (c.get('role') === 'ops') {
    try { phone = normalizeZmPhone(c.req.query('phone') ?? (phone || '')); }
    catch { return c.json({ error: 'invalid_phone' }, 400); }
  }
  if (!phone) return c.json({ error: 'identity_required' }, 401);
  const rider = await c.env.DB.prepare(
    'SELECT id, full_name, last_lat, last_lng FROM riders WHERE phone = ?1 AND active = 1',
  ).bind(phone).first<any>();
  if (!rider) return c.json({ error: 'rider not found' }, 404);

  const { results } = await c.env.DB.prepare(
    `SELECT j.ref, j.pickup_address, j.pickup_lat, j.pickup_lng, j.parcels, j.status, j.last_mile,
            j.sender_name, j.sender_phone, j.description, j.recipient_name, j.recipient_phone,
            j.eta_minutes, j.pickup_window, j.created_at, j.from_city,
            co.name AS courier_name, co.depot_name, co.city AS courier_city,
            co.lat AS courier_lat, co.lng AS courier_lng,
            cb.lat AS branch_lat, cb.lng AS branch_lng
       FROM jobs j JOIN couriers co ON co.id = j.courier_id
        LEFT JOIN courier_branches cb ON cb.courier_id = co.id AND cb.name = j.branch AND cb.active = 1
      WHERE j.rider_id = ?1 AND j.status NOT IN ('delivered', 'ready_for_collection', 'canceled', 'cancelled', 'deleted')
      ORDER BY j.created_at`,
  ).bind(rider.id).all<any>();

  // NO INSTANT PICK-UPS (owner directive 2026-11-17): every job rides a TIMED
  // sweep (06:00 / 10:00 / 14:00 CAT). A job whose window is missing or
  // unknown rolls into the next slot whose cutoff has not passed; after the
  // last cutoff it rolls to TOMORROW's 06:00 slot. The old "instant" bucket
  // (ASAP stops with made-up ETAs) is gone.
  const TOMORROW_SLOT = 'tomorrow-06:00';
  const buckets: Record<string, any[]> = { '06:00': [], '10:00': [], '14:00': [], [TOMORROW_SLOT]: [] };
  const nowCatMin = minutesOf(catHM());
  // CAT date of "now" (UTC+2) — compared against each job's pickup_at date so
  // a TOMORROW-6am booking shows in the TOMORROW 06:00 card instead of
  // today's 06:00 sweep (owner bug 2026-11-17: "the 6am is not showing").
  const todayCatDate = new Date(Date.now() + 2 * 3600_000).toISOString().slice(0, 10);
  for (const job of results) {
    let w: string;
    if (SWEEP_SLOTS[job.pickup_window]) {
      const pickupDay = job.pickup_at ? String(job.pickup_at).slice(0, 10) : null;
      w = pickupDay && pickupDay > todayCatDate ? TOMORROW_SLOT : job.pickup_window;
    } else {
      w = nowCatMin < minutesOf(SWEEP_SLOTS['06:00'].cutoff) ? '06:00'
        : nowCatMin < minutesOf(SWEEP_SLOTS['10:00'].cutoff) ? '10:00'
        : nowCatMin < minutesOf(SWEEP_SLOTS['14:00'].cutoff) ? '14:00'
        : TOMORROW_SLOT;
    }
    buckets[w].push(job);
  }

  const depot = { lat: -15.4255, lng: 28.2805 };
  // ONE CARD PER SLOT (owner 2026-11-19: depot grouping produced duplicate
  // 06:00 cards). Each stop still carries its depot name; the app groups
  // visually without splitting the slot.
  const batches = Object.entries(buckets)
    .filter(([, jobs]) => jobs.length > 0)
    .map(([slot, jobs]) => {
      // Slot metadata (the TOMORROW roll-up reuses the 06:00 timings).
      const meta = slot === TOMORROW_SLOT ? SWEEP_SLOTS['06:00'] : SWEEP_SLOTS[slot];
      const slotLabel = slot === TOMORROW_SLOT ? 'TOMORROW 06:00—07:30 SLOT' : meta.label;
      // Nearest-neighbour stop chain from the rider's last known position.
      let curLat = Number(rider.last_lat ?? depot.lat);
      let curLng = Number(rider.last_lng ?? depot.lng);
      const remaining = [...jobs];
      const stops: any[] = [];
      // LIVE CHAIN (owner directive 2026-11-17): the chain ticks with the
      // clock — it starts at max(slot start, now CAT), so times recompute
      // from reality on every refresh instead of showing a stale plan.
      const clockMin = slot === TOMORROW_SLOT
        ? minutesOf(meta.start) // tomorrow's slot has not started yet
        : Math.max(minutesOf(meta.start), nowCatMin);
      let chainMin = clockMin; // mutable running clock for the ETA chain
      const slotStartMin = minutesOf(meta.start);
      while (remaining.length) {
        let bestIdx = 0;
        let bestKm = Infinity;
        for (let i = 0; i < remaining.length; i++) {
          const lat = Number(remaining[i].pickup_lat ?? 0);
          const lng = Number(remaining[i].pickup_lng ?? 0);
          const km = lat && lng ? haversine(curLat, curLng, lat, lng) : 2; // no coords -> ~2km guess
          if (km < bestKm) { bestKm = km; bestIdx = i; }
        }
        const job = remaining.splice(bestIdx, 1)[0];
        chainMin += Math.max(5, Math.round((bestKm / 22) * 60 + 4)); // 22 km/h + 4 min stop
        stops.push({
          n: stops.length + 1,
          time: hmOf(chainMin),
          ref: job.ref,
          address: job.pickup_address,
          // Coordinates let the app offer one-tap in-app navigation per stop;
          // null for typed addresses without a pin (the app then navigates
          // by address text).
          lat: job.pickup_lat ?? null,
          lng: job.pickup_lng ?? null,
          // Depot drop coordinates for the "navigate to depot" leg after the
          // pickup is done — the matched branch first, else the courier's own
          // depot pin, so the leg almost always opens the in-app navigator
          // instead of falling through to address geocoding (owner bug
          // 2026-11-18: "keeps toasting Finding… but never navigates").
          depot_lat: job.branch_lat ?? job.courier_lat ?? null,
          depot_lng: job.branch_lng ?? job.courier_lng ?? null,
          from_city: job.from_city ?? '',
          seller: job.sender_name,
          seller_phone: job.sender_phone ?? '',
          // Parcel content names the pickup/collection sheet ("PICKUP-BOOKS-…"),
          // and the recipient contact names who holds the door code.
          description: job.description ?? '',
          recipient: job.recipient_name ?? '',
          recipient_phone: job.recipient_phone ?? '',
          parcels: Number(job.parcels ?? 1),
          status: job.status,
          last_mile: Number(job.last_mile ?? 0),
          courier: job.courier_name,
          // The DEPOT name itself ("Platinum", "Icypeed") — the depot-leg
          // button and navigator label read this, not a generic "depot".
          depot: job.depot_name ?? job.courier_name,
        });
        curLat = Number(job.pickup_lat ?? curLat);
        curLng = Number(job.pickup_lng ?? curLng);
      }
      // Majority destination branch across the batch.
      const counts = new Map<string, { name: string; branch: string; city: string; n: number }>();
      for (const j of jobs) {
        const key = `${j.courier_name}|${j.depot_name}`;
        const e = counts.get(key) ?? { name: j.courier_name, branch: j.depot_name, city: j.courier_city, n: 0 };
        e.n++;
        counts.set(key, e);
      }
      const dest = [...counts.values()].sort((a, b) => b.n - a.n)[0];
      const totalParcels = jobs.reduce((s, j) => s + Number(j.parcels ?? 1), 0);
      return {
        slot,
        label: slotLabel,
        cutoff: SWEEP_SLOTS[slot]?.cutoff ?? null,
        // The full CAT window shown on the slot card footer (owner audit
        // 2026-11-17: the footer range was ambiguous).
        range: slot === TOMORROW_SLOT ? 'Tomorrow 6:00—7:30 AM' : meta.range,
        total_parcels: totalParcels,
        total_stops: jobs.length,
        destination: dest ? { courier: dest.name, branch: dest.branch, city: dest.city } : null,
        target_dropoff: meta.target,
        minutes_on_road: chainMin - slotStartMin,
        stops,
      };
    });

  return c.json({
    rider: rider.full_name,
    generated_at: catHM(),
    batches,
  });
});

const REF_REWARD_PCT = 20;  // referrer gets a single-use promo for their own next leg
const REF_SHARE_PREFIX = 'DRP';

function randomCode(len: number): string {
  const abc = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  let s = '';
  for (let i = 0; i < len; i++) s += abc[Math.floor(Math.random() * abc.length)];
  return s;
}

/** Return the user's share code, generating + persisting it on first use. */
async function ensureReferralCode(db: D1Database, phone: string): Promise<string> {
  const existing = await db.prepare('SELECT referral_code FROM auth_users WHERE phone = ?1').bind(phone).first<any>();
  if (existing?.referral_code) return existing.referral_code as string;
  for (let i = 0; i < 6; i++) {
    const code = `${REF_SHARE_PREFIX}-${randomCode(5)}`;
    const taken = await db.prepare('SELECT phone FROM auth_users WHERE referral_code = ?1').bind(code).first<any>();
    if (taken) continue;
    await db.prepare('UPDATE auth_users SET referral_code = ?2 WHERE phone = ?1').bind(phone, code).run();
    return code;
  }
  const fallback = `${REF_SHARE_PREFIX}-${randomCode(6)}`;
  await db.prepare('UPDATE auth_users SET referral_code = ?2 WHERE phone = ?1').bind(phone, fallback).run();
  return fallback;
}

app.get('/refer/code', async (c) => {
  const phone = c.get('phone');
  if (!phone) return c.json({ error: 'identity_required' }, 401);
  const code = await ensureReferralCode(c.env.DB, phone);
  const stats = await c.env.DB.prepare(
    `SELECT SUM(CASE WHEN status='pending' THEN 1 ELSE 0 END) AS pending,
            SUM(CASE WHEN status='rewarded' THEN 1 ELSE 0 END) AS rewarded,
            COUNT(*) AS total
       FROM referrals WHERE referrer_phone = ?1`,
  ).bind(phone).first<any>();
  return c.json({
    code,
    share_text: `Join me on DropOff — senders get home pickup to their courier. Use my link: https://api.carpsosolutions.store/r/${code}`,
    stats: { pending: stats?.pending ?? 0, rewarded: stats?.rewarded ?? 0, total: stats?.total ?? 0 },
  });
});

app.post('/refer/claim', async (c) => {
  const b: any = await c.req.json().catch(() => null);
  const code = String(b?.code ?? '').trim().toUpperCase();
  if (!code) return c.json({ error: 'missing code' }, 400);
  const phone = c.get('phone');
  if (!phone) return c.json({ error: 'identity_required' }, 401);
  const referrer = await c.env.DB.prepare('SELECT phone FROM auth_users WHERE referral_code = ?1').bind(code).first<any>();
  if (!referrer) return c.json({ error: 'referral_code_not_found' }, 404);
  if (referrer.phone === phone) return c.json({ error: 'cannot_refer_yourself' }, 400);
  const out = await c.env.DB.prepare(
    'INSERT OR IGNORE INTO referrals (referrer_phone, referred_phone) VALUES (?1, ?2)',
  ).bind(referrer.phone, phone).run();
  return c.json({ ok: true, tracked: (out.meta.changes ?? 0) > 0, referrer: referrer.phone });
});

/* -------- admin reporting of the referral funnel ------------------------- */
app.get('/admin/referrals', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'admin_key_required' }, 403);
  const { results } = await c.env.DB.prepare(
    `SELECT referrer_phone, referred_phone, status, reward_code, created_at, rewarded_at
       FROM referrals ORDER BY id DESC LIMIT 200`,
  ).all();
  const agg = await c.env.DB.prepare(
    `SELECT SUM(CASE WHEN status='pending' THEN 1 ELSE 0 END) AS pending,
            SUM(CASE WHEN status='rewarded' THEN 1 ELSE 0 END) AS rewarded,
            COUNT(*) AS total FROM referrals`,
  ).first<any>();
  return c.json({ total: agg?.total ?? 0, pending: agg?.pending ?? 0, rewarded: agg?.rewarded ?? 0, recent: results });
});

/* -------- recurring parcel plans (standing orders) ------------------------- */
// Sellers pre-register repetitive drops ("every Tuesday to Ndola"); the app one-taps
// them into a booking so the rider arrives with the route already loaded.
app.post('/recurring', async (c) => {
  const b: any = await c.req.json().catch(() => null);
  if (!b) return c.json({ error: 'invalid JSON body' }, 400);
  const role = c.get('role');
  const phone = role === 'ops'
    ? normalizeZmPhone(String(b.phone ?? ''))
    : normalizeZmPhone(c.get('phone') ?? String(b.phone ?? ''));
  if (!phone) return c.json({ error: 'missing phone' }, 401);
  const dest = String(b.dest_city ?? '').trim();
  if (!dest) return c.json({ error: 'dest_city required' }, 400);
  const freq = String(b.frequency ?? 'weekly');
  if (!['weekly', 'biweekly', 'monthly'].includes(freq)) {
    return c.json({ error: 'frequency must be weekly | biweekly | monthly' }, 400);
  }
  const wc = String(b.weight_class ?? '0-5kg');
  if (!['0-5kg', '5-15kg', '15kg+'].includes(wc)) return c.json({ error: 'bad weight_class' }, 400);
  // optional wiring for the cron materialiser: courier + origin route (NULL = create
  // from the app UI manually; the standing order stays a template)
  const courierId = b.courier_id == null ? null : Math.round(Number(b.courier_id) || 0) || null;
  const fromCity = b.from_city ? String(b.from_city).trim().slice(0, 40) : 'Lusaka';
  const { meta } = await c.env.DB.prepare(
    `INSERT INTO recurring_plans (phone, dest_city, weight_class, recipient_name, recipient_phone,
       description, pickup_address, frequency, weekday, courier_id, from_city)
     VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11)`,
  ).bind(
    phone, dest, wc, b.recipient_name ?? null, b.recipient_phone ?? null,
    b.description ?? null, b.pickup_address ?? null, freq,
    b.weekday == null ? null : Math.min(7, Math.max(1, Math.round(Number(b.weekday)))),
    courierId, fromCity,
  ).run();
  return c.json({ ok: true, id: meta.last_row_id }, 201);
});

app.get('/recurring', async (c) => {
  const role = c.get('role');
  const q = c.req.query('phone');
  const phone = role === 'ops' && q ? normalizeZmPhone(q) : c.get('phone')!;
  if (!phone) return c.json({ error: 'missing phone' }, 401);
  const { results } = await c.env.DB.prepare(
    'SELECT * FROM recurring_plans WHERE phone = ?1 ORDER BY id DESC',
  ).bind(phone).all();
  return c.json({ recurring: results });
});

app.post('/recurring/:id/toggle', async (c) => {
  const id = Number(c.req.param('id'));
  if (!id) return c.json({ error: 'bad id' }, 400);
  const role = c.get('role');
  const plan = await c.env.DB.prepare('SELECT * FROM recurring_plans WHERE id = ?1').bind(id).first() as any;
  if (!plan) return c.json({ error: 'not found' }, 404);
  if (role !== 'ops' && c.get('phone') !== plan.phone) return c.json({ error: 'forbidden' }, 403);
  await c.env.DB.prepare('UPDATE recurring_plans SET active = CASE active WHEN 1 THEN 0 ELSE 1 END WHERE id = ?1').bind(id).run();
  const updated = await c.env.DB.prepare('SELECT active FROM recurring_plans WHERE id = ?1').bind(id).first() as any;
  return c.json({ ok: true, id, active: updated.active });
});

const deleteRecurringPlan = async (c: any) => {
  const id = Number(c.req.param('id'));
  const role = c.get('role');
  const plan = await c.env.DB.prepare('SELECT phone FROM recurring_plans WHERE id = ?1').bind(id).first() as any;
  if (!plan) return c.json({ error: 'not found' }, 404);
  if (role !== 'ops' && c.get('phone') !== plan.phone) return c.json({ error: 'forbidden' }, 403);
  await c.env.DB.prepare('DELETE FROM recurring_plans WHERE id = ?1').bind(id).run();
  return c.json({ ok: true });
};
app.delete('/recurring/:id', deleteRecurringPlan);
app.post('/recurring/:id/delete', deleteRecurringPlan); // client-friendly alias

// pickup route is available to ops/admin JWT roles too; no new role needed.

/* ---------------------------- web console pages ---------------------------- */
// GET /console?key=… (superadmin HTML dashboard) + GET /partner/console (partner
// panel; the page speaks JSON to /partner/* with the login token it asks for).
const CONSOLE_CSS = `body{font-family:-apple-system,Segoe UI,Roboto,sans-serif;max-width:860px;margin:24px auto;padding:0 16px;color:#10312a}
h1{font-size:20px} table{border-collapse:collapse;width:100%;margin:12px 0} td,th{padding:6px 10px;border-bottom:1px solid #dde6e2;text-align:left;font-size:14px}
th{background:#eef4f1} .kpi{display:inline-block;background:#eef4f1;border-radius:10px;padding:10px 16px;margin:4px 8px 4px 0;font-size:13px}
.kpi b{display:block;font-size:20px} input,button,select{padding:8px;border-radius:8px;border:1px solid #cfd8d4;font-size:14px}
button{background:#17855f;color:#fff;border:0;font-weight:700}
.toggle.on{background:#17855f;color:#fff} .toggle.off{background:#c0392b;color:#fff}`;

/** Superadmin console — open as https://<worker>/console#key=<ADMIN_AUTH_KEY>
 *  The FRAGMENT form is preferred: fragments never reach the server, so the
 *  key stays out of access logs, Referer headers and browser history.
 *  A legacy ?key= is validated server-side — wrong key 403s, right key is
 *  bounced to the #key= form so it never lingers in a query string. */
app.get('/console', (c) => {
  const qKey = c.req.query('key');
  if (qKey !== undefined) {
    if (qKey !== c.env.ADMIN_AUTH_KEY) {
      return c.html(`<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><title>Denied</title>
<body style="font-family:sans-serif;color:#10312a;padding:40px"><h1>403 — wrong admin key</h1>
<p>Open <code>/console#key=YOUR_KEY</code> instead (the fragment never leaves your browser).</p></body>`, 403);
    }
    return c.redirect(`/console#key=${encodeURIComponent(qKey)}`);
  }
  return c.html(`<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="referrer" content="no-referrer">
<title>DropOff — Admin</title><style>${CONSOLE_CSS}</style></head><body>
<h1>DropOff — superadmin console</h1>
<div id="kpis">Loading…</div>
<table id="tbl"><thead><tr><th>KPI</th><th>Last 30 days</th></tr></thead><tbody></tbody></table>
<h2>Partner shops</h2>
<p>Add email + courier id → the partner logs in with that email and confirms prices/rides.</p>
<input id="pEmail" placeholder="partner@shop.co.zm"><input id="pCourier" type="number" placeholder="courier id">
<button onclick="makePartner()">Promote to partner</button><span id="pMsg"></span>

<h2>Plans (seller packs — full edit + on/off)</h2>
<p>Every field is live. A toggled-off plan disappears from sales and listings instantly; existing subscribers keep their cycle benefit.</p>
<table id="tiersTbl"><thead><tr><th>tier</th><th>on/off</th><th>fee K</th><th>parcels/day</th><th>parcels/mo</th><th>overage %</th><th>cycle days</th><th>rider fee</th><th>tag</th></tr></thead><tbody></tbody></table>
<div>
<select id="tTier"><option>rider_daily</option><option>weekly</option><option>silver</option><option>gold</option><option>platinum</option></select>
<input id="tFee" type="number" placeholder="fee ZMW" step="1">
<input id="tPpd" type="number" placeholder="parcels/day" step="1">
<input id="tPpm" type="number" placeholder="parcels/month" step="1">
<input id="tRider" type="number" placeholder="rider fee (0 = bundled)" step="1">
<input id="tDisc" type="number" placeholder="overage discount %" step="1">
<input id="tDays" type="number" placeholder="cycle days" step="1">
<input id="tTag" placeholder="tag e.g. Most popular / PROMO">
<label style="font-size:12px"><input type="checkbox" id="tActive" checked> plan active</label>
<button onclick="saveTier()">Save plan</button><span id="tMsg"></span>
</div>
<h2>Couriers — on/off (sellers never see an off courier)</h2>
<table id="couriersTbl"><thead><tr><th>id</th><th>name</th><th>city</th><th>depot</th><th>on/off</th></tr></thead><tbody></tbody></table>

<h2>Promo codes (sellers)</h2>
<table id="promosTbl"><thead><tr><th>code</th><th>% off</th><th>uses left</th><th>expires</th><th>applies</th><th>note</th></tr></thead><tbody></tbody></table>
<div>
<input id="prCode" placeholder="CODE e.g. FIRSTM10" style="text-transform:uppercase">
<input id="prPct" type="number" placeholder="% off leg" step="0.5">
<input id="prUses" type="number" placeholder="max uses (blank = unlimited)">
<input id="prExp" type="date">
<input id="prTier" placeholder="applies to tier (blank = any)">
<input id="prNote" placeholder="note">
<button onclick="savePromo()">Save promo</button><span id="prMsg"></span>
</div>

<h2>Partner collection rails (their POS — never our money)</h2>
<p>Set how the customer pays the courier directly at the counter/depot. Shown on the courier page.</p>
<table id="posTbl"><thead><tr><th>courier id</th><th>rail</th><th>merchant</th><th>instructions</th></tr></thead><tbody></tbody></table>
<div>
<input id="posCourier" type="number" placeholder="courier id">
<select id="posRail"><option>momo</option><option>bank</option><option>pos_terminal</option><option>whatsapp</option><option>cash</option></select>
<input id="posMerchant" placeholder="merchant/till/momo number">
<input id="posInstructions" placeholder="e.g. Send K110 to 096… ref=waybill" size="46">
<button onclick="savePos()">Save POS</button><span id="posMsg"></span>
</div>
<script>
// Key comes from the URL fragment (#key=—, never sent to the server) with a
// one-shot ?key= fallback; scrubbed from history either way.
const key = new URLSearchParams(location.hash.slice(1)).get('key')
  || new URLSearchParams(location.search).get('key') || '';
if (key) history.replaceState(null, '', location.pathname);
const H = { 'X-Admin-Key': key };
fetch('/admin/stats', { headers: H }).then(r => r.json()).then(s => {
  document.getElementById('kpis').innerHTML = [
    ['active plan sellers', s.paying_sellers_active],
    ['paygo regulars (3+/mo)', s.paygo_regulars],
    ['parcels (30d)', s.parcels_last_30d],
    ['platform fees (30d)', 'K' + (s.platform_fees_last_30d ?? 0).toFixed(2)],
    ['Lipila fees (30d)', 'K' + (s.lipila_fees_last_30d ?? 0).toFixed(2)],
    ['ride float held', 'K' + (s.wallet_float_total ?? 0).toFixed(2)],
    ['referrals pending', s.referrals_pending ?? 0],
    ['referrals rewarded', s.referrals_rewarded ?? 0],
  ].map(([label, v]) => '<span class="kpi"><b>' + esc(v) + '</b>' + label + '</span>').join('');
  const tb = document.querySelector('#tbl tbody'); tb.innerHTML = '';
  for (const [k, v] of Object.entries(s)) if (!(v instanceof Object)) {
    tb.insertAdjacentHTML('beforeend', '<tr><td>' + esc(k) + '</td><td>' + esc(v) + '</td></tr>');
  }
  const tiers = s.subs_by_tier ?? [];
  for (const t of tiers) tb.insertAdjacentHTML('beforeend', '<tr><td>pack: ' + esc(t.tier) + '</td><td>' + esc(t.n) + ' active</td></tr>');
}).catch(() => document.getElementById('kpis').textContent = 'Admin key wrong — open /console#key=YOUR_KEY');
// note: esc() is defined further down — hoisted function, safe here
async function makePartner() {
  const r = await fetch('/admin/partners', { method: 'POST', headers: { ...H, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: document.getElementById('pEmail').value.trim(), courier_id: Number(document.getElementById('pCourier').value) }) });
  const j = await r.json(); document.getElementById('pMsg').textContent = r.ok ? '✔ ' + esc(j.email) + ' → ' + esc(j.role) : '✖ ' + esc(j.error || 'failed');
}
function esc(v) { return (v ?? '').toString().replace(/[&<>"]/g, (m) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[m])); }
async function loadTiers() {
  const r = await fetch('/admin/tiers', { headers: H }); const j = await r.json(); const tb = document.querySelector('#tiersTbl tbody'); tb.innerHTML = '';
  for (const t of j.tiers ?? []) {
    tb.insertAdjacentHTML('beforeend', '<tr>' +
      '<td>' + esc(t.tier) + '</td><td><button class="toggle ' + (t.active ? 'on' : 'off') + '" onclick="toggleTier(\'' + esc(t.tier) + '\',' + (t.active ? 0 : 1) + ')">' + (t.active ? 'ON' : 'OFF') + '</button></td>' +
      '<td>' + t.fee_zmw + '</td><td>' + t.parcels_per_day + '</td><td>' + t.parcels_per_month + '</td><td>' + t.overage_discount_pct + '</td><td>' + t.cycle_days + '</td><td>' + t.rider_fee_zmw + '</td><td>' + esc(t.tag ?? '') + '</td></tr>' +
      '<tr><td colspan="9" style="text-align:right"><button style="background:#b6c4bd;color:#10312a" onclick="editTier(\'' + esc(t.tier) + '\',' + t.fee_zmw + ',' + t.parcels_per_day + ',' + t.parcels_per_month + ',' + t.rider_fee_zmw + ',' + t.overage_discount_pct + ',' + t.cycle_days + ',\'' + esc(t.tag ?? '') + '\',' + (t.active ? 1 : 0) + ')">edit this plan</button></td></tr>');
  }
}
function editTier(tier, fee, ppd, ppm, rider, disc, days, tag, active) {
  tTier.value = tier; tFee.value = fee; tPpd.value = ppd; tPpm.value = ppm;
  tRider.value = rider; tDisc.value = disc; tDays.value = days; tTag.value = tag; tActive.checked = !!active;
}
async function saveTier() {
  const b = { tier: tTier.value, fee_zmw: Number(tFee.value), parcels_per_day: Number(tPpd.value),
    parcels_per_month: Number(tPpm.value), rider_fee_zmw: Number(tRider.value),
    overage_discount_pct: Number(tDisc.value), cycle_days: Number(tDays.value),
    tag: tTag.value.trim() || null, active: tActive.checked ? 1 : 0 };
  const r = await fetch('/admin/tiers', { method: 'POST', headers: { ...H, 'Content-Type': 'application/json' }, body: JSON.stringify(b) });
  const j = await r.json(); tMsg.textContent = r.ok ? ' ✔ saved' : ' ✖ ' + esc(j.error || 'failed'); loadTiers();
}
async function toggleTier(tier, on) {
  const r = await fetch('/admin/tiers', { method: 'POST', headers: { ...H, 'Content-Type': 'application/json' },
    body: JSON.stringify({ tier, active: on }) });
  if (r.ok) loadTiers();
}
async function loadCouriers() {
  const r = await fetch('/admin/couriers', { headers: H }); const j = await r.json(); const tb = document.querySelector('#couriersTbl tbody'); tb.innerHTML = '';
  for (const c of j.couriers ?? []) tb.insertAdjacentHTML('beforeend', '<tr><td>' + c.id + '</td><td>' + esc(c.name) + '</td><td>' + esc(c.city) + '</td><td>' + esc(c.depot_name) + '</td>' +
    '<td><button class="toggle ' + (Number(c.active) === 1 ? 'on' : 'off') + '" onclick="toggleCourier(' + c.id + ',' + (Number(c.active) === 1 ? 0 : 1) + ')">' + (Number(c.active) === 1 ? 'ON' : 'OFF') + '</button></td></tr>');
}
async function toggleCourier(id, on) {
  const r = await fetch('/admin/couriers', { method: 'POST', headers: { ...H, 'Content-Type': 'application/json' },
    body: JSON.stringify({ id, active: on }) });
  if (r.ok) loadCouriers();
}
async function loadPromos() {
  const r = await fetch('/admin/promos', { headers: H }); const j = await r.json(); const tb = document.querySelector('#promosTbl tbody'); tb.innerHTML = '';
  for (const p of j.promos ?? []) tb.insertAdjacentHTML('beforeend', '<tr><td>' + esc(p.code) + '</td><td>' + p.discount_pct + '</td><td>' + (p.uses_left ?? '∞') + '</td><td>' + esc(p.expires_at ?? '') + '</td><td>' + esc(p.applies_tier ?? 'any') + '</td><td>' + esc(p.note ?? '') + '</td></tr>');
}
async function savePromo() {
  const r = await fetch('/admin/promos', { method: 'POST', headers: { ...H, 'Content-Type': 'application/json' },
    body: JSON.stringify({ code: prCode.value.trim().toUpperCase(), discount_pct: Number(prPct.value), uses_left: prUses.value ? Number(prUses.value) : null, expires_at: prExp.value || null, applies_tier: prTier.value.trim().toLowerCase() || null, note: prNote.value.trim() || null }) });
  const j = await r.json(); prMsg.textContent = r.ok ? ' ✔ saved' : ' ✖ ' + esc(j.error || 'failed'); loadPromos();
}
async function loadPos() {
  const r = await fetch('/admin/pos', { headers: H }); const j = await r.json(); const tb = document.querySelector('#posTbl tbody'); tb.innerHTML = '';
  for (const p of j.pos ?? []) tb.insertAdjacentHTML('beforeend', '<tr><td>' + p.courier_id + '</td><td>' + esc(p.rail) + '</td><td>' + esc(p.merchant_id ?? '') + '</td><td>' + esc(p.instructions ?? '') + '</td></tr>');
}
async function savePos() {
  const r = await fetch('/admin/pos', { method: 'POST', headers: { ...H, 'Content-Type': 'application/json' },
    body: JSON.stringify({ courier_id: Number(posCourier.value), rail: posRail.value, merchant_id: posMerchant.value.trim(), instructions: posInstructions.value.trim() }) });
  const j = await r.json(); posMsg.textContent = r.ok ? ' ✔ saved' : ' ✖ ' + esc(j.error || 'failed'); loadPos();
}
loadTiers(); loadPromos(); loadPos(); loadCouriers();
</script></body></html>`);
});

/** Partner console — the partner logs in (email) and pastes the token. */
app.get('/partner/console', (c) => c.html(`<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<title>DropOff — Partner</title><style>${CONSOLE_CSS}</style></head><body>
<h1>DropOff — courier partner console</h1>
<p>Paste your login token from the app or one issued to you. In-browser logins keep the token local.</p>
<input id="token" placeholder="login token" style="width:100%">
<button onclick="load()">Open</button>
<div id="me"></div>
<h2>Counter prices</h2>
<table id="q"><thead><tr><th>from</th><th>to</th><th>weight</th><th>service</th><th>price K</th><th>updated</th></tr></thead><tbody></tbody></table>
<h3>Confirm/update a price</h3>
<div style="display:flex;gap:6px;flex-wrap:wrap">
<input id="fCity" placeholder="from" value="Lusaka"><input id="tCity" placeholder="to">
<input id="w" placeholder="0-5kg" value="0-5kg"><input id="sv" placeholder="standard" value="standard">
<input id="p" type="number" placeholder="K"><button onclick="save()">Save</button><span id="msg"></span></div>
<h2>Parcels handed to us</h2>
<table id="r"><thead><tr><th>ref</th><th>to</th><th>weight</th><th>status</th><th>paid</th><th></th></tr></thead><tbody></tbody></table>
<script>
let t = new URLSearchParams(location.search).get('t') || localStorage.getItem('dof_partner_token') || '';
// don't keep the login token in browser history / Referer headers
if (new URLSearchParams(location.search).has('t')) history.replaceState(null, '', location.pathname);
document.getElementById('token').value = t;
let CID = null;
const H = () => ({ 'Authorization': 'Bearer ' + document.getElementById('token').value.trim(), 'Content-Type': 'application/json' });
function esc(v) { return (v ?? '').toString().replace(/[&<>"]/g, (m) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[m])); }
async function load() {
  t = document.getElementById('token').value.trim();
  localStorage.setItem('dof_partner_token', t);
  const me = await (await fetch('/partner/me', { headers: H() })).json();
  if (!me.courier) { document.getElementById('me').textContent = 'Not a partner account yet.'; return; }
  CID = me.courier.id;
  document.getElementById('me').innerHTML = '<b>' + esc(me.email) + '</b> — ' + esc(me.courier.name) + ' (' + esc(me.courier.city) + ', ' + esc(me.courier.depot_name) + ')';
  const q = await (await fetch('/partner/quotes', { headers: H() })).json();
  document.querySelector('#q tbody').innerHTML =
    (q.quotes || []).map(z => '<tr><td>' + esc(z.from_city) + '</td><td>' + esc(z.to_city) + '</td><td>' + esc(z.weight_class) + '</td><td>' + esc(z.service) + '</td><td>K' + esc(z.counter_price_zmw) + '</td><td>' + esc(z.updated_at) + '</td></tr>').join('');
  const r = await (await fetch('/partner/rides', { headers: H() })).json();
  document.querySelector('#r tbody').innerHTML =
    (r.jobs || []).map(z => '<tr><td>' + esc(z.ref) + '</td><td>' + esc(z.dest_city) + '</td><td>' + esc(z.weight_class) + '</td><td>' + esc(z.last_event) + '</td><td>' + (z.paid ? 'paid' : '—') + '</td><td><button onclick="confirmRide(\\'' + z.ref + '\\')">confirm</button></td></tr>').join('');
}
async function save() {
  const r = await fetch('/partner/quotes', { method: 'POST', headers: H(), body: JSON.stringify({
    courier_id: CID, from_city: document.getElementById('fCity').value, to_city: document.getElementById('tCity').value,
    weight_class: document.getElementById('w').value, service: document.getElementById('sv').value,
    counter_price_zmw: Number(document.getElementById('p').value) }) });
  const j = await r.json(); document.getElementById('msg').textContent = r.ok ? '✔ price confirmed' : '✖ ' + esc(j.error || '');
  if (r.ok) load();
}
async function confirmRide(ref) {
  await fetch('/partner/rides/' + ref + '/confirm', { method: 'POST', headers: H() });
  load();
}
</script></body></html>`));
app.post('/subscriptions', async (c) => {
  const b: any = await c.req.json().catch(() => null);
  if (!b) return c.json({ error: 'invalid JSON body' }, 400);
  const tier: PlanTier = b.tier;
  const packs = await plans(c.env.DB);
  const plan = packs[tier];
  if (!plan || plan.fee_zmw <= 0) return c.json({ error: `tier must be one of ${Object.keys(packs).join(', ')}` }, 400);
  // identity: customers subscribe their own phone; ops/admin may set any
  const phone = c.get('role') === 'customer' ? c.get('phone')! : normalizeZmPhone(b.phone ?? '');
  if (!phone) return c.json({ error: 'missing phone' }, 401);
  const window: string = b.pickup_window ?? '10:00';
  if (!plan.windows.includes(window)) {
    return c.json({ error: `pickup_window must be one of ${plan.windows.join(', ')}` }, 400);
  }
  // Cycle length comes from the plan: daily pass = 1 day, weekly = 7, packs = 30.
  const cycleMod = `+${Math.max(1, plan.cycle_days || 30)} days`;
  const { meta } = await c.env.DB.prepare(
    `INSERT INTO subscriptions (phone, sender_name, tier, city, pickup_window, status, period_start, period_end)
     VALUES (?1,?2,?3,?4,?5,
       CASE WHEN EXISTS (SELECT 1 FROM subscriptions s2 WHERE s2.phone = ?1 AND s2.status = 'active' AND s2.period_end > datetime('now'))
            THEN 'active' ELSE 'pending_payment' END,
       datetime('now'), datetime('now', ?6))
     ON CONFLICT(phone) DO UPDATE SET
       tier = excluded.tier, sender_name = excluded.sender_name, city = excluded.city,
       pickup_window = excluded.pickup_window,
       status = CASE WHEN subscriptions.status = 'active' AND subscriptions.period_end > datetime('now')
                  THEN 'active' ELSE 'pending_payment' END,
       period_start = CASE WHEN subscriptions.status = 'active' AND subscriptions.period_end > datetime('now')
                  THEN subscriptions.period_start ELSE datetime('now') END,
       period_end = CASE WHEN subscriptions.status = 'active' AND subscriptions.period_end > datetime('now')
                  THEN subscriptions.period_end ELSE datetime('now', ?6) END`,
  ).bind(phone, b.sender_name ?? null, tier, b.city ?? 'Lusaka', window, cycleMod).run();
  const sub = await c.env.DB.prepare('SELECT id, tier, period_start, period_end FROM subscriptions WHERE phone = ?1')
    .bind(phone).first<any>();
  return c.json({
    ok: true, id: sub?.id, tier, pickup_window: window,
    monthly_fee_zmw: plan.fee_zmw, parcels_per_month: plan.parcels_per_month,
    period_start: sub?.period_start, period_end: sub?.period_end,
    cycle_days: plan.cycle_days,
    note: 'Approve the Lipila prompt to activate your plan. Auto-renewal bills via Lipila 3 days before the cycle ends.',
  });
});

app.get('/subscriptions/:phone?', async (c) => {
  let phone = c.req.param('phone') ?? '';
  const role = c.get('role');
  const staff = role === 'ops' || isAdmin(c);
  if (role === 'customer' || role === 'partner' || !phone || !staff) {
    // Anyone non-staff reads only their own subscription — no IDOR.
    phone = c.get('phone') ?? (staff ? normalizeZmPhone(phone) : '');
  } else {
    phone = normalizeZmPhone(phone);
  }
  if (!phone) return c.json({ subscription: null });
  const sub = await c.env.DB.prepare(
    `SELECT id, tier, city, pickup_window, status, started_at, period_start, period_end
       FROM subscriptions WHERE phone = ?1`,
  ).bind(phone).first<any>();
  if (!sub) return c.json({ subscription: null });
  const plan = (await plans(c.env.DB, { forExistingSubscribers: true }))[sub.tier as PlanTier] ?? null;
  let usedThisPeriod = 0;
  let effectiveCap = (() => {
    const cycleDays = Number(plan?.cycle_days ?? 30) || 30;
    return cycleDays <= 1
      ? (Number(plan?.parcels_per_day ?? 0) || Number(plan?.parcels_per_month ?? 0))
      : (Number(plan?.parcels_per_month ?? 0) || Number(plan?.parcels_per_day ?? 0));
  })();
  let rollover = 0;
  if (sub.period_start && sub.period_end) {
    // Every parcel counts: usage is the sum of parcels across the cycle's trips.
    usedThisPeriod = (await c.env.DB.prepare(
      `SELECT COALESCE(SUM(parcels * COALESCE(billable_rides, 1)), 0) AS n FROM jobs j
            WHERE sender_phone = ?1
            AND created_at >= ?2 AND created_at < ?3
            AND status NOT IN ('cancelled', 'canceled')
            AND NOT EXISTS (SELECT 1 FROM job_events e WHERE e.job_id = j.id AND e.status IN ('advance_pending', 'prepayment_pending'))
            AND NOT EXISTS (SELECT 1 FROM payments p WHERE p.job_id = j.id AND p.kind IN ('booking_deposit', 'job'))`,
    ).bind(phone, sub.period_start, sub.period_end).first<any>())?.n ?? 0;
    rollover = 0; // no rollover — unused parcels expire with the cycle
    const cycleDays = Number(plan?.cycle_days ?? 30) || 30;
    effectiveCap = cycleDays <= 1
      ? (Number(plan?.parcels_per_day ?? 0) || Number(plan?.parcels_per_month ?? 0))
      : (Number(plan?.parcels_per_month ?? 0) || Number(plan?.parcels_per_day ?? 0));
  }
  return c.json({
    subscription: sub,
    plan,
    usage_this_period: usedThisPeriod,
    remaining_this_period: plan ? Math.max(0, effectiveCap - usedThisPeriod) : null,
    effective_cap: plan ? effectiveCap : null,
    rollover_parcels: rollover,
    feature_flags: {
      overage_discount_enabled: flagOn(await getSetting(c.env.DB, 'overage_discount_enabled')),
      door_to_door_enabled: flagOn(await getSetting(c.env.DB, 'door_to_door_enabled')),
    },
  });
});

/* --------------------- pack codes (bulk / offline sale) -------------------- */
// Codes are generated by staff (agents, market days) and redeemed by a seller
// onto their own number: the pack activates with no payment prompt because it
// was already paid for in bulk.
app.post('/admin/pack-codes', async (c) => {
  if (!isAdmin(c) && c.get('role') !== 'ops') return c.json({ error: 'forbidden' }, 403);
  const b: any = await c.req.json().catch(() => null);
  const tier = String(b?.tier ?? '').toLowerCase() as PlanTier;
  const packs = await plans(c.env.DB);
  const plan = packs[tier];
  if (!plan) return c.json({ error: `tier must be one of ${Object.keys(packs).join(', ')}` }, 400);
  const count = Math.max(1, Math.min(Number(b?.count ?? 1) || 1, 50));
  const note = b?.note != null ? String(b.note).slice(0, 120) : null;
  const days = Math.max(1, plan.cycle_days || 30);
  const codes: string[] = [];
  for (let i = 0; i < count; i++) {
    for (let attempt = 0; attempt < 5; attempt++) {
      const code = `DROP-${randomCode(4)}-${randomCode(4)}`;
      const ins = await c.env.DB.prepare(
        `INSERT OR IGNORE INTO pack_codes (code, tier, cycle_days, note) VALUES (?1, ?2, ?3, ?4)`,
      ).bind(code, tier, days, note).run();
      if ((ins.meta.changes ?? 0) > 0) { codes.push(code); break; }
    }
  }
  // Return the full persisted set from the DB (old + new), newest first, so
  // the admin console can show history immediately after a batch.
  const { results } = await c.env.DB.prepare(
    `SELECT pc.code, pc.tier, pc.cycle_days, pc.note, pc.created_at, pc.used_by, pc.used_at,
            u.full_name AS redeemed_name, u.email AS redeemed_email,
            (SELECT s.period_end FROM subscriptions s WHERE s.phone = pc.used_by ORDER BY s.period_end DESC LIMIT 1) AS period_end,
            CASE WHEN pc.used_by IS NULL THEN 'unused'
                 WHEN NOT EXISTS (SELECT 1 FROM subscriptions s WHERE s.phone = pc.used_by AND s.status = 'active' AND s.period_end > datetime('now')) THEN 'used'
                 WHEN (SELECT s.period_end FROM subscriptions s WHERE s.phone = pc.used_by ORDER BY s.period_end DESC LIMIT 1) <= datetime('now') THEN 'expired'
                 ELSE 'active' END AS status
       FROM pack_codes pc
       LEFT JOIN auth_users u ON u.phone = pc.used_by
       ORDER BY pc.id DESC LIMIT 200`,
  ).all();
  return c.json({ ok: true, tier, cycle_days: days, codes, persisted_codes: results ?? [] });
});

app.get('/admin/pack-codes', async (c) => {
  if (!isAdmin(c) && c.get('role') !== 'ops') return c.json({ error: 'admin_key_required' }, 403);
  const { results } = await c.env.DB.prepare(
    `SELECT pc.code, pc.tier, pc.cycle_days, pc.note, pc.created_at, pc.used_by, pc.used_at,
            u.full_name AS redeemed_name, u.email AS redeemed_email,
            (SELECT s.period_end FROM subscriptions s WHERE s.phone = pc.used_by ORDER BY s.period_end DESC LIMIT 1) AS period_end,
            CASE WHEN pc.used_by IS NULL THEN 'unused'
                 WHEN NOT EXISTS (SELECT 1 FROM subscriptions s WHERE s.phone = pc.used_by AND s.status = 'active' AND s.period_end > datetime('now')) THEN 'used'
                 WHEN (SELECT s.period_end FROM subscriptions s WHERE s.phone = pc.used_by ORDER BY s.period_end DESC LIMIT 1) <= datetime('now') THEN 'expired'
                 ELSE 'active' END AS status
       FROM pack_codes pc
       LEFT JOIN auth_users u ON u.phone = pc.used_by
       ORDER BY pc.id DESC LIMIT 200`,
  ).all();
  return c.json({ codes: results ?? [] });
});

app.post('/subscriptions/redeem', async (c) => {
  const phone = c.get('phone');
  if (!phone) return c.json({ error: 'sign_in_required' }, 401);
  const b: any = await c.req.json().catch(() => null);
  const code = String(b?.code ?? '').trim().toUpperCase();
  if (!code) return c.json({ error: 'code_required' }, 400);
  const row = await c.env.DB.prepare(
    'SELECT code, tier, cycle_days, used_by FROM pack_codes WHERE code = ?1',
  ).bind(code).first<any>();
  if (!row) return c.json({ error: 'code_not_found' }, 404);
  if (row.used_by) return c.json({ error: 'code_used' }, 409);
  const packs = await plans(c.env.DB);
  const plan = packs[row.tier as PlanTier];
  if (!plan) return c.json({ error: 'pack_tier_unavailable' }, 409);
  const days = Math.max(1, Number(row.cycle_days) || plan.cycle_days || 30);
  // Consume atomically — two devices racing the same code: exactly one wins.
  const upd = await c.env.DB.prepare(
    `UPDATE pack_codes SET used_by = ?1, used_at = datetime('now') WHERE code = ?2 AND used_by IS NULL`,
  ).bind(phone, code).run();
  if ((upd.meta.changes ?? 0) === 0) return c.json({ error: 'code_used' }, 409);
  const cycleMod = `+${days} days`;
  await c.env.DB.prepare(
    `INSERT INTO subscriptions (phone, tier, city, pickup_window, status, period_start, period_end)
     VALUES (?1, ?2, 'Lusaka', '10:00', 'active', datetime('now'), datetime('now', ?3))
     ON CONFLICT(phone) DO UPDATE SET
       tier = excluded.tier, status = 'active',
       period_start = excluded.period_start, period_end = excluded.period_end`,
  ).bind(phone, row.tier, cycleMod).run();
  const sub = await c.env.DB.prepare(
    'SELECT tier, period_start, period_end FROM subscriptions WHERE phone = ?1',
  ).bind(phone).first<any>();
  return c.json({
    ok: true,
    tier: sub?.tier ?? row.tier,
    period_start: sub?.period_start,
    period_end: sub?.period_end,
    cycle_days: days,
    parcels: plan.parcels_per_month,
  });
});

/* ----------------------- mid-cycle upgrade (prorated) ---------------------- */
// Pay the difference for the remaining days; the new tier's cap applies the
// moment the upgrade is requested. Failed/abandoned payments are reverted by
// the reconciliation sweep using the prevTier stored on the payment row.
const TIER_RANK: Record<string, number> = { rider_daily: 0, daily: 0, weekly: 1, silver: 2, gold: 3, platinum: 4 };

app.post('/subscriptions/upgrade', async (c) => {
  if (await rateLimited(c, 'payment_create', 30)) return c.json({ error: 'too_many_requests' }, 429);
  const b: any = await c.req.json().catch(() => null);
  const tier = String(b?.tier ?? '').toLowerCase() as PlanTier;
  const phone = c.get('role') === 'customer' ? c.get('phone')! : normalizeZmPhone(b?.phone ?? '');
  if (!phone) return c.json({ error: 'identity_required' }, 401);
  const packs = await plans(c.env.DB);
  const newPlan = packs[tier];
  if (!newPlan || newPlan.fee_zmw <= 0) return c.json({ error: `tier must be one of ${Object.keys(packs).join(', ')}` }, 400);
  const sub = await c.env.DB.prepare(
    `SELECT id, phone, tier, status, period_start, period_end FROM subscriptions WHERE phone = ?1 ORDER BY id DESC LIMIT 1`,
  ).bind(phone).first<any>();
  if (!sub) return c.json({ error: 'no_subscription', detail: 'Choose a pack first.' }, 404);
  if ((TIER_RANK[tier] ?? 0) <= (TIER_RANK[sub.tier] ?? 0)) {
    return c.json({ error: 'upgrades_only', detail: 'Downgrades apply automatically at your next renewal.' }, 400);
  }
  if (sub.status !== 'active' || !sub.period_end || sub.period_end <= new Date().toISOString().slice(0, 19).replace('T', ' ')) {
    return c.json({ error: 'pack_not_active', detail: 'Subscribe (pay) first, then upgrade.' }, 400);
  }
  const pending = await c.env.DB.prepare(
    `SELECT id FROM payments WHERE subscription_id = ?1 AND status = 'pending'`,
  ).bind(sub.id).first<any>();
  if (pending) return c.json({ error: 'payment_already_pending' }, 409);

  const oldPlan = packs[sub.tier as PlanTier];
  const cycleDays = oldPlan?.cycle_days || 30;
  const remainingMs = Date.parse(`${sub.period_end}Z`) - Date.now();
  const remainingDays = Math.max(1, Math.ceil(remainingMs / 86_400_000));
  const prorated = round2(Math.max(0, ((newPlan.fee_zmw - (oldPlan?.fee_zmw ?? 0)) * remainingDays) / cycleDays));

  // Bump the tier NOW — the bigger cap is live immediately.
  await c.env.DB.prepare('UPDATE subscriptions SET tier = ?2 WHERE id = ?1').bind(sub.id, tier).run();

  if (prorated <= 0) {
    return c.json({ ok: true, tier, prorated_zmw: 0, detail: 'Upgraded — nothing extra to pay for the rest of this cycle.' });
  }

  const platformFeeZmw = platformFee(prorated);
  const amount = round2(prorated + platformFeeZmw + MOMO_COLLECTION_FEE);
  const lipilaRef = `upg-${sub.id}-${new Date().toISOString().slice(0, 10).replace(/-/g, '')}`;
  const init = await lipilaCollect(c.env, phone, amount, lipilaRef, `DropOff ${tier} upgrade (prorated)`);
  if (!init.ok) {
    // revert the bump so a failed collect never leaves a free upgrade
    await c.env.DB.prepare('UPDATE subscriptions SET tier = ?2 WHERE id = ?1').bind(sub.id, sub.tier).run();
    return c.json({ error: 'lipila_init_failed', detail: init.raw }, 502);
  }
  const provider: Provider = providerFromPhone(phone);
  await c.env.DB.prepare(
    `INSERT INTO payments (subscription_id, phone, provider, amount_zmw, platform_fee_zmw,
       lipila_fee_zmw, lipila_reference, status, channel, kind, meta)
     VALUES (?1,?2,?3,?4,?5,?6,?7,'pending','merchant','upgrade',?8)`,
  ).bind(sub.id, phone, provider, amount, platformFeeZmw, MOMO_COLLECTION_FEE,
    init.lipilaReference ?? null, JSON.stringify({ prevTier: sub.tier, newTier: tier, prorated })).run();
  return c.json({ ok: true, tier, prorated_zmw: prorated, amount_zmw: amount,
    note: 'Approve the Lipila prompt. Your bigger cap is already live.' });
});

/* ------------------ admin (superadmin pricebook + ops) -------------------- */
app.use('/admin/*', async (c, next) => {
  // Rider creation is superadmin/admin only (per team policy) — no rider or
  // ops role may create riders/drivers. Every other /admin/* surface likewise.
  if (!isAdmin(c)) return c.json({ error: 'admin_key_required' }, 403);
  return next();
});

// Upsert courier partner profile (the partner "page" sellers see in-app).
// A bare {id, active} pair is the on/off TOGGLE — it flips availability
// without touching the profile. Full bodies edit the profile too.
app.get('/admin/couriers', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'admin_key_required' }, 403);
  const { results } = await c.env.DB.prepare(
    `SELECT id, name, city, depot_name, lat, lng, website, price_status, note, active
       FROM couriers ORDER BY active DESC, name`,
  ).all();
  return c.json({ couriers: results });
});
app.post('/admin/couriers', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'admin_key_required' }, 403);
  const b: any = await c.req.json().catch(() => null);
  // Toggle-only request: { id, active } — bare toggle, no full profile needed.
  if (b?.id && b.name == null && b.active !== undefined) {
    await c.env.DB.prepare('UPDATE couriers SET active = ?2 WHERE id = ?1')
      .bind(Number(b.id), b.active ? 1 : 0).run();
    return c.json({ ok: true, id: Number(b.id), active: b.active ? 1 : 0 });
  }
  if (!b?.name || !b.city || !b.depot_name) return c.json({ error: 'name, city, depot_name required' }, 400);
  const active = b.active == null ? 1 : (b.active ? 1 : 0);
  if (b.id) {
    await c.env.DB.prepare(
      `UPDATE couriers SET name = ?2, city = ?3, depot_name = ?4, lat = ?5, lng = ?6,
         website = ?7, price_status = ?8, note = ?9, logo_url = ?10, active = ?11
       WHERE id = ?1`,
    ).bind(b.id, b.name, b.city, b.depot_name, b.lat ?? null, b.lng ?? null,
      b.website ?? null, b.price_status ?? null, b.note ?? null, b.logo_url ?? null, active).run();
    return c.json({ ok: true, id: b.id, active });
  }
  const { meta } = await c.env.DB.prepare(
    `INSERT INTO couriers (name, city, depot_name, lat, lng, website, price_status, note, logo_url, active)
     VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10)`,
  ).bind(b.name, b.city, b.depot_name, b.lat ?? null, b.lng ?? null,
    b.website ?? null, b.price_status ?? null, b.note ?? null, b.logo_url ?? null, active).run();
  return c.json({ ok: true, id: meta.last_row_id, active });
});

// Price-list entry (chargebook) — superadmin captures depot tariffs here.
// `source` is provenance only: 'ops' (keyed in by staff) or 'recorded'
// (learned automatically from the rider's depot-counter reading).
app.post('/admin/quotes', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'admin_key_required' }, 403);
  const b: any = await c.req.json().catch(() => null);
  const required = ['courier_id', 'from_city', 'to_city', 'weight_class', 'service', 'counter_price_zmw'];
  for (const k of required) if (b?.[k] === undefined) return c.json({ error: `${k} required` }, 400);
  if (b.counter_price_zmw <= 0) return c.json({ error: 'counter_price_zmw must be > 0' }, 400);
  const source = ['ops', 'recorded'].includes(b.source) ? b.source : 'ops';
  const exists = await c.env.DB.prepare(
    `SELECT id FROM quotes WHERE courier_id = ?1 AND from_city = ?2 AND to_city = ?3
       AND weight_class = ?4 AND service = ?5`,
  ).bind(b.courier_id, b.from_city, b.to_city, b.weight_class, b.service).first<any>();
  if (exists) {
    await c.env.DB.prepare(
      `UPDATE quotes SET counter_price_zmw = ?2, source = ?3, updated_at = datetime('now') WHERE id = ?1`,
    ).bind(exists.id, b.counter_price_zmw, source).run();
    return c.json({ ok: true, id: exists.id, updated: true });
  }
  const { meta } = await c.env.DB.prepare(
    `INSERT INTO quotes (courier_id, from_city, to_city, weight_class, service, counter_price_zmw, source)
     VALUES (?1,?2,?3,?4,?5,?6,?7)`,
  ).bind(b.courier_id, b.from_city, b.to_city, b.weight_class, b.service, b.counter_price_zmw, source).run();
  return c.json({ ok: true, id: meta.last_row_id });
});

// Chargebook listing for the ops console (coverage + freshness at a glance).
app.get('/admin/quotes', async (c) => {
  if (!isFinanceExec(c)) return c.json({ error: 'forbidden' }, 403);
  const courierId = Number(c.req.query('courier_id') ?? '0');
  const { results } = await c.env.DB.prepare(
    `SELECT q.id, q.courier_id, co.name AS courier_name, q.from_city, q.to_city,
            q.weight_class, q.service, q.counter_price_zmw, q.source, q.updated_at,
            CASE WHEN q.updated_at < datetime('now', '-90 days') THEN 1 ELSE 0 END AS stale
       FROM quotes q JOIN couriers co ON co.id = q.courier_id
      WHERE (?1 = 0 OR q.courier_id = ?1)
      ORDER BY q.updated_at DESC, co.name, q.from_city, q.to_city LIMIT 500`,
  ).bind(courierId).all();
  return c.json({ quotes: results });
});

// Rider roster (rider identity lives here; rider apps log in by phone OTP)
// Team creation policy: superadmin (owner) and admins ONLY. No ops/rider may
// create riders or drivers.
app.post('/admin/riders', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'admin_key_required' }, 403);
  const b: any = await c.req.json().catch(() => null);
  if (!b?.full_name || !b.vehicle) return c.json({ error: 'full_name and vehicle required' }, 400);
  const phone = normalizeZmPhone(b.phone ?? '');
  if (!phone) return c.json({ error: 'phone required' }, 400);
  const vc = VEHICLE_CLASSES.includes(b.vehicle_class) ? b.vehicle_class : 'motorcycle';
  await c.env.DB.prepare(
    `INSERT INTO riders (phone, full_name, vehicle, vehicle_class) VALUES (?1,?2,?3,?4)
     ON CONFLICT(phone) DO UPDATE SET full_name = excluded.full_name, vehicle = excluded.vehicle,
       vehicle_class = excluded.vehicle_class, active = 1`,
  ).bind(phone, b.full_name, b.vehicle, vc).run();
  const rider = await c.env.DB.prepare('SELECT id FROM riders WHERE phone = ?1').bind(phone).first<any>();
  return c.json({ ok: true, id: rider?.id, vehicle_class: vc });
});

// Manual rider assignment and the whole override route were REMOVED (owner
// directive 2026-11-15): every dispatch flows through nearestAvailableRider().
// No human picks a rider — not even with the superadmin key. Ops recovery
// calls dispatchToNearestRider, which is post-payment and algorithmic.

// Promote an email account to a partner shop tied to a courier row.
// Partner then signs in with that email and uses /partner/* or /partner/console.
app.post('/admin/partners', async (c) => {
  // This endpoint mints 'partner' roles - it must never be reachable without
  // an admin identity (previously any signed-in account could self-promote).
  if (!isAdmin(c)) return c.json({ error: 'forbidden' }, 403);
  const b: any = await c.req.json().catch(() => null);
  const email = String(b?.email ?? '').trim().toLowerCase();
  const courierId = Number(b?.courier_id ?? 0);
  if (!isValidEmail(email) || !courierId) return c.json({ error: 'email and courier_id required' }, 400);
  const courier = await c.env.DB.prepare('SELECT id FROM couriers WHERE id = ?1').bind(courierId).first<any>();
  if (!courier) return c.json({ error: 'courier not found' }, 404);
  const user = await c.env.DB.prepare('SELECT email FROM auth_users WHERE email = ?1').bind(email).first<any>();
  if (!user) return c.json({ error: 'that email has no account yet — ask them to register in the app first' }, 404);
  await c.env.DB.prepare(
    `UPDATE auth_users SET role = 'partner', courier_id = ?2 WHERE email = ?1`,
  ).bind(email, courierId).run();
  return c.json({ ok: true, email, role: 'partner', courier_id: courierId });
});

/* ------------------ rider payroll (auto-generated, confirm-gated) --------- */
// Salaried riders (K3,000/mo incl. K300/wk fuel — see constants above). Runs
// are generated automatically by cron (Sunday 16:00 CAT = weekly; 1st of the
// month 16:00 CAT = monthly / monthly balance) and require an admin AND THEN
// a superadmin confirmation before the money moves. Each paid row has a
// downloadable proof-of-payment receipt at /admin/payroll/:id/proof.

const PAYROLL_EVENT_STATUSES = "('at_depot','delivered','ready_for_collection')";
const TOT_MONTHLY_ZERO_BAND_ZMW = 2500;   // ZRA 2026: 0% up to K2,500 monthly turnover
const TOT_RATE = 0.05;                    // ZRA 2026: 5% above the zero band (annual ≤ K5,000,000)

function catNow(): Date {
  return new Date(Date.now() + 2 * 60 * 60 * 1000);
}
function catYm(d: Date, monthsBack = 0): string {
  const dd = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() - monthsBack, 1));
  return `${dd.getUTCFullYear()}-${String(dd.getUTCMonth() + 1).padStart(2, '0')}`;
}

/** Completed-trip count for a rider inside a CAT window (same event set the
 *  targets use: depot drop for first mile, delivered/ready for last mile). */
async function riderTripsInWindow(db: D1Database, riderId: number, start: string, end: string): Promise<number> {
  const row = await db.prepare(
    `SELECT COUNT(DISTINCT j.id) AS n
       FROM job_events je JOIN jobs j ON j.id = je.job_id
      WHERE j.rider_id = ?1 AND je.status IN ${PAYROLL_EVENT_STATUSES}
        AND datetime(je.created_at, '${CAT_OFFSET}') >= ?2
        AND datetime(je.created_at, '${CAT_OFFSET}') < ?3`,
  ).bind(riderId, start, end).first<any>();
  return Number(row?.n ?? 0);
}

interface PayrollPeriod { kind: string; start: string; end: string; label: string }

/** The period that just ENDED at the pay instant. Weekly: last Sunday
 *  16:00 CAT → this Sunday 16:00 CAT. Monthly: the whole previous CAT month. */
function payrollPeriod(kind: 'weekly' | 'monthly'): PayrollPeriod {
  const now = catNow();
  if (kind === 'weekly') {
    const end = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate(), 16, 0, 0));
    const start = new Date(end.getTime() - 7 * 86400_000);
    return {
      kind,
      start: start.toISOString(),
      end: end.toISOString(),
      label: `Week ${start.toISOString().slice(0, 10)} → ${end.toISOString().slice(0, 10)}`,
    };
  }
  const ym = catYm(now, 1);
  const start = `${ym}-01`;
  const startD = new Date(Date.UTC(Number(ym.slice(0, 4)), Number(ym.slice(5, 7)) - 1, 1));
  const endD = new Date(Date.UTC(Number(ym.slice(0, 4)), Number(ym.slice(5, 7)), 1));
  return { kind, start, end: endD.toISOString(), label: `Month ${ym}` };
}

/** Pace-gated base/fuel split for a period (pro-rated to the shortfall). */
function paceSplit(trips: number, periodTarget: number, fullBase: number, fullFuel: number) {
  const ratio = periodTarget > 0 ? Math.max(0, Math.min(1, trips / periodTarget)) : 1;
  return {
    base: round2(fullBase * ratio),
    fuel: round2(fullFuel * ratio),
    paceMet: trips >= periodTarget,
    ratio,
  };
}

/** Generate this instant's pending payroll rows. Idempotent per period. */
export async function generatePayroll(env: Env, kind: 'weekly' | 'monthly'): Promise<void> {
  const period = payrollPeriod(kind);
  const { results: riders } = await env.DB.prepare(
    `SELECT id, phone, full_name, pay_cycle FROM riders WHERE active = 1 AND verification_status = 'verified'`,
  ).all<any>();
  for (const r of riders ?? []) {
    try {
      if (kind === 'weekly') {
        if ((r.pay_cycle ?? 'weekly') !== 'weekly') continue;
        const trips = await riderTripsInWindow(env.DB, Number(r.id), period.start, period.end);
        const split = paceSplit(trips, DRIVER_DAILY_TARGET * 7, DRIVER_BASE_MONTHLY_ZMW / 4, DRIVER_FUEL_ALLOWANCE_WEEKLY_ZMW);
        const amount = round2(split.base + split.fuel);
        if (amount <= 0) continue;
        await env.DB.prepare(
          `INSERT OR IGNORE INTO rider_payroll
             (rider_phone, rider_name, period_kind, period_start, period_end,
              base_zmw, fuel_zmw, trips, period_target, pace_met, amount_zmw, status, note)
           VALUES (?1, ?2, 'weekly', ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, 'pending', ?11)`,
        ).bind(r.phone, r.full_name ?? null, period.start, period.end, split.base, split.fuel,
          trips, DRIVER_DAILY_TARGET * 7, split.paceMet ? 1 : 0, amount,
          split.paceMet ? null : `Behind pace (${trips}/${DRIVER_DAILY_TARGET * 7} trips) — pay pro-rated.`).run();
      } else {
        // Monthly cron: full salary for monthly-cycle riders; balance top-up
        // (K3,000 − weeks already paid) for weekly-cycle riders.
        const startD = new Date(Date.UTC(Number(period.start.slice(0, 4)), Number(period.start.slice(5, 7)) - 1, 1));
        const daysInPeriod = Math.round((new Date(period.end).getTime() - startD.getTime()) / 86400_000);
        const prog = await incentiveProgramme(env);
        if ((r.pay_cycle ?? 'weekly') === 'monthly') {
          const trips = await riderTripsInWindow(env.DB, Number(r.id), period.start, period.end);
          const monthTarget = DRIVER_DAILY_TARGET * daysInPeriod;
          const split = paceSplit(trips, monthTarget, DRIVER_BASE_MONTHLY_ZMW, DRIVER_FUEL_MONTHLY_ZMW);
          // Over-target incentive bonus (paid through payroll, additive to salary; admin-promoted promo if configured):
          const bonusSplit = riderBonusSplits(trips, monthTarget, prog);
          const amount = round2(split.base + split.fuel + bonusSplit.total_bonus_zmw);
          if (amount <= 0) continue;
          const note = bonusSplit.total_bonus_zmw > 0
            ? `${split.paceMet ? 'On target' : `Behind pace (${trips}/${monthTarget} trips) — base pro-rated`}. Bonus: +K${bonusSplit.total_bonus_zmw.toFixed(2)} (${bonusSplit.completion_bonus_zmw > 0 ? 'completion +K200 ' : ''}${bonusSplit.over_target_bonus_zmw > 0 ? `+K${bonusSplit.over_target_bonus_zmw.toFixed(2)} ${bonusSplit.counted_extra} over-target ` : ''}${bonusSplit.stretch_bonus_zmw > 0 ? '+ stretch +K150' : ''}).`
            : (split.paceMet ? null : `Behind pace (${trips}/${monthTarget} trips) — pay pro-rated.`);
          await env.DB.prepare(
            `INSERT OR IGNORE INTO rider_payroll
               (rider_phone, rider_name, period_kind, period_start, period_end,
                base_zmw, fuel_zmw, trips, period_target, pace_met, amount_zmw, status, note)
             VALUES (?1, ?2, 'monthly', ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, 'pending', ?11)`,
          ).bind(r.phone, r.full_name ?? null, period.start, period.end, split.base, split.fuel,
            trips, monthTarget, split.paceMet ? 1 : 0, amount, note).run();
        } else {
          const paidRow = await env.DB.prepare(
            `SELECT COALESCE(SUM(amount_zmw), 0) AS paid FROM rider_payroll
              WHERE rider_phone = ?1 AND status = 'paid'
                AND period_kind = 'weekly' AND period_start >= ?2 AND period_end <= ?3`,
          ).bind(r.phone, period.start, period.end).first<any>();
          // Over-target bonus paid at month close regardless of cycle (weekly
          // riders don't wait for the monthly reconciliation to chase it).
          const monthTarget = DRIVER_DAILY_TARGET * daysInPeriod;
          const trips = await riderTripsInWindow(env.DB, Number(r.id), period.start, period.end);
          const bonusSplit = riderBonusSplits(trips, monthTarget, prog);
          const balance = round2(DRIVER_MONTHLY_PAY_ZMW - Number(paidRow?.paid ?? 0) + bonusSplit.total_bonus_zmw);
          if (balance <= 0) continue;
          await env.DB.prepare(
            `INSERT OR IGNORE INTO rider_payroll
               (rider_phone, rider_name, period_kind, period_start, period_end,
                base_zmw, fuel_zmw, trips, period_target, pace_met, amount_zmw, status, note)
             VALUES (?1, ?2, 'monthly_balance', ?3, ?4, 0, 0, ?5, ?6, 1, ?7, 'pending',
               'Monthly reconciliation: K${DRIVER_MONTHLY_PAY_ZMW} salary top-up minus K${Number(paidRow?.paid ?? 0)} weekly pay already settled this month.${bonusSplit.total_bonus_zmw > 0 ? ` Bonus: +K${bonusSplit.total_bonus_zmw.toFixed(2)} (${bonusSplit.counted_extra} over target; ).` : ''}')`,
          ).bind(r.phone, r.full_name ?? null, period.start, period.end,
            trips, monthTarget, balance).run();
        }
      }
    } catch (e) {
      await captureError(env, e, { method: 'PAYROLL', url: `https://internal/payroll` });
    }
  }
}

/* -------------------------- ZRA turnover tax ledger ----------------------- */
// Rates (2026, ZRA): monthly turnover ≤ K2,500 → 0%; above → 5% of the whole
// month's turnover (annual-regime cap K5,000,000; partnerships/consultancies
// are ineligible). Return + payment due by the 14th of the FOLLOWING month.
// Turnover lines (DropOff's own charged income — never the partner's counter
// fare, which is paid at the depot):
//   1. momo job collections (payments kind='job')
//   2. delivery-credit-settled DropOff legs (jobs paid & settled from the
//      sender's prepayment)
//   3. subscription / upgrade payments
//   4. platform cut on legacy door cash-on-delivery remittances (historical
//      rows only — COD is removed by policy; historical entries still count
//      as platform revenue recognised when settled).
export async function updateTaxPeriod(env: Env, ym: string): Promise<void> {
  const start = `${ym}-01`;
  const nextYm = catYm(new Date(Date.UTC(Number(ym.slice(0, 4)), Number(ym.slice(5, 7)), 1)), 0);
  const end = `${nextYm}-01`;
  const bounds = `datetime(ifnull(paid_at, created_at), '${CAT_OFFSET}') >= '${start}'
        AND datetime(ifnull(paid_at, created_at), '${CAT_OFFSET}') < '${end}'`;
  const jobRow = await env.DB.prepare(
    `SELECT COALESCE(SUM(amount_zmw), 0) AS a FROM payments
      WHERE status = 'success' AND kind = 'job' AND ${bounds}`,
  ).first<any>();
  const subRow = await env.DB.prepare(
    `SELECT COALESCE(SUM(amount_zmw), 0) AS a FROM payments
      WHERE status = 'success' AND kind IN ('subscription', 'upgrade') AND ${bounds}`,
  ).first<any>();
  const walletRow = await env.DB.prepare(
    `SELECT COALESCE(SUM(MAX(0, j.rider_fee_zmw + IFNULL(j.leg2_fee_zmw, 0)
        + IFNULL(j.leg2_processing_fee_zmw, 0) + IFNULL(j.wait_fee_zmw, 0)
        - IFNULL(j.promo_discount_zmw, 0))), 0) AS a
       FROM jobs j
      WHERE j.paid = 1 AND j.pay_method = 'wallet'
        AND datetime(j.created_at, '${CAT_OFFSET}') >= '${start}'
        AND datetime(j.created_at, '${CAT_OFFSET}') < '${end}'`,
  ).first<any>();
  const codRow = await env.DB.prepare(
    `SELECT COALESCE(SUM(cod_collected_zmw), 0) AS a FROM jobs
      WHERE status IN ('delivered', 'ready_for_collection') AND cod_collected_zmw > 0
        AND datetime(created_at, '${CAT_OFFSET}') >= '${start}'
        AND datetime(created_at, '${CAT_OFFSET}') < '${end}'`,
  ).first<any>();
  const lines = {
    job_collections: round2(Number(jobRow?.a ?? 0)),
    wallet_jobs: round2(Number(walletRow?.a ?? 0)),
    subscriptions: round2(Number(subRow?.a ?? 0)),
    cod_platform_cut: round2(Number(codRow?.a ?? 0) * COD_FEE),
  };
  const gross = round2(lines.job_collections + lines.wallet_jobs + lines.subscriptions + lines.cod_platform_cut);
  const zeroBand = Math.min(gross, TOT_MONTHLY_ZERO_BAND_ZMW);
  const taxable = round2(Math.max(0, gross - TOT_MONTHLY_ZERO_BAND_ZMW));
  const tax = round2(gross > TOT_MONTHLY_ZERO_BAND_ZMW ? gross * TOT_RATE : 0);
  const dueDate = `${nextYm}-14`;
  await env.DB.prepare(
    `INSERT INTO tax_periods (year_month, gross_turnover_zmw, zero_band_zmw, taxable_zmw,
        rate, tax_zmw, due_date, status, breakdown)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, 'open', ?8)
     ON CONFLICT (year_month) DO UPDATE SET
        gross_turnover_zmw = excluded.gross_turnover_zmw,
        zero_band_zmw = excluded.zero_band_zmw,
        taxable_zmw = excluded.taxable_zmw,
        rate = excluded.rate,
        tax_zmw = excluded.tax_zmw,
        due_date = excluded.due_date,
        breakdown = excluded.breakdown,
        updated_at = datetime('now')
       WHERE tax_periods.status = 'open'`,
  ).bind(ym, gross, zeroBand, taxable, TOT_RATE, tax, dueDate,
    JSON.stringify(lines) || null).run();
}

/* ------------------------ payroll + tax endpoints ------------------------- */

app.post('/admin/payouts', async (c) => {
  // Money path: superadmin only (owner/admin key). A leaked ledger write
  // here is how fake ride-float balances are born.
  if (!isSuperAdmin(c)) return c.json({ error: 'superadmin_required' }, 403);
  const b: any = await c.req.json().catch(() => null);
  const kind: string = ['rider_earning', 'rider_payout'].includes(b?.kind) ? b.kind : 'rider_earning';
  const phone = normalizeZmPhone(b?.phone ?? '');
  const amount = Math.round(Math.abs(Number(b?.amount_zmw) || 0) * 100) / 100;
  if (!phone || amount <= 0) return c.json({ error: 'phone and positive amount required' }, 400);
  await c.env.DB.batch(await walletCreditStatements(c, phone, b.kind === 'rider_payout' ? -amount : amount, kind));
  return c.json({ ok: true });
});

/* ------------- public team roster — verified riders only ------------------- */
// Any signed-in member can see who is on the verified team (name/vehicle
// only — no phones, docs, or payment data). Riders sync it live from any
// account, which is why the app counts stale local entries no longer.
app.get('/team', async (c) => {
  const role = String(c.get('role') ?? '');
  if (role === 'customer') return c.json({ error: 'account_required' }, 403);
  const rows = await c.env.DB.prepare(
    `SELECT id, full_name, vehicle, vehicle_class, pay_cycle, status FROM riders
      WHERE active = 1 AND verification_status = 'verified'
      ORDER BY full_name COLLATE NOCASE`,
  ).all<any>();
  return c.json({
    riders: (rows.results ?? []).map((r: any) => ({
      id: r.id, full_name: r.full_name, vehicle: r.vehicle, vehicle_class: r.vehicle_class,
      pay_cycle: r.pay_cycle ?? 'weekly',
    })),
    total: (rows.results ?? []).length,
  });
});

/* ---------------- payroll (admin/superadmin confirmation chain) ------------ */
app.get('/admin/payroll', async (c) => {
  if (!isFinanceExec(c)) return c.json({ error: 'forbidden' }, 403);
  const status = String(c.req.query('status') ?? '').trim();
  const kind = String(c.req.query('kind') ?? '').trim();
  let sql = `SELECT * FROM rider_payroll`;
  const conds: string[] = [];
  const binds: any[] = [];
  if (status) { conds.push(`status = ${binds.push(status)}`); }
  if (kind) { conds.push(`period_kind = ${binds.push(kind)}`); }
  if (conds.length) sql += ` WHERE ${conds.join(' AND ')}`;
  sql += ` ORDER BY id DESC LIMIT 100`;
  const { results } = await c.env.DB.prepare(sql).bind(...binds).all<any>();
  const sums = await c.env.DB.prepare(
    `SELECT status, COUNT(*) AS n, COALESCE(SUM(amount_zmw),0) AS total FROM rider_payroll GROUP BY status`,
  ).all<any>();
  return c.json({ payouts: results ?? [], summary: sums.results ?? [] });
});

// Salaries run-rate — the CFO/ops view of the payroll cost as the business
// grows. All numbers derive from live D1 rows (verified roster, tax ledger).
app.get('/admin/payroll/runrate', async (c) => {
  if (!isFinanceExec(c)) return c.json({ error: 'forbidden' }, 403);
  const ry = await c.env.DB.prepare(
    `SELECT COUNT(*) AS n FROM riders WHERE active = 1 AND verification_status = 'verified'`,
  ).first<any>();
  const riders = Number(ry?.n ?? 0);
  const pending = await c.env.DB.prepare(
    `SELECT COALESCE(SUM(amount_zmw), 0) AS t, COUNT(*) AS n FROM rider_payroll
       WHERE status IN ('pending', 'admin_confirmed')`,
  ).first<any>();
  const periods = await c.env.DB.prepare(
    `SELECT gross_turnover_zmw FROM tax_periods ORDER BY year_month DESC LIMIT 3`,
  ).all<any>();
  const turns = (periods.results ?? []).map((r: any) => Number(r.gross_turnover_zmw ?? 0));
  const avgTurn = turns.length ? round2(turns.reduce((a, b) => a + b, 0) / turns.length) : 0;
  const weeklyOut = round2(riders * DRIVER_WEEKLY_PAY_ZMW);   // K750/rider/week
  const monthlyOut = round2(riders * DRIVER_MONTHLY_PAY_ZMW); // K3,000/rider/month
  const annualOut = round2(monthlyOut * 12);
  const monthlyTarget = riders * DRIVER_DAILY_TARGET * 30;    // pace-gated needed trips
  const payableForRiderPerDay = DRIVER_MONTHLY_PAY_ZMW / 30;  // K100/rider/day cost
  const selfSustainTrips = Math.ceil(payableForRiderPerDay / 45); // PAYG legs at K45
  const growth = [10, 25, 50, 100].map((add) => {
    const cost = round2((riders + add) * DRIVER_MONTHLY_PAY_ZMW);
    const share = avgTurn > 0 ? round2((cost / avgTurn) * 100) : null;
    return { riders: riders + add, add, monthly_payroll_zmw: cost, payroll_share_pct: share, needed_turnover_zmw: round2(cost / 0.25) };
  });
  return c.json({
    verified_active_riders: riders,
    pending_payroll_n: Number(pending?.n ?? 0),
    pending_payroll_zmw: round2(Number(pending?.t ?? 0)),
    weekly_out_zmw: weeklyOut,
    monthly_out_zmw: monthlyOut,
    annual_out_zmw: annualOut,
    monthly_trip_target: monthlyTarget,
    avg_monthly_turnover_zmw: avgTurn,
    payroll_share_of_turnover_pct: avgTurn > 0 ? round2((monthlyOut / avgTurn) * 100) : null,
    self_sustain_trips_per_rider_day: selfSustainTrips,
    constants: { monthly_pay_zmw: DRIVER_MONTHLY_PAY_ZMW, base_pay_zmw: DRIVER_BASE_MONTHLY_ZMW, fuel_weekly_zmw: DRIVER_FUEL_ALLOWANCE_WEEKLY_ZMW, daily_target: DRIVER_DAILY_TARGET, weekly_pay_zmw: DRIVER_WEEKLY_PAY_ZMW },
    growth_planner: growth,
  });
});

// Manual generation trigger (cron auto-runs it; admins can also force it).
app.post('/admin/payroll/generate', async (c) => {
  if (!isFinanceExec(c)) return c.json({ error: 'forbidden' }, 403);
  const b: any = await c.req.json().catch(() => null);
  const kind = b?.kind === 'monthly' ? 'monthly' : 'weekly';
  await generatePayroll(c.env, kind);
  return c.json({ ok: true, kind });
});

// Two-signature confirmation chain: admin confirms intent, superadmin releases
// the money (Lipila disbursement to the rider's registered momo). The payout
// row is mtime-stamped at each step so the proof receipt shows both hands.
app.post('/admin/payroll/:id/confirm', async (c) => {
  const phone = c.get('phone');
  if (!isAdmin(c)) return c.json({ error: 'forbidden' }, 403);
  const id = Number(c.req.param('id'));
  const row = await c.env.DB.prepare(`SELECT * FROM rider_payroll WHERE id = ?1`).bind(id).first<any>();
  if (!row) return c.json({ error: 'payout_not_found' }, 404);
  if (row.status === 'pending') {
    // Step 1: admin intent recorded. Also workable via the admin key header.
    const adminIdentity = phone ?? 'admin-key';
    if (isSuperAdmin(c) && phone) {
      // The owner alone may collapse both steps in one go (small team reality),
      // but the receipt still records both confirmations explicitly.
      const disbRef = `payroll-${row.id}-${Date.now().toString(36)}`;
      const disb = await lipilaDisburse(c.env, row.rider_phone, row.amount_zmw, disbRef, `DropOff rider payroll ${row.period_kind} ${row.period_start}`);
      await c.env.DB.prepare(
        `UPDATE rider_payroll SET status = ?2, admin_confirm_by = ?3, admin_confirm_at = datetime('now'),
            confirmed_by = ?3, confirmed_at = datetime('now'),
            lipila_reference = ?4, paid_at = CASE WHEN ?5 = 1 THEN datetime('now') ELSE paid_at END,
            note = COALESCE(?6, note) WHERE id = ?1`,
      ).bind(id, disb.ok ? 'paid' : 'failed', adminIdentity, disb.lipilaReference ?? disbRef, disb.ok ? 1 : 0,
        disb.ok ? null : `Lipila disbursement failed: ${String(disb.raw ?? '').slice(0, 200)}`).run();
      return c.json({ ok: true, status: disb.ok ? 'paid' : 'failed', owner_collapsed: true });
    }
    await c.env.DB.prepare(
      `UPDATE rider_payroll SET status = 'admin_confirmed', admin_confirm_by = ?2, admin_confirm_at = datetime('now') WHERE id = ?1`,
    ).bind(id, adminIdentity).run();
    return c.json({ ok: true, status: 'admin_confirmed', next: 'awaiting superadmin confirmation' });
  }
  if (row.status === 'admin_confirmed') {
    if (!isSuperAdmin(c)) return c.json({ error: 'superadmin_required' }, 403);
    const disbRef = `payroll-${row.id}-${Date.now().toString(36)}`;
    const disb = await lipilaDisburse(c.env, row.rider_phone, row.amount_zmw, disbRef, `DropOff rider payroll ${row.period_kind}`);
    await c.env.DB.prepare(
      `UPDATE rider_payroll SET status = ?2, confirmed_by = ?3, confirmed_at = datetime('now'),
          lipila_reference = ?4, paid_at = CASE WHEN ?5 = 1 THEN datetime('now') ELSE paid_at END,
          note = COALESCE(?6, note) WHERE id = ?1`,
    ).bind(id, disb.ok ? 'paid' : 'failed', c.get('phone') ?? 'admin-key', disb.lipilaReference ?? disbRef,
      disb.ok ? 1 : 0, disb.ok ? null : `Lipila disbursement failed: ${String(disb.raw ?? '').slice(0, 200)}`).run();
    return c.json({ ok: true, status: disb.ok ? 'paid' : 'failed' });
  }
  return c.json({ error: 'invalid_state', status: row.status }, 409);
});

// Superadmin can void a mis-generated row before it's paid.
app.post('/admin/payroll/:id/void', async (c) => {
  if (!isSuperAdmin(c)) return c.json({ error: 'superadmin_required' }, 403);
  const id = Number(c.req.param('id'));
  const res = await c.env.DB.prepare(
    `UPDATE rider_payroll SET status = 'void', confirmed_by = ?2, confirmed_at = datetime('now')
      WHERE id = ?1 AND status IN ('pending', 'admin_confirmed', 'failed')`,
  ).bind(id, c.get('phone') ?? 'admin-key').run();
  if (!res.meta.changes) return c.json({ error: 'not_voidable' }, 409);
  return c.json({ ok: true });
});

/** Downloadable proof-of-payment receipt (HTML, prints to PDF from any browser). */
function payrollProofHtml(row: any): string {
  const esc = (v: unknown) => String(v ?? '').replace(/[&<>"]/g, (ch) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[ch] as string));
  const status = String(row.status ?? '').toUpperCase();
  return `<!doctype html><html><head><meta charset="utf-8"><title>DropOff payout proof #${esc(row.id)}</title>
<style>body{font-family:-apple-system,Segoe UI,Roboto,sans-serif;margin:32px;color:#10201a}h1{font-size:20px;margin:0 0 4px}table{border-collapse:collapse;width:100%;margin-top:16px}td,th{border:1px solid #cfd8d3;padding:8px 10px;font-size:13px;text-align:left}th{background:#eef5f1}big{font-size:22px;font-weight:800}.ok{color:#0a7a3d}.bad{color:#a33}</style></head><body>
<h1>DropOff — Proof of Payment / Recu de Paie</h1>
<p>Rider payroll · generated ${esc(new Date().toISOString())} (CAT +2)</p>
<table>
<tr><th>Rider</th><td>${esc(row.rider_name ?? '')} · ${esc(row.rider_phone)}</td></tr>
<tr><th>Period</th><td>${esc(row.period_kind)} ${esc(row.period_start)} → ${esc(row.period_end)}</td></tr>
<tr><th>Base wage (pace-gated)</th><td>K${esc(Number(row.base_zmw ?? 0).toFixed(2))}</td></tr>
<tr><th>Fuel allowance (pace-gated)</th><td>K${esc(Number(row.fuel_zmw ?? 0).toFixed(2))}</td></tr>
<tr><th>Trips completed / target</th><td>${esc(row.trips ?? 0)} / ${esc(row.period_target ?? 0)}${Number(row.pace_met ?? 0) ? ' (on pace)' : ' (below pace — pro-rated)'}</td></tr>
<tr><th><b>Total paid</b></th><td><big>K${esc(Number(row.amount_zmw ?? 0).toFixed(2))}</big></td></tr>
<tr><th>Status</th><td class="${status === 'PAID' ? 'ok' : 'bad'}">${esc(status)}</td></tr>
<tr><th>1st confirmation (admin)</th><td>${esc(row.admin_confirm_by ?? '—')} at ${esc(row.admin_confirm_at ?? '—')}</td></tr>
<tr><th>2nd confirmation (superadmin)</th><td>${esc(row.confirmed_by ?? '—')} at ${esc(row.confirmed_at ?? '—')}</td></tr>
<tr><th>Disbursement reference</th><td>${esc(row.lipila_reference ?? '—')} (Lipila → ${esc(row.rider_phone)} mobile money)</td></tr>
<tr><th>Paid at</th><td>${esc(row.paid_at ?? '—')}</td></tr>
<tr><th>Note</th><td>${esc(row.note ?? '—')}</td></tr>
</table>
<p style="color:#5a6b63;font-size:11px">DropOff (depot-to-door courier, Zambia). This receipt is generated from the payroll ledger and reflects the state above at generation time.</p>
</body></html>`;
}

app.get('/admin/payroll/:id/proof', async (c) => {
  const id = Number(c.req.param('id'));
  const row = await c.env.DB.prepare(`SELECT * FROM rider_payroll WHERE id = ?1`).bind(id).first<any>();
  if (!row) return c.json({ error: 'payout_not_found' }, 404);
  if (!isFinanceExec(c) && c.get('phone') !== row.rider_phone) return c.json({ error: 'forbidden' }, 403);
  return new Response(payrollProofHtml(row), {
    status: 200,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Content-Disposition': `attachment; filename="DropOff-payout-${row.id}-${String(row.period_kind ?? '').slice(0, 6)}.html"`,
    },
  });
});

// A rider can see their own payroll history + proof links in the app.
app.get('/rider/payroll', async (c) => {
  const phone = c.get('phone');
  if (!phone) return c.json({ error: 'sign_in_required' }, 401);
  const { results } = await c.env.DB.prepare(
    `SELECT id, period_kind, period_start, period_end, base_zmw, fuel_zmw, trips,
            period_target, pace_met, amount_zmw, status, paid_at, lipila_reference, note
       FROM rider_payroll WHERE rider_phone = ?1 ORDER BY id DESC LIMIT 52`,
  ).bind(phone).all();
  return c.json({ payouts: results ?? [] });
});

/* --------------------------- tax endpoints (ZRA) -------------------------- */
app.get('/admin/tax', async (c) => {
  if (!isFinanceExec(c)) return c.json({ error: 'forbidden' }, 403);
  const { results } = await c.env.DB.prepare(`SELECT * FROM tax_periods ORDER BY year_month DESC LIMIT 24`).all();
  return c.json({ periods: results ?? [] });
});

// Manual refresh (cron keeps it current automatically; admins can force it).
app.post('/admin/tax/refresh', async (c) => {
  if (!isFinanceExec(c)) return c.json({ error: 'forbidden' }, 403);
  const b: any = await c.req.json().catch(() => null);
  const ym = b?.year_month ?? catYm(catNow(), 1);
  await updateTaxPeriod(c.env, String(ym).slice(0, 7));
  return c.json({ ok: true, year_month: ym });
});

app.post('/admin/tax/:ym/mark', async (c) => {
  if (!isFinanceExec(c)) return c.json({ error: 'forbidden' }, 403);
  const ym = c.req.param('ym').slice(0, 7);
  const b: any = await c.req.json().catch(() => null);
  const status = b?.status;
  if (!['submitted', 'paid'].includes(status)) return c.json({ error: 'status must be submitted|paid' }, 400);
  const res = await c.env.DB.prepare(
    `UPDATE tax_periods SET status = ?2, submitted_by = ?3, submitted_note = ?4,
        paid_at = CASE WHEN ?2 = 'paid' THEN datetime('now') ELSE paid_at END,
        updated_at = datetime('now') WHERE year_month = ?1`,
  ).bind(ym, status, c.get('phone') ?? 'admin-key', String(b?.note ?? '').slice(0, 300)).run();
  if (!res.meta.changes) return c.json({ error: 'period_not_found' }, 404);
  return c.json({ ok: true });
});

/** Printable ZRA turnover-tax return sheet (HTML → download/print-to-PDF). */
function taxReportHtml(p: any): string {
  const esc = (v: unknown) => String(v ?? '').replace(/[&<>"]/g, (ch) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[ch] as string));
  const lines = (() => { try { return JSON.parse(p.breakdown ?? '{}') as Record<string, number>; } catch { return {}; } })();
  const row = (k: string, v: number | string) => `<tr><th>${esc(k)}</th><td>${typeof v === 'number' ? 'K' + v.toFixed(2) : esc(v)}</td></tr>`;
  return `<!doctype html><html><head><meta charset="utf-8"><title>DropOff TOT ${esc(p.year_month)}</title>
<style>body{font-family:-apple-system,Segoe UI,Roboto,sans-serif;margin:32px;color:#10201a}h1{font-size:20px}table{border-collapse:collapse;width:100%;margin-top:12px}td,th{border:1px solid #cfd8d3;padding:8px 10px;font-size:13px;text-align:left}th{background:#eef5f1;white-space:nowrap}big{font-size:22px;font-weight:800}</style></head><body>
<h1>DropOff — ZRA Turnover Tax working sheet · ${esc(p.year_month)}</h1>
<p>Regime: micro/small business turnover tax, annual turnover ≤ K5,000,000. Rates per ZRA 2026: 0% up to K2,500 monthly turnover; 5% of gross monthly turnover above the band. Due by the <b>14th of the following month</b>. Keep records 6 years.</p>
<table>
${row('Gross turnover (components below)', Number(p.gross_turnover_zmw ?? 0))}
${row('· momo job collections', lines.job_collections ?? 0)}
${row('· float-settled DropOff legs (legacy)', lines.wallet_jobs ?? 0)}
${row('· subscriptions & upgrades', lines.subscriptions ?? 0)}
${row('· reward/legacy COD cut (historical)', lines.cod_platform_cut ?? 0)}
${row('0% band applied', `K${Number(p.zero_band_zmw ?? 0).toFixed(2)} of K${TOT_MONTHLY_ZERO_BAND_ZMW}`)}
${row('Taxable turnover', Number(p.taxable_zmw ?? 0))}
${row('Rate', `${((Number(p.rate ?? 0)) * 100).toFixed(1)}%`)}
${row('TAX DUE', Number(p.tax_zmw ?? 0))}
${row('Due date', p.due_date ?? '')}
${row('Status', String(p.status ?? '').toUpperCase())}
${row('Paid at', p.paid_at ?? '—')}
</table>
<p style="color:#5a6b63;font-size:11px">Generated ${esc(new Date().toISOString().slice(0, 16).replace('T', ' '))} from the DropOff main ledger. Excludes courier-partner counter fares (paid at depot) and customer prepayments (single-purpose delivery credit, recognised when spent on jobs per docs/PAYMENT_COMPLIANCE.md).</p>
</body></html>`;
}

app.get('/admin/tax/:ym/report', async (c) => {
  if (!isFinanceExec(c)) return c.json({ error: 'forbidden' }, 403);
  const ym = c.req.param('ym').slice(0, 7);
  const p = await c.env.DB.prepare(`SELECT * FROM tax_periods WHERE year_month = ?1`).bind(ym).first<any>();
  if (!p) return c.json({ error: 'period_not_found' }, 404);
  return new Response(taxReportHtml(p), {
    status: 200,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Content-Disposition': `attachment; filename="DropOff-TOT-${ym}.html"`,
    },
  });
});

/* ------------------------ rider docs: uploads + media ---------------------- */
// Photos (driver selfie, NRC, licence, number plate) live in the existing R2
// bucket under uploads/ and are served through an authenticated /media route -
// never public. Used by rider onboarding and admin verification.
const MAX_UPLOAD_BYTES = 6 * 1024 * 1024;
const UPLOAD_TYPES: Record<string, string> = {
  'image/jpeg': 'jpg', 'image/jpg': 'jpg', 'image/png': 'png',
  'image/webp': 'webp', 'image/heic': 'heic', 'image/heif': 'heif',
};

app.post('/uploads', async (c) => {
  if (!c.get('phone') && !isAdmin(c) && c.get('role') !== 'ops') return c.json({ error: 'sign_in_required' }, 401);
  if (!c.env.BACKUPS) return c.json({ error: 'uploads_not_configured' }, 503);
  let form: FormData;
  try { form = await c.req.formData(); } catch { return c.json({ error: 'multipart_required' }, 400); }
  // 'kyc' = identity/KYC documents (staff + the uploading rider only);
  // 'selfie' = the rider's face for sellers to see (any signed-in user).
  // Missing kind defaults to the PRIVATE one - never leak docs by accident.
  const kind = String((form as any).get?.('kind') ?? '') === 'selfie' ? 'selfie' : 'kyc';
  const file = form.get('file');
  if (!(file instanceof File)) return c.json({ error: 'file_required' }, 400);
  if (file.size <= 0 || file.size > MAX_UPLOAD_BYTES) return c.json({ error: 'file_too_large', max_mb: 6 }, 400);
  let type = String(file.type || '').toLowerCase();
  let ext = UPLOAD_TYPES[type];
  if (!ext) {
    // Some mobile multipart clients send application/octet-stream; trust a
    // known image extension from the filename instead of rejecting the photo.
    const nameExt = String(file.name || '').split('.').pop()?.toLowerCase() ?? '';
    if (['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'].includes(nameExt)) {
      ext = nameExt === 'jpeg' ? 'jpg' : nameExt;
      type = `image/${nameExt === 'jpg' ? 'jpeg' : nameExt}`;
    }
  }
  if (!ext) return c.json({ error: 'unsupported_image_type', allowed: Object.keys(UPLOAD_TYPES) }, 400);
  // Selfies go under uploads/selfie/; KYC documents under uploads/kyc/<phone>/ so
  // /media can enforce staff-or-owner access by key prefix alone.
  const callerPhone = c.get('phone') ?? 'staff';
  const key = kind === 'selfie'
    ? `uploads/selfie/${crypto.randomUUID()}.${ext}`
    : `uploads/kyc/${callerPhone}/${crypto.randomUUID()}.${ext}`;
  const bytes = await file.arrayBuffer();
  if (!looksLikeImage(new Uint8Array(bytes), ext)) {
    return c.json({ error: 'file_not_an_image' }, 400);
  }
  // Force a safe image content-type regardless of what the client sent.
  const safeType = `image/${ext === 'jpg' ? 'jpeg' : ext}`;
  await c.env.BACKUPS.put(key, bytes, { httpMetadata: { contentType: safeType } });
  return c.json({ ok: true, key, url: `/media/${key}` });
});

app.get('/media/*', async (c) => {
  if (!c.get('phone') && !isAdmin(c) && c.get('role') !== 'ops') return c.json({ error: 'sign_in_required' }, 401);
  if (!c.env.BACKUPS) return c.json({ error: 'uploads_not_configured' }, 503);
  const key = decodeURIComponent(c.req.path.replace(/^\/media\//, ''));
  if (!key) return c.json({ error: 'key_required' }, 400);
  // Prefix rules - see /uploads:
  //   uploads/selfie/<uuid>              any signed-in user (sellers track their parcel)
  //   uploads/kyc/<phone>/<uuid>         staff OR that phone (the rider's own docs)
  //   anything else under uploads/       staff only (legacy root keys, POD photos)
  if (key.startsWith('uploads/selfie/')) {
    // any signed-in identity - still no anonymous access
  } else if (key.startsWith('uploads/kyc/')) {
    const owner = key.split('/')[2] ?? '';
    if (c.get('phone') !== owner && !isAdmin(c) && c.get('role') !== 'ops') {
      // Parcel-evidence sharing (owner directive 2026-11-17): the SELLER's
      // booking photo and the RIDER's drop photo are stored under
      // uploads/kyc/<uploader>/<uuid> — the other side of that job must see
      // them so the photo comparison works end-to-end. Authorization =
      // participant of a job that references this exact key.
      const linked = await c.env.DB.prepare(
        `SELECT j.sender_phone, r.phone AS rider_phone
           FROM jobs j LEFT JOIN riders r ON r.id = j.rider_id
          WHERE j.parcel_photo_url = ?1 OR j.dropoff_photo_url = ?1
             OR j.pod_pickup_url = ?1 OR j.pod_delivery_url = ?1 LIMIT 1`,
      ).bind(`/media/${key}`).first<any>();
      const participant = !!linked
        && (linked.sender_phone === c.get('phone') || linked.rider_phone === c.get('phone'));
      if (!participant) {
        return c.json({ error: 'kyc_media_staff_only' }, 403);
      }
    }
  } else {
    if (!isAdmin(c) && c.get('role') !== 'ops') {
      return c.json({ error: 'kyc_media_staff_only' }, 403);
    }
  }
  const object = await c.env.BACKUPS.get(key);
  if (!object) return c.json({ error: 'not_found' }, 404);
  return new Response(object.body, {
    headers: {
      'Content-Type': object.httpMetadata?.contentType ?? 'application/octet-stream',
      'Cache-Control': 'private, max-age=3600',
    },
  });
});

/* ---------------------- rider onboarding (ID / vehicle) -------------------- */
// A rider submits their own NRC, licence, plate, vehicle details and photos;
// the record flips to 'pending' and the owner/admins approve or reject it.
app.get('/rider/profile', async (c) => {
  const phone = c.get('phone');
  if (!phone) return c.json({ error: 'sign_in_required' }, 401);
  if (c.get('role') !== 'rider' && !isAdmin(c)) return c.json({ error: 'forbidden' }, 403);
  // Rejected riders are inactive (blocked from jobs) but MUST still see their
  // REJECTED card + reviewer note — otherwise the app lies with a blank state
  // and the rider can never fix what was wrong.
  const rider = await c.env.DB.prepare(
    `SELECT ${riderDocSelect()} FROM riders WHERE phone = ?1 AND (active = 1 OR verification_status = 'rejected')`,
  ).bind(phone).first<any>();
  if (!rider) return c.json({ error: 'rider_not_found' }, 404);
  const prog = await incentiveProgramme(c.env);
  const targets = await riderTargetStats(c.env.DB, rider.id, prog);
  return c.json({ rider, targets: targets.get(rider.id) ?? shapeTargets(0, 0) });
});

app.post('/rider/profile', async (c) => {
  const phone = c.get('phone');
  if (!phone) return c.json({ error: 'sign_in_required' }, 401);
  if (c.get('role') !== 'rider') return c.json({ error: 'rider_only' }, 403);
  const rider = await c.env.DB.prepare(
    'SELECT id, phone, full_name, verification_status FROM riders WHERE phone = ?1',
  ).bind(phone).first<any>();
  if (!rider) return c.json({ error: 'rider_not_found' }, 404);
  const b: any = await c.req.json().catch(() => null);
  if (!b) return c.json({ error: 'invalid JSON body' }, 400);
  const clean = (v: unknown, max = 120) => String(v ?? '').trim().slice(0, max);
  const nrc = clean(b.nrc_number, 40).toUpperCase();
  const plate = clean(b.plate_number, 20).toUpperCase().replace(/\s+/g, ' ');
  const vehicleMake = clean(b.vehicle_make, 60);
  const photo = clean(b.photo_url, 300);
  const nrcPhoto = clean(b.nrc_photo_url, 300);
  const platePhoto = clean(b.plate_photo_url, 300);
  if (nrc.length < 6) return c.json({ error: 'nrc_required' }, 400);
  if (plate.length < 3) return c.json({ error: 'plate_required' }, 400);
  if (!vehicleMake) return c.json({ error: 'vehicle_make_required' }, 400);
  if (!photo || !nrcPhoto || !platePhoto) return c.json({ error: 'photos_required', detail: 'Selfie, NRC photo and plate photo are required.' }, 400);
  await c.env.DB.prepare(
    `UPDATE riders SET nrc_number = ?2, license_number = ?3, plate_number = ?4,
        vehicle_make = ?5, vehicle_color = ?6, photo_url = ?7, nrc_photo_url = ?8,
        license_photo_url = ?9, plate_photo_url = ?10,
        verification_status = 'pending', verification_note = NULL,
        submitted_at = datetime('now'), verified_by = NULL, verified_at = NULL,
        ai_check_json = NULL,
        active = 1
      WHERE id = ?1`,
  ).bind(
    rider.id, nrc, clean(b.license_number, 40).toUpperCase() || null, plate,
    vehicleMake, clean(b.vehicle_color, 40) || null, photo, nrcPhoto,
    clean(b.license_photo_url, 300) || null, platePhoto,
  ).run();
  // Re-applying re-opens the pipeline: a rejected (inactive) rider who fixes
  // their documents goes back to PENDING and shows up in the admin queue again
  // instead of hitting a permanent rider_not_found dead end.
  // Sync the submission to everyone who verifies it — never rely on someone
  // happening to open the admin queue (owner directive 2026-11-17).
  try {
    const owner = ownerPhone(c.env);
    const staff = await c.env.DB.prepare(
      `SELECT phone FROM auth_users WHERE role IN ('admin', 'ops') AND phone IS NOT NULL AND phone <> ''`,
    ).all<any>();
    const phones = new Set<string>([
      ...(owner ? [owner] : []),
      ...((staff.results ?? []) as any[]).map((r) => String(r.phone).trim()).filter((p) => p !== ''),
    ]);
    const name = String(rider.full_name ?? 'A driver');
    for (const p of phones) {
      try {
        await sendToPhone(c.env, p, {
          title: 'Driver verification waiting',
          body: `${name} submitted NRC/licence/plate documents — review in Admin → Driver verification & targets.`,
          data: { kind: 'rider_kyc', rider_id: rider.id },
        });
      } catch { /* one dead token must not stop the rest */ }
    }
    if (owner) {
      await sendSms(c.env, owner,
        `DropOff: driver verification submitted by ${name} (${String(rider.phone ?? '')}). Review it in the admin queue.`, { transactional: true });
    }
  } catch { /* best-effort — submission already saved */ }
  return c.json({ ok: true, verification_status: 'pending' });
});

/* ---------------------- rider daily / monthly targets ---------------------- */
app.get('/rider/targets', async (c) => {
  const phone = c.get('phone');
  if (!phone) return c.json({ error: 'sign_in_required' }, 401);
  if (c.get('role') !== 'rider' && !isAdmin(c)) return c.json({ error: 'forbidden' }, 403);
  const rider = await c.env.DB.prepare(
    'SELECT id, full_name FROM riders WHERE phone = ?1 AND active = 1',
  ).bind(phone).first<any>();
  if (!rider) return c.json({ error: 'rider_not_found' }, 404);
  const prog = await incentiveProgramme(c.env);
  const targets = await riderTargetStats(c.env.DB, rider.id, prog);
  const t = targets.get(rider.id) ?? shapeTargets(0, 0);
  return c.json({
    rider: { id: rider.id, name: rider.full_name },
    targets: t,
    // Pay band (K3,200/month inclusive of fuel) + pace gate: weekly pay needs
    // the week's sweep target met — see the pace line in targets.
    pay: {
      monthly_total_zmw: DRIVER_MONTHLY_PAY_ZMW,
      base_monthly_zmw: DRIVER_BASE_MONTHLY_ZMW,
      fuel_weekly_zmw: DRIVER_FUEL_ALLOWANCE_WEEKLY_ZMW,
      fuel_monthly_zmw: DRIVER_FUEL_MONTHLY_ZMW,
      daily_target: DRIVER_DAILY_TARGET,
      adjustable: (t.month >= t.pace_target) ? null : Math.max(0, t.pace_target - t.month),
    },
  });
});

/* ------------------ admin/owner: verify riders + fleet targets ------------ */
app.get('/admin/riders', async (c) => {
  // admin/ops can read the roster — it's the app's server-side source of
  // truth for the Team tab (written only via the admin-only POST above).
  if (!isAdmin(c) && c.get('role') !== 'ops') return c.json({ error: 'forbidden' }, 403);
  const limit = pageLimit(c.req.query('limit'));
  const { results } = await c.env.DB.prepare(
    `SELECT ${riderDocSelect()}, last_lat, last_lng, last_seen_at
       FROM riders ORDER BY
       CASE verification_status WHEN 'pending' THEN 0 WHEN 'rejected' THEN 1 ELSE 2 END,
       full_name COLLATE NOCASE
       LIMIT ?1`,
  ).bind(limit + 1).all<any>();
  const hasMore = results.length > limit;
  const page = hasMore ? results.slice(0, -1) : results;
  const prog = await incentiveProgramme(c.env);
  const targets = await riderTargetStats(c.env.DB, undefined, prog);
  const riders = ((page ?? []) as any[]).map((r) => ({
    ...r,
    targets: targets.get(Number(r.id)) ?? shapeTargets(0, 0),
  }));
  return c.json({
    riders,
    next_after: hasMore ? Number(page[page.length - 1]?.id ?? 0) : undefined,
    has_more: hasMore,
    pending: riders.filter((r) => r.verification_status === 'pending').length,
    verified: riders.filter((r) => r.verification_status === 'verified').length,
    daily_target: DRIVER_DAILY_TARGET,
  });
});

// Edit a rider's basic roster fields (admin/superadmin only). Verification/KYC
// status changes stay on the dedicated /verify and /ai-check endpoints.
app.patch('/admin/riders/:id', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'admin_required' }, 403);
  const id = Number(c.req.param('id'));
  if (!Number.isFinite(id) || id <= 0) return c.json({ error: 'bad_rider_id' }, 400);
  const existing = await c.env.DB.prepare(
    `SELECT id, phone, full_name, vehicle, vehicle_class, active, verification_status FROM riders WHERE id = ?1`,
  ).bind(id).first<any>();
  if (!existing) return c.json({ error: 'not_found' }, 404);
  const b: any = await c.req.json().catch(() => ({}));
  const fullName = b.full_name != null ? String(b.full_name).trim().slice(0, 120) : String(existing.full_name ?? '');
  const vehicle = b.vehicle != null ? String(b.vehicle).trim().slice(0, 80) : String(existing.vehicle ?? '');
  const vehicleClass = b.vehicle_class != null ? String(b.vehicle_class).trim().toLowerCase().slice(0, 30) : (existing.vehicle_class ?? 'motorcycle');
  const phone = b.phone != null ? normalizeZmPhone(String(b.phone)) : String(existing.phone ?? '');
  if (fullName.length < 2) return c.json({ error: 'full_name_required' }, 400);
  if (!phone) return c.json({ error: 'invalid_phone' }, 400);
  if (vehicle.length < 2) return c.json({ error: 'vehicle_required' }, 400);
  // active toggle is allowed here for roster management, but do not silently
  // "verify" a rider — verification remains explicit via /verify.
  const active = b.active != null ? (b.active ? 1 : 0) : Number(existing.active ?? 1);
  if (phone !== existing.phone) {
    const dup = await c.env.DB.prepare(`SELECT id FROM riders WHERE phone = ?1 AND id <> ?2`).bind(phone, id).first<any>();
    if (dup) return c.json({ error: 'phone_already_used' }, 409);
  }
  await c.env.DB.prepare(
    `UPDATE riders SET full_name = ?2, phone = ?3, vehicle = ?4, vehicle_class = ?5, active = ?6 WHERE id = ?1`,
  ).bind(id, fullName, phone, vehicle, vehicleClass, active).run();
  return c.json({ ok: true, id, full_name: fullName, phone, vehicle, vehicle_class: vehicleClass, active: !!active });
});

// Conditional, gated deletion (admin/superadmin only). "Not easy": requires an
// explicit confirm flag and is blocked while the rider has open/assigned work.
app.delete('/admin/riders/:id', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'admin_required' }, 403);
  const id = Number(c.req.param('id'));
  if (!Number.isFinite(id) || id <= 0) return c.json({ error: 'bad_rider_id' }, 400);
  const b: any = await c.req.json().catch(() => ({}));
  if (b?.confirm !== true && b?.confirm !== 'DELETE') {
    return c.json({ error: 'confirm_required', detail: 'Pass {"confirm": true} to delete a rider. This is permanent for the roster record.' }, 400);
  }
  const existing = await c.env.DB.prepare(`SELECT id, full_name, phone, active FROM riders WHERE id = ?1`).bind(id).first<any>();
  if (!existing) return c.json({ error: 'not_found' }, 404);
  // Conditional: block deletion if rider has open/active jobs. Deactivate instead.
  const open = await c.env.DB.prepare(
    `SELECT COUNT(*) AS n FROM jobs
      WHERE rider_id = ?1
        AND COALESCE(status, '') NOT IN ('delivered','ready_for_collection','collected','cancelled','failed')`,
  ).bind(id).first<any>();
  const openJobs = Number(open?.n ?? 0);
  if (openJobs > 0) {
    return c.json({
      error: 'rider_has_open_jobs',
      detail: `Cannot delete: ${openJobs} open/assigned job(s) still reference this rider. Reassign or complete them, or deactivate the rider instead.`,
      open_jobs: openJobs,
    }, 409);
  }
  // Unassign any terminal-history references safely by nulling rider_id? Keep history intact:
  // we block open jobs; delivered history may still reference rider_id (FK-like usage) — use soft delete pattern?
  // To preserve history without FK issues, mark inactive and clear identity-like operational availability; hard delete roster row.
  // SQLite has no FK enforcement by default in D1 here; delivered rows keep rider_id as historical value. We null it to be clean.
  await c.env.DB.batch([
    c.env.DB.prepare(`UPDATE jobs SET rider_id = NULL WHERE rider_id = ?1`).bind(id),
    c.env.DB.prepare(`DELETE FROM riders WHERE id = ?1`).bind(id),
  ]);
  return c.json({ ok: true, deleted: true, id, name: existing.full_name });
});

// Soft-delete a booking: status='deleted' + audit event. Every normal queue /
// cron / dispatch query filters on status NOT IN (...) so the booking is
// invisible instantly, with payments & events retained for audit.
app.post('/admin/jobs/:ref/delete', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'admin_required' }, 403);
  const ref = String(c.req.param('ref') ?? '').trim();
  if (!ref) return c.json({ error: 'ref required' }, 400);
  const row = await c.env.DB.prepare(
    `SELECT id, ref, status FROM jobs WHERE ref = ?1`,
  ).bind(ref).first<any>();
  if (!row) return c.json({ error: 'not found' }, 404);
  await c.env.DB.batch([
    c.env.DB.prepare(`UPDATE jobs SET status = 'deleted' WHERE id = ?1`).bind(row.id),
    c.env.DB.prepare(`INSERT INTO job_events (job_id, status, note) VALUES (?1, 'admin_deleted', 'Booking deleted by admin')`).bind(row.id),
  ]);
  return c.json({ ok: true, ref: row.ref });
});

// Admin DELETE user (superadmin only): wipe the auth row, push tokens and
// device sessions so no session survives. Job history is kept (jobs have
// sender_phone referencing the phone) — this is a compliance de-listing, not
// a data shred. Refuses to delete the owner account.
app.delete('/admin/users/:phone', async (c) => {
  if (!isSuperAdmin(c)) return c.json({ error: 'superadmin_required' }, 403);
  const phone = String(c.req.param('phone') ?? '').trim();
  if (!phone) return c.json({ error: 'phone required' }, 400);
  if (phone === ownerPhone(c.env)) return c.json({ error: 'cannot_delete_owner' }, 403);
  const target = await c.env.DB.prepare(
    'SELECT phone FROM auth_users WHERE phone = ?1',
  ).bind(phone).first<any>();
  if (!target) return c.json({ error: 'not found' }, 404);
  const b: any = await c.req.json().catch(() => ({}));
  if (b?.confirm !== true && b?.confirm !== 'DELETE') {
    return c.json({ error: 'confirm_required', detail: 'Pass {"confirm": true} to delete a user.' }, 400);
  }
  await c.env.DB.batch([
    c.env.DB.prepare(`DELETE FROM auth_users WHERE phone = ?1`).bind(phone),
    c.env.DB.prepare(`DELETE FROM push_tokens WHERE phone = ?1`).bind(phone),
    c.env.DB.prepare(`DELETE FROM device_sessions WHERE phone = ?1`).bind(phone),
  ]);
  return c.json({ ok: true, deleted: true, phone });
});

app.post('/admin/riders/:id/verify', async (c) => {
  if (!isAdmin(c) && c.get('role') !== 'ops') return c.json({ error: 'admin_required' }, 403);
  const id = Number(c.req.param('id'));
  const b: any = await c.req.json().catch(() => null);
  const status = String(b?.status ?? '');
  if (!['verified', 'rejected'].includes(status)) return c.json({ error: 'status must be verified or rejected' }, 400);
  const note = String(b?.note ?? '').trim().slice(0, 500) || null;
  if (status === 'rejected' && !note) return c.json({ error: 'rejection_note_required' }, 400);
  const rider = await c.env.DB.prepare(
    `SELECT id, phone, full_name, verification_status, nrc_number, plate_number FROM riders WHERE id = ?1`,
  ).bind(id).first<any>();
  if (!rider) return c.json({ error: 'not found' }, 404);
  await c.env.DB.prepare(
    `UPDATE riders SET verification_status = ?2, verification_note = ?3,
        verified_by = ?4, verified_at = datetime('now'), active = ?5
      WHERE id = ?1`,
  ).bind(id, status, note, c.get('phone') ?? 'admin-key', status === 'verified' ? 1 : 0).run();
  // Close the loop (owner directive 2026-11-17): the rider learns the decision
  // the moment it is made — SMS always, push where a token exists. Verified
  // riders go straight back to earning; rejected riders know exactly what to
  // fix (the note is the same text their app card shows).
  const decision = status === 'verified'
    ? `DropOff: you are VERIFIED. Jobs can now assign you automatically. Welcome to the road${rider.full_name ? `, ${rider.full_name}` : ''}.`
    : `DropOff: verification not approved. Reason: ${note}. Update your documents in the app (Team tab > Driver verification) and re-submit.`;
  try { await sendSms(c.env, String(rider.phone ?? ''), decision, { transactional: true }); } catch { /* best-effort */ }
  try { await sendToPhone(c.env, String(rider.phone ?? ''), {
    title: status === 'verified' ? 'You are verified' : 'Verification declined',
    body: status === 'verified' ? 'Jobs can now assign you automatically.' : (note ?? ''),
    data: { kind: 'rider_verification', status },
  }); } catch { /* best-effort */ }
  return c.json({ ok: true, id, verification_status: status });
});

// AI assist (never the decision): read the plate photo and compare the text it
type FaceCheck = {
  face: boolean;
  single_person: boolean;
  real_photo: boolean;
  document_or_id: boolean;
  illustration_or_avatar: boolean;
  verdict: 'pass' | 'review' | 'fail';
  note: string;
  checked_at: string;
};

/** Workers AI vision review of a rider's selfie: is this a genuine, single
 *  real person (the rider) - not a document, screen photo, illustration,
 *  avatar or group shot? Strictly informational: admins still make the call. */
async function analyzeSelfieFace(env: Env, bytes: number[]): Promise<FaceCheck> {
  if (!env?.AI) {
    return { face: true, single_person: true, real_photo: true, document_or_id: false, illustration_or_avatar: false, verdict: 'review', note: 'AI selfie review unavailable — a human must judge.', checked_at: new Date().toISOString() };
  }
  const out: any = await runAi(env, '@cf/llava-hf/llava-1.5-7b-hf', {
    image: bytes,
    prompt: 'You review rider profile photos for a delivery app. Decide whether this is a genuine photograph of one real person (the rider themself). Answer with JSON ONLY: {"has_face":true|false,"single_person":true|false,"real_photo":true|false,"document_or_id":true|false,"illustration_or_avatar":true|false,"note":"<one short sentence>"}. Rules: a document/NRC/plate/licence photo, a photo of a screen or paper, a drawing/avatar/cartoon/logo/meme/no face at all, or a group photo => set the matching flag true and real_photo false. If unsure, say so honestly. No extra text.',
    max_tokens: 200,
  });
  if (!out) {
    return { face: true, single_person: true, real_photo: true, document_or_id: false, illustration_or_avatar: false, verdict: 'review', note: 'AI selfie review failed — retry once, otherwise a human must judge.', checked_at: new Date().toISOString() };
  }
  const raw = String(out?.response ?? out?.description ?? '').trim();
  const match = raw.match(/\{[\s\S]*\}/);
  let j: any = {};
  try { j = match ? JSON.parse(match[0]) : {}; } catch { j = {}; }
  const bool = (v: any) => v === true || String(v).toLowerCase() === 'true';
  const face = bool(j.has_face);
  const single = bool(j.single_person);
  const real = bool(j.real_photo);
  const doc = bool(j.document_or_id);
  const illus = bool(j.illustration_or_avatar);
  const ok = face && single && real && !doc && !illus;
  const verdict: FaceCheck['verdict'] = ok ? 'pass' : (face ? 'review' : 'fail');
  return {
    face, single_person: single, real_photo: real,
    document_or_id: doc, illustration_or_avatar: illus,
    verdict,
    note: String(j.note ?? raw).slice(0, 200),
    checked_at: new Date().toISOString(),
  };
}

/** AI assist: does the selfie depict the same person as the portrait on an ID
 *  document (licence, or NRC/permit when it carries one)? Single-image model
 *  calls (no multi-image input), then a text model compares the two
 *  descriptions. British: heuristic — the admin always decides. */
async function compareFaceToId(env: Env, selfieBytes: number[], portraitBytes: number[]): Promise<{
  same_person: 'yes' | 'uncertain' | 'no';
  confidence: 'high' | 'medium' | 'low';
  note: string;
}> {
  const describe = async (bytes: number[], hint: string) => {
    const out: any = await runAi(env, '@cf/llava-hf/llava-1.5-7b-hf', {
      image: bytes,
      prompt: `This is ${hint}. Describe this person's VISIBLE face as plainly as possible (gender presentation, apparent age range, hair style/colour, glasses, facial hair, skin tone, distinguishing marks). One sentence, no identity guesses, no comparisons yet.`,
      max_tokens: 120,
    });
    if (!out) return 'unavailable';
    return String(out?.response ?? out?.description ?? '').trim().slice(0, 300);
  };
  const selfieDesc = await describe(selfieBytes, "a rider's selfie");
  const idDesc = await describe(portraitBytes, 'the portrait on an ID document');
  const out: any = await runAi(env, '@cf/mistralai/mistral-small-3.1-24b-instruct', {
    messages: [
      { role: 'system', content: 'You compare two interview-grade facial descriptions for consistency. Be conservative: if either is vague, answer uncertain. Reply with JSON ONLY.' },
      { role: 'user', content: `Description A (selfie): ${selfieDesc}\nDescription B (ID portrait): ${idDesc}\nDecide if these likely depict the same person. Reply with JSON ONLY: {"same_person":"yes"|"uncertain"|"no","confidence":"high"|"medium"|"low","note":"<one short sentence>"}` },
    ],
    max_tokens: 120,
  });
  if (!out) {
    return { same_person: 'uncertain', confidence: 'low', note: 'AI comparison unavailable — admin must decide.' };
  }
  const raw = (typeof out?.response === 'string' ? out.response
    : (typeof out?.choices?.[0]?.message?.content === 'string' ? out.choices[0].message.content : '')).trim();
  const m = raw.match(/\{[\s\S]*\}/);
  let j: any = {};
  try { j = m ? JSON.parse(m[0]) : {}; } catch { j = {}; }
  const sp = String(j.same_person ?? 'uncertain').toLowerCase();
  const same_person = sp === 'yes' || sp === 'no' ? sp : 'uncertain';
  const confidence = (['high', 'medium', 'low'] as const).includes(String(j.confidence) as 'high' | 'medium' | 'low') ? (String(j.confidence) as 'high' | 'medium' | 'low') : 'low';
  return {
    same_person, confidence,
    note: String(j.note ?? `selfie: ${selfieDesc} | id: ${idDesc}`).slice(0, 220),
  };
}

/** Merge-or-write the face check into ai_check_json on the rider row. */
async function persistFaceCheck(db: D1Database, riderId: number, face: FaceCheck): Promise<void> {
  const row = await db.prepare('SELECT ai_check_json FROM riders WHERE id = ?1').bind(riderId).first<any>();
  let blob: any = {};
  try { blob = row?.ai_check_json ? JSON.parse(String(row.ai_check_json)) : {}; } catch { blob = {}; }
  blob.face = face;
  await db.prepare('UPDATE riders SET ai_check_json = ?2 WHERE id = ?1')
    .bind(riderId, JSON.stringify(blob)).run().catch(() => {});
}

// finds with the rider's submitted plate/NRC. Admins still approve manually.
app.post('/admin/riders/:id/ai-check', async (c) => {
  if (!isAdmin(c) && c.get('role') !== 'ops') return c.json({ error: 'admin_required' }, 403);
  const id = Number(c.req.param('id'));
  const rider = await c.env.DB.prepare(
    `SELECT id, plate_number, nrc_number, plate_photo_url, nrc_photo_url, license_photo_url, photo_url FROM riders WHERE id = ?1`,
  ).bind(id).first<any>();
  if (!rider) return c.json({ error: 'not found' }, 404);
  if (!c.env.AI) return c.json({ error: 'ai_unavailable' }, 503);
  if (!c.env.BACKUPS) return c.json({ error: 'uploads_not_configured' }, 503);
  const key = r2KeyFromUrl(rider.plate_photo_url) ?? r2KeyFromUrl(rider.nrc_photo_url);
  if (!key) return c.json({ error: 'no_document_photo' }, 400);
  const object = await c.env.BACKUPS.get(key);
  if (!object) return c.json({ error: 'photo_missing' }, 404);
  const bytes = [...new Uint8Array(await object.arrayBuffer())];
  let text = '';
  const out: any = await runAi(c.env, '@cf/llava-hf/llava-1.5-7b-hf', {
    image: bytes,
    prompt: 'This is a photo of a vehicle number plate or a Zambian NRC. Transcribe every visible character exactly (letters, digits, slashes, spaces). Output only the transcribed text.',
    max_tokens: 120,
  });
  if (!out) {
    return c.json({ error: 'ai_unavailable', detail: 'Vision call produced no output. Check `wrangler tail` for workers_ai logs.' }, 503);
  }
  text = String(out?.response ?? out?.description ?? '').trim().slice(0, 500);
  const norm = (s: string) => s.toUpperCase().replace(/[^A-Z0-9]/g, '');
  const found = norm(text);
  const plateMatch = !!rider.plate_number && found.includes(norm(String(rider.plate_number)));
  const nrcMatch = !!rider.nrc_number && found.includes(norm(String(rider.nrc_number)));
  // Selfie face review rides the same button: one AI pass for the whole KYC.
  let face: FaceCheck | null = null;
  let selfieBytesLocal: number[] | null = null;
  const selfieKey = rider.photo_url ? r2KeyFromUrl(rider.photo_url) : null;
  if (selfieKey) {
    const selfie = await c.env.BACKUPS.get(selfieKey).catch(() => null);
    if (selfie) {
      selfieBytesLocal = [...new Uint8Array(await selfie.arrayBuffer())];
      try { face = await analyzeSelfieFace(c.env, selfieBytesLocal); }
      catch { face = null; }
    }
  }
  // Face-vs-portrait match: selfie vs the portrait on the licence (or the NRC
  // when it carries one). AI assist only - the admin still approves.
  let faceMatch: { same_person: 'yes' | 'uncertain' | 'no'; confidence: 'high' | 'medium' | 'low'; note: string } | null = null;
  const portraitKey = r2KeyFromUrl(rider.license_photo_url) ?? r2KeyFromUrl(rider.nrc_photo_url);
  if (portraitKey && selfieBytesLocal) {
    const portrait = await c.env.BACKUPS.get(portraitKey).catch(() => null);
    if (portrait) {
      try { faceMatch = await compareFaceToId(c.env, selfieBytesLocal, [...new Uint8Array(await portrait.arrayBuffer())]); }
      catch { faceMatch = null; }
    }
  }
  const result = { text, plate_match: plateMatch, nrc_match: nrcMatch, face, face_match: faceMatch, checked_at: new Date().toISOString() };
  await c.env.DB.prepare('UPDATE riders SET ai_check_json = ?2 WHERE id = ?1')
    .bind(id, JSON.stringify(result)).run().catch(() => {});
  return c.json({ ok: true, ...result, submitted_plate: rider.plate_number, submitted_nrc: rider.nrc_number });
});

// Rider adds JUST their selfie (grandfathered verified riders keep their
// standing). The photo is AI-reviewed inline: a clear 'fail' (not one real
// person) demotes a verified rider back to pending until an admin re-checks -
/** Shared selfie-apply for the two ways a selfie can be linked:
 *   POST /me/photo     - any signed-in user (riders, sellers, recipients, admins)
 *   POST /rider/photo  - rider alias kept for 0.4.1 clients
 * One behaviour, two doors: auth_users.photo_url (and riders.photo_url when the
 * caller is an active rider; KYC documents untouched). Inline AI review; a clear
 * fail demotes a VERIFIED rider to pending. A clear pass keeps verified standing. */
async function applySelfie(c: any, rawUrl: unknown) {
  const phone = c.get('phone');
  if (!phone) return c.json({ error: 'sign_in_required' }, 401);
  const url = String(rawUrl ?? '').trim();
  const m = /^\/media\/uploads\/selfie\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|jpeg|png|webp|heic|heif)$/i
    .exec(url);
  if (!m) return c.json({ error: 'bad_photo_url', detail: 'Upload the selfie first, then link it here.' }, 400);
  const key = url.replace(/^\/media\//, '');
  if (!c.env.BACKUPS) return c.json({ error: 'uploads_not_configured' }, 503);
  const object = await c.env.BACKUPS.get(key);
  if (!object) return c.json({ error: 'photo_missing' }, 404);
  let verdict: FaceCheck['verdict'] | 'skipped' = 'skipped';
  let face: FaceCheck | null = null;
  if (c.env.AI) {
    try {
      face = await analyzeSelfieFace(c.env, [...new Uint8Array(await object.arrayBuffer())]);
      verdict = face.verdict;
    } catch {
      verdict = 'skipped'; // AI down: keep the photo, let a human decide
    }
  }
  const db = c.env.DB as D1Database;
  // Rider row? Apply to riders.photo_url too (sellers see this one).
  const rider = await db.prepare(
    'SELECT id, verification_status FROM riders WHERE phone = ?1 AND active = 1',
  ).bind(phone).first<any>();
  if (rider && face) await persistFaceCheck(db, rider.id, face);
  // IMMUTABILITY OF VERIFIED IDENTITY (owner directive 2026-11-15): a verified
  // rider may NOT silently swap the selfie admins approved — any change drops
  // them to pending re-review, exactly like re-uploading the KYC documents.
  // Pre-fix: demotion was only on AI fail, so a judged "pass" selfie swap
  // stayed dispatchable with a different face.
  const demote = Boolean(rider) && rider.verification_status === 'verified';
  if (rider) {
    await db.prepare(
      `UPDATE riders SET photo_url = ?2, submitted_at = datetime('now'),
          verification_status = CASE WHEN ?3 THEN 'pending' ELSE verification_status END,
          verification_note = CASE WHEN ?3 THEN 'Selfie changed after approval — re-verify before assignment.' ELSE NULL END,
          verified_by = CASE WHEN ?3 THEN NULL ELSE verified_by END,
          verified_at = CASE WHEN ?3 THEN NULL ELSE verified_at END
        WHERE id = ?1`,
    ).bind(rider.id, url, demote ? 1 : 0).run();
  }
  await c.env.DB.prepare('UPDATE auth_users SET photo_url = ?2 WHERE phone = ?1')
    .bind(phone, url).run().catch(() => {}); // OTP-only riders have no auth_users row
  return {
    ok: true as const, verdict, demote,
    rider: rider ? { verification_status: demote ? 'pending' : rider.verification_status } : null,
    verification_status: rider ? (demote ? 'pending' : rider.verification_status) : null,
    photo_url: url,
    detail: demote
      ? 'Your selfie changed after approval — an admin must re-verify you before assignments resume. A verified rider’s photo is frozen evidence, never silently swappable.'
      : 'Photo saved.',
  };
}

// pass/review keep the current status. Never touches KYC documents.
app.post('/rider/photo', async (c) => {
  if (c.get('role') !== 'rider') return c.json({ error: 'rider_only' }, 403);
  const rider = await c.env.DB.prepare(
    'SELECT id FROM riders WHERE phone = ?1 AND active = 1',
  ).bind(c.get('phone') ?? '').first<any>();
  if (!rider) return c.json({ error: 'rider_not_found' }, 404);
  const b: any = await c.req.json().catch(() => null);
  const r = await applySelfie(c, b?.photo_url);
  return r instanceof Response ? r : c.json(r);
});

// ANY signed-in user sets their profile photo (upload via kind=selfie first).
// Riders get the same inline AI review as /rider/photo (sellers see it).
app.post('/me/photo', async (c) => {
  const b: any = await c.req.json().catch(() => null);
  const r = await applySelfie(c, b?.photo_url);
  return r instanceof Response ? r : c.json(r);
});

// Remove the caller's profile photo (back to initials).
app.delete('/me/photo', async (c) => {
  const phone = c.get('phone');
  if (!phone) return c.json({ error: 'sign_in_required' }, 401);
  await c.env.DB.batch([
    c.env.DB.prepare('UPDATE auth_users SET photo_url = NULL WHERE phone = ?1').bind(phone),
    c.env.DB.prepare('UPDATE riders SET photo_url = NULL WHERE phone = ?1 AND active = 1').bind(phone),
  ]);
  return c.json({ ok: true });
});

/* ---- recipient door PIN (owner 2026-11-18) ------------------------------- */
// A registered recipient sets their OWN 4-digit door PIN. No SMS code is sent
// for same-city parcels — the rider asks for this PIN at the door instead.
app.post('/me/door-pin', async (c) => {
  const phone = c.get('phone');
  if (!phone) return c.json({ error: 'sign_in_required' }, 401);
  const b: any = await c.req.json().catch(() => null);
  const pin = String(b?.pin ?? '').replace(/\D/g, '');
  if (!/^\d{4}$/.test(pin)) return c.json({ error: 'pin_must_be_4_digits' }, 400);
  await c.env.DB.prepare('UPDATE auth_users SET door_pin_hash = ?2 WHERE phone = ?1')
    .bind(phone, await hashOtp(pin, c.env.JWT_SECRET)).run();
  return c.json({ ok: true, pin_set: true });
});
app.delete('/me/door-pin', async (c) => {
  const phone = c.get('phone');
  if (!phone) return c.json({ error: 'sign_in_required' }, 401);
  await c.env.DB.prepare('UPDATE auth_users SET door_pin_hash = NULL WHERE phone = ?1').bind(phone).run();
  return c.json({ ok: true, pin_set: false });
});

// Rider self-check: run the AI face review on their OWN current selfie
// (KYC card calls this right after upload). Returns the verdict; merging it
// into ai_check_json lets the admin review screen read it later.
app.post('/rider/profile/ai-face-check', async (c) => {
  const phone = c.get('phone');
  if (!phone) return c.json({ error: 'sign_in_required' }, 401);
  if (c.get('role') !== 'rider') return c.json({ error: 'rider_only' }, 403);
  const rider = await c.env.DB.prepare(
    'SELECT id, photo_url FROM riders WHERE phone = ?1 AND active = 1',
  ).bind(phone).first<any>();
  if (!rider) return c.json({ error: 'rider_not_found' }, 404);
  if (!rider.photo_url) return c.json({ error: 'no_selfie', detail: 'Upload a selfie first (KYC card).' }, 400);
  if (!c.env.AI) return c.json({ error: 'ai_unavailable' }, 503);
  if (!c.env.BACKUPS) return c.json({ error: 'uploads_not_configured' }, 503);
  const key = r2KeyFromUrl(rider.photo_url);
  if (!key) return c.json({ error: 'bad_photo_url' }, 400);
  const object = await c.env.BACKUPS.get(key);
  if (!object) return c.json({ error: 'photo_missing' }, 404);
  let face: FaceCheck;
  try { face = await analyzeSelfieFace(c.env, [...new Uint8Array(await object.arrayBuffer())]); }
  catch (e: any) { return c.json({ error: 'ai_failed', detail: String(e?.message ?? e).slice(0, 200) }, 502); }
  await persistFaceCheck(c.env.DB, rider.id, face);
  return c.json({ ok: true, face });
});

/* ------------------- declared value + optional cover (NOT insurance) ------- */
// Optional quoted protection: priced transparently, recorded as evidence context.
// NOT automatic/regulated insurance. Cover becomes "active" only under confirmed
// terms/eligibility (future). Until then status is quoted/declined/none.
const COVER_TERMS_VERSION = '2026-11-08';
// COVER REMOVED (owner directive 2026-11-17) — the terms summary and quote
// engine below stay dormant in case cover returns after legal sign-off.
function coverQuote(declaredValueZmw: number, weightClass: string): { fee_zmw: number; cap_zmw: number } {
  const v = Math.max(0, declaredValueZmw);
  if (v <= 0) return { fee_zmw: 0, cap_zmw: 0 };
  // Simple transparent quote: 1.5% of declared value, min K5, max K150 fee; cap = declared value up to K5000 by default.
  const base = v * 0.015;
  const heavy = /15\+|large|bulk/i.test(weightClass) ? 5 : 0;
  const fee = Math.min(150, Math.max(5, round2(base + heavy)));
  const cap = Math.min(5000, round2(v));
  return { fee_zmw: fee, cap_zmw: cap };
}

/* --------------------- hybrid parcel photo check (AI + signals + rules) ---- */
// The SELLER captures the parcel at booking (parcel_photo_url); the rider
// captures it again at the depot/courier drop-off (dropoff_photo_url /
// pod_delivery_url). Hybrid verdict = deterministic signals + LLM semantic
// comparison + rules → needs_review/flag. Perceptual hash/embedding is a
// pluggable upgrade (needs pixel decode or an embedding model); today we use
// exact SHA-256 fingerprints + LLM + rules and store feedback for training/eval.
type ParcelCheck = {
  same_parcel: 'yes' | 'uncertain' | 'no';
  confidence: 'high' | 'medium' | 'low';
  note: string;
  checked_at: string;
  exact_fingerprint_match?: boolean;
  booking_fingerprint_sha256?: string;
  dropoff_fingerprint_sha256?: string;
  booking_bytes?: number;
  dropoff_bytes?: number;
  perceptual_hash?: string | null; // semv1 semantic signal now; true pHash/embedding later
  similarity_score?: number | null;
  llm?: { booking_desc?: string; dropoff_desc?: string; model: string };
  rules?: { needs_review: boolean; reasons: string[]; risk_score: number; semantic_score?: number | null };
  needs_review?: boolean;
  review_status?: 'pending' | 'confirmed_match' | 'confirmed_mismatch' | 'inconclusive';
};

async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(digest)].map((x) => x.toString(16).padStart(2, '0')).join('');
}

function normalizeTokens(s: string): string[] {
  return (s.toLowerCase().match(/[a-z0-9]+/g) ?? []).filter((t: string) => t.length > 2 && !['the','and','with','one','two','has','for','its','parcel','photo'].includes(t));
}
function jaccard(a: string[], b: string[]): number {
  if (!a.length && !b.length) return 1;
  const A = new Set(a), B = new Set(b);
  let inter = 0;
  for (const t of A) if (B.has(t)) inter++;
  const union = A.size + B.size - inter;
  return union ? inter / union : 0;
}
async function semanticSignature(descA: string, descB: string): Promise<{ score: number; signature: string }> {
  const ta = normalizeTokens(descA), tb = normalizeTokens(descB);
  const score = Math.round(jaccard(ta, tb) * 1000) / 1000;
  const sig = `semv1:${(await sha256Hex(new TextEncoder().encode([...new Set([...ta, ...tb].sort())].join('|')))).slice(0, 16)}:${score.toFixed(3)}`;
  return { score, signature: sig };
}

function parcelCheckRules(result: Pick<ParcelCheck, 'same_parcel' | 'confidence'>, exactMatch: boolean, semanticScore: number | null, ctx: { partnerConfirmed?: boolean; hasOtp?: boolean }): { needs_review: boolean; reasons: string[]; risk_score: number; semantic_score?: number | null } {
  const reasons: string[] = [];
  let risk = 0;
  if (exactMatch) reasons.push('exact_fingerprint_match'); // same bytes reused — notable
  if (semanticScore != null) {
    if (semanticScore >= 0.55) { reasons.push('semantic_high'); risk = Math.max(0, risk - 1); }
    else if (semanticScore < 0.20) { reasons.push('semantic_low'); risk += 1; }
    else reasons.push('semantic_mid');
  }
  if (result.same_parcel === 'no') { risk += 4; reasons.push('llm_mismatch'); }
  if (result.same_parcel === 'uncertain') { risk += 1; reasons.push('llm_uncertain'); }
  if (result.confidence === 'low') { risk += 1; reasons.push('low_confidence'); }
  if (ctx.partnerConfirmed) { risk = Math.max(0, risk - 1); reasons.push('partner_confirmed'); }
  if (ctx.hasOtp) { risk = Math.max(0, risk - 1); reasons.push('otp_verified'); }
  const needs_review = result.same_parcel !== 'yes' || risk >= 2 || reasons.includes('exact_fingerprint_match') || semanticScore != null && semanticScore < 0.20;
  return { needs_review, reasons, risk_score: risk, semantic_score: semanticScore };
}

async function compareParcelPhotos(env: Env, bookingBytesArr: number[], dropoffBytesArr: number[], ctx: { partnerConfirmed?: boolean; hasOtp?: boolean } = {}): Promise<ParcelCheck> {
  const bookingBytes = new Uint8Array(bookingBytesArr);
  const dropoffBytes = new Uint8Array(dropoffBytesArr);
  const [bookingFp, dropoffFp] = await Promise.all([sha256Hex(bookingBytes), sha256Hex(dropoffBytes)]);
  const exactMatch = bookingFp === dropoffFp;

  const describe = async (bytes: number[], hint: string) => {
    // PRIMARY: free Workers AI (LLaVA). FALLBACK: optional paid HF Inference.
    const out: any = await runAi(env, '@cf/llava-hf/llava-1.5-7b-hf', {
      image: bytes,
      prompt: `This is ${hint}. Describe the PARCEL in it factually: dominant packaging material, shape (sack/box/envelope/bag/crate), colour, approximate size class, any visible tape/branding/labels/handles and how it is closed. If several parcels are visible, describe the most prominent one. One sentence, no guesses about contents.`,
      max_tokens: 140,
    });
    if (!out) {
      // Workers AI failed → try the optional paid HF path instead.
      return hfVision(env, HF_VISION_MODEL, new Uint8Array(bytes));
    }
    return String(out?.response ?? out?.description ?? '').trim().slice(0, 300);
  };
  let bookingDesc = '', dropoffDesc = '';
  let llmVerdict: { same_parcel: 'yes' | 'uncertain' | 'no'; confidence: 'high' | 'medium' | 'low'; note: string } = {
    same_parcel: 'uncertain', confidence: 'low', note: 'AI unavailable — photos filed as evidence for manual review.',
  };
  try {
    [bookingDesc, dropoffDesc] = await Promise.all([
      describe(bookingBytesArr, 'the parcel photo captured by the sender at booking'),
      describe(dropoffBytesArr, 'the parcel photo captured by the rider at the depot/courier drop-off'),
    ]);
    // VERDICT — two providers, same shape:
    // PRIMARY: local robust rule on the two captions (determinstic, free).
    // FALLBACK inside it: HF Mistral verdict when the descriptions are too
    // close to call by tokens alone.
    const localTokens = (s: string) => [...new Set(normalizeTokens(s))];
    const captionScore = (() => {
      if (!bookingDesc || !dropoffDesc) return null;
      const a = localTokens(bookingDesc), b = localTokens(dropoffDesc);
      const j = jaccard(a, b);
      return { jaccard: Math.round(j * 1000) / 1000, normA: normalizeTokens(bookingDesc), normB: normalizeTokens(dropoffDesc) };
    })();
    const verdictModel = async (): Promise<typeof llmVerdict | null> => {
      if (env.AI) {
        const out: any = await runAi(env, '@cf/mistralai/mistral-small-3.1-24b-instruct', {
          messages: [
            { role: 'system', content: 'You compare two descriptions of parcel photos to detect parcel swaps or fabricated deliveries. Be conservative: if either description is vague or contradicts nothing but proves little, answer uncertain. Reply with JSON ONLY.' },
            { role: 'user', content: `Description A (booking photo from the seller): ${bookingDesc}\nDescription B (drop-off photo from the rider): ${dropoffDesc}\nCould these plausibly show the SAME parcel? Reply with JSON ONLY: {"same_parcel":"yes"|"uncertain"|"no","confidence":"high"|"medium"|"low","note":"<one short sentence>"}` },
          ],
          max_tokens: 120,
        });
        if (out) {
          const raw = (typeof out?.response === 'string' ? out.response
            : (typeof out?.choices?.[0]?.message?.content === 'string' ? out.choices[0].message.content : '')).trim();
          const m = raw.match(/\{[\s\S]*\}/);
          let j: any = {};
          try { j = m ? JSON.parse(m[0]) : {}; } catch { j = {}; }
          const sp = String(j.same_parcel ?? 'uncertain').toLowerCase();
          const conf = String(j.confidence ?? 'low').toLowerCase();
          return {
            same_parcel: sp === 'yes' || sp === 'no' ? sp : 'uncertain',
            confidence: conf === 'high' || conf === 'medium' ? conf : 'low',
            note: String(j.note ?? '').slice(0, 200),
          };
        }
      }
      // HF Mistral text verdict (used only when the vision pair ran through HF)
      const hf = (env as any).HF_API_KEY ? await hfText(env, HF_TEXT_MODEL,
        `Description A (booking photo, seller): ${bookingDesc}\nDescription B (drop-off photo, rider): ${dropoffDesc}\nJudge whether these plausibly show the SAME parcel. Reply with one JSON object only: {"same_parcel":"yes"|"uncertain"|"no","confidence":"high"|"medium"|"low","note":"one short sentence"}`, 120) : '';
      if (hf) {
        const m = hf.match(/\{[\s\S]*\}/);
        let j: any = {};
        try { j = m ? JSON.parse(m[0]) : {}; } catch { j = {}; }
        const sp = String(j.same_parcel ?? '').toLowerCase();
        const conf = String(j.confidence ?? '').toLowerCase();
        return {
          same_parcel: sp === 'yes' || sp === 'no' ? sp : 'uncertain',
          confidence: conf === 'high' || conf === 'medium' ? conf : 'low',
          note: String(j.note ?? 'HF verdict').slice(0, 200),
        };
      }
      return null;
    };
    if (captionScore) {
      if (captionScore.jaccard >= 0.42) {
        llmVerdict = { same_parcel: 'yes', confidence: captionScore.jaccard >= 0.60 ? 'high' : 'medium', note: `Descriptions match (jaccard ${captionScore.jaccard.toFixed(2)}).` };
      } else if (captionScore.jaccard <= 0.08) {
        llmVerdict = { same_parcel: 'no', confidence: 'medium', note: `Descriptions do not match (jaccard ${captionScore.jaccard.toFixed(2)}).` };
      } else {
        const v = await verdictModel();
        llmVerdict = v ?? { same_parcel: 'uncertain', confidence: 'low', note: `Descriptions too close to call (jaccard ${captionScore.jaccard.toFixed(2)}) — manual review.` };
      }
    } else {
      const v = await verdictModel();
      llmVerdict = v ?? { same_parcel: 'uncertain', confidence: 'low', note: 'AI unavailable — photos filed as evidence for manual review.' };
    }
  } catch { /* keep default uncertain */ }
  const semantic = (bookingDesc || dropoffDesc) ? await semanticSignature(bookingDesc, dropoffDesc) : null;
  const rules = parcelCheckRules(llmVerdict, exactMatch, semantic?.score ?? null, ctx);
  return {
    ...llmVerdict,
    checked_at: new Date().toISOString(),
    exact_fingerprint_match: exactMatch,
    booking_fingerprint_sha256: bookingFp,
    dropoff_fingerprint_sha256: dropoffFp,
    booking_bytes: bookingBytes.length,
    dropoff_bytes: dropoffBytes.length,
    // semv1 = semantic (description-derived) similarity signal; upgrade path: true pHash (WASM) or image-embedding model.
    perceptual_hash: semantic?.signature ?? null,
    similarity_score: semantic?.score ?? null,
    llm: { booking_desc: bookingDesc || undefined, dropoff_desc: dropoffDesc || undefined, model: 'llava-1.5-7b-hf+mistral-small-3.1-24b-instruct' },
    rules,
    needs_review: rules.needs_review,
    review_status: 'pending',
  };
}

// POST /jobs/:ref/parcel-check — the assigned rider (or ops/admin) re-verifies
// the depot drop against the seller's booking photo. Runs with or without AI:
// no AI => verdict is 'uncertain' by default and the photos remain as evidence.
app.post('/jobs/:ref/parcel-check', async (c) => {
  const phone = c.get('phone') ?? null;
  const isAdminKey = isAdmin(c);
  const isOpsKey = c.get('role') === 'ops';
  const job = await c.env.DB.prepare(
    `SELECT j.id, j.ref, j.sender_phone, j.parcel_photo_url, j.dropoff_photo_url, j.pod_delivery_url,
            j.partner_confirmed, j.last_mile, j.delivery_otp_hash,
            r.phone AS rider_phone
       FROM jobs j LEFT JOIN riders r ON r.id = j.rider_id
      WHERE j.ref = ?1`,
  ).bind(c.req.param('ref')).first() as any;
  if (!job) return c.json({ error: 'not found' }, 404);
  if (!isAdminKey && !isOpsKey && job.rider_phone !== phone) {
    return c.json({ error: 'only the assigned rider can run the check' }, 403);
  }
  const bookingKey = r2KeyFromUrl(job.parcel_photo_url);
  const dropKey = r2KeyFromUrl(job.dropoff_photo_url) ?? r2KeyFromUrl(job.pod_delivery_url);
  if (!bookingKey) return c.json({ error: 'no_booking_photo', detail: 'The seller did not attach a parcel photo at booking.' }, 409);
  if (!dropKey) return c.json({ error: 'no_dropoff_photo', detail: 'The rider has not filed a depot/delivery photo yet.' }, 409);
  if (!c.env.BACKUPS) return c.json({ error: 'uploads_not_configured' }, 503);
  const booking = await c.env.BACKUPS.get(bookingKey).catch(() => null);
  const drop = await c.env.BACKUPS.get(dropKey).catch(() => null);
  if (!booking || !drop) return c.json({ error: 'photo_missing' }, 404);
  const ctx = {
    partnerConfirmed: Number(job.partner_confirmed ?? 0) === 1,
    hasOtp: !!job.delivery_otp_hash && job.delivery_otp_hash !== '0000',
  };
  let result: ParcelCheck;
  try {
    result = await compareParcelPhotos(
      c.env,
      [...new Uint8Array(await booking.arrayBuffer())],
      [...new Uint8Array(await drop.arrayBuffer())],
      ctx,
    );
  } catch {
    result = {
      same_parcel: 'uncertain', confidence: 'low',
      note: 'Check failed — photos filed as evidence for manual review.',
      checked_at: new Date().toISOString(),
      perceptual_hash: null,
      rules: { needs_review: true, reasons: ['check_error'], risk_score: 1 },
      needs_review: true,
      review_status: 'pending',
    };
  }
  const flag = result.same_parcel === 'no' ? 1 : 0;
  const reviewFlag = result.needs_review ? 1 : 0;
  const stmts: D1PreparedStatement[] = [
    c.env.DB.prepare('UPDATE jobs SET parcel_check = ?2 WHERE id = ?1').bind(job.id, JSON.stringify(result)),
    c.env.DB.prepare(
      `INSERT INTO job_events (job_id, status, note) VALUES (?1, 'parcel_check', ?2)`,
    ).bind(job.id, `Parcel check [hybrid]: ${result.same_parcel} (${result.confidence}) review=${reviewFlag} — ${result.note}`),
  ];
  if (flag) {
    stmts.push(c.env.DB.prepare(
      `INSERT INTO fraud_flags (job_id, job_ref, phone, score, reasons, status)
         VALUES (?1, ?2, ?3, 4, 'parcel_mismatch_ai', 'open')`,
    ).bind(job.id, job.ref, job.sender_phone));
  }
  if (reviewFlag) {
    try {
      stmts.push(c.env.DB.prepare(
        `INSERT INTO parcel_check_feedback (job_id, job_ref, verdict, decision, reviewer, note, signals_json)
         VALUES (?1, ?2, ?3, 'pending_review', 'system', ?4, ?5)`,
      ).bind(job.id, job.ref, result.same_parcel, result.note ?? '', JSON.stringify({ rules: result.rules, exact_fingerprint_match: result.exact_fingerprint_match })));
    } catch { /* feedback table may not exist yet on old DBs */ }
  }
  await c.env.DB.batch(stmts);
  return c.json({ ok: true, ...result, flagged: flag === 1, needs_review: reviewFlag === 1 });
});

// Human review for hybrid parcel checks (ops/admin). Stores feedback for eval/training.
app.post('/jobs/:ref/parcel-review', async (c) => {
  if (!isAdmin(c) && c.get('role') !== 'ops') return c.json({ error: 'forbidden' }, 403);
  const b: any = await c.req.json().catch(() => null);
  const decision = String(b?.decision ?? '');
  if (!['confirm_match', 'confirm_mismatch', 'inconclusive'].includes(decision)) {
    return c.json({ error: 'decision must be confirm_match, confirm_mismatch, or inconclusive' }, 400);
  }
  const note = String(b?.note ?? '').trim().slice(0, 500) || null;
  const reviewer = c.get('phone') ?? 'admin-key';
  const job = await c.env.DB.prepare(
    'SELECT id, ref, parcel_check FROM jobs WHERE ref = ?1',
  ).bind(c.req.param('ref')).first<any>();
  if (!job) return c.json({ error: 'not found' }, 404);
  let check: any = {};
  try { check = job.parcel_check ? JSON.parse(job.parcel_check) : {}; } catch { check = {}; }
  check.review_status = decision === 'confirm_match' ? 'confirmed_match' : decision === 'confirm_mismatch' ? 'confirmed_mismatch' : 'inconclusive';
  check.reviewed_by = reviewer;
  check.reviewed_at = new Date().toISOString();
  check.review_note = note;
  await c.env.DB.batch([
    c.env.DB.prepare('UPDATE jobs SET parcel_check = ?2, parcel_check_review = ?3 WHERE id = ?1')
      .bind(job.id, JSON.stringify(check), JSON.stringify({ decision, reviewer, note, reviewed_at: check.reviewed_at })),
    c.env.DB.prepare(
      `INSERT INTO parcel_check_feedback (job_id, job_ref, verdict, decision, reviewer, note, signals_json)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)`,
    ).bind(job.id, job.ref, check.same_parcel ?? null, decision, reviewer, note, JSON.stringify(check)),
    c.env.DB.prepare(`INSERT INTO job_events (job_id, status, note) VALUES (?1, 'parcel_review', ?2)`)
      .bind(job.id, `Parcel review: ${decision}${note ? ` — ${note}` : ''}`),
  ]);
  return c.json({ ok: true, ref: job.ref, review: check });
});

// Proof-of-condition / evidence locker: immutable timeline for disputes & insurance.
// Access: sender, recipient (verified track grant), assigned rider, ops/admin.
app.get('/jobs/:ref/evidence', async (c) => {
  const phone = c.get('phone') ?? null;
  const isAdminKey = isAdmin(c);
  const isOpsKey = c.get('role') === 'ops';
  const job = await c.env.DB.prepare(
    `SELECT j.id, j.ref, j.sender_phone, j.recipient_phone, j.status, j.created_at,
            j.parcel_photo_url, j.dropoff_photo_url, j.pod_pickup_url, j.pod_delivery_url,
            j.parcel_check, j.parcel_check_review, j.partner_confirmed, j.last_mile,
            j.declared_value_zmw, j.cover_opt_in, j.cover_fee_zmw, j.cover_status,
            j.counter_receipt_url, j.counter_receipt_zmw, j.counter_receipt_paid,
            j.counter_receipts_json,
            j.delivery_otp_hash, j.courier_waybill, j.pickup_window, j.dest_city, j.branch,
            r.phone AS rider_phone, r.full_name AS rider_name
       FROM jobs j LEFT JOIN riders r ON r.id = j.rider_id
      WHERE j.ref = ?1`,
  ).bind(c.req.param('ref')).first<any>();
  if (!job) return c.json({ error: 'not found' }, 404);
  let authorized = isAdminKey || isOpsKey || (phone && (phone === job.sender_phone || phone === job.rider_phone));
  if (!authorized && phone && phone === job.recipient_phone) authorized = true; // signed-in recipient
  if (!authorized) return c.json({ error: 'forbidden' }, 403);
  const { results: events } = await c.env.DB.prepare(
    `SELECT status, note, created_at FROM job_events WHERE job_id = ?1 ORDER BY id ASC`,
  ).bind(job.id).all<any>();
  let parcelCheck: any = null;
  try { parcelCheck = job.parcel_check ? JSON.parse(job.parcel_check) : null; } catch {}
  const isOwnSender = phone === job.sender_phone;
  // REAL RECEIPT, VISIBLE BUT LOCKED (owner directive 2026-11-12): the sender
  // (and staff) always receive the rider-submitted depot receipt photo(s) and
  // amount(s) — the app renders them blurred behind a lock until the depot
  // bill is cleared. Recipients and strangers get nothing.
  const counterReceipt = job.counter_receipt_zmw && (isOwnSender || isAdminKey || isOpsKey)
    ? {
        amount_zmw: job.counter_receipt_zmw,
        url: job.counter_receipt_url ?? null,
        paid: Number(job.counter_receipt_paid ?? 0) === 1,
        // Multi-receipt depot drops: every photographed receipt with its own
        // exact written amount (first = the primary preview).
        receipts: job.counter_receipts_json ? JSON.parse(job.counter_receipts_json) : null,
      }
    : null;
  const evidence = {
    booking_photo: job.parcel_photo_url || null,
    pickup_photo: job.pod_pickup_url || null,
    depot_or_dropoff_photo: job.dropoff_photo_url || job.pod_delivery_url || null,
    handover_photo: job.pod_delivery_url || null,
    parcel_check: parcelCheck,
    parcel_review: parcelCheck?.review_status ?? null,
    partner_confirmed: Number(job.partner_confirmed ?? 0) === 1,
    otp_required: !!job.delivery_otp_hash && job.delivery_otp_hash !== '0000' && Number(job.last_mile) === 1,
    waybill: job.courier_waybill || null,
    counter_receipt: counterReceipt,
  };
  return c.json({
    ok: true,
    ref: job.ref,
    status: job.status,
    created_at: job.created_at,
    route: { dest_city: job.dest_city, branch: job.branch, pickup_window: job.pickup_window },
    rider: job.rider_name ? { name: job.rider_name } : null,
    declared_value_zmw: job.declared_value_zmw,
    cover: { opt_in: Number(job.cover_opt_in ?? 0) === 1, fee_zmw: job.cover_fee_zmw, status: job.cover_status },
    evidence,
    timeline: (events ?? []).map((e: any) => {
      const riderStatuses = new Set(['picked_up', 'at_depot', 'delivered', 'ready_for_collection']);
      const who = riderStatuses.has(e.status) ? 'rider' : e.status === 'partner_confirmed' ? 'partner' : 'system';
      return {
        status: e.status,
        at: e.created_at,
        note: e.note,
        who,
        actor: who === 'rider' ? (job.rider_name ?? 'rider') : null,
      };
    }),
  });
});

/* ------------------------------ web dashboard ----------------------------- */
// Server-rendered admin dashboard (no separate build / hosting needed).
// Superadmin (owner) sees everything; admins see riders/jobs/fraud/alerts but
// cannot mint/demote admins. Sellers & partners use the mobile app (app-first)
// — they get read-only job/tracking surfaces via the existing API.
function h(str: string): string {
  return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}
function layout(title: string, user: string, body: string): string {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>${h(title)} — DropOff</title><style>
* { box-sizing: border-box; }
body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 0; background: #f4f7f5; color: #17221e; }
.top { background: #123c32; color: #fff; padding: 12px 20px; display: flex; align-items: center; gap: 16px; position: sticky; top: 0; z-index: 50; }
.top h1 { margin: 0; font-size: 17px; letter-spacing: -0.5px; }
.top a { color: #f6b73c; text-decoration: none; font-weight: 700; font-size: 13px; }
.top a:hover { text-decoration: underline; }
.wrap { max-width: 1200px; margin: 0 auto; padding: 20px; }
nav { display: flex; gap: 8px; margin-bottom: 16px; flex-wrap: wrap; }
nav a { padding: 8px 14px; border-radius: 8px; background: #fff; border: 1px solid #e2e6e1; color: #17221e; text-decoration: none; font-weight: 700; font-size: 13px; }
nav a.active { background: #123c32; color: #fff; border-color: #123c32; }
nav a:hover { border-color: #123c32; }
.card { background: #fff; border: 1px solid #e2e6e1; border-radius: 12px; padding: 16px; margin-bottom: 16px; }
.card h2 { margin: 0 0 12px; font-size: 15px; text-transform: uppercase; letter-spacing: 0.6px; color: #65736d; }
.metrics { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 12px; margin-bottom: 16px; }
.metric { background: #fff; border: 1px solid #e2e6e1; border-radius: 10px; padding: 14px; text-align: center; }
.metric .v { font-size: 26px; font-weight: 800; color: #123c32; }
.metric .l { font-size: 12px; color: #65736d; margin-top: 4px; }
table { width: 100%; border-collapse: collapse; font-size: 13px; }
th { text-align: left; padding: 10px 8px; border-bottom: 2px solid #e2e6e1; color: #65736d; font-weight: 800; font-size: 11px; text-transform: uppercase; }
td { padding: 10px 8px; border-bottom: 1px solid #eef1ee; vertical-align: top; }
tr:hover td { background: #f4f7f5; }
.badge { display: inline-block; padding: 2px 8px; border-radius: 10px; font-size: 11px; font-weight: 800; }
.badge-verified { background: #e3efe6; color: #123c32; }
.badge-pending { background: #fdf3e3; color: #8a5a00; }
.badge-rejected { background: #fdeceb; color: #b3261e; }
.badge-open { background: #fdeceb; color: #b3261e; }
.badge-cleared { background: #e3efe6; color: #123c32; }
.btn { background: #123c32; color: #fff; border: none; padding: 6px 12px; border-radius: 8px; font-weight: 800; font-size: 12px; cursor: pointer; }
.btn:hover { background: #175445; }
.btn-sm { padding: 4px 8px; font-size: 11px; }
.btn-outline { background: transparent; border: 1px solid #123c32; color: #123c32; }
.btn-outline:hover { background: #123c32; color: #fff; }
.btn-danger { background: #b3261e; color: #fff; }
.btn-danger:hover { background: #9a1f19; }
input, select { padding: 6px 10px; border: 1px solid #e2e6e1; border-radius: 8px; font-size: 13px; }
.empty { color: #65736d; font-size: 13px; text-align: center; padding: 30px; }
.foot { margin-top: 24px; color: #65736d; font-size: 11px; border-top: 1px solid #e2e6e1; padding-top: 12px; }
@media (max-width: 700px) { .wrap { padding: 10px; } .metrics { grid-template-columns: 1fr; } table { font-size: 11px; } th, td { padding: 6px 4px; } }
</style></head><body>
<div class="top"><strong style="font-size:18px;letter-spacing:-0.6px;">DropOff</strong> <span style="opacity:.8">first-mile — Zambia</span> <a href="/dashboard">Dashboard</a> <span style="opacity:.6">—</span> <a href="/admin/riders">Riders</a> <span style="opacity:.6">—</span> <a href="/dashboard/analytics">Analytics</a> <span style="opacity:.6">—</span> <a href="/admin/fraud">Fraud</a> <span style="opacity:.6">—</span> <a href="/security/alerts">Alerts</a> <span style="opacity:.6">—</span> <strong>${h(user)}</strong> <a href="/auth/logout" style="margin-left:10px;">Sign out</a></div>
<div class="wrap">${body}</div>
<div class="foot">DropOff — home or shop pickup to your courier depot. Internal admin surface. Not for sellers or recipients.</div>
</body></html>`;
}
function statusBadge(s: string): string {
  const cls = s === 'verified' ? 'badge-verified' : s === 'rejected' ? 'badge-rejected' : 'badge-pending';
  return `<span class="badge ${cls}">${h(s)}</span>`;
}

/* Dashboard home: key metrics + quick links */
app.get('/dashboard', async (c) => {
  if (!isAdmin(c) && c.get('role') !== 'ops') return c.json({ error: 'forbidden' }, 403);
  const phone = c.get('phone') ?? 'admin';
  const stats = await c.env.DB.prepare(
    `SELECT (SELECT COUNT(*) FROM riders) AS riders,
            (SELECT COUNT(*) FROM riders WHERE verification_status = 'pending') AS pending,
            (SELECT COUNT(*) FROM riders WHERE verification_status = 'verified') AS verified,
            (SELECT COUNT(*) FROM jobs) AS jobs,
            (SELECT COUNT(*) FROM jobs WHERE status IN ('rider_assigned','picked_up','at_depot','departed','arrived')) AS in_flight,
            (SELECT COUNT(*) FROM fraud_flags WHERE status = 'open') AS open_fraud,
            (SELECT COUNT(*) FROM security_alerts WHERE acknowledged = 0) AS unacked_alerts
       FROM riders LIMIT 1`,
  ).first<any>();
  const pendingRiders = await c.env.DB.prepare(
    `SELECT id, phone, full_name, vehicle, vehicle_class, nrc_number, plate_number, vehicle_make, vehicle_color, submitted_at, created_at
       FROM riders WHERE verification_status = 'pending' ORDER BY submitted_at DESC LIMIT 10`,
  ).all<any>();
  const pendingRows = ((pendingRiders?.results ?? []) as any[]).map((r) => `<tr>
    <td>${h(r.full_name)}</td>
    <td>${h(r.phone)}</td>
    <td>${h(r.vehicle)} ${h(r.vehicle_class ?? '')}</td>
    <td>${h(r.nrc_number ?? '-')}</td>
    <td>${h(r.plate_number ?? '-')}</td>
    <td>${h(r.vehicle_make ?? '-')} ${h(r.vehicle_color ?? '')}</td>
    <td>${h(r.submitted_at ?? r.created_at ?? '—')}</td>
    <td>
      <form method="post" action="/admin/riders/${h(r.id)}/verify" style="display:inline" onsubmit="return confirm('Verify this rider?')">
        <input type="hidden" name="status" value="verified">
        <button class="btn btn-sm">Verify</button>
      </form>
      <form method="post" action="/admin/riders/${h(r.id)}/verify" style="display:inline" onsubmit="return confirm('Reject this rider?')">
        <input type="hidden" name="status" value="rejected">
        <input type="hidden" name="note" value="Rejected from dashboard">
        <button class="btn btn-sm btn-danger">Reject</button>
      </form>
    </td>
  </tr>`).join('');
  const b = `
  <div class="metrics">
    <div class="metric"><div class="v">${h(stats?.jobs ?? 0)}</div><div class="l">Jobs total</div></div>
    <div class="metric"><div class="v">${h(stats?.in_flight ?? 0)}</div><div class="l">In flight</div></div>
    <div class="metric"><div class="v">${h(stats?.riders ?? 0)}</div><div class="l">Riders</div></div>
    <div class="metric"><div class="v">${h(stats?.pending ?? 0)}</div><div class="l">Pending verification</div></div>
    <div class="metric"><div class="v">${h(stats?.open_fraud ?? 0)}</div><div class="l">Open fraud flags</div></div>
    <div class="metric"><div class="v">${h(stats?.unacked_alerts ?? 0)}</div><div class="l">Unacked alerts</div></div>
  </div>
  <div class="card" style="border-left:4px solid #b3261e">
    <h2>Pending review</h2>
    <table>
      <thead><tr><th>Name</th><th>Phone</th><th>Vehicle</th><th>NRC</th><th>Plate</th><th>Vehicle</th><th>Submitted</th><th>Action</th></tr></thead>
      <tbody>${pendingRows || '<tr><td colspan="8" class="empty">No pending drivers.</td></tr>'}</tbody>
    </table>
  </div>
  <div class="card">
    <h2>Quick actions</h2>
    <div style="display:flex;gap:10px;flex-wrap:wrap">
      <a class="btn" href="/admin/riders">Manage riders</a>
      <a class="btn btn-outline" href="/dashboard/riders">Rider list + targets</a>
      <a class="btn btn-outline" href="/dashboard/jobs">Job list</a>
      <a class="btn btn-outline" href="/admin/fraud">Review fraud</a>
      <a class="btn btn-outline" href="/security/alerts?unacknowledged=1">Security alerts</a>
    </div>
  </div>
  `;
  return new Response(layout('Dashboard', phone, b), { headers: { 'Content-Type': 'text/html; charset=utf-8' } });
});

/* Rider list + targets (dashboard view of /admin/riders) */
app.get('/dashboard/riders', async (c) => {
  if (!isAdmin(c) && c.get('role') !== 'ops') return c.json({ error: 'forbidden' }, 403);
  const limit = pageLimit(c.req.query('limit'));
  const { results } = await c.env.DB.prepare(
    `SELECT ${riderDocSelect()}, last_lat, last_lng, last_seen_at
       FROM riders ORDER BY CASE WHEN verification_status = 'pending' THEN 0 ELSE 1 END, id DESC LIMIT ?1`,
  ).bind(limit + 1).all<any>();
  const hasMore = results.length > limit;
  const page = hasMore ? results.slice(0, -1) : results;
  const prog = await incentiveProgramme(c.env);
  const targets = await riderTargetStats(c.env.DB, undefined, prog);
  const rows = ((page ?? []) as any[]).map((r) => {
    const t = targets.get(Number(r.id)) ?? shapeTargets(0, 0);
    return `<tr>
      <td>${h(r.full_name)}</td>
      <td>${h(r.phone)}</td>
      <td>${h(r.vehicle)} ${h(r.vehicle_class ?? '')}</td>
      <td>${statusBadge(r.verification_status ?? 'pending')}</td>
      <td>${t.today}/${t.daily_target}</td>
      <td>${t.month}/${t.month_target}</td>
      <td>${t.on_track ? 'on track' : 'behind'}</td>
      <td>
        <form method="post" action="/admin/riders/${h(r.id)}/verify" style="display:inline" onsubmit="return confirm('Verify this rider?')">
          <input type="hidden" name="status" value="verified">
          <button class="btn btn-sm" ${r.verification_status === 'verified' ? 'disabled' : ''}>Verify</button>
        </form>
        <form method="post" action="/admin/riders/${h(r.id)}/verify" style="display:inline" onsubmit="return confirm('Reject this rider?')">
          <input type="hidden" name="status" value="rejected">
          <input type="hidden" name="note" value="Rejected from dashboard">
          <button class="btn btn-sm btn-danger" ${r.verification_status === 'rejected' ? 'disabled' : ''}>Reject</button>
        </form>
      </td>
    </tr>`;
  }).join('');
  const b = `
  <div class="card">
    <h2>Riders &amp; drivers</h2>
    <p style="margin:0 0 10px;color:#65736d;font-size:12px">${hasMore ? `Showing ${page.length} of more than ${limit}` : `Showing ${page.length} riders`}</p>
    <table>
      <thead><tr><th>Name</th><th>Phone</th><th>Vehicle</th><th>Verification</th><th>Today</th><th>Month</th><th>Pace</th><th>Action</th></tr></thead>
      <tbody>${rows || '<tr><td colspan="8" class="empty">No riders.</td></tr>'}</tbody>
    </table>
  </div>
  `;
  return new Response(layout('Riders', c.get('phone') ?? 'admin', b), { headers: { 'Content-Type': 'text/html; charset=utf-8' } });
});

/* Job list (dashboard view) */
app.get('/dashboard/jobs', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'forbidden' }, 403);
  const limit = pageLimit(c.req.query('limit'));
  const { results } = await c.env.DB.prepare(
    `SELECT j.ref, j.sender_phone, j.sender_name, j.recipient_name, j.pickup_address, j.dest_city, j.status, j.rider_fee_zmw, j.total_zmw, j.created_at,
            co.name AS courier_name
       FROM jobs j JOIN couriers co ON co.id = j.courier_id
      ORDER BY j.id DESC LIMIT ?1`,
  ).bind(limit + 1).all<any>();
  const hasMore = results.length > limit;
  const page = hasMore ? results.slice(0, -1) : results;
  const rows = ((page ?? []) as any[]).map((j) => `<tr>
    <td>${h(j.ref)}</td>
    <td>${h(j.sender_name)}</td>
    <td>${h(j.sender_phone)}</td>
    <td>${h(j.recipient_name)}</td>
    <td>${h(j.pickup_address)}</td>
    <td>${h(j.dest_city)}</td>
    <td>${h(j.courier_name)}</td>
    <td><span class="badge ${j.status === 'delivered' ? 'badge-cleared' : 'badge-open'}">${h(j.status)}</span></td>
    <td>K${Number(j.total_zmw ?? 0).toFixed(2)}</td>
    <td>${h(j.created_at)}</td>
  </tr>`).join('');
  const b = `
  <div class="card">
    <h2>Jobs</h2>
    <table>
      <thead><tr><th>Ref</th><th>Sender</th><th>Phone</th><th>Recipient</th><th>Pickup</th><th>Dest</th><th>Courier</th><th>Status</th><th>Total</th><th>Created</th></tr></thead>
      <tbody>${rows || '<tr><td colspan="10" class="empty">No jobs.</td></tr>'}</tbody>
    </table>
  </div>
  `;
  return new Response(layout('Jobs', c.get('phone') ?? 'admin', b), { headers: { 'Content-Type': 'text/html; charset=utf-8' } });
});

/* ------------------------------ app analytics ----------------------------- */
// Feature usage / click KPI for superadmin & admin (app-first).
// The Flutter app batches events locally (offline-first outbox) and POSTs them
// here; the worker only stores them — aggregation happens on read via KPI.
// Auth: any signed-in caller (phone JWT) or admin key. Rate-limited per IP.
app.post('/analytics/ingest', async (c) => {
  if (await rateLimited(c, 'analytics_ingest', 120)) return c.json({ error: 'too_many_requests' }, 429);
  const phone = c.get('phone') ?? null;
  const role = c.get('role') ?? null;
  if (!phone && !isAdmin(c)) return c.json({ error: 'sign_in_required' }, 401);
  const b: any = await c.req.json().catch(() => null);
  if (!b || !Array.isArray(b.events)) return c.json({ error: 'events array required' }, 400);
  const events = b.events.slice(0, 200); // cap batch size
  const now = new Date().toISOString();
  const stmts: D1PreparedStatement[] = [];
  for (const e of events) {
    const feature = String(e.feature ?? '').slice(0, 60);
    const action = String(e.action ?? '').slice(0, 60);
    if (!feature || !action) continue;
    stmts.push(c.env.DB.prepare(
      `INSERT INTO analytics_events (phone, role, feature, action, context, meta, created_at)
       VALUES (?1,?2,?3,?4,?5,?6,?7)`,
    ).bind(
      phone,
      role,
      feature,
      action,
      String(e.context ?? '').slice(0, 80) || null,
      e.meta != null ? JSON.stringify(e.meta) : null,
      String(e.created_at ?? now).slice(0, 30) || now,
    ));
  }
  if (stmts.length) await c.env.DB.batch(stmts);
  return c.json({ ok: true, inserted: stmts.length });
});

// Aggregated feature-usage KPI for the owner/admin console (web + mobile app).
// Superadmin sees everything; admin/ops see the same aggregate (no PII beyond
// phone which is already their own account identity).
app.get('/admin/analytics/kpi', async (c) => {
  if (!isAdmin(c) && c.get('role') !== 'ops') return c.json({ error: 'forbidden' }, 403);
  const days = Math.min(Math.max(Number(c.req.query('days') ?? '30'), 1), 90);
  const since = `datetime('now', '-${days} days')`;
  const base = `FROM analytics_events WHERE created_at >= ${since}`;
  // Top features by event count (last N days).
  const topFeatures = await c.env.DB.prepare(
    `SELECT feature, COUNT(*) AS n, COUNT(DISTINCT phone) AS users ${base}
      GROUP BY feature ORDER BY n DESC LIMIT 12`,
  ).all<any>();
  // Top actions within the top feature.
  const topActions = await c.env.DB.prepare(
    `SELECT feature, action, COUNT(*) AS n ${base}
      GROUP BY feature, action ORDER BY n DESC LIMIT 24`,
  ).all<any>();
  // Most-visited screens/tabs (feature=screen, action=view).
  const topScreens = await c.env.DB.prepare(
    `SELECT context AS screen, COUNT(*) AS n, COUNT(DISTINCT phone) AS users ${base}
      AND feature = 'screen' AND action = 'view'
      GROUP BY context ORDER BY n DESC LIMIT 15`,
  ).all<any>();
  // Conversion funnel: key milestones (unique users).
  const funnel = await c.env.DB.prepare(
    `SELECT feature, COUNT(DISTINCT phone) AS users ${base}
      AND feature IN ('booking','subscriptions','pack_codes','rider_verification','collections')
      GROUP BY feature ORDER BY users DESC`,
  ).all<any>();
  // Daily active users (distinct phones with >=1 event).
  const dau = await c.env.DB.prepare(
    `SELECT date(created_at) AS day, COUNT(DISTINCT phone) AS users ${base}
      GROUP BY day ORDER BY day`,
  ).all<any>();
  // Usage by role.
  const byRole = await c.env.DB.prepare(
    `SELECT role, COUNT(*) AS n, COUNT(DISTINCT phone) AS users ${base}
      GROUP BY role ORDER BY n DESC`,
  ).all<any>();
  // Hour of day heatmap (CAT-agnostic: stored UTC; fine for relative shape).
  const byHour = await c.env.DB.prepare(
    `SELECT CAST(strftime('%H', created_at) AS INTEGER) AS hour, COUNT(*) AS n ${base}
      GROUP BY hour ORDER BY hour`,
  ).all<any>();
  const totalEvents = await c.env.DB.prepare(`SELECT COUNT(*) AS n ${base}`).first<any>();
  return c.json({
    days,
    total_events: Number(totalEvents?.n ?? 0),
    top_features: ((topFeatures?.results ?? []) as any[]).map((r) => ({ feature: r.feature, n: Number(r.n), users: Number(r.users) })),
    top_actions: ((topActions?.results ?? []) as any[]).map((r) => ({ feature: r.feature, action: r.action, n: Number(r.n) })),
    top_screens: ((topScreens?.results ?? []) as any[]).map((r) => ({ screen: r.screen ?? 'unknown', n: Number(r.n), users: Number(r.users) })),
    funnel: ((funnel?.results ?? []) as any[]).map((r) => ({ feature: r.feature, users: Number(r.users) })),
    dau: ((dau?.results ?? []) as any[]).map((r) => ({ day: r.day, users: Number(r.users) })),
    by_role: ((byRole?.results ?? []) as any[]).map((r) => ({ role: r.role, n: Number(r.n), users: Number(r.users) })),
    by_hour: ((byHour?.results ?? []) as any[]).map((r) => ({ hour: Number(r.hour), n: Number(r.n) })),
  });
});

// Operational KPIs — the fundamental "how is the business really working"
// view, computed from the operational tables (NOT from app telemetry, which
// is lossy by design). Admin/ops only; no PII beyond aggregates.
app.get('/admin/analytics/ops', async (c) => {
  if (!isAdmin(c) && c.get('role') !== 'ops') return c.json({ error: 'forbidden' }, 403);
  const days = Math.min(Math.max(Number(c.req.query('days') ?? '30'), 1), 90);
  const since = `datetime('now', '-${days} days')`;
  const todayCAT = `date('now', '+2 hours')`;
  const one = async (sql: string) => Number((await c.env.DB.prepare(sql).first<any>())?.n ?? 0);
  const money = async (sql: string) => Math.round(Number((await c.env.DB.prepare(sql).first<any>())?.n ?? 0) * 100) / 100;

  const [
    booked, bookedToday, parcels, delivered, pickups, deliveredToday,
    activeSellers, activeRiders, ridersOnBooks, paygZmw, paygSuccess, paygFailed,
    walletCharges, walletChargesCount, subsActive, routesLearned,
  ] = await Promise.all([
    one(`SELECT COUNT(*) AS n FROM jobs WHERE created_at >= ${since}`),
    one(`SELECT COUNT(*) AS n FROM jobs WHERE date(created_at, '+2 hours') = ${todayCAT}`),
    one(`SELECT COALESCE(SUM(parcels), 0) AS n FROM jobs WHERE created_at >= ${since}`),
    one(`SELECT COUNT(DISTINCT job_id) AS n FROM job_events WHERE status = 'delivered' AND created_at >= ${since}`),
    one(`SELECT COUNT(DISTINCT job_id) AS n FROM job_events WHERE status = 'picked_up' AND created_at >= ${since}`),
    one(`SELECT COUNT(DISTINCT job_id) AS n FROM job_events WHERE status = 'delivered' AND date(created_at, '+2 hours') = ${todayCAT}`),
    one(`SELECT COUNT(DISTINCT sender_phone) AS n FROM jobs WHERE created_at >= ${since}`),
    one(`SELECT COUNT(DISTINCT rider_id) AS n FROM jobs WHERE rider_id IS NOT NULL AND created_at >= ${since}`),
    // Roster truth: verified + active riders on the books right now (not just
    // those who carried a parcel in the window) — this is the number every
    // rider sees on their Team tab via GET /team.
    one(`SELECT COUNT(*) AS n FROM riders WHERE active = 1 AND verification_status = 'verified'`),
    money(`SELECT COALESCE(SUM(amount_zmw), 0) AS n FROM payments WHERE status = 'success' AND kind = 'job' AND created_at >= ${since}`),
    one(`SELECT COUNT(*) AS n FROM payments WHERE status = 'success' AND kind = 'job' AND created_at >= ${since}`),
    one(`SELECT COUNT(*) AS n FROM payments WHERE status = 'failed' AND kind = 'job' AND created_at >= ${since}`),
    money(`SELECT COALESCE(SUM(-amount_zmw), 0) AS n FROM wallet_ledger WHERE amount_zmw < 0 AND kind IN ('job_charge', 'job_payment') AND created_at >= ${since}`),
    one(`SELECT COUNT(*) AS n FROM wallet_ledger WHERE amount_zmw < 0 AND kind IN ('job_charge', 'job_payment') AND created_at >= ${since}`),
    one(`SELECT COUNT(*) AS n FROM subscriptions WHERE status = 'active' AND (period_end IS NULL OR period_end > datetime('now'))`),
    one(`SELECT COUNT(*) AS n FROM quotes WHERE source = 'recorded' AND updated_at >= ${since}`),
  ]);

  const momoAttempts = paygSuccess + paygFailed;
  const momoSuccessPct = momoAttempts > 0 ? Math.round((1000 * paygSuccess) / momoAttempts) / 10 : null;
  const deliveryRatePct = booked > 0 ? Math.round((1000 * delivered) / booked) / 10 : null;

  return c.json({
    days,
    parcels_booked: booked,
    parcels_booked_today: bookedToday,
    parcels_shipped: parcels,
    deliveries: delivered,
    deliveries_today: deliveredToday,
    pickups,
    delivery_rate_pct: deliveryRatePct,
    active_sellers: activeSellers,
    active_riders: activeRiders,
    riders_on_books: ridersOnBooks,
    payg_collected_zmw: paygZmw,
    payg_success: paygSuccess,
    payg_failed: paygFailed,
    momo_success_pct: momoSuccessPct,
    wallet_charges_zmw: walletCharges,
    wallet_charge_jobs: walletChargesCount,
    subscriptions_active: subsActive,
    chargebook_routes_learned: routesLearned,
  });
});

/* Analytics KPI page (HTML) — server-rendered view of the same aggregation. */
app.get('/dashboard/analytics', async (c) => {
  if (!isAdmin(c) && c.get('role') !== 'ops') return c.json({ error: 'forbidden' }, 403);
  const phone = c.get('phone') ?? 'admin';
  const days = Math.min(Math.max(Number(c.req.query('days') ?? '30'), 1), 90);
  const since = `datetime('now', '-${days} days')`;
  const base = `FROM analytics_events WHERE created_at >= ${since}`;
  const total = await c.env.DB.prepare(`SELECT COUNT(*) AS n ${base}`).first<any>();
  const feats = await c.env.DB.prepare(
    `SELECT feature, COUNT(*) AS n, COUNT(DISTINCT phone) AS users ${base}
      GROUP BY feature ORDER BY n DESC LIMIT 10`,
  ).all<any>();
  const acts = await c.env.DB.prepare(
    `SELECT feature, action, COUNT(*) AS n ${base}
      GROUP BY feature, action ORDER BY n DESC LIMIT 14`,
  ).all<any>();
  const screens = await c.env.DB.prepare(
    `SELECT context AS screen, COUNT(*) AS n, COUNT(DISTINCT phone) AS users ${base}
      AND feature = 'screen' AND action = 'view'
      GROUP BY context ORDER BY n DESC LIMIT 15`,
  ).all<any>();
  const fun = await c.env.DB.prepare(
    `SELECT feature, COUNT(DISTINCT phone) AS users ${base}
      AND feature IN ('booking','subscriptions','pack_codes','rider_verification','collections')
      GROUP BY feature ORDER BY users DESC`,
  ).all<any>();
  const dau = await c.env.DB.prepare(
    `SELECT date(created_at) AS day, COUNT(DISTINCT phone) AS users ${base}
      GROUP BY day ORDER BY day`,
  ).all<any>();
  const byRol2 = await c.env.DB.prepare(
    `SELECT role, COUNT(*) AS n, COUNT(DISTINCT phone) AS users ${base}
      GROUP BY role ORDER BY n DESC`,
  ).all<any>();
  const byHour = await c.env.DB.prepare(
    `SELECT CAST(strftime('%H', created_at) AS INTEGER) AS hour, COUNT(*) AS n ${base}
      GROUP BY hour ORDER BY hour`,
  ).all<any>();
  const hourRows = ((byHour?.results ?? []) as any[]).map((r) => `<tr>
    <td>${Number(r.hour)}:00</td>
    <td>${Number(r.n)}</td>
  </tr>`).join('');

  const featureRows = ((feats?.results ?? []) as any[]).map((r) => `<tr>
    <td>${h(r.feature)}</td>
    <td>${Number(r.n)}</td>
    <td>${Number(r.users)}</td>
  </tr>`).join('');
  const screenRows = ((screens?.results ?? []) as any[]).map((r) => `<tr>
    <td>${h(r.screen ?? 'unknown')}</td>
    <td>${Number(r.n)}</td>
    <td>${Number(r.users)}</td>
  </tr>`).join('');
  const actionRows = ((acts?.results ?? []) as any[]).map((r) => `<tr>
    <td>${h(r.feature)}</td>
    <td>${h(r.action)}</td>
    <td>${Number(r.n)}</td>
  </tr>`).join('');
  const funnelRows = ((fun?.results ?? []) as any[]).map((r) => `<tr>
    <td>${h(r.feature)}</td>
    <td>${Number(r.users)}</td>
  </tr>`).join('');
  const dauRows = ((dau?.results ?? []) as any[]).map((r) => `<tr>
    <td>${r.day}</td>
    <td>${Number(r.users)}</td>
  </tr>`).join('');
  const roleRows = ((byRol2?.results ?? []) as any[]).map((r) => `<tr>
    <td>${h(r.role ?? 'anonymous')}</td>
    <td>${Number(r.n)}</td>
    <td>${Number(r.users)}</td>
  </tr>`).join('');
  const dayOpts = [7, 14, 30, 60, 90].map((d) => `<option value="${d}" ${d === days ? 'selected' : ''}>${d} days</option>`).join('');
  const b = `
  <div style="display:flex;justify-content:space-between;align-items:center;gap:10px;flex-wrap:wrap;margin-bottom:14px">
    <div class="metrics">
      <div class="metric"><div class="v">${Number(total?.n ?? 0)}</div><div class="l">Events (${days} days)</div></div>
      <div class="metric"><div class="v">${((feats?.results ?? []) as any[]).reduce((a: number, r: any) => a + Number(r.users), 0)}</div><div class="l">Active users</div></div>
    </div>
    <form style="display:flex;gap:6px;align-items:flex-end">
      <label style="font-size:12px;color:#65736d">Days</label>
      <select name="days" onchange="this.form.submit()" style="padding:6px 10px;border-radius:8px;border:1px solid #e2e6e1;font-size:13px">${dayOpts}</select>
    </form>
  </div>
  <div class="card">
    <h2>Most visited screens</h2>
    <table>
      <thead><tr><th>Screen</th><th>Views</th><th>Users</th></tr></thead>
      <tbody>${screenRows || '<tr><td colspan="3" class="empty">No screen events yet.</td></tr>'}</tbody>
    </table>
  </div>
  <div class="card">
    <h2>Feature usage leaderboard</h2>
    <table>
      <thead><tr><th>Feature</th><th>Events</th><th>Users</th></tr></thead>
      <tbody>${featureRows || '<tr><td colspan="3" class="empty">No events yet.</td></tr>'}</tbody>
    </table>
  </div>
  <div class="card">
    <h2>Top actions</h2>
    <table>
      <thead><tr><th>Feature</th><th>Action</th><th>Count</th></tr></thead>
      <tbody>${actionRows || '<tr><td colspan="3" class="empty">—</td></tr>'}</tbody>
    </table>
  </div>
  <div class="card">
    <h2>Conversion funnel (unique users)</h2>
    <table>
      <thead><tr><th>Milestone</th><th>Users</th></tr></thead>
      <tbody>${funnelRows || '<tr><td colspan="2" class="empty">—</td></tr>'}</tbody>
    </table>
  </div>
  <div style="display:flex;gap:12px;flex-wrap:wrap">
    <div class="card" style="flex:1;min-width:260px">
      <h2>Daily active users</h2>
      <table style="font-size:12px">
        <thead><tr><th>Day</th><th>Users</th></tr></thead>
        <tbody>${dauRows || '<tr><td colspan="2" class="empty">—</td></tr>'}</tbody>
      </table>
    </div>
    <div class="card" style="flex:1;min-width:260px">
      <h2>Hourly activity</h2>
      <table style="font-size:12px">
        <thead><tr><th>Hour</th><th>Events</th></tr></thead>
        <tbody>${hourRows || '<tr><td colspan="2" class="empty">No hourly data.</td></tr>'}</tbody>
      </table>
    </div>
    <div class="card" style="flex:1;min-width:260px">
      <h2>Usage by role</h2>
      <table style="font-size:12px">
        <thead><tr><th>Role</th><th>Events</th><th>Users</th></tr></thead>
        <tbody>${roleRows || '<tr><td colspan="3" class="empty">—</td></tr>'}</tbody>
      </table>
    </div>
  </div>
  `;
  return new Response(layout('Analytics', phone, b), { headers: { 'Content-Type': 'text/html; charset=utf-8' } });
});

/* ------------------------------ AI helpers -------------------------------- */
// Workers AI is FREE for this account. IMPORTANT: Meta Llama models require a
// one-time Meta License agreement ("prompt":"agree") or every call errors out —
// that is what made the AI stack silently fail since day 1. We now run
// exclusively on non-Meta models that need no agreement:
//   LLM  : @cf/mistralai/mistral-small-3.1-24b-instruct (Apache-2.0, strong JSON)
//   VISION: @cf/llava-hf/llava-1.5-7b-hf                (LLaVA vision)
const LLM_MODEL = '@cf/mistralai/mistral-small-3.1-24b-instruct';
const VISION_MODEL = '@cf/llava-hf/llava-1.5-7b-hf';

/** Run Workers AI with real diagnostics. Returns `null` on any failure but
 *  ALWAYS emits a `console.error` line so `wrangler tail` (and captured logs)
 *  show exactly why the call failed instead of a silent mystery. */
// Hugging Face Inference Providers (https://router.huggingface.co) — NOT free
// for this account (the supplied token returned HTTP 402 Payment Required,
// and the legacy free serverless endpoint is fully retired). Kept as an
// OPTIONAL paid path only: used when HF_API_KEY is set AND paid credits exist.
// PRIMARY AI is always the free Workers AI models chosen above.
// HF Inference API — returns null on any failure so callers can fall back
// to Workers AI or the safe envelope (never throws).
async function hfVision(env: Env, model: string, bytes: Uint8Array): Promise<string> {
  const key = (env as any).HF_API_KEY;
  if (!key) return '';
  try {
    const res = await fetch(`https://router.huggingface.co/hf-inference/models/${model}`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/octet-stream' },
      body: bytes,
    });
    if (!res.ok) {
      const t = (await res.text()).slice(0, 200);
      console.error(JSON.stringify({ where: 'hf_vision', model, status: res.status, err: t }));
      return '';
    }
    const out: any = await res.json().catch(() => null);
    const text = Array.isArray(out) ? out[0]?.generated_text : (out?.generated_text ?? '');
    return String(text ?? '').trim().slice(0, 300);
  } catch (e: any) {
    console.error(JSON.stringify({ where: 'hf_vision', model, err: String(e?.message ?? e).slice(0, 200) }));
    return '';
  }
}

async function hfText(env: Env, model: string, prompt: string, maxTokens = 220): Promise<string> {
  const key = (env as any).HF_API_KEY;
  if (!key) return '';
  try {
    const res = await fetch(`https://router.huggingface.co/v1/chat/completions`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model,
        messages: [{ role: 'user', content: prompt }],
        max_tokens: maxTokens,
        temperature: 0.2,
        stream: false,
      }),
    });
    if (!res.ok) {
      const t = (await res.text()).slice(0, 200);
      console.error(JSON.stringify({ where: 'hf_text', model, status: res.status, err: t }));
      return '';
    }
    const out: any = await res.json().catch(() => null);
    return String(out?.choices?.[0]?.message?.content ?? '').trim();
  } catch (e: any) {
    console.error(JSON.stringify({ where: 'hf_text', model, err: String(e?.message ?? e).slice(0, 200) }));
    return '';
  }
}

// Support the same image pairs with BLIP captioning — best on-device model
// for this job family on free tiers (Salesforce/blip-image-captioning-large).
const HF_VISION_MODEL = 'Salesforce/blip-image-captioning-large';
const HF_TEXT_MODEL = 'mistralai/Mistral-7B-Instruct-v0.3';

async function runAi(env: any, model: string, input: Record<string, unknown>): Promise<any> {
  if (!env?.AI) return null;
  try {
    return await (env.AI as any).run(model, input);
  } catch (e: any) {
    console.error(JSON.stringify({ where: 'workers_ai', model, err: String(e?.message ?? e).slice(0, 300) }));
    return null;
  }
}

// Address cleanup for the booking form: free text in, structured Lusaka address
// out. Best-effort; the app keeps the seller's original text when AI is off.
app.post('/ai/address', async (c) => {
  if (!c.get('phone')) return c.json({ error: 'sign_in_required' }, 401);
  const b: any = await c.req.json().catch(() => null);
  const text = String(b?.text ?? '').trim().slice(0, 400);
  if (text.length < 5) return c.json({ error: 'text_required' }, 400);
  const fallback = () => {
    const parts = text.split(',').map((p) => p.trim()).filter(Boolean);
    return { street: parts[0] ?? text, area: parts[1] ?? '', landmark: parts.slice(2).join(', '), phone: '', notes: '' };
  };
  if (!c.env.AI && !(c.env as any).HF_API_KEY) {
    return c.json({ fallback: true, parsed: fallback(), detail: 'AI unavailable (neither Workers AI binding nor HF_API_KEY set).' });
  }
  // PRIMARY: free Workers AI. FALLBACK: optional paid HF Mistral.
  // Tidy canonicalises against the zones Zambia actually books in (all cities
  // the app can name + top Lusaka delivery districts) so typos snap — "kabvata"
  // -> "Kabwata" — instead of being passed through verbatim.
  const zones = 'Lusaka, Lusaka districts: Kabwata, Kabulonga, Northmead, Rhodes Park, Roma, Woodlands, Avondale, Chalala, Garden, Kalingalinga, Mtendere, Kanyama, Libala, Thornpark, Chilenje, Matero, Chelstone, Chalimbana, Chibolya, Longacres, Chilanga, Ndola, Kitwe, Kabwe, Kapiri Mposhi, Livingstone, Chingola, Choma, Chipata, Solwezi, Kasama, Mongu, Mufulira, Luanshya, Kalulushi, Chililabombwe, Kasumbalesa, Mpongwe, Mumbwa, Mkushi, Serenje, Kafue, Mazabuka, Monze, Chinsali, Nakonde, Mpika, Mansa, Samfya, Chilanga, Chongwe, Katete, Petauke, Nyimba, Chadiza, Mbala, Kaputa, Isoka, Mafinga, Zambezi, Mufumbwe, Kasempa, Kalabo, Sesheke, Kazungula, Shangombo, Namwala, Itezhi-Tezhi, Kalomo, Zimba, Milenge, Nchelenge, Mwense, Chembe, Lufwanyama, Chingambwe.';
  const sys = 'You are Tidy, the DropOff address AI for Zambia. Normalise messy Zambian delivery addresses (senders type fast). Fix obvious spelling typos and abbreviations ONLY by snapping to the zones below. Reply with a SINGLE JSON object only, no markdown, exactly: {"street":"","area":"","city":"","landmark":"","phone":"","notes":"","plus_code":"","confidence":"high"}. Zones: ' + zones + '. Rules: never invent a street, area or town that is absent; when unsure keep the sender text untouched with confidence=low; if the text contains a plus code (e.g. 8FQ4+22 Lusaka), echo it EXACTLY into plus_code; city must be one of the zones when recognisable.';
  let out: any = await runAi(c.env, LLM_MODEL, {
    messages: [
      { role: 'system', content: sys },
      { role: 'user', content: `Address: ${text}` },
    ],
    max_tokens: 300,
  });
  if (!out && (c.env as any).HF_API_KEY) {
    const hfRaw = await hfText(c.env, HF_TEXT_MODEL,
      `${sys}\nAddress: ${text}`, 300);
    if (hfRaw) out = { response: hfRaw };
  }
  if (!out) {
    return c.json({ fallback: true, parsed: fallback(), detail: 'AI call failed — see wrangler tail logs for the exact model error.' });
  }
  let raw = '';
  if (typeof out?.response === 'string') raw = out.response;
  else if (typeof out?.choices?.[0]?.message?.content === 'string') raw = out.choices[0].message.content;
  else if (typeof out?.result === 'string') raw = out.result;
  else if (typeof out?.text === 'string') raw = out.text;
  else raw = JSON.stringify(out ?? '');
  const start = raw.indexOf('{');
  const end = raw.lastIndexOf('}');
  const parsed = start >= 0 && end > start ? JSON.parse(raw.slice(start, end + 1)) : fallback();
  return c.json({ fallback: false, parsed, raw: raw.slice(0, 400) });
});

// Draft (never auto-send) a support reply from the ticket history.
app.post('/admin/support/threads/:id/ai-draft', async (c) => {
  if (!isAdmin(c) && c.get('role') !== 'ops') return c.json({ error: 'forbidden' }, 403);
  if (!c.env.AI) return c.json({ error: 'ai_unavailable' }, 503);
  const id = Number(c.req.param('id'));
  const thread = await c.env.DB.prepare(
    `SELECT id, phone FROM chat_threads WHERE id = ?1 AND kind = 'support'`,
  ).bind(id).first<any>();
  if (!thread) return c.json({ error: 'not found' }, 404);
  const { results } = await c.env.DB.prepare(
    `SELECT sender_role, body FROM chat_messages WHERE thread_id = ?1 ORDER BY id DESC LIMIT 12`,
  ).bind(id).all<any>();
  const history = ((results ?? []) as any[]).reverse()
    .map((m) => `${m.sender_role === 'ops' ? 'DropOff' : 'Customer'}: ${String(m.body).slice(0, 400)}`).join('\n');
  try {
    let draft = '';
    // PRIMARY: free Workers AI (Mistral). FALLBACK: optional paid HF Mistral.
    if (c.env.AI) {
      try {
        const out: any = await runAi(c.env, '@cf/mistralai/mistral-small-3.1-24b-instruct', {
          messages: [
            { role: 'system', content: 'You are DropOff support in Lusaka, Zambia. Write a short, warm, concrete reply (max 90 words). Never promise refunds or payments you cannot verify; ask for the parcel reference when needed. Output the reply text only.' },
            { role: 'user', content: `Support ticket history:\n${history}\n\nWrite the next reply from DropOff.` },
          ],
          max_tokens: 260,
        });
        draft = (typeof out?.response === 'string' ? out.response
          : (typeof out?.choices?.[0]?.message?.content === 'string' ? out.choices[0].message.content : '')).trim();
      } catch { draft = ''; }
    }
    if (!draft) {
      draft = await hfText(c.env, HF_TEXT_MODEL,
        `You are DropOff support in Lusaka, Zambia. Write a short, warm, concrete reply (max 90 words). Never promise refunds or payments you cannot verify; ask for the parcel reference when needed. Output the reply text only.\n\nSupport ticket history:\n${history}\n\nWrite the next reply from DropOff.`,
        260);
    }
    if (!draft) return c.json({ error: 'ai_unavailable', detail: 'AI draft failed on Workers AI and the paid HF fallback (HF_API_KEY) — check `wrangler tail` for workers_ai logs.' }, 503);
    return c.json({ draft: draft.slice(0, 1200) });
  } catch (e: any) {
    return c.json({ error: 'ai_failed', detail: String(e?.message ?? e).slice(0, 200) }, 502);
  }
});

// Depot drop-off receipt / POD: the driver attaches a photo to the job
// (dropoff_photo_url), then AI reads the depot, parcel count, condition and
// flags damage or shortage. Owner/admins review it on the job; the result is
// kept as a job event so it can't be edited after the fact.
app.post('/ai/receipt/:ref', async (c) => {
  const phone = c.get('phone');
  if (!phone) return c.json({ error: 'sign_in_required' }, 401);
  if (!c.env.AI) return c.json({ error: 'ai_unavailable' }, 503);
  if (!c.env.BACKUPS) return c.json({ error: 'uploads_not_configured' }, 503);
  const ref = c.req.param('ref');
  const job = await c.env.DB.prepare(
    `SELECT id, ref, rider_id, sender_phone, dropoff_photo_url, status FROM jobs WHERE ref = ?1`,
  ).bind(ref).first<any>();
  if (!job) return c.json({ error: 'not found' }, 404);
  const role = c.get('role');
  const isAssignedRider = role === 'rider' && c.get('riderId') !== undefined && Number(c.get('riderId')) === Number(job.rider_id);
  if (!isAssignedRider && !isAdmin(c) && role !== 'ops') return c.json({ error: 'forbidden' }, 403);
  const key = r2KeyFromUrl(job.dropoff_photo_url);
  if (!key) return c.json({ error: 'no_receipt_photo', hint: 'Attach a depot drop-off photo to this job first.' }, 400);
  const object = await c.env.BACKUPS.get(key);
  if (!object) return c.json({ error: 'photo_missing' }, 404);
  const bytes = [...new Uint8Array(await object.arrayBuffer())];
  // PRIMARY: free Workers AI LLaVA. FALLBACK: optional paid HF TrOCR OCR.
  let text = '';
  try {
    const out: any = await runAi(c.env, '@cf/llava-hf/llava-1.5-7b-hf', {
      image: bytes,
      prompt: 'This is a delivery drop-off / proof-of-delivery photo at a courier depot. Transcribe everything visible: depot name or location, number of parcels or packages, condition of parcels, any damage, shortage or discrepancy notes, dates, times and signatures. Output only the transcribed text, no extra labels.',
      max_tokens: 400,
    });
    if (!out && (c.env as any).HF_API_KEY) {
      // Workers AI failed → the optional paid HF OCR path.
      text = await hfVision(c.env, 'microsoft/trocr-large-printed', new Uint8Array(bytes));
    }
    if (!out && !text) return c.json({ error: 'ai_unavailable', detail: 'Vision call failed on Workers AI and the paid HF fallback — check `wrangler tail` for workers_ai logs.' }, 503);
    if (out) text = String(out?.response ?? out?.description ?? '').trim().slice(0, 1200);
  } catch (e: any) {
    return c.json({ error: 'ai_failed', detail: String(e?.message ?? e).slice(0, 200) }, 502);
  }
  const norm = text.toLowerCase();
  const parcelMatch = text.match(/(\d+)\s*(parcel|package|box|item|piece)/i);
  const result = {
    text,
    depot_hint: '',
    parcel_count: parcelMatch ? Number(parcelMatch[1]) : null,
    damage_flag: /damage|broken|torn|leak|crushed|dented/i.test(norm),
    shortage_flag: /shortage|missing|less than|short|not all/i.test(norm),
    discrepancy_flag: /discrepancy|mismatch|wrong|incorrect/i.test(norm),
    checked_at: new Date().toISOString(),
  };
  await c.env.DB.prepare(
    `INSERT INTO job_events (job_id, status, note) VALUES (?1,'receipt_ai_check',?2)`,
  ).bind(job.id, JSON.stringify(result)).run().catch(() => {});
  return c.json({ ok: true, ref, ...result });
});

// Rider reputation: the rider's own rating summary + latest reviews.
app.get('/rider/reviews', async (c) => {
  const role = c.get('role');
  const phone = c.get('phone');
  if (!phone) return c.json({ error: 'sign_in_required' }, 401);
  if (role !== 'rider' && !isAdmin(c)) return c.json({ error: 'forbidden' }, 403);
  const rider = await c.env.DB.prepare(
    'SELECT id, full_name FROM riders WHERE phone = ?1 AND active = 1').bind(phone).first<any>() as any;
  if (!rider) return c.json({ error: 'rider_not_found' }, 404);
  const sum = await c.env.DB.prepare(
    `SELECT COUNT(*) AS n, COALESCE(ROUND(AVG(stars), 1), 0) AS avg FROM ratings
      WHERE target_type = 'rider' AND target_key = CAST(?1 AS TEXT) AND hidden = 0 AND verified = 1`,
  ).bind(rider.id).first<any>() as any;
  const recent = await c.env.DB.prepare(
    `SELECT stars, comment, created_at FROM ratings
      WHERE target_type = 'rider' AND target_key = CAST(?1 AS TEXT) AND hidden = 0 AND verified = 1
      ORDER BY created_at DESC, id DESC LIMIT 5`,
  ).bind(rider.id).all<any>();
  return c.json({
    rider: { id: rider.id, name: rider.full_name },
    n: Number(sum?.n ?? 0),
    average: Number(sum?.avg ?? 0),
    reviews: (recent.results ?? []),
  });
});

// Refund a settled payment to the payer's momo. Admin-key only: this moves money.
app.post('/admin/payments/:id/refund', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'forbidden' }, 403);
  const id = Number(c.req.param('id'));
  const pay = await c.env.DB.prepare(
    `SELECT id, job_id, phone, provider, amount_zmw, status FROM payments WHERE id = ?1`,
  ).bind(id).first<any>();
  if (!pay) return c.json({ error: 'not found' }, 404);
  if (pay.status !== 'success') return c.json({ error: 'only settled payments can be refunded' }, 409);
  const amount = Math.round(Number(pay.amount_zmw) * 100) / 100;
  if (!(amount > 0)) return c.json({ error: 'nothing to refund' }, 409);
  const ref = `refund-${pay.id}-${Date.now().toString(36)}`;
  const disb = await lipilaDisburse(c.env, pay.phone, amount, ref, `DropOff refund payment ${pay.id}`);
  if (!disb.ok) return c.json({ error: 'lipila refund failed', detail: disb.raw ?? null }, 502);
  await c.env.DB.batch([
    c.env.DB.prepare(
      `INSERT INTO payments (job_id, phone, provider, amount_zmw, credit_zmw, platform_fee_zmw,
         lipila_fee_zmw, lipila_reference, status, channel, kind, refund_of_payment_id, refunded_at)
       VALUES (?1,?2,?3,?4,0,0,0,?5,'pending','merchant','refund',?6,datetime('now'))`,
    ).bind(pay.job_id, pay.phone, pay.provider, amount, disb.lipilaReference ?? ref, pay.id),
    c.env.DB.prepare(`UPDATE payments SET status = 'refunded', refunded_at = datetime('now') WHERE id = ?1`).bind(pay.id),
  ]);
  if (pay.job_id) {
    await c.env.DB.prepare(
      `INSERT INTO job_events (job_id, status, note) VALUES (?1, 'refunded', ?2)`,
    ).bind(pay.job_id, `Payment ${pay.id} refunded K${amount} via momo`).run();
  }
  return c.json({ ok: true, refund_reference: disb.lipilaReference ?? ref, amount_zmw: amount });
});

// Growth dashboard: tiers, paygo regulars (target: 100 paying sellers/mo)
app.get('/admin/stats', async (c) => {
  if (!isFinanceExec(c)) return c.json({ error: 'forbidden' }, 403);
  const db = c.env.DB;
  const one = async (sql: string, ...bind: unknown[]) => (await db.prepare(sql).bind(...bind).first<any>())?.n ?? 0;
  const tiers = await db.prepare(
    `SELECT tier, COUNT(*) AS n FROM subscriptions WHERE status = 'active' GROUP BY tier`,
  ).all();
  const stats = {
    paying_sellers_active: (await db.prepare(
      `SELECT COUNT(DISTINCT phone) AS n FROM subscriptions WHERE status = 'active'
        AND (expires_at IS NULL OR expires_at > datetime('now'))`,
    ).first<any>())?.n ?? 0,
    subs_by_tier: tiers.results,
    paygo_last_30d: await one(
      `SELECT COUNT(DISTINCT sender_phone) AS n FROM jobs
        WHERE datetime(created_at, '${CAT_OFFSET}') > datetime('now', '-30 days') AND sender_phone NOT IN
        (SELECT phone FROM subscriptions WHERE status = 'active')`,
    ),
    paygo_regulars: await one(
      `SELECT COUNT(*) AS n FROM (
         SELECT sender_phone FROM jobs WHERE datetime(created_at, '${CAT_OFFSET}') > datetime('now', '-30 days')
         GROUP BY sender_phone HAVING COUNT(*) >= 3
       ) WHERE sender_phone NOT IN (SELECT phone FROM subscriptions WHERE status = 'active')`,
    ),
    parcels_last_30d: await one(
      `SELECT COUNT(*) AS n FROM jobs WHERE datetime(created_at, '${CAT_OFFSET}') > datetime('now', '-30 days')`,
    ),
    revenue_job_payments: await one(
      `SELECT COALESCE(SUM(amount_zmw), 0) AS n FROM payments WHERE status = 'success'
        AND kind = 'job' AND datetime(ifnull(paid_at, created_at), '${CAT_OFFSET}') > datetime('now', '-30 days')`,
    ),
    revenue_topups: await one(
      `SELECT COALESCE(SUM(amount_zmw), 0) AS n FROM payments WHERE status = 'success'
        AND kind = 'topup' AND datetime(ifnull(paid_at, created_at), '${CAT_OFFSET}') > datetime('now', '-30 days')`,
    ),
    // fee-engine income (Chisomo / Wardrobe-Valet pattern): what DropOff earned
    platform_fees_last_30d: await one(
      `SELECT COALESCE(SUM(platform_fee_zmw), 0) AS n FROM payments WHERE status = 'success'
        AND datetime(ifnull(paid_at, created_at), '${CAT_OFFSET}') > datetime('now', '-30 days')`,
    ),
    lipila_fees_last_30d: await one(
      `SELECT COALESCE(SUM(lipila_fee_zmw), 0) AS n FROM payments WHERE status = 'success'
        AND datetime(ifnull(paid_at, created_at), '${CAT_OFFSET}') > datetime('now', '-30 days')`,
    ),
    wallet_float_total: await one(`SELECT COALESCE(SUM(balance_zmw), 0) AS n FROM wallets`),
    // Platform revenue pipeline: total earned as fees sitting in the Lipila
    // merchant account vs how much has been swept to the business momo.
    lipila_earned_total: await one(
      `SELECT COALESCE(SUM(platform_fee_zmw), 0) AS n FROM payments WHERE status = 'success'`,
    ),
    business_swept_total: await one(
      `SELECT COALESCE(SUM(amount_zmw), 0) AS n FROM platform_disbursements WHERE status = 'success'`,
    ),
    lipila_undistributed: 0, // filled below (earned − swept)
    // Zambia compliance taxes (ZRA). Turnover = ALL successful payments.
    // Turnover Tax: 0% to K30,000 annual; 5% above K30,000 (2026 Act).
    turnover_total: await one(
      `SELECT COALESCE(SUM(amount_zmw), 0) AS n FROM payments WHERE status = 'success'`,
    ),
    cod_last_30d: await one(
      `SELECT COALESCE(SUM(cod_collected_zmw), 0) AS n FROM jobs
        WHERE cod_collected_zmw > 0 AND datetime(created_at, '${CAT_OFFSET}') > datetime('now', '-30 days')`,
    ),
    wait_fee_last_30d: await one(
      `SELECT COALESCE(SUM(wait_fee_zmw), 0) AS n FROM jobs
        WHERE wait_fee_zmw > 0 AND datetime(created_at, '${CAT_OFFSET}') > datetime('now', '-30 days')`,
    ),
    referrals_pending: await one(`SELECT COUNT(*) AS n FROM referrals WHERE status = 'pending'`),
    referrals_rewarded: await one(`SELECT COUNT(*) AS n FROM referrals WHERE status = 'rewarded'`),
  };
  // Compliance taxes (Zambia). Turnover = ALL successful payments (gross).
  // Turnover Tax (ZRA, 2026 Act): 0% up to K30,000 annual; 5% above K30,000
  // up to the K5,000,000 turnover-tax ceiling. Above that the business falls
  // under corporate income tax instead — flagged so you re-register in time.
  const turnover = Number((stats as any).turnover_total ?? 0);
  const over = Math.max(0, turnover - 30_000);
  const turnoverTax = round2(over * 0.05);
  (stats as any).compliance = {
    turnover_total_zmw: round2(turnover),
    turnover_tax_zmw: turnoverTax,
    turnover_tax_rate: turnover <= 30_000 ? 0 : 0.05,
    turnover_tax_headroom_zmw: Math.max(0, 5_000_000 - turnover),
    over_turnover_tax_ceiling: turnover > 5_000_000,
    note: 'Turnover tax applies to gross sales (all successful payments). ' +
      'Crossing K5,000,000 moves you to corporate income tax (30%) — re-register with ZRA.',
  };
  (stats as any).lipila_undistributed = round2(
    Number((stats as any).lipila_earned_total ?? 0) - Number((stats as any).business_swept_total ?? 0),
  );
  return c.json(stats);
});

/* ------------------- subscription auto-renewal (cron) ---------------------- */
// Billing sweeps 3 days before expiry; grace of 7 days before the pack lapses.
async function billExpiringSubscriptions(env: Env): Promise<{ billed: number; failed: number; expired: number }> {
  const due = await env.DB.prepare(
    `SELECT s.id, s.phone, s.tier FROM subscriptions s WHERE s.status = 'active'
       AND s.period_end IS NOT NULL AND s.period_end <= datetime('now', '+3 days')`,
  ).all().then((r: { results?: unknown[] }) => (r.results ?? []) as any[]);
  let billed = 0, failed = 0;
  for (const sub of due) {
    const plan = (await plans(env.DB))[sub.tier as PlanTier];
    if (!plan) continue;
    const existing = await env.DB.prepare(
      `SELECT id FROM payments WHERE subscription_id = ?1 AND status = 'pending'`,
    ).bind(sub.id).first<any>();
    if (existing) continue;
    const ref = `sub-${sub.id}-${new Date().toISOString().slice(0, 10).replace(/-/g, '')}`;
    // pack renewals carry the full collection fees (platform cut + Lipila legs)
    const pf = platformFee(plan.fee_zmw);
    const renewAmount = round2(plan.fee_zmw + pf + MOMO_COLLECTION_FEE);
    const init = await lipilaCollect(env, sub.phone, renewAmount, ref, `DropOff ${sub.tier} pack renewal`);
    if (init.ok) {
      await env.DB.prepare(
        `INSERT INTO payments (phone, provider, amount_zmw, credit_zmw, platform_fee_zmw,
           lipila_fee_zmw, lipila_reference, status, channel, kind, subscription_id)
         VALUES (?1,?2,?3,?4,?5,?6,?7,'pending','merchant','subscription',?8)`,
      ).bind(sub.phone, providerFromPhone(sub.phone), renewAmount, plan.fee_zmw, pf, MOMO_COLLECTION_FEE,
        init.lipilaReference ?? null, sub.id).run();
      billed++;
    } else {
      failed++;
    }
  }
  // lapse packs past their 30-day cycle (overage keeps them selling until renewal)
  const lapse = await env.DB.prepare(
    `UPDATE subscriptions SET status = 'expired'
      WHERE status = 'active' AND period_end IS NOT NULL AND period_end < datetime('now', '-7 days')
        AND NOT EXISTS (SELECT 1 FROM payments WHERE subscription_id = subscriptions.id AND status = 'pending')`,
  ).run();
  return { billed, failed, expired: lapse.meta.changes ?? 0 };
}

/* --------- cron: expiry/grace nudge (renewal prompt safety net) ------------ */
// Auto-renewal fires a Lipila prompt 3 days before expiry. If that prompt never
// surfaced (collect init failed / dismissed), the seller still finds out here:
// one SMS per cycle pre-expiry, and a lapsed-into-grace warning after.
async function notifyExpiryNudges(env: Env): Promise<void> {
  try {
    const now = `datetime('now')`;
    const { results } = await env.DB.prepare(
      `SELECT s.id, s.phone, s.tier, s.period_start, s.period_end, s.expiry_nudge_period,
              (SELECT COUNT(*) FROM payments p WHERE p.subscription_id = s.id AND p.status = 'pending') AS pending
         FROM subscriptions s
        WHERE s.status = 'active' AND s.period_end IS NOT NULL AND s.period_end <= datetime('now', '+3 days')`,
    ).all();
    for (const row of results as any[]) {
      const mark = String(row.expiry_nudge_period ?? '');
      const end = String(row.period_end);
      const key = mark.includes('|') ? mark : `${mark}|`; // legacy cap-nudge value never collides
      const lapsed = end < now.replace(/'/g, '');
      const want = `${String(row.period_start)}|${lapsed ? 'grace' : 'exp'}`;
      if (key.includes(want) || mark === want) continue;
      if (lapsed) {
        await sendSms(env, row.phone,
          `DropOff: your ${row.tier} pack lapsed on ${end.slice(0, 10)}; trips now bill ad hoc. Renew in the app to get your pack rate back.`);
      } else {
        if (Number(row.pending ?? 0) > 0) continue; // renewal prompt already on the phone
        await sendSms(env, row.phone,
          `DropOff: your ${row.tier} pack ends ${end.slice(0, 10)}. Renew in the app to keep your free rider rate (we auto-bill 3 days before - approve the prompt).`);
      }
      await env.DB.prepare('UPDATE subscriptions SET expiry_nudge_period = ?2 WHERE id = ?1')
        .bind(row.id, want).run().catch(() => {});
    }
  } catch { /* nudges are best-effort — never break the cron */ }
}

/* --------------------- cron: 19:00 driver target nudge --------------------- */
// Daily 19:00 CAT: any verified driver under 30 parcels gets one SMS with the
// day's remaining, month pace and deficit; the owner gets a compact shortfall
// list so gaps are caught before month-end rather than after.
/* ----------------------- cron: weekly ops digest (Mon) ---------------------- */
// Monday-morning digest for admins/ops/owner: parcels this week, deliveries,
// chargebook routes learned, and stale counter-fare rows to reconfirm. Push to
// every staff phone with a registered token; SMS fallback to the owner.
async function weeklyOpsDigest(env: Env): Promise<void> {
  try {
    const one = async (sql: string) => Number((await env.DB.prepare(sql).first<any>())?.n ?? 0);
    const [created, delivered, learned, stale, pendingKyc] = await Promise.all([
      one(`SELECT COUNT(*) AS n FROM jobs WHERE created_at >= datetime('now', '-7 days')`),
      one(`SELECT COUNT(*) AS n FROM job_events je WHERE je.status = 'delivered'
             AND je.created_at >= datetime('now', '-7 days')`),
      one(`SELECT COUNT(*) AS n FROM quotes WHERE source = 'recorded'
             AND updated_at >= datetime('now', '-7 days')`),
      one(`SELECT COUNT(*) AS n FROM quotes WHERE updated_at < datetime('now', '-90 days')`),
      one(`SELECT COUNT(*) AS n FROM riders WHERE verification_status = 'pending'`),
    ]);
    const title = 'DropOff weekly digest';
    const body = 'Week: ' +
      `${created} parcel${created === 1 ? '' : 's'} booked, ${delivered} delivered. ` +
      `Chargebook: ${learned} counter fare${learned === 1 ? '' : 's'} newly recorded. ` +
      (stale > 0 ? `${stale} rate${stale === 1 ? '' : 's'} stale (>90 days) — reconfirm at the counter.` : 'All rates fresh.') +
      (pendingKyc > 0 ? ` ${pendingKyc} driver verification${pendingKyc === 1 ? '' : 's'} waiting your review.` : '');
    // Recipients: owner + every admin/ops/cfo account with a phone on file.
    const owner = ownerPhone(env);
    const staff = await env.DB.prepare(
      `SELECT phone FROM auth_users WHERE role IN ('admin', 'ops', 'cfo') AND phone IS NOT NULL AND phone <> ''`,
    ).all<any>();
    const phones = new Set<string>();
    if (owner) phones.add(owner);
    for (const r of (staff.results ?? []) as any[]) phones.add(String(r.phone).trim());
    phones.delete('');
    let pushed = 0;
    for (const p of phones) {
      try {
        await sendToPhone(env, p, { title, body, data: { kind: 'ops_digest' } });
        pushed++;
      } catch { /* keep going — one dead token must not stop the digest */ }
    }
    if (pushed === 0 && owner) {
      await sendSms(env, owner, `DropOff weekly: ${body}`, { transactional: true });
    }
  } catch { /* digest is best-effort — never break the cron */ }
}

async function notifyRiderTargets(env: Env): Promise<void> {
  try {
    const { results } = await env.DB.prepare(
      `SELECT id, phone, full_name FROM riders
        WHERE active = 1 AND verification_status = 'verified'`,
    ).all<any>();
    const prog = await incentiveProgramme(env);
    const stats = await riderTargetStats(env.DB, undefined, prog);
    const short: { name: string; t: RiderTargetStats }[] = [];
    for (const r of (results ?? []) as any[]) {
      const t = stats.get(Number(r.id)) ?? shapeTargets(0, 0);
      if (t.daily_met) continue;
      short.push({ name: String(r.full_name ?? 'Driver'), t });
      await sendSms(env, r.phone,
        `DropOff target: ${t.today}/${t.daily_target} today, ${t.daily_remaining} to go. Month ${t.month}/${t.month_target}${t.on_track ? ' - on track' : ` - ${t.behind_by} behind pace`}. Check your queue.`);
    }
    if (short.length > 0 && env.OWNER_PHONE) {
      const lines = short.slice(0, 5).map((s) => `${s.name} ${s.t.today}/${s.t.daily_target}`).join(', ');
      await sendSms(env, env.OWNER_PHONE,
        `DropOff targets: ${short.length} driver(s) short today. ${lines}${short.length > 5 ? ` +${short.length - 5} more` : ''}. Full view in Admin > Targets.`, { transactional: true });
    }
  } catch { /* target nudges are best-effort */ }
}

/* --------------------- cron: 80%-cap renewal nudge ------------------------- */
// One SMS per cycle per seller, at >=80% of their effective cap. The nudge is
// honest: parcels left + renewal date + the upgrade lever.
async function notifyCapNudges(env: Env): Promise<void> {
  try {
    const packs = await plans(env.DB);
    const { results } = await env.DB.prepare(
      `SELECT s.id, s.phone, s.tier, s.period_start, s.period_end, s.cap_nudge_period,
              (SELECT COALESCE(SUM(j.parcels), 0) FROM jobs j
                WHERE j.sender_phone = s.phone AND j.created_at >= s.period_start
                  AND j.created_at < s.period_end) AS used
         FROM subscriptions s
        WHERE s.status = 'active' AND s.period_end IS NOT NULL AND s.period_end > datetime('now')`,
    ).all();
    for (const row of results as any[]) {
      const plan = packs[row.tier as PlanTier];
      if (!plan || !row.period_start) continue;
      const cap = plan.parcels_per_month;
      const used = Number(row.used ?? 0);
      if (cap <= 0 || used < cap * 0.8) continue;
      if (row.cap_nudge_period === row.period_start) continue; // once per cycle
      const left = Math.max(0, cap - used);
      const renewDate = String(row.period_end).slice(0, 10);
      await sendSms(env, row.phone,
        `DropOff: ${left} parcel${left === 1 ? '' : 's'} left on your ${row.tier} pack this cycle (renews ${renewDate}). Renew or upgrade in the app to keep your free rider rate.`);
      await env.DB.prepare('UPDATE subscriptions SET cap_nudge_period = ?2 WHERE id = ?1')
        .bind(row.id, row.period_start).run().catch(() => {});
    }
  } catch { /* nudges are best-effort — never break the cron */ }
}

/* ----------------------- cron: purge stale auth rows ----------------------- */
// rate_hits / login_attempts / expired otp_codes + email_tokens otherwise grow
// forever (every throttled request inserts a row).
async function purgeStaleRows(env: Env): Promise<void> {
  try {
    await env.DB.batch([
      env.DB.prepare(`DELETE FROM rate_hits WHERE created_at < datetime('now', '-2 hours')`),
      env.DB.prepare(`UPDATE subscriptions SET status = 'expired' WHERE status = 'pending_payment' AND period_end IS NOT NULL AND period_end < datetime('now', '-7 days')`),
      env.DB.prepare(`DELETE FROM subscriptions WHERE status = 'expired' AND period_end IS NOT NULL AND period_end < datetime('now', '-90 days')`),
      env.DB.prepare(`DELETE FROM login_attempts WHERE created_at < datetime('now', '-25 hours')`),
      env.DB.prepare(`DELETE FROM otp_codes  WHERE expires_at < datetime('now', '-1 day')`),
      env.DB.prepare(`DELETE FROM email_tokens WHERE expires_at < datetime('now', '-1 day')`),
      env.DB.prepare(`DELETE FROM job_events WHERE created_at IS NULL`), // data hygiene no-op guard
      env.DB.prepare(`DELETE FROM idempotency_keys WHERE created_at < datetime('now', '-7 days')`),
    ]);
  } catch { /* purge is best-effort — never break billing */ }
}

/* ----------------------- cron: daily app-data backup ----------------------- */
// Every CAT night at 02:00, dump core business entities from D1 as gzipped
// JSONL into R2 (dropoff-backups). Read-only: never mutates production data.
// If R2 isn't configured the cron silently skips (never blocks billing/purge).

async function gzipBytes(text: string): Promise<Uint8Array> {
  const stream = new CompressionStream('gzip');
  const writer = stream.writable.getWriter();
  writer.write(new TextEncoder().encode(text));
  writer.close();
  const chunks: Uint8Array[] = [];
  const reader = stream.readable.getReader();
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    chunks.push(value!);
  }
  const out = new Uint8Array(chunks.reduce((n, c) => n + c.byteLength, 0));
  let o = 0;
  for (const c of chunks) { out.set(c, o); o += c.byteLength; }
  return out;
}

async function dumpTable(env: Env, table: string): Promise<string | null> {
  try {
    const { results } = await env.DB.prepare(`SELECT * FROM ${table}`).all();
    const rows = (results ?? []) as any[];
    return rows.map((r) => JSON.stringify(r)).join('\n') + (rows.length ? '\n' : '');
  } catch { return null; }
}

async function backupAppData(env: Env): Promise<{ ok: string[]; skipped: string[]; manifest_key?: string }> {
  if (!env.BACKUPS) return { ok: [], skipped: [] };
  const tables = ['auth_users','jobs','payments','wallets','wallet_ledger','subscriptions',
    'recurring_plans','referrals','riders','couriers','quotes','job_events'];
  const stamp = new Date(Date.now() + 2 * 3600_000).toISOString().slice(0, 10); // CAT date
  const ok: string[] = [], skipped: string[] = [];
  for (const table of tables) {
    const payload = await dumpTable(env, table);
    if (payload == null) { skipped.push(table); continue; }
    const blob = await gzipBytes(payload);
    const key = `backups/${stamp}/${table}.jsonl.gz`;
    try {
      await env.BACKUPS.put(key, blob, { httpMetadata: { contentType: 'application/gzip' } });
      ok.push(key);
    } catch { skipped.push(table); }
  }
  const manifest = JSON.stringify({ date: stamp, ok, skipped, generated_at: new Date().toISOString() });
  try { await env.BACKUPS.put(`backups/${stamp}/manifest.json`, manifest, { httpMetadata: { contentType: 'application/json' } }); } catch {}
  return { ok, skipped, manifest_key: `backups/${stamp}/manifest.json` };
}

/* --------------------------- admin: backup on demand ----------------------- */
// Same dump the 02:00 CAT cron runs — lets you verify the R2 target and grab a
// fresh snapshot at any moment (e.g. before a large migration or launch).
app.get('/admin/backup-now', async (c) => {
  if (!isAdmin(c)) return c.json({ error: 'forbidden' }, 403);
  if (!c.env.BACKUPS) return c.json({ error: 'backups_not_configured' }, 503);
  const res = await backupAppData(c.env);
  return c.json({ ...res, ok: true, bucket: 'dropoff-backups' });
});

/* ------- prepaid refunds: canceled-before-pickup → back to source momo ----- */
// Single-purpose compliance guard: a sender's prepayment is pinned to exactly
// one parcel. When that booking dies before pickup, whatever part was never
// spent on the delivery goes back to the sender's original momo number via
// Lipila — DropOff does not keep it, and no generic stored credit grows. If
// Lipila cannot pay out (insufficient disbursement float, receiver off), the credit stays
// untouched and the event row tells ops to use /admin/payments/:id/refund.
async function refundUnspentPrepaid(
  env: Env,
  job: { id: number; ref: string | null; sender_phone: string },
): Promise<void> {
  const dep = await env.DB.prepare(
    `SELECT COALESCE(SUM(amount_zmw), 0) AS n, MIN(id) AS first_id FROM payments
      WHERE job_id = ?1 AND kind = 'booking_deposit' AND status = 'success'`,
  ).bind(job.id).first<any>();
  const prepaid = round2(Number(dep?.n ?? 0));
  if (prepaid <= 0) return; // charge-on-pickup or float sender — nothing to return
  // NOT A WALLET: the unspent residue is computed JOB-SCOPED from the audit
  // trail — this job's successful deposits minus what its ledger rows show
  // was charged or already refunded. Customer balances never hold the money,
  // so the refund never depends on (or drains) a stored balance.
  const spent = round2(Number((await env.DB.prepare(
    `SELECT COALESCE(SUM(-amount_zmw), 0) AS n FROM wallet_ledger
       WHERE job_id = ?1 AND kind = 'job_charge'`,
  ).bind(job.id).first<any>())?.n ?? 0));
  const refunded = round2(Number((await env.DB.prepare(
    `SELECT COALESCE(SUM(-amount_zmw), 0) AS n FROM wallet_ledger
       WHERE job_id = ?1 AND kind = 'prepaid_refund'`,
  ).bind(job.id).first<any>())?.n ?? 0));
  const unspent = round2(prepaid - Math.max(0, spent) - Math.max(0, refunded));
  if (unspent < 0.5) return; // fully spent or already refunded — nothing to return
  const ref = `prepay_refund-${job.id}-${Date.now().toString(36)}`;
  const disb = await lipilaDisburse(env, job.sender_phone, unspent, ref,
    `DropOff unspent prepayment ${job.ref ?? job.id}`.replace(/[^A-Za-z0-9 ]/g, ' '));
  if (!disb.ok) {
    // keep the credit exactly as it is; ops refunds it manually (admin refund
    // endpoint pays the sender's momo). Flag it on the job so it can't rot.
    await env.DB.prepare(
      `INSERT INTO job_events (job_id, status, note) VALUES (?1, 'prepaid_refund_failed', ?2)`,
    ).bind(job.id, `Auto-cancel: unspent prepayment K${unspent.toFixed(2)} could not be paid back to momo (Lipila payout failed — e.g. insufficient disbursement float or receiver off) — refund manually via /admin/payments/:id/refund.`).run();
    return;
  }
  // Audit row only — no balance to drain (customers hold no stored value);
  // the momo refund is recorded exactly like the admin refund path does.
  await env.DB.batch([
    env.DB.prepare(`INSERT INTO wallet_ledger (phone, amount_zmw, kind, job_id) VALUES (?1, ?2, 'prepaid_refund', ?3)`)
      .bind(job.sender_phone, -unspent, job.id),
    env.DB.prepare(
      `INSERT INTO payments (job_id, phone, provider, amount_zmw, credit_zmw, platform_fee_zmw,
         lipila_fee_zmw, lipila_reference, status, channel, kind, refund_of_payment_id, refunded_at)
       VALUES (?1,?2,?3,?4,0,0,0,?5,'pending','merchant','refund',?6,datetime('now'))`,
    ).bind(job.id, job.sender_phone, 'lipila', unspent, ref, dep?.first_id ?? null),
  ]);
  await sendSms(env, job.sender_phone,
    `DropOff: ${job.ref ?? ''} was canceled before pickup. Your unspent prepayment of K${unspent.toFixed(2)} has been returned to your momo.`, { transactional: true }).catch(() => {});
}

/* ------------------- cron: no-show auto-cancel + strikes ------------------ */
// Ghost bookings die on their own: a pickup that sits past its window (or an
// assignment that never moved) is auto-canceled, a strike lands on the
// sender's phone, and 3 strikes inside 14 days park new bookings for ops.
// Prepaid senders get their unspent prepayment returned to their momo
// automatically — no money of theirs ever stays behind.
async function addStrike(env: Env, phone: string, jobId: number, reason: string): Promise<void> {
  if (!phone) return;
  try {
    await env.DB.prepare('INSERT INTO booking_strikes (phone, job_id, reason) VALUES (?1, ?2, ?3)')
      .bind(phone, jobId, reason).run();
  } catch { /* strike bookkeeping must never break a cron */ }
}

// ------------------- cron: expire abandoned payment holds -------------------
// A HELD booking the sender never paid (prompt ignored, provider down, left
// the app) used to sit 'created' forever: it counted toward plan capacity,
// kept its single-use promo burned, and stayed on the books as a ghost. After
// 24 hours the hold expires — the booking dies, the promo use comes back, and
// the sender gets one clear SMS. NO strike: a failed prepayment is not a
// no-show. If the momo prompt is approved AFTER expiry, settlePaymentSuccess
// sees the canceled status and refunds it automatically.
async function cancelExpiredHolds(env: Env): Promise<number> {
  const { results } = await env.DB.prepare(
    `SELECT j.id, j.ref, j.sender_phone, j.promo_code
       FROM jobs j
      WHERE j.status = 'created' AND j.paid = 0
        AND j.created_at < datetime('now', '-24 hours')
        AND EXISTS (SELECT 1 FROM job_events e
                     WHERE e.job_id = j.id AND e.status IN ('advance_pending', 'prepayment_pending'))
      LIMIT 20`,
  ).all<any>();
  for (const job of (results ?? []) as any[]) {
    try {
      const refundPromo = job.promo_code
        ? [env.DB.prepare(
            `UPDATE promo_codes SET uses_left = COALESCE(uses_left, 0) + 1 WHERE code = ?1 AND uses_left IS NOT NULL`,
          ).bind(job.promo_code)]
        : [];
      await env.DB.batch([
        env.DB.prepare(
          `UPDATE jobs SET status = 'canceled' WHERE id = ?1 AND status = 'created' AND paid = 0`,
        ).bind(job.id),
        env.DB.prepare(`INSERT INTO job_events (job_id, status, note) VALUES (?1, 'hold_expired', ?2)`)
          .bind(job.id, 'Prepayment was never approved within 24 hours — booking canceled. No money was taken; book again anytime.'),
        ...refundPromo,
      ]);
      await sendSms(env, job.sender_phone,
        `DropOff: booking ${job.ref} was canceled - the prepayment was never approved in 24 hours. No rider was sent, no money taken.`, { transactional: true }).catch(() => {});
    } catch { /* never break the minute cron */ }
  }
  return (results ?? []).length;
}

async function cancelStaleOrders(env: Env): Promise<{ canceled: number }> {
  let canceled = 0;
  // A) assigned rides that never entered 'picked_up' within 3 hours
  const staleAssigned = await env.DB.prepare(
    `SELECT j.id, j.ref, j.sender_phone, r.id AS rider_id
       FROM jobs j LEFT JOIN riders r ON r.id = j.rider_id
      WHERE j.status = 'rider_assigned' AND j.assigned_at < datetime('now', '-3 hours')`,
  ).all<any>();
  for (const job of staleAssigned.results ?? []) {
    try {
      await env.DB.batch([
        env.DB.prepare(
          `UPDATE jobs SET status = 'canceled' WHERE id = ?1 AND status = 'rider_assigned'`,
        ).bind(job.id),
        ...(job.rider_id ? [env.DB.prepare(
          `UPDATE riders SET current_load = MAX(0, current_load - 1), status = 'available', route_updated_at = datetime('now') WHERE id = ?1`,
        ).bind(job.rider_id)] : []),
        env.DB.prepare(`INSERT INTO job_events (job_id, status, note) VALUES (?1, 'auto_canceled_no_show', ?2)`)
          .bind(job.id, 'Sender never handed the parcel over (3h grace) — auto-canceled; a no-show strike was recorded.'),
      ]);
      await addStrike(env, job.sender_phone, job.id, 'no_show_pickup');
      await sendSms(env, job.sender_phone,
        `DropOff: ${job.ref} was auto-canceled because the parcel wasn't handed over in time (no-show). Repeated missed pickups can pause new bookings.`, { transactional: true }).catch(() => {});
      await refundUnspentPrepaid(env, job).catch(() => { /* refund bookkeeping never breaks the cron */ });
      canceled++;
    } catch { /* never break the minute cron */ }
  }
  // B) slotted (never assigned) bookings whose window is long past
  const staleUnassigned = await env.DB.prepare(
    `SELECT j.id, j.ref, j.sender_phone
       FROM jobs j
      WHERE j.status = 'created'
        AND j.pickup_window IS NOT NULL AND j.pickup_window <> 'now'
        AND datetime(j.created_at, '+16 hours') < datetime('now')`,
  ).all<any>();
  for (const job of staleUnassigned.results ?? []) {
    try {
      await env.DB.batch([
        env.DB.prepare(
          `UPDATE jobs SET status = 'canceled' WHERE id = ?1 AND status = 'created'`,
        ).bind(job.id),
        env.DB.prepare(`INSERT INTO job_events (job_id, status, note) VALUES (?1, 'auto_canceled_no_show', ?2)`)
          .bind(job.id, 'Slotted booking stayed unassigned far past its window — auto-canceled; a no-show strike was recorded.'),
      ]);
      await addStrike(env, job.sender_phone, job.id, 'no_show_pickup');
      await sendSms(env, job.sender_phone,
        `DropOff: ${job.ref} was auto-canceled after its slot window (no-show). Repeated missed pickups can pause new bookings.`, { transactional: true }).catch(() => {});
      await refundUnspentPrepaid(env, job).catch(() => { /* refund bookkeeping never breaks the cron */ });
      canceled++;
    } catch { /* never break the minute cron */ }
  }
  return { canceled };
}

/* ------------ cron: auto-dispatch paid-but-unassigned jobs ----------------- */
// Operator-free dispatch (owner directive 2026-11-15): when a prepayment
// settles while every rider is busy (or a plan-covered booking was made
// during a rider gap), the nearest-available-rider algorithm picks the job
// up on the next minute sweep — nobody re-assigns it by hand. HELD bookings
// (prompt waiting / provider down) are excluded: no dispatch on credit.
async function redispatchUnassignedPaidJobs(env: Env): Promise<number> {
  // PAID JOBS ALWAYS DISPATCH (owner bug 2026-11-17): a paid job can never be
  // "on credit", so its stale advance_pending event (the at-booking prompt
  // that SETTLED) must not exclude it. Only UNPAID jobs still awaiting a
  // prompt or with a live payment row hold back — that is the no-credit rule.
  const { results } = await env.DB.prepare(
    `SELECT j.ref FROM jobs j
      WHERE j.rider_id IS NULL AND j.status = 'created'
        AND j.created_at > datetime('now', '-2 days')
        AND (
          j.paid = 1
          OR (
            NOT EXISTS (SELECT 1 FROM job_events e WHERE e.job_id = j.id AND e.status IN ('advance_pending', 'prepayment_pending'))
            AND NOT EXISTS (SELECT 1 FROM payments p WHERE p.job_id = j.id AND p.status IN ('pending', 'failed'))
            AND NOT EXISTS (SELECT 1 FROM payments p2 WHERE p2.job_id = j.id AND p2.kind IN ('booking_deposit', 'job'))
          )
        )
      LIMIT 20`,
  ).all<any>();
  let dispatched = 0;
  for (const row of (results ?? []) as any[]) {
    const pick = await dispatchToNearestRider(env, String(row.ref));
    if (pick) dispatched++;
  }
  return dispatched;
}

/* ------------------- cron: drift detection --------------------------------- */
// If a rider was assigned more than 2h ago and there's no pickup/depot event,
// or the job went to pickup but never reached the depot, flag it for ops review.
async function detectDrift(env: Env): Promise<void> {
  try {
    const rows = await env.DB.prepare(
      `SELECT j.id, j.ref, j.sender_phone, j.status
         FROM jobs j
        WHERE j.status IN ('rider_assigned', 'picked_up')
          AND datetime(j.assigned_at, '+2 hours') < datetime('now')
          AND NOT EXISTS (SELECT 1 FROM job_events e WHERE e.job_id = j.id AND e.status = 'drift_flagged')`,
    ).all<any>();
    for (const job of rows.results ?? []) {
      try {
        await env.DB.batch([
          env.DB.prepare(
            `INSERT INTO job_events (job_id, status, note) VALUES (?1, 'drift_flagged', ?2)`,
          ).bind(job.id, `Rider assigned but no pickup/depot confirmation after 2h — flagged for ops review.`),
          env.DB.prepare(`UPDATE jobs SET review_required = 1, fraud_score = fraud_score + 10 WHERE id = ?1`).bind(job.id),
          env.DB.prepare(
            `INSERT INTO fraud_flags (job_id, job_ref, phone, score, reasons, status) VALUES (?1, ?2, ?3, 10, 'rider_assigned_no_pickup_2h', 'open')`,
          ).bind(job.id, job.ref, job.sender_phone),
        ]);
      } catch { /* never break cron */ }
    }
    if ((rows.results?.length ?? 0) > 0) {
      await raiseAlert(env.DB, ownerPhone(env) ?? '', 'drift_detected', 'medium',
        `DropOff: ${rows.results?.length} job(s) assigned 2h+ ago with no pickup/depot confirmation. See Admin → Fraud queue.`).catch(() => {});
    }
  } catch (e) {
    /* never break cron */
  }
}

/* ------------- cron: timed-pickup reminders (every minute) ----------------- */
// Jobs with a booked pickup_at get a push at T-30 and T-10 to sender + rider,
// and are flagged 'missed' when the window passes without a status change.
// Keeps timed parcels honest without a separate queue infra.
async function checkTimedPickups(env: Env): Promise<void> {
  try {
    const now = new Date().toISOString();
    const due = await env.DB.prepare(
      `SELECT sp.job_ref, sp.phone, sp.rider_phone, sp.pickup_at, sp.status,
              j.pickup_address, j.dest_city, j.ref
         FROM scheduled_pickups sp
         JOIN jobs j ON j.ref = sp.job_ref
        WHERE sp.status = 'pending'
          AND sp.pickup_at <= datetime('now', '+30 minutes')
          AND sp.pickup_at > datetime('now', '-10 minutes')
           AND (j.status IS NULL OR j.status NOT IN ('delivered','ready_for_collection','canceled','cancelled'))
           AND NOT EXISTS (SELECT 1 FROM job_events e WHERE e.job_id = j.id AND e.status IN ('advance_pending', 'prepayment_pending'))`,
    ).all<{ job_ref: string; phone: string; rider_phone: string | null; pickup_at: string; pickup_address: string | null; dest_city: string | null; ref: string }>();
    const rows = (due.results ?? []) as any[];
    for (const r of rows) {
      const mins = Math.round((new Date(r.pickup_at).getTime() - new Date(now).getTime()) / 60000);
      const when = mins <= 0 ? 'now' : `in ${mins} min`;
      await sendToPhone(env, r.phone, {
        title: 'Timed pickup due',
        body: `Job ${r.job_ref} — ${r.pickup_address ?? ''} → ${r.dest_city ?? ''}, pickup ${when}.`,
        data: { job_ref: r.job_ref, kind: 'pickup_reminder' },
      });
      if (r.rider_phone && r.rider_phone !== r.phone) {
        await sendToPhone(env, r.rider_phone, {
          title: 'Rider: timed pickup due',
          body: `Job ${r.job_ref} — ${r.pickup_address ?? ''} → ${r.dest_city ?? ''}, pickup ${when}.`,
          data: { job_ref: r.job_ref, kind: 'pickup_reminder' },
        });
      }
      await env.DB.prepare(
        `UPDATE scheduled_pickups SET status = 'notified', notified_at = datetime('now')
          WHERE job_ref = ?1 AND status = 'pending'`,
      ).bind(r.job_ref).run();
    }
    // Missed: window passed and the job never left 'created'/'rider_assigned'
    await env.DB.prepare(
      `UPDATE scheduled_pickups SET status = 'missed'
        WHERE status = 'pending' AND pickup_at < datetime('now', '-10 minutes')
          AND job_ref IN (SELECT ref FROM jobs WHERE status IN ('created','rider_assigned'))`,
    ).run();
    // Completed: job moved on
    await env.DB.prepare(
      `UPDATE scheduled_pickups SET status = 'completed'
        WHERE status IN ('pending','notified')
          AND job_ref IN (SELECT ref FROM jobs WHERE status IN ('delivered','ready_for_collection'))`,
    ).run();
  } catch { /* timed pickups are best-effort — never block the cron */ }
}

/* ------------- cron: materialise recurring plans into jobs ----------------- */
// Standing orders become real jobs on their due day (CAT). Rules: weekly =
// the plan's weekday; biweekly = every other ISO week (parity by plan id);
// monthly = the weekday recurring every 4th week. A job is only created when a
// verified chargebook price exists — else the plan is skipped this run (never
// invent a fare). Jobs are pre-booked and need rider assignment as usual.
async function materializeRecurringJobs(env: Env): Promise<{ created: number; skipped: number }> {
  let created = 0, skipped = 0;
  try {
    const todayIso = new Date(Date.now() + 2 * 3600_000).toISOString().slice(0, 10); // CAT date
    const { results } = await env.DB.prepare(
      `SELECT * FROM recurring_plans WHERE active = 1 AND courier_id IS NOT NULL
         AND (last_created_at IS NULL OR last_created_at <> ?1)`,
    ).bind(todayIso).all();
    const catDate = new Date(todayIso + 'T12:00:00Z'); // mid-day so date math is stable
    const dow = catDate.getUTCDay() === 0 ? 7 : catDate.getUTCDay();          // 1=Mon … 7=Sun
    const isoWeek = Number(await env.DB.prepare("SELECT strftime('%W', ?1) AS w")
      .bind(todayIso).first<any>().then((r: any) => r?.w ?? '0'));            // 00–53
    for (const plan of results as any[]) {
      const due =
        plan.frequency === 'weekly' ? Number(plan.weekday) === dow :
        plan.frequency === 'biweekly' ? Number(plan.weekday) === dow && isoWeek % 2 === Math.abs(plan.id) % 2 :
        Number(plan.weekday) === dow && Math.floor(isoWeek / 4) % 2 === Math.abs(plan.id) % 2;
      if (!due) continue;
      const fromCity = plan.from_city ?? 'Lusaka';
      // Stale-quote decay: quotes untouched for 90+ days are ignored — the
      // standing order skips this cycle rather than price from a rotted rate.
      const quote = await env.DB.prepare(
        `SELECT counter_price_zmw FROM quotes
          WHERE courier_id = ?1 AND from_city = ?2 AND to_city = ?3 AND weight_class = ?4 AND service = 'standard'
            AND updated_at >= datetime('now', '-90 days')`,
      ).bind(plan.courier_id, fromCity, plan.dest_city, plan.weight_class ?? '0-5kg').first<any>();
      if (!quote) { skipped++; continue; }
      // STANDING-ORDER PARITY (owner directive 2026-11-15): a standing order
      // is a real parcel — it rides the sender's plan when there is capacity,
      // otherwise the DropOff leg is PREPAID BEFORE any rider is dispatched.
      // No plan → no prompt sent → never dispatched on credit.
      const base = baseRiderFee(fromCity, 0, 0, 'motorcycle');
      let riderFee = base;
      let planCovered = false;
      const sub = await env.DB.prepare(
        `SELECT tier, period_start, period_end FROM subscriptions WHERE phone = ?1 AND status = 'active'
           AND period_end IS NOT NULL AND period_end > datetime('now')`,
      ).bind(plan.phone).first<any>();
      if (sub?.period_start && sub?.period_end) {
        const packs = await plans(env.DB, { forExistingSubscribers: true });
        const planInfo = packs[sub.tier as PlanTier];
        const overageOn = flagOn(await getSetting(env.DB, 'overage_discount_enabled'));
        if (planInfo) {
          const used = await env.DB.prepare(
            `SELECT COALESCE(SUM(parcels * COALESCE(billable_rides, 1)), 0) AS n FROM jobs j
              WHERE sender_phone = ?1
                AND created_at >= ?2 AND created_at < ?3
                AND status NOT IN ('cancelled', 'canceled')
                AND NOT EXISTS (SELECT 1 FROM job_events e WHERE e.job_id = j.id AND e.status IN ('advance_pending', 'prepayment_pending'))
                AND NOT EXISTS (SELECT 1 FROM payments p WHERE p.job_id = j.id AND p.kind IN ('booking_deposit', 'job'))`,
          ).bind(plan.phone, sub.period_start, sub.period_end).first<any>();
          const cycleDays = Number(planInfo.cycle_days ?? 30) || 30;
          const cap = cycleDays <= 1
            ? (planInfo.parcels_per_day || planInfo.parcels_per_month)
            : (planInfo.parcels_per_month || planInfo.parcels_per_day);
          if (((used?.n ?? 0) + 1) <= cap) {
            riderFee = planInfo.rider_fee_zmw;
            planCovered = true;
          } else {
            // Over cap: the standing order still gets the tier's overage
            // discount on the PAYG leg — same math as a normal booking.
            riderFee = tierOverageFee(sub.tier, base, overageOn ? planInfo.overage_discount_pct : 0);
          }
        }
      }
      const totals = computeJobTotals({
        counterPriceZmw: Number(quote.counter_price_zmw),
        riderFeeZmw: riderFee,
      });
      const ref = `DRO-${todayIso.replace(/-/g, '')}-${randomCode(5)}`;
      try {
        const { meta } = await env.DB.prepare(
          `INSERT INTO jobs (ref, sender_phone, sender_name, pickup_address, courier_id,
             recipient_name, recipient_phone, dest_city, description, weight_class,
             counter_price_zmw, rider_fee_zmw, total_zmw, pay_method)
           VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, 'mobile_money')`,
        ).bind(
          ref, plan.phone, plan.sender_name || 'DropOff customer', plan.pickup_address ?? 'Address on file', plan.courier_id,
          plan.recipient_name ?? null, plan.recipient_phone ?? null, plan.dest_city,
          plan.description ?? (freqLabel(plan.frequency) + ' standing order'),
          plan.weight_class ?? '0-5kg',
          Number(quote.counter_price_zmw), riderFee, totals.total_zmw,
        ).run();
        if (planCovered) {
          await env.DB.prepare('INSERT INTO job_events (job_id, status, note) VALUES (?1, ?2, ?3)')
            .bind(meta.last_row_id, 'created', 'Standing order created — covered by plan, no prepayment required.').run();
          const pick = await dispatchToNearestRider(env, ref);
          if (!pick) {
            await env.DB.prepare('INSERT INTO job_events (job_id, status, note) VALUES (?1, ?2, ?3)')
              .bind(meta.last_row_id, 'created', 'Standing order created — no verified rider available; the minute cron retries dispatch.').run();
          }
        } else {
          const depAmount = round2(riderFee + round2(platformFee(riderFee)) + MOMO_COLLECTION_FEE);
          const collect = await lipilaCollect(env, plan.phone, depAmount,
            `adv-${ref}`, `DropOff advance ${ref}`.replace(/[^A-Za-z0-9 ]/g, ' ')).catch(() => ({ ok: false } as any));
          if (collect.ok) {
            await env.DB.batch([
              env.DB.prepare(
                `INSERT INTO payments (job_id, phone, provider, amount_zmw, credit_zmw, platform_fee_zmw,
                   lipila_fee_zmw, lipila_reference, status, channel, kind)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, 'pending', 'merchant', 'booking_deposit')`,
              ).bind(meta.last_row_id, plan.phone, providerFromPhone(plan.phone), depAmount, depAmount,
                round2(platformFee(riderFee)), MOMO_COLLECTION_FEE, collect.lipilaReference ?? `adv-${ref}`),
              env.DB.prepare('INSERT INTO job_events (job_id, status, note) VALUES (?1, ?2, ?3)')
                .bind(meta.last_row_id, 'advance_pending', 'Advance payment prompt sent for this standing order — dispatch at settlement.'),
            ]);
            await sendSms(env, plan.phone,
              `DropOff: your standing order for ${plan.dest_city} (${ref}) is due now — approve the K${depAmount.toFixed(2)} prepayment to dispatch your rider.`, { transactional: true }).catch(() => {});
          } else {
            await env.DB.prepare('INSERT INTO job_events (job_id, status, note) VALUES (?1, ?2, ?3)')
              .bind(meta.last_row_id, 'prepayment_pending', 'Standing order created but the prepayment prompt could not start — HELD; open Bookings and tap Pay now to dispatch.').run();
            await sendSms(env, plan.phone,
              `DropOff: standing order ${ref} is HELD - the momo prompt failed. Open Bookings and tap Pay now to dispatch your rider.`, { transactional: true }).catch(() => {});
          }
        }
        created++;
        await env.DB.prepare('UPDATE recurring_plans SET last_created_at = ?2 WHERE id = ?1')
          .bind(plan.id, todayIso).run();
      } catch {
        skipped++;
      }
    }
  } catch { /* recurring is best-effort — do not fail the cron */ }
  return { created, skipped };
}

function freqLabel(f: string): string {
  return f === 'weekly' ? 'Weekly' : f === 'biweekly' ? 'Fortnightly' : 'Monthly';
}

/* --------------------------- error reporting ------------------------------ */
// Minimal Sentry "store" client (no SDK): one POST per uncaught error. Safe to
// leave unset — telemetry must never break a delivery.
/**
 * Daily silent-failure detector (19:00 UTC cron):
 *  - 5xx storm: more than 15 server errors in the last day → SMS the admin
 *    (once per UTC day, tracked in app_settings.last_5xx_alert).
 *  - Dead pipeline: active subscriptions exist but ZERO deliveries in 48h.
 * Both are best-effort: a ping that never sends is worse than a false alarm,
 * a missed signal is worse than either.
 */
async function eveningHealthProbe(env: Env): Promise<void> {
  const db = env.DB;
  const admin = ownerPhone(env);
  const alertToday = async (key: string) => (await getSetting(db, key));
  const stampAlert = async (key: string) => setSetting(db, key, new Date().toISOString(), 'cron:evening-probe');
  const todayIso = new Date().toISOString().slice(0, 10);

  // 1) server-error storm
  const fivexx = await db.prepare(
    `SELECT COUNT(*) AS n FROM error_events WHERE status >= 500 AND created_at > datetime('now', '-1 day')`,
  ).first<any>();
  if (Number(fivexx?.n ?? 0) > 15 && (await alertToday('last_5xx_alert')) !== todayIso && admin) {
    await sendSms(env, admin, `DropOff health: ${fivexx.n} server errors in 24h — check Workers Logs. The app may be erroring for users.`, { transactional: true });
    await stampAlert('last_5xx_alert');
  }

  // 2) dead pipeline
  const active = await db.prepare(`SELECT COUNT(*) AS n FROM subscriptions WHERE status = 'active'`).first<any>();
  const delivered = await db.prepare(
    `SELECT COUNT(*) AS n FROM job_events WHERE status IN ('delivered', 'ready_for_collection') AND created_at > datetime('now', '-48 hours')`,
  ).first<any>();
  if (Number(active?.n ?? 0) > 0 && Number(delivered?.n ?? 0) === 0 && (await alertToday('last_dead_pipeline_alert')) !== todayIso && admin) {
    await sendSms(env, admin, 'DropOff health: active packs exist but ZERO deliveries in 48h — dispatch or payments may be down. Check the console now.', { transactional: true });
    await stampAlert('last_dead_pipeline_alert');
  }
}

// UPTIME MONITOR (owner 2026-11-18): every 5 minutes the Worker checks its own
// health endpoint, records the result in D1 and alerts the owner on the first
// failure and every 6th consecutive failure (30 min). An UptimeRobot-style
// heartbeat without needing a separate account.
async function runUptimeProbe(env: Env): Promise<void> {
  const base = String(env.APP_URL ?? 'https://api.carpsosolutions.store').replace(/\/$/, '');
  const url = `${base}/health`;
  const ac = new AbortController();
  const timer = setTimeout(() => ac.abort(), 8000);
  const t0 = Date.now();
  let ok = false, status = 0, detail = '';
  try {
    const res = await fetch(url, { signal: ac.signal });
    status = res.status;
    const body = await res.text().catch(() => '');
    try { ok = res.ok && (JSON.parse(body)?.ok === true); } catch { ok = false; }
    detail = body.slice(0, 160);
  } catch (e: any) {
    detail = String(e?.message ?? e).slice(0, 160);
  } finally {
    clearTimeout(timer);
  }
  const latency = Date.now() - t0;
  try {
    await env.DB.prepare(
      'INSERT INTO uptime_checks (ok, status, latency_ms, detail) VALUES (?1, ?2, ?3, ?4)',
    ).bind(ok ? 1 : 0, status, latency, detail).run();
  } catch { /* logging must never break the probe */ }
  if (ok) return;
  let consecutive = 0;
  try {
    const rows = await env.DB.prepare('SELECT ok FROM uptime_checks ORDER BY id DESC LIMIT 12').all<any>();
    for (const r of (rows.results ?? [])) { if (Number(r.ok) === 0) consecutive++; else break; }
  } catch { consecutive = 1; }
  if (consecutive !== 1 && consecutive % 6 !== 0) return;
  const msg = `DropOff API DOWN for ~${consecutive * 5} min — ${url} returned ${status || 'no response'} (${detail}). Check Workers logs.`;
  const phone = ownerPhone(env);
  if (phone) await sendToPhone(env, phone, {
    title: 'DropOff API DOWN', body: msg, data: { kind: 'security_alert' },
  }).catch(() => {});
  const email = ownerEmail(env);
  if (email) await sendMail(env, { to: email, subject: 'DropOff API DOWN', text: msg, html: `<p>${msg}</p>` }).catch(() => {});
}

async function captureError(env: Env, err: unknown, req: { method: string; url: string }): Promise<void> {
  // Always record to D1 first — the daily health probe reads error_events.
  // Sentry remains optional when SENTRY_DSN is set.
  try {
    await env.DB.prepare(
      'INSERT INTO error_events (req_id, method, path, status, message) VALUES (?1, ?2, ?3, ?4, ?5)',
    ).bind(
      crypto.randomUUID(),
      String(req.method ?? 'ERR').slice(0, 8),
      String(new URL(req.url).pathname).slice(0, 160),
      500,
      String((err as any)?.message ?? err).slice(0, 400),
    ).run();
  } catch { /* telemetry is best-effort */ }
  const dsn = env.SENTRY_DSN;
  if (!dsn) return;
  try {
    const u = new URL(dsn);
    const project = u.pathname.replace(/^\//, '');
    const e = err as any;
    const event = {
      event_id: crypto.randomUUID().replace(/-/g, ''),
      timestamp: new Date().toISOString(),
      platform: 'javascript',
      level: 'error',
      logger: 'dropoff-worker',
      environment: env.ENV ?? 'production',
      transaction: `${req.method} ${new URL(req.url).pathname}`,
      exception: { values: [{ type: e?.name ?? 'Error', value: String(e?.message ?? e).slice(0, 1000) }] },
    };
    await fetch(`${u.protocol}//${u.host}/api/${project}/store/`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Sentry-Auth': `Sentry sentry_version=7, sentry_key=${u.username}, sentry_client=dropoff-worker/1.0`,
      },
      body: JSON.stringify(event),
    });
  } catch { /* telemetry is best-effort */ }
}

/* ------------------------- guaranteed-JSON failures ------------------------- */
// Hono's default plain-text 500/404 breaks clients that expect JSON — the app
// surfaced any unhandled throw as a vague "network error". Every error is now
// a clean JSON body; the client can render the real story.
app.notFound((c) => c.json({ error: 'not_found' }, 404));
app.onError((err, c) => {
  try {
    console.error(JSON.stringify({
      where: 'onError',
      method: c.req.method,
      path: c.req.path,
      message: String((err as any)?.message ?? err).slice(0, 300),
    }));
  } catch { /* logging must never throw */ }
  captureError(c.env, err, { method: c.req.method, url: c.req.path }).catch(() => {});
  return c.json({ error: 'internal_error' }, 500);
});

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    try {
      // Realtime chat: hand WebSocket upgrades to the per-thread Durable Object.
      const url = new URL(request.url);
      if (url.pathname.startsWith('/ws/chat/')) {
        if (request.headers.get('Upgrade')?.toLowerCase() !== 'websocket') {
          return new Response(JSON.stringify({ error: 'websocket_required' }), {
            status: 426, headers: { 'Content-Type': 'application/json' },
          });
        }
        const id = env.CHAT.idFromName(url.pathname);
        return env.CHAT.get(id).fetch(request);
      }
      return await app.fetch(request, env, ctx);
    } catch (e) {
      await captureError(env, e, request);
      return new Response(JSON.stringify({ error: 'internal_error' }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      });
    }
  },
  async scheduled(event: ScheduledEvent, env: Env, ctx: ExecutionContext): Promise<void> {
    ctx.waitUntil((async () => {
      try {
        if (event.cron === '*/5 * * * *') {
          await runUptimeProbe(env);
          return;
        }
        if (event.cron === '0 19 * * *') {
          try { await eveningHealthProbe(env); } catch (e) {
            await captureError(env, e, { method: 'CRON', url: 'https://cron/evening-probe' });
          }
          await notifyRiderTargets(env);
          return;
        }
        // Weekly ops digest: Monday 08:00 CAT (06:00 UTC) — parcels,
        // deliveries, chargebook growth, stale rates to reconfirm.
        if (event.cron === '0 6 * * MON') {
          await weeklyOpsDigest(env);
          return;
        }
        // Weekly rider payroll: Sunday 16:00 CAT (crons run UTC → 14:00 UTC).
        if (event.cron === '0 14 * * SUN') {
          try { await generatePayroll(env, 'weekly'); } catch (e) {
            await captureError(env, e, { method: 'CRON', url: 'https://cron/payroll-weekly' });
          }
          return;
        }
        // Monthly rider payroll + prior-month tax ledger close: 1st, 16:00 CAT.
        if (event.cron === '0 14 1 * *') {
          const lastMonth = catYm(new Date(Date.now() + 2 * 60 * 60 * 1000), 1);
          try { await generatePayroll(env, 'monthly'); } catch (e) {
            await captureError(env, e, { method: 'CRON', url: 'https://cron/payroll-monthly' });
          }
          try { await updateTaxPeriod(env, lastMonth); } catch (e) {
            await captureError(env, e, { method: 'CRON', url: 'https://cron/tax-period' });
          }
          return;
        }
        if (event.cron === '* * * * *') {
          await cancelStaleOrders(env);
          await cancelExpiredHolds(env);
          await checkTimedPickups(env);
          await detectDrift(env);
          await redispatchUnassignedPaidJobs(env);
          await healMissingTrackingSms(env);
          await notifyCapNudges(env);
          await notifyExpiryNudges(env);
          return;
        }
        // Daily chain — each task isolated so one failure (e.g. a Lipila
        // collect throw in billing) can no longer starve the rest. Before
        // this fix a single nightly exception silently skipped the R2
        // backup, payment reconcile AND the platform income sweep (the
        // outer catch only logged to Sentry, which is not configured).
        const daily: Array<[string, () => Promise<unknown>]> = [
          ['purge', () => purgeStaleRows(env)],
          ['backup', () => backupAppData(env)],
          ['reconcile', () => reconcilePayments(env)],
          ['sweep', () => sweepPlatformIncome(env)],
          ['bill', () => billExpiringSubscriptions(env)],
          ['recurring', () => materializeRecurringJobs(env)],
          ['tax', () => updateTaxPeriod(env, catYm(new Date(Date.now() + 2 * 60 * 60 * 1000), 1))],
        ];
        for (const [name, task] of daily) {
          try { await task(); } catch (e) {
            await captureError(env, e, { method: 'CRON', url: `https://cron/daily/${name}` });
            try {
              await env.BACKUPS?.put(
                `cron_errors/daily-${name}-${new Date().toISOString().slice(0, 19)}.json`,
                JSON.stringify({ task: name, at: new Date().toISOString(), error: String(e).slice(0, 500) }),
                { httpMetadata: { contentType: 'application/json' } },
              );
            } catch { /* logging must never throw */ }
          }
        }
      } catch (e) {
        await captureError(env, e, { method: 'CRON', url: `https://cron/${event.cron}` });
      }
    })());
  },
};
