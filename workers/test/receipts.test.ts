import { describe, expect, it } from 'vitest';
import { filedReceiptTotal, invalidFiledReceipt, parseFiledReceipts } from '../src/receipts';

// Owner check 2026-11-23: the sender must pay EXACTLY the amount the rider
// transcribed from the depot's written receipt. The rider cannot be allowed to
// type an estimate or add a fee of their own, and the app cannot invent a sum.
describe('depot receipt amount contract', () => {
  it('files each photographed document with its own exact amount', () => {
    const filed = parseFiledReceipts({
      receipts: [
        { amount_zmw: 60, url: '/media/a.jpg' },
        { amount_zmw: 42.5, url: '/media/b.jpg' },
      ],
    });
    expect(filed).toEqual([
      { amount_zmw: 60, url: '/media/a.jpg' },
      { amount_zmw: 42.5, url: '/media/b.jpg' },
    ]);
    expect(invalidFiledReceipt(filed)).toBe(false);
    // Only the photographed figures are summed — no rider fee, no quote.
    expect(filedReceiptTotal(filed)).toBe(102.5);
  });

  it('rounds to 2 decimals, never to a rider-friendly round number', () => {
    expect(parseFiledReceipts({ receipts: [{ amount_zmw: 37.456, url: '/media/a.jpg' }] })[0].amount_zmw).toBe(37.46);
  });

  it('supports the legacy single-receipt payload as a one-item list', () => {
    expect(parseFiledReceipts({ receipt_amount_zmw: 85, receipt_url: '/media/r.jpg' })).toEqual([
      { amount_zmw: 85, url: '/media/r.jpg' },
    ]);
    expect(parseFiledReceipts({ receipt_amount_zmw: 85 })).toEqual([]);
  });

  it('rejects zero, negative, non-numeric, over-cap and photo-less amounts', () => {
    const bad = [
      { amount_zmw: 0, url: '/media/a.jpg' },
      { amount_zmw: -5, url: '/media/a.jpg' },
      { amount_zmw: 'abc', url: '/media/a.jpg' },
      { amount_zmw: 20001, url: '/media/a.jpg' },
      { amount_zmw: 50, url: '' },
    ];
    for (const receipt of bad) {
      expect(invalidFiledReceipt(parseFiledReceipts({ receipts: [receipt] }))).toBe(true);
    }
    expect(invalidFiledReceipt([])).toBe(true);
  });

  it('never lets a client-supplied total override the filed documents', () => {
    const filed = parseFiledReceipts({
      total_zmw: 1, // ignored — never read
      receipts: [{ amount_zmw: 85, url: '/media/r.jpg' }],
    });
    expect(filedReceiptTotal(filed)).toBe(85);
  });
});
