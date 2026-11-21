// ─────────────────────────────────────────────────────────────────────
// DROPOFF — ownership stamp (do not remove)
// :Godfrey Moses Kalambo:Carpso Solutions:0968551110.
// © 2026 Godfrey Moses Kalambo · Carpso Solutions · Lusaka, Zambia.
// All rights reserved — unauthorised copying, resale or rebranding of
// this source code is prohibited.
// ─────────────────────────────────────────────────────────────────────
enum ParcelSize { small, medium, large }

extension ParcelSizeLabel on ParcelSize {
  String get label => switch (this) {
        ParcelSize.small => 'Small',
        ParcelSize.medium => 'Medium',
        ParcelSize.large => 'Large',
      };
}

class CourierRate {
  final String province;
  final List<String> towns;
  final int small;
  final int medium;
  final String large;

  const CourierRate({
    required this.province,
    required this.towns,
    required this.small,
    required this.medium,
    required this.large,
  });

  int priceFor(ParcelSize size) => switch (size) {
        ParcelSize.small => small,
        ParcelSize.medium => medium,
        ParcelSize.large => int.tryParse(large.replaceAll(RegExp(r'[^0-9]'), '')) ?? small,
      };
}

/// A courier depot/branch the rider can hand a parcel to.
class CourierBranch {
  final String name;
  final String city;
  final String address;
  final String? phone;
  final double? lat;
  final double? lng;

  const CourierBranch({
    required this.name,
    required this.city,
    this.address = '',
    this.phone,
    this.lat,
    this.lng,
  });
}

class CourierInfo {
  final String id;
  final String name;
  final String strapline;
  final String priceStatus;
  final String sourceLabel;
  final String sourceUrl;
  final String sourceDate;
  final String note;
  final int colorValue;
  final List<CourierRate> rates;
  final List<CourierBranch> branches;
  final List<String> receiptAssets;

  const CourierInfo({
    required this.id,
    required this.name,
    required this.strapline,
    required this.priceStatus,
    required this.sourceLabel,
    required this.sourceUrl,
    required this.sourceDate,
    required this.note,
    required this.colorValue,
    this.rates = const [],
    this.branches = const [],
    this.receiptAssets = const [],
  });

  bool get hasVerifiedRates => rates.isNotEmpty;

  /// Couriers with no explicit branch list are Lusaka-headquartered depots
  /// (Mercury, DHL, One World, Icypeed); the rest must list a Lusaka branch.
  bool get isLusakaLive =>
      branches.isEmpty || branches.any((b) => b.city.trim().toLowerCase() == 'lusaka');

  CourierRate? rateFor(String destination) {
    final query = destination.trim().toLowerCase();
    for (final rate in rates) {
      if (rate.towns.any((town) => town.toLowerCase() == query)) return rate;
    }
    return null;
  }
}

class Rider {
  final String id;
  final String name;
  final String phone;
  final String vehicle;
  final bool isOwner;
  final bool active;

  const Rider({
    required this.id,
    required this.name,
    required this.phone,
    required this.vehicle,
    this.isOwner = false,
    this.active = true,
  });

  Rider copyWith({bool? active}) => Rider(
        id: id,
        name: name,
        phone: phone,
        vehicle: vehicle,
        isOwner: isOwner,
        active: active ?? this.active,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'vehicle': vehicle,
        'isOwner': isOwner,
        'active': active,
      };

  factory Rider.fromJson(Map<String, dynamic> json) => Rider(
        id: json['id'] as String,
        name: json['name'] as String,
        phone: json['phone'] as String,
        vehicle: json['vehicle'] as String,
        isOwner: json['isOwner'] as bool? ?? false,
        active: json['active'] as bool? ?? true,
      );
}

class Booking {
  /// 'standard' | 'collection' — a Collection job is rider-to-courier → door.
  final String service;

  /// The proof-of-payment receipt the SENDER uploaded for a Collection job —
  /// shown in the rider's screen at the courier counter, then again to this
  /// sender here. null/empty when there is nothing to show.
  final String collectionReceiptUrl;

