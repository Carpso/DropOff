import 'dart:math';

import '../models/booking.dart';

const cities = [
  'Lusaka', 'Ndola', 'Kitwe', 'Kabwe', 'Kapiri Mposhi', 'Livingstone',
  'Chingola', 'Choma', 'Chipata', 'Solwezi', 'Kasama', 'Mongu',
  'Mufulira', 'Luanshya', 'Kalulushi', 'Chililabombwe', 'Kasumbalesa',
  'Mpongwe', 'Mumbwa', 'Mkushi', 'Serenje', 'Kafue', 'Mazabuka',
  'Monze', 'Chinsali', 'Nakonde', 'Mpika', 'Mansa', 'Samfya',
  'Chilanga', 'Chongwe', 'Katete', 'Petauke', 'Nyimba', 'Chadiza',
  'Mbala', 'Kaputa', 'Isoka', 'Mafinga', 'Zambezi', 'Mufumbwe',
  'Kasempa', 'Kalabo', 'Sesheke', 'Kazungula', 'Shangombo', 'Namwala',
  'Itezhi-Tezhi', 'Kalomo', 'Zimba', 'Milenge', 'Nchelenge', 'Mwense',
  'Chembe', 'Lufwanyama', 'Chingambwe',
];

const couriers = <CourierInfo>[
  CourierInfo(
    id: 'platinum',
    name: 'Platinum Courier Services',
    strapline: 'Countrywide parcels • depot to depot',
    priceStatus: 'Quoted at counter',
    sourceLabel: 'Counter quote recorded at booking',
    sourceUrl: '',
    sourceDate: 'Checked 4 November 2026',
    note: 'No public route/parcel price card is surfaced in-app. The counter fare is confirmed at the depot and recorded before dispatch. Handle-with-care parcels are charged at the office. Confirm the final counter charge before payment.',
    colorValue: 0xFF176B87,
    // Rates confirmed at counter — none surfaced/invented in-app.
    rates: [],
    // Depot cities taken from the same published rate board (the towns the
    // price list serves) — shown nearest-to-seller first in the app.
    branches: [
      CourierBranch(name: 'Lusaka branch', city: 'Lusaka', lat: -15.4167, lng: 28.2833),
      CourierBranch(name: 'Ndola branch', city: 'Ndola', lat: -12.9714, lng: 28.6367),
      CourierBranch(name: 'Kitwe branch', city: 'Kitwe', lat: -12.8024, lng: 28.2132),
      CourierBranch(name: 'Kabwe branch', city: 'Kabwe', lat: -14.4469, lng: 28.4464),
      CourierBranch(name: 'Livingstone branch', city: 'Livingstone', lat: -17.8419, lng: 25.8573),
      CourierBranch(name: 'Chipata branch', city: 'Chipata', lat: -13.6333, lng: 32.6500),
      CourierBranch(name: 'Kasama branch', city: 'Kasama', lat: -10.2128, lng: 31.1806),
      CourierBranch(name: 'Mongu branch', city: 'Mongu', lat: -15.2484, lng: 23.1274),
      CourierBranch(name: 'Solwezi branch', city: 'Solwezi', lat: -12.1686, lng: 26.3939),
      CourierBranch(name: 'Mansa branch', city: 'Mansa', lat: -11.2000, lng: 28.8833),
      CourierBranch(name: 'Mpika branch', city: 'Mpika', lat: -11.8333, lng: 31.4500),
    ],
    receiptAssets: [
      'assets/images/platinum_receipt_1.jpeg',
      'assets/images/platinum_receipt_2.jpeg',
      'assets/images/platinum_receipt_3.jpeg',
    ],
  ),
  CourierInfo(
    id: 'mercury',
    name: 'Mercury Express Logistics',
    strapline: 'Domestic express • road and air freight',
    priceStatus: 'Receipt sample • tariff on request',
    sourceLabel: 'Official website + supplied customer waybill',
    sourceUrl: 'https://www.mercury.co.zm/',
    sourceDate: 'Waybill sample dated 26 August 2026',
    note: 'No complete public domestic tariff was verified. The supplied Lusaka–Ndola sample shows one 40×20×20 cm piece, 3.20 kg chargeable weight: service K95.23 + fuel K8.00 + VAT K13.65 = K116.88. This is a sample transaction, NOT a general rate.',
    colorValue: 0xFF3B4652,
    receiptAssets: ['assets/images/mercury_waybill.jpeg'],
  ),
  CourierInfo(
    id: 'dhl',
    name: 'DHL Zambia',
    strapline: 'Domestic and international express',
    priceStatus: 'Shipment-specific quote',
    sourceLabel: 'DHL service and quote channels',
    sourceUrl: 'https://www.dhl.com/zm-en/home.html',
    sourceDate: 'Checked 4 November 2026',
    note: 'No reliable public Zambia domestic price card was verified. Price depends on route, actual/volumetric weight and service. DropOff records the counter quote before dispatch.',
    colorValue: 0xFFD40511,
  ),
  CourierInfo(
    id: 'rovert',
    name: 'Rovert Logistics',
    strapline: 'SA ⇄ Zambia parcels • door-to-door, 2× weekly',
    priceStatus: 'Shipment-specific quote — no public price card',
    sourceLabel: 'Official site + LinkedIn',
    sourceUrl: 'https://rovertlogistics.co.za',
    sourceDate: 'Checked 4 November 2026',
    note: 'Rovert Logistics runs SA→Zambia bound consignments (e-commerce/Takealot pickups + freight forwarding with customs clearing). Lusaka office: +260 572307906 (07:00–17:00 CAT). SA HQ: Building F, St Andrews Office Park, Meadowbrook Ln, Epsom Downs, Sandton 2152, +27 767360695. Services: procurement + delivery, delivery-only, self-service (your online cart), freight forwarding to Zambia/Botswana/Namibia/Mozambique/Malawi/Tanzania/Zimbabwe, FTL/LTL/container/refrigerated loads. No verifiable public tariff — rates on request (our counter quote is recorded before dispatch). DropOff booking: they are not a walk-in Lusaka depot network like Platinum; treat as SA-leg partner.',
    colorValue: 0xFF1B4F72,
    branches: [
      CourierBranch(
        name: 'Lusaka office',
        city: 'Lusaka',
        address: 'Lusaka office · 07:00–17:00 CAT',
        phone: '+260 572307906',
        lat: -15.4167,
        lng: 28.2833,
      ),
      CourierBranch(
        name: 'South Africa HQ',
        city: 'Sandton',
        address: 'Building F, St Andrews Office Park, Meadowbrook Ln, Epsom Downs, Sandton 2152',
        phone: '+27 767360695',
        lat: -26.1076,
        lng: 28.0567,
      ),
    ],
  ),
  CourierInfo(
    id: 'oneworld',
    name: 'One World Courier',
    strapline: 'Domestic courier • UPS partner services',
    priceStatus: 'Official rate calculator',
    sourceLabel: 'One World rate calculator',
    sourceUrl: 'https://oneworld.co.zm/rate-calculator',
    sourceDate: 'Checked 4 November 2026',
    note: 'Use a shipment-specific quote for domestic parcels. No fixed fare has been copied into DropOff without a verifiable tariff.',
    colorValue: 0xFF6941C6,
  ),
  CourierInfo(
    id: 'icypeed',
    name: 'Icypeed Logistics',
    strapline: 'Zambia logistics • international forwarding',
    priceStatus: 'International rates online • local quote needed',
    sourceLabel: 'Icypeed official rates page',
    sourceUrl: 'https://icypeed.com/rates/',
    sourceDate: 'Checked 4 November 2026',
    note: 'The public rate cards primarily cover UK/South Africa to Zambia forwarding. They must not be presented as Lusaka–Ndola domestic fares. Request a local counter quote instead.',
    colorValue: 0xFF147D92,
  ),
];

