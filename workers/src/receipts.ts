// Depot counter receipts — the rider's transcription is the money fact.
//
// The rider FRONTS the depot's counter fare, photographs the written receipt
// and types the exact printed figure beside its photo. That typed figure —
// never a quote, an estimate, or a sum the rider computes — is what the sender
// is asked to repay through DropOff. The server totals the photographed
// documents and stores the result as the job's `counter_receipt_zmw`; the
// payment endpoint reads only that stored total. These helpers keep that
// contract in one testable place.

export type FiledReceipt = { amount_zmw: number; url: string };

const round2 = (n: unknown): number => Math.round(Number(n) * 100) / 100;

/** Read every filed receipt. One photographed document = one amount + one photo. */
export function parseFiledReceipts(body: any): FiledReceipt[] {
  if (Array.isArray(body?.receipts)) {
    return (body.receipts as any[]).map((r) => ({
      amount_zmw: round2(r?.amount_zmw),
      url: String(r?.url ?? '').trim(),
    }));
  }
  // Legacy single-receipt payload, honoured as a one-item list.
  const amount = round2(body?.receipt_amount_zmw);
  const url = String(body?.receipt_url ?? '').trim();
  return Number.isFinite(amount) && amount > 0 && url ? [{ amount_zmw: amount, url }] : [];
}

/** A filed receipt must be a real photographed document with a sane amount. */
export function invalidFiledReceipt(filed: FiledReceipt[]): boolean {
  return filed.length === 0 || filed.some((r) =>
    !Number.isFinite(r.amount_zmw) ||
    r.amount_zmw <= 0 ||
    r.amount_zmw > 20000 ||
    !r.url,
  );
}

/** The ONLY source of the amount the sender pays: the filed documents. */
export function filedReceiptTotal(filed: FiledReceipt[]): number {
  return round2(filed.reduce((sum, r) => sum + r.amount_zmw, 0));
}
