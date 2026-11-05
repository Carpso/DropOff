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

const platinumRates = <CourierRate>[
  CourierRate(province: 'Copperbelt', towns: ['Ndola', 'Kitwe', 'Luanshya', 'Kalulushi', 'Mufulira', 'Chambishi', 'Chingola', 'Chililabombwe'], small: 50, medium: 60, large: 'K80 & above'),
  CourierRate(province: 'Copperbelt', towns: ['Kasumbalesa'], small: 50, medium: 70, large: 'K100 & above'),
  CourierRate(province: 'Copperbelt', towns: ['Mpongwe'], small: 70, medium: 100, large: 'K120 & above'),
  CourierRate(province: 'Central', towns: ['Kabwe', 'Kapiri Mposhi'], small: 50, medium: 60, large: 'K80 & above'),
  CourierRate(province: 'Central', towns: ['Mumbwa'], small: 50, medium: 70, large: 'K100 & above'),
  CourierRate(province: 'Central', towns: ['Mkushi', 'Serenje', 'Mukando'], small: 70, medium: 100, large: 'K120 & above'),
  CourierRate(province: 'Southern', towns: ['Kafue'], small: 40, medium: 50, large: 'K70 & above'),
  CourierRate(province: 'Southern', towns: ['Mazabuka', 'Monze', 'Pemba', 'Choma', 'Kalomo', 'Zimba', 'Livingstone', 'Kazungula'], small: 50, medium: 70, large: 'K100 & above'),
  CourierRate(province: 'Western', towns: ['T.B.Z'], small: 50, medium: 70, large: 'K100 & above'),
  CourierRate(province: 'Western', towns: ['Kaoma', 'Mongu', 'Senanga', 'Mwandi', 'Katima Mulilo', 'Sesheke'], small: 100, medium: 130, large: 'K150 & above'),
  CourierRate(province: 'North-Western', towns: ['Solwezi'], small: 100, medium: 130, large: 'K150 & above'),
  CourierRate(province: 'North-Western', towns: ['Kalumbila', 'Kisasa', 'Manyama'], small: 100, medium: 130, large: 'K150 & above'),
  CourierRate(province: 'Luapula', towns: ['Chembe', 'Mansa', 'Samfya'], small: 100, medium: 130, large: 'K150 & above'),
  CourierRate(province: 'Eastern', towns: ['Nyimba', 'Katete', 'Petauke', 'Sinda', 'Chipata'], small: 70, medium: 100, large: 'K130 & above'),
  CourierRate(province: 'Northern', towns: ['Kasama'], small: 100, medium: 130, large: 'K150 & above'),
  CourierRate(province: 'Northern', towns: ['Mbala'], small: 130, medium: 150, large: 'K180 & above'),
  CourierRate(province: 'Muchinga', towns: ['Mpika'], small: 100, medium: 130, large: 'K150 & above'),
  CourierRate(province: 'Muchinga', towns: ['Isoka', 'Chinsali', 'Nakonde'], small: 100, medium: 130, large: 'K150 & above'),
];

const couriers = <CourierInfo>[
  CourierInfo(
    id: 'platinum',
    name: 'Platinum Courier Services',
    strapline: 'Countrywide parcels • depot to depot',
    priceStatus: '2026 Lusaka price list captured',
    sourceLabel: 'In-app source: supplied depot price board',
    sourceUrl: '',
    sourceDate: 'Effective 1 July 2026 • photographed 2 September 2026',
    note: 'Published prices are FROM Lusaka. Large parcels start at the shown amount. Handle-with-care parcels are charged at the office. Confirm the final counter charge before payment.',
    colorValue: 0xFF176B87,
    rates: platinumRates,
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


double? courierFareFor({
  required String courierId,
  required String fromCity,
  required String toCity,
  required ParcelSize size,
}) {
  final courier = courierById(courierId);
  if (courier.id != 'platinum' || fromCity != 'Lusaka') return null;
  return courier.rateFor(toCity)?.priceFor(size).toDouble();
}
