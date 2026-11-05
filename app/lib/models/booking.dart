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
  /// DropOff-fulfilled leg only: rider fee + last-mile door delivery.
  /// The courier counter fare is partner money and is NEVER collected by DropOff.
  double get dropoffLeg => riderFee + lastMileFee;

  /// Stage timeline for this booking — tracking ends at depot drop-off
  /// (tracking of partner legs is a future opt-in per depot).
  List<String> get timeline => lastMileFee > 0
      ? const [
          'Booking placed',
          'Rider assigned',
          'Parcel collected',
          'At courier depot',
          'Dropped at depot',
          'Out for door delivery',
          'Delivered to door',
        ]
      : const [
          'Booking placed',
          'Rider assigned',
          'Parcel collected',
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

  /// Round trip: the parcel returns to the origin city/depot after delivery.
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

  const Booking({
    required this.id,
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
  });

  bool get dispatched => serverRef != null && serverRef!.isNotEmpty;

  double? get total => courierFare == null ? null : courierFare! + riderFee + lastMileFee;

  Booking copyWith({int? stage, String? riderId, double? courierFare, String? serverRef, String? promoCode, double? promoDiscount, int? parcels, String? vehicleClass}) => Booking(
        id: id,
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
      );

  Map<String, dynamic> toJson() => {
        'id': id,
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
      };

  factory Booking.fromJson(Map<String, dynamic> json) => Booking(
        id: json['id'] as String,
        reference: json['reference'] as String,
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
      );
}
