// DropOff fee engine — kwacha (ZMW), 2-decimal money.
//
// MODEL (per owner instruction):
//   • The customer pays the base + a single "processing fee"
//     (platform cut + Lipila mobile-money collection leg). The customer NEVER
//     pays for the rider's payout/settlement.
//   • The rider keeps 90% of the rider fee MINUS the transaction costs of
//     receiving the payout (Lipila disbursement leg + its platform cut).
//     DropOff absorbs the payout disbursement cost out of its 10% take.

export const PLATFORM_FEE_PCT = 1.0;     // 1% of the customer base
export const PLATFORM_FIXED_FEE = 0.48;  // + K0.48 per collection
export const PLATFORM_MIN_FEE = 3.0;     // minimum platform portion (K3.00)
export const MOMO_COLLECTION_FEE = 2.5;  // Lipila collect leg (passed to customer)
export const MOMO_DISBURSEMENT_FEE = 1.5; // Lipila payout leg (rider-side)
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

export interface CollectionFees {
  /** money for goods + rider service, before any processing */
  base: number;
  /** what the RIDER receives at payout (90% − transaction fees) */
  rider_payout_zmw: number;
  /** the one customer-visible line item: platform cut + momo collect leg */
  processing_fee_zmw: number;
  /** DropOff's platform portion of the processing fee (customer leg) */
  platform_fee_zmw: number;
  /** Lipila collection leg inside the processing fee */
  lipila_fee_zmw: number;
  /** what the customer authorises on the prompt */
  prompt_total_zmw: number;
}

/**
 * Fees for a money request.
 *  - riderFeeZmw set  → normal customer collection.
 *  - riderFeeZmw null → pack parcel / admin stash: no per-parcel fees (the
 *    pack renewal prompt already charges the processing fee on the pack price).
 */
export function collectionFees(base: number, riderFeeZmw?: number | null): CollectionFees {
  const base2 = round2(base);
  const riderPayout = riderFeeZmw != null && riderFeeZmw > 0 ? payoutNet(riderFeeZmw) : 0;
  if (riderFeeZmw == null || riderFeeZmw === 0) {
    return {
      base: base2,
      rider_payout_zmw: round2(riderPayout),
      processing_fee_zmw: 0,
      platform_fee_zmw: 0,
      lipila_fee_zmw: 0,
      prompt_total_zmw: base2,
    };
  }
  const platform = platformFee(base2);
  const collectLeg = MOMO_COLLECTION_FEE;
  const processing = round2(platform + collectLeg);
  return {
    base: base2,
    rider_payout_zmw: round2(riderPayout),
    processing_fee_zmw: processing,
    platform_fee_zmw: platform,
    lipila_fee_zmw: collectLeg,
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