CourierInfo courierById(String id) => couriers.firstWhere((courier) => courier.id == id);

/// Approximate town coordinates used to order a courier's branches by how
/// close they are to the seller's pickup city.
const Map<String, (double, double)> cityCoords = {
  'Lusaka': (-15.4167, 28.2833),
  'Ndola': (-12.9714, 28.6367),
  'Kitwe': (-12.8024, 28.2132),
  'Kabwe': (-14.4469, 28.4464),
  'Livingstone': (-17.8419, 25.8573),
  'Chingola': (-12.5283, 27.8483),
  'Choma': (-16.8167, 26.9833),
  'Chipata': (-13.6333, 32.6500),
  'Solwezi': (-12.1686, 26.3939),
  'Kasama': (-10.2128, 31.1806),
  'Mongu': (-15.2484, 23.1274),
  'Mansa': (-11.2000, 28.8833),
  'Mpika': (-11.8333, 31.4500),
  'Mufulira': (-12.5500, 28.2500),
  'Luanshya': (-13.1333, 28.0000),
  'Kalulushi': (-12.8417, 28.0944),
  'Chililabombwe': (-12.9333, 27.8500),
  'Kasumbalesa': (-13.0500, 27.6000),
  'Mpongwe': (-13.5000, 27.9000),
  'Mumbwa': (-14.9917, 27.0619),
  'Mkushi': (-13.6433, 29.3939),
  'Serenje': (-13.2333, 30.2333),
  'Kafue': (-15.7667, 28.1833),
  'Mazabuka': (-15.8500, 27.7500),
  'Monze': (-16.2833, 27.4833),
  'Chinsali': (-13.5433, 31.3133),
  'Nakonde': (-9.3333, 31.3333),
  'Sandton': (-26.1076, 28.0567),
};

