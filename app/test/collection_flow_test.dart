import 'package:dropoff/data/dropoff_api.dart';
import 'package:dropoff/models/booking.dart';
import 'package:dropoff/state/app_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// Collection flow coverage (owner 2026-11-22: "do all map tests and
/// collection test").
///
/// A Collection job runs DEPOT → RECIPIENT — the parcel is already at the
/// courier point, a rider collects it there and delivers to the door. It has
/// NO sender pickup step and NO counter fare, so its timeline, stage mapping
/// and fee prompt must never inherit the standard door-to-door shape.
Booking collection({
  String service = 'collection',
  String receipt = '',
  double lastMileFee = 0,
}) =>
    Booking(
      id: 'srv-1',
      service: service,
      collectionReceiptUrl: receipt,
      reference: 'DRO-TEST01',
      createdAt: DateTime(2026, 11, 22, 8),
      senderName: 'Chanda',
      senderPhone: '260970000001',
      pickupAddress: 'Icypeed Longacres',
      fromCity: 'Lusaka',
      toCity: 'Lusaka',
      courierId: 'icypeed',
      parcelSize: ParcelSize.small,
      description: 'Books',
      recipientName: 'Mutale',
      recipientPhone: '260970000002',
      paymentMethod: 'mobile_money',
      riderFee: 20,
      courierFare: null,
      lastMileFee: lastMileFee,
      riderId: '',
      declaredValueZmw: 500,
    );

void main() {
  group('Collection booking', () {
    test('is a collection only when the service says so', () {
      expect(collection().isCollection, isTrue);
      expect(collection(service: 'standard').isCollection, isFalse);
    });

    test('receipt photo only counts for a collection that actually has one', () {
      expect(collection(receipt: '').hasCollectionReceipt, isFalse);
      expect(collection(receipt: 'https://x/r.jpg').hasCollectionReceipt, isTrue);
      // A standard job must never surface a collection receipt, even if a
      // stale URL survived on the row.
      expect(
        collection(service: 'standard', receipt: 'https://x/r.jpg').hasCollectionReceipt,
        isFalse,
      );
    });

    test('timeline is depot → recipient, five steps, no sender pickup step', () {
      final steps = collection().timeline;
      expect(steps, const [
        'Booking placed',
        'Rider assigned',
        'Rider at depot',
        'Item collected',
        'Delivered to recipient',
      ]);
      expect(steps.any((s) => s.contains('Dropped at depot')), isFalse);
      expect(steps.length, 5);
    });

    test('a collection keeps its 5-step timeline even with a last-mile fee', () {
      // lastMileFee switches STANDARD jobs to the 7-step door timeline; a
      // collection must stay depot → recipient regardless.
      expect(collection(lastMileFee: 15).timeline.length, 5);
    });

    test('standard timelines stay untouched (regression guard)', () {
      expect(collection(service: 'standard').timeline.length, 5); // no last mile
      expect(collection(service: 'standard', lastMileFee: 15).timeline.length, 7);
    });
  });

  group('Collection stage mapping', () {
    test('collection statuses map onto the 5-step depot → recipient track', () {
      int stage(String status) =>
          AppStore.stageFromJobStatus(status, true, collection: true);

      expect(stage('created'), 0);
      expect(stage('rider_assigned'), 1);
      expect(stage('partner_confirmed'), 1);
      expect(stage('at_depot'), 2);
      expect(stage('counter_recorded'), 2);
      expect(stage('picked_up'), 3);
      expect(stage('departed'), 3);
      expect(stage('arrived'), 3);
      expect(stage('delivered'), 4);
      expect(stage('ready_for_collection'), 4);
    });

    test('collection stages never exceed its 4-step maximum', () {
      for (final s in const [
        'created',
        'rider_assigned',
        'at_depot',
        'picked_up',
        'delivered',
      ]) {
        final stage = AppStore.stageFromJobStatus(s, true, collection: true);
        expect(stage, inInclusiveRange(0, 4));
      }
    });

    test('standard mapping is unchanged (door and non-door)', () {
      // Door: 7 steps, at_depot is step 4, delivered is step 6.
      expect(AppStore.stageFromJobStatus('at_depot', true), 4);
      expect(AppStore.stageFromJobStatus('delivered', true), 6);
      // No door: 5 steps, at_depot is step 3.
      expect(AppStore.stageFromJobStatus('at_depot', false), 3);
      expect(AppStore.stageFromJobStatus('delivered', false), 4);
    });
  });

  group('Pickup payment prompt', () {
    test('a standard pickup charges the DropOff leg plus processing, never the courier counter fare', () {
      final fees = DropOffApi.collectionFees(45, riderFee: 45);
      expect(fees['base'], 45);
      expect(fees['prompt_total_zmw'], DropOffApi.round2(45 + fees['processing_fee_zmw']!));
      expect(fees['lipila_fee_zmw'], DropOffApi.momoCollectionFee);
      expect(fees['platform_fee_zmw'], DropOffApi.platformFee(45));
    });

    test('a plan-covered pickup prompts only the leg', () {
      final fees = DropOffApi.collectionFees(45);
      expect(fees['prompt_total_zmw'], 45);
      expect(fees.containsKey('processing_fee_zmw'), isFalse);
    });
  });

  group('Collection fee prompt', () {
    test('a plan-covered collection prompts only the leg', () {
      final fees = DropOffApi.collectionFees(45);
      expect(fees['prompt_total_zmw'], 45);
      expect(fees.containsKey('processing_fee_zmw'), isFalse);
    });

    test('a PAYG collection adds our platform fee plus the momo fee', () {
      final fees = DropOffApi.collectionFees(100, riderFee: 20);
      expect(fees['base'], 100);
      expect(fees['lipila_fee_zmw'], DropOffApi.momoCollectionFee);
      expect(fees['platform_fee_zmw'], DropOffApi.platformFee(100));
      expect(
        fees['processing_fee_zmw'],
        DropOffApi.round2(fees['platform_fee_zmw']! + DropOffApi.momoCollectionFee),
      );
      expect(
        fees['prompt_total_zmw'],
        DropOffApi.round2(100 + fees['processing_fee_zmw']!),
      );
    });

    test('the platform fee never drops below its floor', () {
      final fees = DropOffApi.collectionFees(5, riderFee: 5);
      expect(fees['platform_fee_zmw'], greaterThanOrEqualTo(DropOffApi.platformMinFee));
    });
  });
}