  /// DropOff-fulfilled leg only: rider fee + last-mile door delivery.
  /// The courier counter fare is partner money and is NEVER collected by DropOff.
  double get dropoffLeg => riderFee + lastMileFee;

  bool get isCollection => service == 'collection';

  bool get hasCollectionReceipt => isCollection && collectionReceiptUrl.isNotEmpty;

  /// Stage timeline for this booking.
  List<String> get timeline => isCollection
      ? const [
          'Booking placed',
          'Rider assigned',
          'Rider at depot',
          'Item collected',
          'Delivered to recipient',
        ]
      : lastMileFee > 0
          ? const [
              'Booking placed',
              'Rider assigned',
              'Item collected',
              'At courier depot',
              'Dropped at depot',
              'Out for door delivery',
              'Delivered to door',
            ]
          : const [
              'Booking placed',
              'Rider assigned',
              'Item collected',
              'At courier depot',
              'Dropped at depot',
            ];

  final String id;
  final String reference;
  final DateTime createdAt;
  final String senderName;
  final String senderPhone;
  final String pickupAddress;
  final String fromCity;
  final String toCity;
  final String courierId;
  final ParcelSize parcelSize;
  final String description;
  final String recipientName;
  final String recipientPhone;
  final String paymentMethod;
  final double riderFee;
  final double? courierFare;
  final double lastMileFee;
  final String pickupWindow; // 'now' | '06:00' | '10:00' | '14:00'
  final String? serverRef; // Worker job ref (DRO-...) once dispatched
  final String? promoCode;
  final double? promoDiscount;
  final int stage;
  final String riderId;

  /// Round trip: if the parcel can't travel on, the rider returns it from the
  /// depot back to the sender's door (no re-booking).
  final bool roundTrip;
  final String? returnCity;
  final String? returnAddress;
  final double returnLegFee;

  /// Scheduled (timed) pickup slot, ISO-8601 CAT. Null = next available sweep.
  final String? pickupAt;

  /// How many parcels are inside this one trip (counts as ONE plan slot).
  final int parcels;

  /// Vehicle class for this trip: motorcycle | car | van | truck.
  final String vehicleClass;

  /// The depot branch the rider delivers to (e.g. 'Longacres branch').
  final String? branch;

  const Booking({
    required this.id,
    this.service = 'standard',
    this.collectionReceiptUrl = '',
    required this.reference,
    required this.createdAt,
    required this.senderName,
    required this.senderPhone,
    required this.pickupAddress,
    required this.fromCity,
    required this.toCity,
    required this.courierId,
    required this.parcelSize,
    required this.description,
    required this.recipientName,
    required this.recipientPhone,
    required this.paymentMethod,
    required this.riderFee,
    required this.courierFare,
    required this.lastMileFee,
    this.pickupWindow = 'now',
    this.serverRef,
    this.promoCode,
    this.promoDiscount,
    this.stage = 0,
    required this.riderId,
    this.roundTrip = false,
    this.returnCity,
    this.returnAddress,
    this.returnLegFee = 0,
    this.pickupAt,
    this.parcels = 1,
    this.vehicleClass = 'motorcycle',
    this.branch,
    this.lastEvent,
    this.riderName,
    this.riderPhone,
    this.paymentHeld = false,
    this.counterReceiptZmw,
    this.counterReceiptUrl,
    this.counterReceiptPaid = false,
    this.repromptPaused = false,
    this.counterReceipts = const [],
  });

  /// Latest server job_event status for dispatched bookings — 'advance_pending'
  /// (momo prompt waiting) / 'prepayment_pending' (held: prompt never started).
  /// Drives the Pay-now affordance in Bookings.
  final String? lastEvent;

  /// The rider the server's dispatch ALGORITHM picked (never a default
  /// "Owner" — owner directive 2026-11-15). Null while nobody is assigned.
  final String? riderName;

