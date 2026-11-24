// DropOff fee engine — kwacha (ZMW), 2-decimal money.
//
// MODEL (per owner instruction — OPERATING STANDARD, approved 2026-11-10):
//   • Riders are SALARIED. No rider is ever paid per parcel, per trip, or out
//     of a plan. Sweep riders are paid the fixed K3,000/month package
//     INCLUSIVE of the K300/week fuel allowance (base wage K1,800), pace-gated
//     — see rider_payroll in index.ts (auto-generated, admin→superadmin
//     confirmed, proof-of-payment per payout).
//   • Because the rider cost is the fixed salary, the CONFIRMED rider-fee
//     policy on pay-as-you-go jobs is: the rider fee charged to the seller
//     stays with DropOff as revenue (nothing is paid out per trip to salaried
//     riders). PAYG/plan bookings alike count toward the rider's sweep
//     targets, which are the pace gate on the salary.
//   • The customer still pays the base + a single "processing fee" (platform
//     cut + Lipila mobile-money collection leg) and NEVER pays for any rider
//     settlement.
//   • The per-trip division below (90% share / payoutNet) is kept ONLY as
//     dormant pricing machinery for a future non-salaried (marketplace)
//     rider mode. It must NOT be used to credit salaried sweep riders.

export const PLATFORM_FEE_PCT = 1.0;     // 1% of the customer base
export const PLATFORM_FIXED_FEE = 0.98;  // + K0.98 per collection (was 0.48 — raised 2026-11-17: SMS/notification + ops costs)
export const PLATFORM_MIN_FEE = 4.0;     // minimum platform portion (K4.00, was K3.00 — same raise)
export const MOMO_COLLECTION_FEE = 2.5;  // Lipila collect leg (passed to customer)
export const MOMO_DISBURSEMENT_FEE = 1.5; // Lipila payout leg (rider-side)

// Lenco (Zambia, lenco.co/zm/pricing, checked 2026-11-24):
// Collections mobile money: 1% (bearer merchant => deducted from settlement;
// bearer customer => added on top of amount). We currently use bearer merchant.
// Payout mobile money: tiered by amount.
export const LENCO_COLLECTION_PCT = 1.0;
/** Flat fee charged to sender on every depot counter-fare repayment.
 *  Covers rider queue/disbursement cost (Lenco payout fees are ~K8.50-K12 for small amounts).
 *  Total sender pays = receipt + processing_fee + depot_queue_fee. */
export const DEPOT_QUEUE_FEE_ZMW = 9;
export const LENCO_PAYOUT_TIERS_ZMW = [
  { max: 1000, minFee: 8.5, maxFee: 12 },
  { max: 50000, minFee: 15, maxFee: 25 },
  { max: 100000000, minFee: 35, maxFee: 35 },
] as const;

export function lencoCollectionFee(amountZmw: number): number {
  return round2(Math.max(0, amountZmw) * (LENCO_COLLECTION_PCT / 100));
}

/** Conservative upper-bound estimate for budgeting; actual Lenco fee is tiered
 *  within the band. Use maxFee for safety until Lenco exposes exact fee. */
export function lencoDisbursementFeeEstimate(amountZmw: number): { min: number; max: number } {
  const amt = Math.max(0, amountZmw);
  const tier = LENCO_PAYOUT_TIERS_ZMW.find((t) => amt <= t.max) ?? LENCO_PAYOUT_TIERS_ZMW[LENCO_PAYOUT_TIERS_ZMW.length - 1];
  return { min: tier.minFee, max: tier.maxFee };
}
/** Platform revenue sweep: minimum undistributed balance before the cron
 *  disburses to the business momo. Keeps the Lipila wallet healthy without
 *  paying a disbursement fee on dust. */
export const PLATFORM_SWEEP_MIN_ZMW = 50;
export const RIDER_TAKE_PCT = 10.0;      // platform take of the rider fee

export const round2 = (v: number) => Math.round((v + Number.EPSILON) * 100) / 100;

export function platformFee(amount: number): number {
  const flat = PLATFORM_MIN_FEE + PLATFORM_FIXED_FEE;
  const pct = round2(amount * (PLATFORM_FEE_PCT / 100)) + PLATFORM_FIXED_FEE;
  return round2(pct > flat ? pct : flat);
}

