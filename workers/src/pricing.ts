// DropOff pricing engine — kwacha (ZMW), 2-decimal money.
//
// MODEL (post-reprice):
//   • Plans are monthly: Silver K250 / 10 trips, Gold K500 / 25 trips,
//     Platinum K750 / 50 trips. Each trip (booking) consumes ONE plan slot no
//     matter how many parcels are inside it. Cycle = 30 days from activation.
//   • Inside the cap the sender pays no per-trip rider fee (bundled).
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

export const VEHICLE_MAX_PARCELS: Record<VehicleClass, number> = {
  motorcycle: 3,
  car: 6,
  van: 10,
  truck: 15,
};

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
  let base = 45; // non-Lusaka default
  if (city === 'Lusaka' && lat && lng) {
    const km = haversineKm(lat, lng, depotLat, depotLng);
    if (km <= 5) base = 35;
    else if (km <= 12) base = 50;
    else base = 75;
  }
  base = round2(base * VEHICLE_MULTIPLIER[vehicleClass]);
  if (vehicleClass === 'truck') base = Math.max(base, TRUCK_MIN_FEE_ZMW);
  return base;
}

/** Per-trip rider fee after the plan cap, keeping the tier discount off PAYG. */
export function tierOverageFee(tier: string, walkUpFeeZmw: number): number {
  const discount: Record<string, number> = { daily: 5, weekly: 10, silver: 15, gold: 25, platinum: 35 };
  const pct = discount[tier] ?? 0;
  return round2(Math.max(0, walkUpFeeZmw * (1 - pct / 100)));
}