  /// The assigned rider's mobile number (260XXXXXXXXX) — the server only ships
  /// it to this booking's own participants and staff. Powers the tap-to-call
  /// button; null while nobody is assigned (or on pre-field cached rows).
  final String? riderPhone;

  /// True while this booking's DropOff-leg prepayment is NOT confirmed
  /// (prompt waiting or the provider never started). A held booking shows the
  /// Pay-now gate and never offers recipient tracking/share actions.
  final bool paymentHeld;

  /// Depot counter flow (owner directive 2026-11-12): the exact amount the
  /// rider transcribed off the depot's written receipt. The sender repays it
  /// (+ processing, waived for plan-active senders) through DropOff; the REAL
  /// receipt photo ([counterReceiptUrl]) is served to the sender as soon as
  /// the rider files it — the app keeps it blurred behind a lock until the
  /// depot bill is cleared (paid). Null = no receipt submitted yet.
  final double? counterReceiptZmw;
  final String? counterReceiptUrl;
  final bool counterReceiptPaid;

  /// Sender paused DropOff's payment reminders for this booking (they know
  /// they can't pay right now). USSD pushes already on their handset are out
  /// of app control; resuming re-arms a fresh prompt on the next deliberate
  /// tap (paused rows are excluded from the advance-prompt reuse check).
  final bool repromptPaused;

  /// Every photographed depot receipt on the trip (multi-receipt drops when
  /// the depot splits a batch): (exact amount written on that receipt, photo
  /// url). [counterReceiptZmw] is the SERVER-computed total of these; the
  /// first entry is the primary preview. Empty for single-receipt drops.
  final List<(double, String)> counterReceipts;

  bool get counterFareDue =>
      counterReceiptZmw != null && counterReceiptZmw! > 0 && !counterReceiptPaid;

  bool get dispatched => serverRef != null && serverRef!.isNotEmpty;

  double? get total => courierFare == null ? null : courierFare! + riderFee + lastMileFee;

  Booking copyWith({int? stage, String? riderId, double? courierFare, String? serverRef, String? promoCode, double? promoDiscount, int? parcels, String? vehicleClass, String? riderName, String? riderPhone, String? lastEvent, bool? paymentHeld}) => Booking(
        id: id,
        service: service,
        reference: reference,
        createdAt: createdAt,
        senderName: senderName,
        senderPhone: senderPhone,
        pickupAddress: pickupAddress,
        fromCity: fromCity,
        toCity: toCity,
        courierId: courierId,
        parcelSize: parcelSize,
        description: description,
        recipientName: recipientName,
        recipientPhone: recipientPhone,
        paymentMethod: paymentMethod,
        riderFee: riderFee,
        courierFare: courierFare ?? this.courierFare,
        lastMileFee: lastMileFee,
        pickupWindow: pickupWindow,
        serverRef: serverRef ?? this.serverRef,
        promoCode: promoCode ?? this.promoCode,
        promoDiscount: promoDiscount ?? this.promoDiscount,
        stage: stage ?? this.stage,
        riderId: riderId ?? this.riderId,
        roundTrip: roundTrip,
        returnCity: returnCity,
        returnAddress: returnAddress,
        returnLegFee: returnLegFee,
        pickupAt: pickupAt,
        parcels: parcels ?? this.parcels,
        vehicleClass: vehicleClass ?? this.vehicleClass,
        riderName: riderName ?? this.riderName,
        riderPhone: riderPhone ?? this.riderPhone,
        lastEvent: lastEvent ?? this.lastEvent,
        paymentHeld: paymentHeld ?? this.paymentHeld,
        counterReceiptZmw: counterReceiptZmw,
        counterReceiptUrl: counterReceiptUrl,
        counterReceiptPaid: counterReceiptPaid,
        counterReceipts: counterReceipts,
        repromptPaused: repromptPaused,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'service': service,
        'reference': reference,
        'createdAt': createdAt.toIso8601String(),
        'senderName': senderName,
        'senderPhone': senderPhone,
        'pickupAddress': pickupAddress,
        'fromCity': fromCity,
        'toCity': toCity,
        'courierId': courierId,
        'parcelSize': parcelSize.name,
        'description': description,
        'recipientName': recipientName,
        'recipientPhone': recipientPhone,
        'paymentMethod': paymentMethod,
        'riderFee': riderFee,
        'courierFare': courierFare,
        'lastMileFee': lastMileFee,
        'pickupWindow': pickupWindow,
        'serverRef': serverRef,
        'promoCode': promoCode,
        'promoDiscount': promoDiscount,
        'stage': stage,
        'riderId': riderId,
        'roundTrip': roundTrip,
        'returnCity': returnCity,
        'returnAddress': returnAddress,
        'returnLegFee': returnLegFee,
        'pickupAt': pickupAt,
        'parcels': parcels,
        'vehicleClass': vehicleClass,
        'branch': branch,
        'lastEvent': lastEvent,
        'riderName': riderName,
        'riderPhone': riderPhone,
        'paymentHeld': paymentHeld,
        'counterReceiptZmw': counterReceiptZmw,
        'counterReceiptUrl': counterReceiptUrl,
        'counterReceiptPaid': counterReceiptPaid,
        'repromptPaused': repromptPaused,
        'counterReceipts': [for (final (amt, url) in counterReceipts) {'amount_zmw': amt, 'url': url}],
      };

