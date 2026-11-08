import 'package:dropoff/data/catalog.dart';
import 'package:dropoff/models/booking.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Platinum is quoted at counter — no route/parcel fares are surfaced or invented', () {
    final n = courierById('platinum').rateFor('Ndola');
    expect(n, isNull);
    expect(courierById('platinum').rateFor('Kitwe'), isNull);
    expect(courierById('platinum').rateFor('Chipata'), isNull);
    expect(courierById('platinum').hasVerifiedRates, isFalse);
    expect(courierById('platinum').priceStatus, 'Quoted at counter');
  });

  test('Smart courier search matches city names with or without noise words', () {
    expect(smartCourierSearch('Lusaka to Ndola').isNotEmpty, isTrue);
    expect(smartCourierSearch('to Ndola').any((c) => c.id == 'platinum' || c.id == 'dhl' || c.id == 'mercury'), isTrue);
    expect(smartCourierSearch('platinum ndola').first.id, 'platinum');
    expect(smartCourierSearch('how much').isNotEmpty, isTrue);
    expect(smartCourierSearch('zzzzzz').isNotEmpty, isTrue);
  });

  test('Unknown and reverse-route fares are never invented', () {
    expect(courierById('platinum').rateFor('Kitwe'), isNull);
    expect(courierById('mercury').rateFor('Ndola'), isNull);
  });

  test('All six requested couriers are booking options', () {
      expect(couriers.map((item) => item.id), containsAll(['platinum', 'dhl', 'mercury', 'rovert', 'oneworld', 'icypeed']));
  });

  test('Booking round-trips through local storage JSON', () {
    final booking = Booking(
      id: '1', reference: 'DO-2026-000001', createdAt: DateTime.utc(2026),
      senderName: 'Sender', senderPhone: '0971234567', pickupAddress: 'Kabwata',
      fromCity: 'Lusaka', toCity: 'Ndola', courierId: 'platinum', parcelSize: ParcelSize.small,
      description: 'Clothes', recipientName: 'Receiver', recipientPhone: '0961234567',
      paymentMethod: 'Mobile money', riderFee: 35, courierFare: 50, lastMileFee: 0, riderId: 'owner',
    );
    final restored = Booking.fromJson(booking.toJson());
    expect(restored.total, 85);
    expect(restored.reference, booking.reference);
  });
}