double _haversineKm((double, double) from, (double, double) to) {
  const earthKm = 6371.0;
  final dLat = (to.$1 - from.$1) * pi / 180;
  final dLng = (to.$2 - from.$2) * pi / 180;
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(from.$1 * pi / 180) * cos(to.$1 * pi / 180) * sin(dLng / 2) * sin(dLng / 2);
  return 2 * earthKm * atan2(sqrt(a), sqrt(1 - a));
}

/// Branches of a courier ordered nearest-to-seller first: a branch in the
/// seller's own pickup city always ranks first, then straight-line distance
/// from the pickup city, then alphabetical for branches we cannot place.
List<CourierBranch> sortBranchesNear(List<CourierBranch> branches, String sellerCity) {
  final origin = cityCoords[sellerCity.trim()];
  final ranked = branches.asMap().entries.map((entry) {
    final branch = entry.value;
    double? km;
    if (branch.city.toLowerCase() == sellerCity.trim().toLowerCase()) {
      km = 0;
    } else if (origin != null && branch.lat != null && branch.lng != null) {
      km = _haversineKm(origin, (branch.lat!, branch.lng!));
    }
    return (index: entry.key, branch: branch, km: km);
  }).toList();

  ranked.sort((a, b) {
    if (a.km != null && b.km != null) {
      final byDistance = a.km!.compareTo(b.km!);
      if (byDistance != 0) return byDistance;
    } else if (a.km == null && b.km != null) {
      return 1;
    } else if (a.km != null && b.km == null) {
      return -1;
    }
    final byCity = a.branch.city.compareTo(b.branch.city);
    return byCity != 0 ? byCity : a.index.compareTo(b.index);
  });
  return ranked.map((item) => item.branch).toList();
}

extension CourierBranches on CourierInfo {
  /// This courier's branches nearest to the seller's pickup city.
  List<CourierBranch> branchesNear(String sellerCity) => sortBranchesNear(branches, sellerCity);
}

/// "in Lusaka" / "118 km from Lusaka" — null when the distance is unknown.
String? branchDistanceLabel(CourierBranch branch, String sellerCity) {
  final seller = sellerCity.trim();
  if (branch.city.toLowerCase() == seller.toLowerCase()) return 'in $seller';
  final origin = cityCoords[seller];
  if (origin == null || branch.lat == null || branch.lng == null) return null;
  return '${_haversineKm(origin, (branch.lat!, branch.lng!)).round()} km from $seller';
}


const _stopWords = {
  'to', 'in', 'from', 'the', 'a', 'an', 'and', 'or', 'for', 'of', 'vs',
  'parcel', 'parcels', 'package', 'small', 'medium', 'large', 'courier', 'delivery',
};