  factory Booking.fromJson(Map<String, dynamic> json) => Booking(
        id: json['id'] as String,
        reference: json['reference'] as String,
        service: json['service'] as String? ?? 'standard',
        createdAt: DateTime.parse(json['createdAt'] as String),
        senderName: json['senderName'] as String,
        senderPhone: json['senderPhone'] as String,
        pickupAddress: json['pickupAddress'] as String,
        fromCity: json['fromCity'] as String,
        toCity: json['toCity'] as String,
        courierId: json['courierId'] as String,
        parcelSize: ParcelSize.values.byName(json['parcelSize'] as String),
        description: json['description'] as String,
        recipientName: json['recipientName'] as String,
        recipientPhone: json['recipientPhone'] as String,
        paymentMethod: json['paymentMethod'] as String,
        riderFee: (json['riderFee'] as num).toDouble(),
        courierFare: (json['courierFare'] as num?)?.toDouble(),
        lastMileFee: (json['lastMileFee'] as num).toDouble(),
        pickupWindow: json['pickupWindow'] as String? ?? 'now',
        serverRef: json['serverRef'] as String?,
        promoCode: json['promoCode'] as String?,
        promoDiscount: (json['promoDiscount'] as num?)?.toDouble(),
        stage: json['stage'] as int? ?? 0,
        riderId: json['riderId'] as String,
        roundTrip: json['roundTrip'] as bool? ?? false,
        returnCity: json['returnCity'] as String?,
        returnAddress: json['returnAddress'] as String?,
        returnLegFee: (json['returnLegFee'] as num?)?.toDouble() ?? 0,
        pickupAt: json['pickupAt'] as String?,
        parcels: (json['parcels'] as num?)?.toInt() ?? 1,
        vehicleClass: json['vehicleClass'] as String? ?? 'motorcycle',
        branch: json['branch'] as String?,
        lastEvent: json['lastEvent'] as String?,
        riderName: json['riderName'] as String?,
        riderPhone: json['riderPhone'] as String?,
        paymentHeld: json['paymentHeld'] as bool? ?? false,
        counterReceiptZmw: (json['counterReceiptZmw'] as num?)?.toDouble(),
        counterReceiptUrl: json['counterReceiptUrl'] as String?,
        counterReceiptPaid: json['counterReceiptPaid'] as bool? ?? false,
        repromptPaused: json['repromptPaused'] as bool? ?? false,
        counterReceipts: [
          for (final r in (json['counterReceipts'] as List?) ?? [])
            if (r is Map)
              ((r['amount_zmw'] as num?)?.toDouble() ?? 0, '${r['url'] ?? ''}')
        ],
      );
}
