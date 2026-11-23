import 'package:dropoff/models/booking.dart';
import 'package:flutter_test/flutter_test.dart';

/// Depot counter fare coverage (owner bug 2026-11-23).
///
/// The rider fronts the depot fare and files the written receipt; the sender
/// repays the exact amount through DropOff. Three things must hold, or the
/// sender gets stuck: the fare must be DETECTABLE from the synced row, the
/// state must SURVIVE every copyWith, and paying must be possible even when
/// the photo has not reached the phone yet.
Booking booking({
  double? counterZmw,
  String counterUrl = '',
  bool paid = false,
  List<(double, String)> receipts = const [],
}) =>
    Booking(
      id: 'srv-1',
      reference: 'DRO-CFARE1',
      createdAt: DateTime(2026, 11, 23, 9),
      senderName: 'Chanda',
      senderPhone: '260970000001',
      pickupAddress: 'Kabulonga',
      fromCity: 'Lusaka',
      toCity: 'Ndola',
      courierId: 'icypeed',
      parcelSize: ParcelSize.small,
      description: 'Books',
      recipientName: 'Mutale',
      recipientPhone: '260970000002',
      paymentMethod: 'mobile_money',
      riderFee: 20,
      courierFare: null,
      lastMileFee: 0,
      riderId: '7',
      serverRef: 'DRO-CFARE1',
      counterReceiptZmw: counterZmw,
      counterReceiptUrl: counterUrl,
      counterReceiptPaid: paid,
      counterReceipts: receipts,
    );

void main() {
  group('counterFareDue', () {
    test('is due when the rider filed an amount that is not paid', () {
      expect(booking(counterZmw: 85).counterFareDue, isTrue);
    });

    test('is not due once paid', () {
      expect(booking(counterZmw: 85, paid: true).counterFareDue, isFalse);
    });

    test('is not due with no amount or a zero amount', () {
      expect(booking().counterFareDue, isFalse);
      expect(booking(counterZmw: 0).counterFareDue, isFalse);
    });

    test('a split batch is due even when the primary photo column is empty', () {
      // Multi-receipt depot drop: the server fills counter_receipts and may
      // leave counter_receipt_url empty. This is exactly the shape that used
      // to disable the receipt button and block the sender.
      final b = booking(counterZmw: 120, receipts: [(60, '/media/a.jpg'), (60, '/media/b.jpg')]);
      expect(b.counterFareDue, isTrue);
      expect(b.counterReceiptUrl, isEmpty);
    });
  });

  group('copyWith carries the depot fare state', () {
    test('merging the server row sets amount, photo, paid flag and receipts', () {
      final synced = booking().copyWith(
        counterReceiptZmw: 85,
        counterReceiptUrl: '/media/r.jpg',
        counterReceiptPaid: false,
        counterReceipts: [(85, '/media/r.jpg')],
      );
      expect(synced.counterReceiptZmw, 85);
      expect(synced.counterReceiptUrl, '/media/r.jpg');
      expect(synced.counterReceiptPaid, isFalse);
      expect(synced.counterReceipts.length, 1);
      expect(synced.counterFareDue, isTrue);
    });

    test('omitting a field keeps the existing value instead of nulling it', () {
      final synced = booking(counterZmw: 85, counterUrl: '/media/r.jpg', receipts: [(85, '/media/r.jpg')]);
      // e.g. a stage-only copyWith from the sync loop
      final staged = synced.copyWith(stage: 4);
      expect(staged.counterReceiptZmw, 85);
      expect(staged.counterReceiptUrl, '/media/r.jpg');
      expect(staged.counterReceipts.length, 1);
    });

    test('a settled fare flips the paid flag and stops being due', () {
      final paid = booking(counterZmw: 85).copyWith(counterReceiptPaid: true);
      expect(paid.counterReceiptPaid, isTrue);
      expect(paid.counterFareDue, isFalse);
    });
  });
}
