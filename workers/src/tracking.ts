// Pure tracking-stage rules shared by the rider, sender, recipient and admin
// tracking surfaces. One source of truth so every view names the same phase,
// draws the same destination pin and stops at the same moment.

export type TrackingDestination = 'pickup' | 'depot' | 'door' | 'done';
export type TrackingPhase = 'to_pickup' | 'at_pickup' | 'to_depot' | 'at_depot' | 'to_door' | 'done';

export interface TrackingStage {
  phase: TrackingPhase;
  label: string;
  destination: TrackingDestination;
  live: boolean;
}

const TERMINAL = new Set(['delivered', 'ready_for_collection', 'collected', 'completed', 'canceled', 'cancelled', 'deleted']);

/** Which leg is active, what to call it, and where the pin should point. */
export function trackingStage(status: string | null | undefined, service: string | null | undefined): TrackingStage {
  const s = String(status ?? '').toLowerCase();
  const isCollection = String(service ?? '').toLowerCase() === 'collection';
  if (TERMINAL.has(s)) {
    return { phase: 'done', label: 'Journey complete', destination: 'done', live: false };
  }
  if (isCollection) {
    // Collection runs depot → recipient door. The pickup pin IS the depot.
    if (s === 'created' || s === 'rider_assigned') {
      return { phase: 'to_pickup', label: 'Rider heading to the depot', destination: 'pickup', live: true };
    }
    return { phase: 'to_door', label: 'Collected — heading to the recipient', destination: 'door', live: true };
  }
  switch (s) {
    case 'created':
    case 'rider_assigned':
      return { phase: 'to_pickup', label: 'Rider heading to your pickup', destination: 'pickup', live: true };
    case 'picked_up':
      return { phase: 'to_depot', label: 'Picked up — heading to the depot', destination: 'depot', live: true };
    case 'at_depot':
      return { phase: 'at_depot', label: 'At the depot — awaiting lodgement', destination: 'depot', live: true };
    case 'departed':
      return { phase: 'to_depot', label: 'Left the depot — on the move', destination: 'depot', live: true };
    case 'arrived':
      return { phase: 'at_depot', label: 'Arrived at the destination depot', destination: 'depot', live: true };
    default:
      return { phase: 'to_depot', label: 'On the move', destination: 'depot', live: true };
  }
}

/** Who may see a job's live rider pin: the two participants or staff. */
export function canTrackJob(
  role: string | null | undefined,
  phone: string | null | undefined,
  job: { sender_phone?: string | null; recipient_phone?: string | null },
): boolean {
  const r = String(role ?? '').toLowerCase();
  if (r === 'ops' || r === 'admin' || r === 'cfo' || r === 'superadmin') return true;
  if (!phone) return false;
  return phone === job.sender_phone || phone === job.recipient_phone;
}

/** A GPS fix older than this is shown as stale, never as "live". */
export const STALE_FIX_SECONDS = 120;

export function fixAgeSeconds(seenAt: string | null | undefined, nowMs: number = Date.now()): number | null {
  if (!seenAt) return null;
  const parsed = Date.parse(String(seenAt).replace(' ', 'T') + (String(seenAt).includes('Z') || String(seenAt).includes('+') ? '' : 'Z'));
  if (!Number.isFinite(parsed)) return null;
  return Math.max(0, Math.floor((nowMs - parsed) / 1000));
}
