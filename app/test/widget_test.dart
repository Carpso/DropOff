import 'package:dropoff/data/catalog.dart';
import 'package:dropoff/models/booking.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Platinum published Lusaka fares are applied by parcel size', () {
    expect(
      courierFareFor(courierId: 'platinum', fromCity: 'Lusaka', toCity: 'Ndola', size: ParcelSize.small),
      50,
    );
    expect(
      courierFareFor(courierId: 'platinum', fromCity: 'Lusaka', toCity: 'Kitwe', size: ParcelSize.medium),
      60,
    );
    expect(
      courierFareFor(courierId: 'platinum', fromCity: 'Lusaka', toCity: 'Chipata', size: ParcelSize.large),
      130,
    );
  });

  test('Unknown and reverse-route fares are never invented', () {
    expect(
      courierFareFor(courierId: 'platinum', fromCity: 'Ndola', toCity: 'Kitwe', size: ParcelSize.small),
      isNull,
    );
    expect(
      courierFareFor(courierId: 'mercury', fromCity: 'Lusaka', toCity: 'Ndola', size: ParcelSize.small),
      isNull,
    );
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