export function riderShareOf(riderFeeZmw: number): number {
  return round2(riderFeeZmw * (1 - RIDER_TAKE_PCT / 100));
}

/** Rider's take-home: 90% share minus their payout transaction fees. */
export function payoutNet(riderFeeZmw: number): number {
  const share = riderShareOf(riderFeeZmw);
  return round2(share - MOMO_DISBURSEMENT_FEE - platformFee(share));
}

export type GatewayFeeProvider = 'lipila' | 'lenco';

export interface CollectionFees {
  /** money for goods + rider service, before any processing */
  base: number;
  /** what the RIDER receives at payout (90% − transaction fees) */
  rider_payout_zmw: number;
  /** the one customer-visible line item: DropOff platform cut + provider collection fee */
  processing_fee_zmw: number;
  /** DropOff's platform portion of the processing fee (stays the same across gateways) */
  platform_fee_zmw: number;
  /** Gateway collection fee inside processing fees (Lipila flat / Lenco 1%) */
  lipila_fee_zmw: number;
  provider_fee_zmw: number;
  gateway: GatewayFeeProvider;
  /** what the customer authorises on the prompt */
  prompt_total_zmw: number;
}

/**
 * Fees for a money request.
 *  - riderFeeZmw set  → normal customer collection.
 *  - riderFeeZmw null → pack parcel / admin stash: no per-parcel fees (the
 *    pack renewal prompt already charges the processing fee on the pack price).
 * Processing fees = DropOff platform cut (same) + gateway provider collection fee.
 */
export function collectionFees(base: number, riderFeeZmw?: number | null, gateway: GatewayFeeProvider = 'lipila'): CollectionFees {
  const base2 = round2(base);
  const riderPayout = riderFeeZmw != null && riderFeeZmw > 0 ? payoutNet(riderFeeZmw) : 0;
  if (riderFeeZmw == null || riderFeeZmw === 0) {
    return {
      base: base2,
      rider_payout_zmw: round2(riderPayout),
      processing_fee_zmw: 0,
      platform_fee_zmw: 0,
      lipila_fee_zmw: 0,
      provider_fee_zmw: 0,
      gateway,
      prompt_total_zmw: base2,
    };
  }
  const platform = platformFee(base2);
  const collectLeg = gateway === 'lenco' ? lencoCollectionFee(base2) : MOMO_COLLECTION_FEE;
  const processing = round2(platform + collectLeg);
  return {
    base: base2,
    rider_payout_zmw: round2(riderPayout),
    processing_fee_zmw: processing,
    platform_fee_zmw: platform,
    lipila_fee_zmw: collectLeg,
    provider_fee_zmw: collectLeg,
    gateway,
    prompt_total_zmw: round2(base2 + processing),
  };
}

/**
 * The ONE canonical job-total recomputation. Single source of truth for
 * POST /jobs, rider events (waiting time), and payment quoting so the numbers
 * never drift between paths. Components:
 *   total        = what the parcel movement costs (counter fare is the partner's own)
 *   dropoff_leg  = the DropOff leg only (rider + leg2 + leg2 processing − promo − wait), >= 0
 */
export function computeJobTotals(components: {
  counterPriceZmw: number; riderFeeZmw: number; leg2FeeZmw?: number;
  leg2ProcessingFeeZmw?: number; promoDiscountZmw?: number; waitFeeZmw?: number;
}): { total_zmw: number; dropoff_leg_zmw: number } {
  const counter = Math.max(0, Number(components.counterPriceZmw) || 0);
  const rider = Math.max(0, Number(components.riderFeeZmw) || 0);
  const leg2Fee = Math.max(0, Number(components.leg2FeeZmw) || 0);
  const leg2Proc = Math.max(0, Number(components.leg2ProcessingFeeZmw) || 0);
  const promo = Math.max(0, Number(components.promoDiscountZmw) || 0);
  const wait = Math.max(0, Number(components.waitFeeZmw) || 0);
  const total = round2(counter + rider + leg2Fee + leg2Proc + wait);
  const dropoffLeg = round2(Math.max(0, rider + leg2Fee + leg2Proc + wait - promo));
  return { total_zmw: total, dropoff_leg_zmw: dropoffLeg };
}