/// Smart courier search: matches name/strapline/status/id/branches plus route
/// cities extracted from the query itself. Rates are quoted at the counter —
/// results never depend on published price boards. Empty/unknown-intent queries
/// return all couriers so the UI never dead-ends.
List<CourierInfo> smartCourierSearch(
  String query, {
  String? fromCity,
  String? toCity,
  ParcelSize size = ParcelSize.small,
}) {
  final q = query.trim().toLowerCase();
  final rawTokens = q.split(RegExp(r'[^a-z0-9]+')).where((t) => t.isNotEmpty).toList();
  final tokens = rawTokens.where((t) => !_stopWords.contains(t)).toList();
  final wantsPrice = q.contains('price') || q.contains('how much') || q.contains('cost') ||
      q.contains('rate') || q.contains('charge') || q.contains('quote') || RegExp(r'\bk\d+').hasMatch(q);

  // Resolve cities mentioned in the query (handles "Lusaka to Ndola" and single-town queries).
  final lowerCities = cities.map((c) => c.toLowerCase()).toList();
  String? cityMatch(String t) {
    // exact town match, or a town that contains the token (min length 3)
    if (t.length >= 3) {
      for (final c in lowerCities) {
        if (c == t) return c;
        final cityWord = c.split(RegExp(r'[\s-]+')).last; // e.g. "Kapiri Mposhi" -> "mposhi"
        if (cityWord == t) return c;
      }
      for (final c in lowerCities) {
        if (c.contains(t)) return c;
      }
    }
    return null;
  }
  final queryCities = tokens.map(cityMatch).whereType<String>().toSet().toList();
  final effectiveFrom = (fromCity ?? '').trim().toLowerCase();
  final effectiveTo = (toCity ?? '').trim().toLowerCase();
  final contextCities = [
    if (effectiveFrom.isNotEmpty) effectiveFrom,
    if (effectiveTo.isNotEmpty) effectiveTo,
  ].whereType<String>().toSet();
  final routeCities = {...queryCities, ...contextCities};

  int score(CourierInfo c) {
    if (queryCities.isEmpty && tokens.isEmpty) return 1;
    final hay = [c.name, c.strapline, c.id, c.priceStatus, c.note, c.sourceLabel]
        .join(' ').toLowerCase();
    int s = 0;
    for (final t in tokens) {
      if (hay.contains(t)) s += 4;
    }
    for (final b in c.branches) {
      final bh = '${b.city} ${b.name} ${b.address}'.toLowerCase();
      for (final t in [...tokens, ...routeCities]) {
        if (bh.contains(t)) {
          s += 6;
          break;
        }
      }
    }
    // Route intent: strongly prefer couriers whose branches cover the requested cities.
    if (routeCities.isNotEmpty) {
      final branchCities = c.branches.map((b) => b.city.toLowerCase()).toSet();
      int cityHits = 0;
      for (final rc in routeCities) {
        if (branchCities.contains(rc)) cityHits++;
      }
      if (cityHits > 0) s += cityHits * 10;
      if (cityHits == 0 && tokens.isEmpty) s += 1;
    }
    // Price intent: keep counter-quote couriers visible, but don't pretend to have published fares.
    if (wantsPrice) s += 2;
    return s;
  }

  final scored = <CourierInfo>[...couriers]
      .map((c) => (c: c, s: score(c)))
      .where((entry) => entry.s > 0)
      .toList()
    ..sort((a, b) => b.s.compareTo(a.s) == 0 ? a.c.name.compareTo(b.c.name) : b.s.compareTo(a.s));
  if (scored.isEmpty && q.isNotEmpty) {
    // Never dead-end: show all couriers (sorted by name) and let the user pick.
    return <CourierInfo>[...couriers]..sort((a, b) => a.name.compareTo(b.name));
  }
  return scored.map((e) => e.c).toList();
}

const courierSearchSamples = <String>[
  'Lusaka to Ndola parcel fare?',
  'How much to Kitwe from Lusaka?',
  'Kabwe to Livingstone delivery price',
  'Platinum depot quote Lusaka → Ndola',
  'Inter-town parcel delivery price',
  'Solwezi medium parcel cost',
  'Chipata depot parcel fare',
  'Copperbelt to Lusaka delivery quote',
];

/// Context-aware rotating search hints (fare/route queries) for the placeholder.
List<String> courierSearchHintsFor(String fromCity, String toCity) {
  final from = fromCity.trim();
  final to = toCity.trim();
  final route = (from.isNotEmpty && to.isNotEmpty && from != to) ? '$from → $to' : 'inter-town';
  return <String>[
    '$route parcel fare?',
    'How much is $route delivery?',
    '$route counter quote',
    '$route parcel price',
  ];
}

/// Indicative DropOff-leg estimate for an inter-town query (NOT the courier's
/// depot fare and NOT the final server price). Clearly labeled + rough.
/// Returns null when route unknown.
double? interTownEstimateZmw(String fromCity, String toCity) {
  final a = cityCoords[fromCity.trim()];
  final b = cityCoords[toCity.trim()];
  if (a == null || b == null) return null;
  final km = _haversineKm(a, b);
  if (km < 1) return 70;
  // Rough VS server-confirmed: K70 non-Lusaka base + K1.8/km, rounded to K5.
  final raw = 70 + km * 1.8;
  return (raw / 5).round() * 5.0;
}
