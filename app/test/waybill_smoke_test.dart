import 'dart:convert';

import 'package:dropoff/main.dart';
import 'package:dropoff/models/booking.dart';
import 'package:dropoff/screens/waybill_screen.dart';
import 'package:dropoff/state/app_store.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('WaybillScreen renders every section', (tester) async {
    final booking = Booking(
      id: 'test-booking-1',
      reference: 'DO-2026-000042',
      createdAt: DateTime(2026, 11, 8, 9, 30),
      senderName: 'Mary Banda',
      senderPhone: '0971111111',
      pickupAddress: 'Kabwata, Lusaka',
      fromCity: 'Lusaka',
      toCity: 'Kitwe',
      courierId: 'platinum',
      parcelSize: ParcelSize.medium,
      description: 'Chitenge fabric rolls x2',
      recipientName: 'Bana Ngoma',
      recipientPhone: '0962222222',
      paymentMethod: 'Mobile money',
      riderFee: 45,
      courierFare: null,
      lastMileFee: 45,
      pickupWindow: '10:00',
      serverRef: null, // not dispatched — offline booking
      promoCode: 'WELCOME10',
      promoDiscount: 10,
      stage: 2,
      riderId: 'owner',
      roundTrip: true,
      returnCity: 'Lusaka',
      returnAddress: 'Kabwata, Lusaka',
      returnLegFee: 45,
      parcels: 2,
      vehicleClass: 'car',
      branch: 'Kitwe branch',
    );

    SharedPreferences.setMockInitialValues({
      'dropoff_acct_v1_anon_bookings': jsonEncode([booking.toJson()]),
    });


    final store = AppStore();

    await tester.runAsync(() async => store.initialize());


    tester.view.physicalSize = const Size(1100, 6000);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);


    await tester.pumpWidget(
      AppScope(
        store: store,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: WaybillScreen(bookingId: booking.id),
        ),
      ),
    );
    expect(find.text('DEPOT COUNTER WAYBILL'), findsOneWidget);
    expect(find.text('DO-2026-000042'), findsNWidgets(2)); // big monospace + Reference row
    expect(find.text('LUSAKA → KITWE BRANCH'), findsOneWidget);
    expect(find.text('SENDER'), findsOneWidget);
    expect(find.text('RECIPIENT'), findsOneWidget);
    expect(find.text('VALUE & COVER'), findsOneWidget);
    expect(find.text('FEES & PAYMENT'), findsOneWidget);
    expect(find.text('Share waybill image'), findsOneWidget);
    expect(find.text('Download / save image'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
