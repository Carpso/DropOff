// DropOff pricing engine — kwacha (ZMW), 2-decimal money.
//
// MODEL (post-reprice):
//   • Plans are cycle-based subscriptions: Daily Rider K49/day (1 parcel),
//     Weekly Sprint K399 / 20 parcels / 7 days, Silver K250 / 10 parcels /
//     30 days, Gold K500 / 25 parcels / 30 days, Platinum K750 / 50 parcels.
//     EVERY parcel in a trip consumes one plan slot (owner decision
//     2026-11-15) — a 3-box booking consumes 3 slots.
//   • Inside the cap the sender pays no per-trip rider fee (bundled).
//   • A trip rides the plan only when ALL its parcels still fit under the
//     cap — otherwise the whole trip pays the tier overage fee.
//   • After the cap, the seller keeps the plan's discount off pay-as-you-go:
//     Silver 15%, Gold 25%, Platinum 35% off the normal rider fee.
//   • Truck runs cost more (big cargo: fridges, sofas). Multipliers apply to
//     the normal rider fee; trucks have a K100 minimum.

import { round2 } from './fees';

export type VehicleClass = 'motorcycle' | 'car' | 'van' | 'truck';

export const VEHICLE_CLASSES: VehicleClass[] = ['motorcycle', 'car', 'van', 'truck'];

export const VEHICLE_LABELS: Record<VehicleClass, string> = {
  motorcycle: 'Motorcycle',
  car: 'Car',
  van: 'Van',
  truck: 'Truck (large cargo only)',
};

export const VEHICLE_MULTIPLIER: Record<VehicleClass, number> = {
  motorcycle: 1.0,
  car: 1.2,
  van: 1.4,
  truck: 2.0,
};

// Owner directive (2026-11-13): cars, vans and trucks have no practical parcel
// limit (they house whole batches). Motorcycles cap by parcel SIZE:
//   small × 10 · medium × 5 · large × 1  — then the rider bumps vehicle.
// Applies the same size-aware numbers as the Flutter estimate (app/lib/screens).
export const MOTORCYCLE_MAX_PARCELS = { small: 10, medium: 5, large: 1 } as const;
export const VEHICLE_UNLIMITED = 9999;
export function parcelCapFor(vehicleClass: VehicleClass, parcelSize?: string): number {
  if (vehicleClass !== 'motorcycle') return VEHICLE_UNLIMITED;
  const k = String(parcelSize ?? '').toLowerCase().trim();
  // Current apps send kg-style weight_class ('0-5kg'); tolerate both until
  // every installed version sends parcel_size as well.
  if (k === 'small' || k === '0-5kg' || k === '0-5') return MOTORCYCLE_MAX_PARCELS.small;
  if (k === 'large' || k === '15kg+' || k === '15kg') return MOTORCYCLE_MAX_PARCELS.large;
  return MOTORCYCLE_MAX_PARCELS.medium;
}
export const TRUCK_MIN_FEE_ZMW = 100;

const depotLat = -15.4255;
const depotLng = 28.2805; // Platinum Chibolya anchor

export function haversineKm(aLat: number, aLng: number, bLat: number, bLng: number): number {
  const R = 6371, d = Math.PI / 180;
  const h = 0.5 - Math.cos((bLat - aLat) * d) / 2 +
            Math.cos(aLat * d) * Math.cos(bLat * d) *
            (1 - Math.cos((bLng - aLng) * d)) / 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

export function baseRiderFee(city: string, lat: number, lng: number,
                             vehicleClass: VehicleClass = 'motorcycle'): number {
  // Pay-as-you-go walk-up rate (no plan).
  let base = 70; // non-Lusaka default
  if (city === 'Lusaka' && lat && lng) {
    const km = haversineKm(lat, lng, depotLat, depotLng);
    if (km <= 5) base = 55;
    else if (km <= 12) base = 75;
    else base = 95;
  }
  base = round2(base * VEHICLE_MULTIPLIER[vehicleClass]);
  if (vehicleClass === 'truck') base = Math.max(base, TRUCK_MIN_FEE_ZMW);
  return base;
}

/** Per-trip rider fee after the plan cap, keeping the tier discount off PAYG. */
export function tierOverageFee(tier: string, walkUpFeeZmw: number, discountPct?: number | null): number {
  // A live tiers row (editable in /admin/tiers) wins; the hardcoded table is
  // only the fallback for DBs without the overage_discount_pct column.
  if (discountPct != null && Number.isFinite(Number(discountPct))) {
    const pct = Math.max(0, Math.min(100, Number(discountPct)));
    return round2(Math.max(0, walkUpFeeZmw * (1 - pct / 100)));
  }
  const discount: Record<string, number> = { weekly: 10, rider_daily: 0, silver: 15, gold: 25, platinum: 35 };
  const pct = discount[tier] ?? 0;
  return round2(Math.max(0, walkUpFeeZmw * (1 - pct / 100)));
}
