import '../ui/app_toast.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/analytics_service.dart';
import '../data/catalog.dart';
import '../data/dropoff_api.dart';
import '../main.dart';
import '../models/booking.dart';
import '../ui/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/sample_stamp.dart';
import 'account_screen.dart';
import 'booking_screen.dart';

class CouriersScreen extends StatefulWidget {
  const CouriersScreen({super.key});

  @override
  State<CouriersScreen> createState() => _CouriersScreenState();
}

class _CouriersScreenState extends State<CouriersScreen> {
  String _query = '';
  Timer? _hintTimer;
  int _hintIdx = 0;
  final _searchCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _hintTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      setState(() => _hintIdx = (_hintIdx + 1) % courierSearchHintsFor('Lusaka', 'Ndola').length);
    });
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _searchCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AnalyticsService.instance.trackScreenView('couriers');
    final store = AppScope.of(context);
    if (!store.linked) {
      // The courier directory is seller tooling — sign up first.
      return SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.lock_outline, size: 44, color: AppColors.muted),
              const SizedBox(height: 16),
              const Text('Sign up to see couriers', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text('Create your free account to browse partner depots, counter quotes and book your first drop.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, height: 1.45)),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccountScreen())),
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Sign up / Sign in'),
              ),
            ]),
          ),
        ),
      );
    }
    final filtered = smartCourierSearch(_query, fromCity: 'Lusaka', toCity: '', size: ParcelSize.small);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
        children: [
          const Text('Courier directory', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.6)),
          const SizedBox(height: 6),
          const Text('Compare available rates, inspect sample receipts, then book a rider to your preferred depot.', style: TextStyle(color: AppColors.muted, height: 1.45)),
          const SizedBox(height: 20),
          TextField(
            controller: _searchCtl,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: courierSearchSamples[_hintIdx % courierSearchSamples.length],
              labelText: 'Search courier, town or route price',
              helperText: 'Search by destination (e.g. Ndola) or courier — fares are confirmed at the depot counter.',
            ),
          ),
          const SizedBox(height: 20),
          _QuoteAnswer(query: _query),
          _LiveDepotsSection(query: _query),
          const SizedBox(height: 26),
          const Text('FEATURED — partner depots', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: AppColors.muted)),
          const SizedBox(height: 12),
          ...filtered.map((courier) {
            final live = courier.isLusakaLive;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    if (live) {
                      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CourierDetailScreen(courier: courier)));
                    } else {
                      AppToast.show(context, 'Coming soon — this courier joins the DropOff network shortly. Lusaka couriers are live today.');
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      CourierAvatar(courier: courier),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(courier.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        const SizedBox(height: 4),
                        Text(courier.strapline, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                        const SizedBox(height: 9),
                        Row(children: [
                          if (!live) ...[
                            const Icon(Icons.lock_outline, size: 15, color: AppColors.muted),
                            const SizedBox(width: 4),
                            const Expanded(child: Text('COMING SOON', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.6, color: AppColors.muted))),
                          ] else ...[
                            Icon(courier.hasVerifiedRates ? Icons.verified : Icons.request_quote_outlined, size: 15, color: courier.hasVerifiedRates ? AppColors.forest : AppColors.muted),
                            const SizedBox(width: 4),
                            Expanded(child: Text('Quoted at counter', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.muted))),
                          ],
                        ]),
                      ])),
                      Icon(live ? Icons.chevron_right : Icons.lock_outline, size: 20, color: AppColors.muted),
                    ]),
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
          const Text('Rate information is dated and sourced. “Quoted at counter” means the fare is set at the depot counter — never an estimated or invented courier fare.', style: TextStyle(fontSize: 11, color: AppColors.muted, height: 1.45)),
        ],
      ),
    );
  }
}

/// Live directory straight from the Worker's chargebook (ZICTA-licensed
/// operators), rendered with each operator's hosted logo when available.
class _LiveDepotsSection extends StatelessWidget {
  final String query;
  const _LiveDepotsSection({required this.query});

  static String _initialsOf(String name) {
    final words = name.split(RegExp(r'\s+'));
    if (words.isEmpty || words.first.isEmpty) return '??';
    return words.length == 1 ? words.first.substring(0, 1) : '${words.first[0]}${words[1][0]}';
  }

  static Widget _logo(String? url, String name, double size) {
    if (url == null || url.isEmpty) {
      return Container(
        width: size, height: size, alignment: Alignment.center,
        decoration: BoxDecoration(color: const Color(0xFF17855F).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(size * 0.3)),
        child: Text(_initialsOf(name), style: const TextStyle(color: Color(0xFF17855F), fontWeight: FontWeight.w900, fontSize: 15)),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.3),
      child: Container(
        width: size, height: size, color: Colors.white,
        child: Image.network(
          url, fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Container(
            alignment: Alignment.center,
            color: const Color(0xFF17855F).withValues(alpha: 0.1),
            child: Text(_initialsOf(name), style: TextStyle(color: const Color(0xFF17855F), fontWeight: FontWeight.w900, fontSize: size * 0.3)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!DropOffApi.enabled) return const SizedBox.shrink();
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: DropOffApi.couriers(),
      builder: (context, snap) {
        final list = snap.data ?? const [];
        if (list.isEmpty) {
          return Text(
            snap.connectionState == ConnectionState.waiting ? 'Loading live partner depots…' : '',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          );
        }
        // Deduplicate against the FEATURED catalog above: a courier already
        // listed there (Platinum, Mercury, DHL, One World, Icypeed, Rovert)
        // must not appear twice on the same tab. Also collapse live rows that
        // share the same normalized name (duplicate seeds / renames).
        const featuredTokens = ['platinum', 'mercury', 'dhl', 'one world', 'icypeed', 'rovert'];
        String norm(String raw) => raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
        final seenNames = <String>{};
        final deduped = <Map<String, dynamic>>[];
        for (final c in list) {
          final name = '${c['name'] ?? ''}';
          final n = norm(name);
          if (n.isEmpty) continue;
          if (featuredTokens.any((t) => n.contains(t))) continue;
          if (!seenNames.add(n)) continue;
          deduped.add(c);
        }
        final filtered = deduped.where((c) {
          final name = '${c['name'] ?? ''}'.toLowerCase();
          final city = '${c['city'] ?? ''}'.toLowerCase();
          final q = query.toLowerCase();
          return name.contains(q) || city.contains(q);
        }).toList();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('LIVE PARTNER DEPOTS (${filtered.length})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: AppColors.muted)),
          const SizedBox(height: 12),
          ...filtered.map<Widget>((c) {
            final isLusaka = '${c['city'] ?? ''}'.trim().toLowerCase() == 'lusaka';
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    if (isLusaka) {
                      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BookingScreen()));
                    } else {
                      AppToast.show(context, 'Coming soon — ${c['city'] ?? 'this city'} depot coverage launches shortly. Lusaka is live today.');
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      _logo(c['logo_url'] as String?, '${c['name'] ?? '?'}', 46),
                      const SizedBox(width: 13),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${c['name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        const SizedBox(height: 3),
                        LinkableText(
                          text: '${c['depot_name'] ?? ''} — ${c['city'] ?? ''}${(c['website'] as String?)?.isNotEmpty == true ? ' · ${c['website']}' : ''}',
                          style: const TextStyle(color: AppColors.muted, fontSize: 12),
                        ),
                        if (!isLusaka) ...[
                          const SizedBox(height: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: AppColors.line.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(8)),
                            child: const Text('COMING SOON', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.muted)),
                          ),
                        ],
                        if (((c['rating_count'] as num?) ?? 0) > 0) ...[
                          const SizedBox(height: 3),
                          Row(children: [
                            const Icon(Icons.star_rounded, size: 14, color: AppColors.amber),
                            const SizedBox(width: 3),
                            Text(
                              '${(c['rating_average'] as num?)?.toStringAsFixed(1) ?? '–'} (${c['rating_count']})',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.muted),
                            ),
                          ]),
                        ],
                        // POLICY: every courier is "quoted at the counter" —
                        // DropOff never advertises fares as published rates,
                        // even when the chargebook has verified entries on file.
                        ...[
                          const SizedBox(height: 3),
                          const Row(children: [
                            Icon(Icons.request_quote_outlined, size: 14, color: AppColors.muted),
                            SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                'Quoted at the courier counter',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.muted),
                              ),
                            ),
                          ]),
                        ],
                        if ((c['payment_instructions'] as String?)?.isNotEmpty == true) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Pay the shop direct: ${c['payment_rail'] ?? 'counter'} • ${c['payment_merchant'] ?? ''} — ${c['payment_instructions']}',
                            style: const TextStyle(color: AppColors.forest, fontSize: 11, fontWeight: FontWeight.w700, height: 1.35),
                          ),
                        ],
                      ])),
                      Icon(isLusaka ? Icons.chevron_right : Icons.lock_outline, size: 20, color: AppColors.muted),
                    ]),
                  ),
                ),
              ),
            );
          }),
          const Text('Depot addresses from ZICTA-licensed operator registers and operator websites.', style: TextStyle(fontSize: 11, color: AppColors.muted)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(color: AppColors.line.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)),
            child: const Row(children: [
              Icon(Icons.info_outline, size: 16, color: AppColors.muted),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'DropOff covers the first mile (your pickup → depot) and last mile (depot → recipient). What happens with your nominated courier between depots is their own operation — we never control their route, timing or depot handling.',
                  style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.4),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          const InfoPill(icon: Icons.info_outline, label: 'In-app courier payment & live parcel scanning — coming soon. Pay the depot at drop-off.'),
        ]);
      },
    );
  }
}

class CourierDetailScreen extends StatelessWidget {
  final CourierInfo courier;

  /// Seller's pickup city — branches are listed nearest to it first.
  final String sellerCity;
  const CourierDetailScreen({super.key, required this.courier, this.sellerCity = 'Lusaka'});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(courier.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
        body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 30), children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(color: Color(courier.colorValue), borderRadius: BorderRadius.circular(24)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CourierAvatar(courier: courier, size: 56),
              const SizedBox(height: 20),
              Text(courier.name, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(courier.strapline, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
                child: Text(courier.priceStatus, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ]),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BookingScreen(initialCourierId: courier.id))),
            icon: const Icon(Icons.two_wheeler),
            label: Text('Book a rider to ${courier.name.split(' ').first}'),
          ),
          const SizedBox(height: 22),
          _CounterRatesSection(courierName: courier.name),
          if (courier.receiptAssets.isNotEmpty) ...[
            const SizedBox(height: 22),
            const SectionTitle('Receipt / waybill samples'),
            const Text('Verified proof straight from the depot counter — tap any to zoom. Personal details belong to the original documents.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
            const SizedBox(height: 12),
            SizedBox(
              height: 260,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: courier.receiptAssets.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) => GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ReceiptViewer(asset: courier.receiptAssets[index], title: '${courier.name} sample ${index + 1}'))),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(width: 210, color: const Color(0xFFE7E9E7), child: SampleStamp(child: Image.asset(courier.receiptAssets[index], fit: BoxFit.cover))),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 26),
          if (courier.branches.isNotEmpty) ...[
            SectionTitle('Branches near $sellerCity'),
            const Text('Closest first — the rider hands your parcel to the nearest branch.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
            const SizedBox(height: 12),
            ...courier.branchesNear(sellerCity).map((branch) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        final live = branch.city.trim().toLowerCase() == 'lusaka';
                        if (live) {
                          Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (_) => BookingScreen(initialCourierId: courier.id),
                          ));
                        } else {
                          AppToast.show(context, 'Coming soon — DropOff pickup in ${branch.city} launches shortly.');
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Icon(Icons.location_on_outlined, color: AppColors.forest, size: 20),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(branch.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                            if (branch.address.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(branch.address, style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.35)),
                            ],
                            const SizedBox(height: 3),
                            Text(
                              [branch.city, branchDistanceLabel(branch, sellerCity)].where((part) => part != null && part.isNotEmpty).join(' · '),
                              style: const TextStyle(color: AppColors.muted, fontSize: 11),
                            ),
                            if (branch.city.trim().toLowerCase() != 'lusaka') ...[
                              const SizedBox(height: 5),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(color: AppColors.line.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(8)),
                                child: const Text('COMING SOON', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.muted)),
                              ),
                            ],
                          ])),
                          if (branch.phone != null)
                            IconButton(
                              tooltip: 'Call branch',
                              icon: const Icon(Icons.phone_outlined, color: AppColors.forest, size: 19),
                              onPressed: () => launchUrl(Uri.parse('tel:${branch.phone!.replaceAll(RegExp(r'\s'), '')}')),
                            ),
                        ]),
                      ),
                    ),
                  ),
                )),
            const SizedBox(height: 6),
          ],
          const SectionTitle('How pricing works'),
          _noteCard('The DropOff rider fee is shown before you book. The courier fare is confirmed at the counter using route, parcel size, weight and service. You keep the original courier receipt.'),
          const SizedBox(height: 24),
          const SectionTitle('Source & pricing note'),
          const SizedBox(height: 6),
          _noteCard('${courier.note}\n\n${courier.sourceLabel}\n${courier.sourceDate}${courier.sourceUrl.isEmpty ? '' : '\n${courier.sourceUrl}'}'),
          if (courier.sourceUrl.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Open source'),
                onPressed: () => launchUrl(Uri.parse(courier.sourceUrl), mode: LaunchMode.externalApplication),
              ),
            ),
          if (courier.id == 'platinum') ...[
            const SizedBox(height: 26),
            const SectionTitle('Depot reference'),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ReceiptViewer(asset: 'assets/images/platinum_offices.jpeg', title: 'Platinum countrywide offices'))),
              child: ClipRRect(borderRadius: BorderRadius.circular(18), child: Image.asset('assets/images/platinum_offices.jpeg', height: 250, fit: BoxFit.cover)),
            ),
          ],
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(color: AppColors.line.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)),
            child: const Row(children: [
              Icon(Icons.info_outline, size: 16, color: AppColors.muted),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'DropOff covers the first mile (your pickup → depot) and last mile (depot → recipient). What happens with your nominated courier between depots is their own operation — we never control their route, timing or depot handling.',
                  style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.4),
                ),
              ),
            ]),
          ),
        ]),
      );

  Widget _noteCard(String text) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: LinkableText(text: text, style: const TextStyle(color: AppColors.muted, height: 1.55, fontSize: 13)),
        ),
      );
}

/// Search-answer banner (enhancement): when the query asks about a fare or a
/// route ("how much to Ndola", "price", "K40"), answer straight from the
/// chargebook — only fares DropOff actually recorded at a courier counter.
/// No query intent, or an unresolvable route, renders nothing at all.
class _QuoteAnswer extends StatefulWidget {
  final String query;
  const _QuoteAnswer({required this.query});

  @override
  State<_QuoteAnswer> createState() => _QuoteAnswerState();
}

class _QuoteAnswerState extends State<_QuoteAnswer> {
  String _lastQuery = '';
  String? _from;
  String? _to;
  List<Map<String, dynamic>> _quotes = const [];
  bool _loading = false;

  @override
  void didUpdateWidget(covariant _QuoteAnswer old) {
    super.didUpdateWidget(old);
    if (widget.query != _lastQuery) {
      _lastQuery = widget.query;
      _resolve();
    }
  }

  void _resolve() {
    final q = widget.query.trim().toLowerCase();
    final wantsPrice = q.contains('price') || q.contains('fare') || q.contains('how much') ||
        q.contains('cost') || q.contains('charge') || q.contains('quote') ||
        q.contains('rate') || RegExp(r'\bk\s?\d+').hasMatch(q);
    // Resolve route towns from the query (same behaviour as courier search).
    final lowerCities = cities.map((c) => c.toLowerCase()).toList();
    String? cityMatch(String t) {
      if (t.length < 3) return null;
      for (final c in lowerCities) {
        if (c == t) return c;
        if (c.split(RegExp(r'[\s-]+')).last == t) return c;
      }
      for (final c in lowerCities) {
        if (c.contains(t)) return c;
      }
      return null;
    }
    final found = q.split(RegExp(r'[^a-z0-9]+')).where((t) => t.isNotEmpty).map(cityMatch).whereType<String>().toSet().toList();
    final from = found.isNotEmpty ? found.first : null;
    final to = found.length > 1 ? found.last : null;
    if (!wantsPrice || from == null || to == null || from == to) {
      if (_quotes.isNotEmpty || _from != null) {
        setState(() { _quotes = const []; _from = null; _to = null; });
      }
      return;
    }
    _from = from; _to = to;
    _loading = true;
    DropOffApi.quotes(from: _from!, to: _to!).then((rows) {
      if (!mounted) return;
      setState(() { _quotes = rows; _loading = false; });
    });
  }

  @override
  Widget build(BuildContext context) {
    final from = _from, to = _to;
    if (from == null || to == null) return const SizedBox.shrink();
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 14),
        child: Text('Checking recorded counter fares…', style: TextStyle(color: AppColors.muted, fontSize: 12)),
      );
    }
    if (_quotes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.line.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)),
          child: Text(
            '$from → $to: no recorded counter fare yet for this route — the depot will quote you at the counter, and DropOff records it once your parcel is dropped.',
            style: const TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.4),
          ),
        ),
      );
    }
    // Group by courier: name → rows sorted by weight class.
    final byCourier = <String, List<Map<String, dynamic>>>{};
    for (final q in _quotes) {
      byCourier.putIfAbsent('${q['courier_name'] ?? 'Courier'}', () => []).add(q);
    }
    String weightLabel(String w) => switch (w) {
          '0-5kg' => 'up to 5kg',
          '5-15kg' => '5–15kg',
          '15kg+' => 'over 15kg',
          _ => w,
        };
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.forest.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.forest.withValues(alpha: 0.25))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.receipt_long_outlined, size: 16, color: AppColors.forest),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Recorded counter fares — $from → $to',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: AppColors.forest)),
            ),
          ]),
          const SizedBox(height: 8),
          for (final entry in byCourier.entries) ...[
            Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
            const SizedBox(height: 2),
            for (final q in entry.value)
              Padding(
                padding: const EdgeInsets.only(left: 10, bottom: 2),
                child: Text(
                  '${weightLabel('${q['weight_class']}')}: K${q['counter_price_zmw']}'
                  '${q['service'] != 'standard' ? ' · ${q['service']}' : ''}',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                ),
              ),
            const SizedBox(height: 6),
          ],
          const Text(
            'Fares DropOff staff or riders recorded at the depot counter — never estimates. The courier confirms the final charge at drop-off, and your DropOff rider leg is shown before you book.',
            style: TextStyle(color: AppColors.muted, fontSize: 10.5, height: 1.4),
          ),
        ]),
      ),
    );
  }
}

/// Verified counter fares recorded in the chargebook, shown on the courier's
/// detail page — labelled exactly as what they are: recorded at the counter,
/// never published rate cards and never estimates.
class _CounterRatesSection extends StatefulWidget {
  final String courierName;
  const _CounterRatesSection({required this.courierName});

  @override
  State<_CounterRatesSection> createState() => _CounterRatesSectionState();
}

class _CounterRatesSectionState extends State<_CounterRatesSection> {
  Future<(String, List<Map<String, dynamic>>)?>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(String, List<Map<String, dynamic>>)?> _load() async {
    final list = await DropOffApi.couriers();
    Map<String, dynamic>? match;
    for (final c in list) {
      final a = '${c['name'] ?? ''}'.trim().toLowerCase();
      final b = widget.courierName.trim().toLowerCase();
      if (a == b || a.contains(b) || b.contains(a)) { match = c; break; }
    }
    final id = (match?['id'] as num?)?.toInt();
    if (id == null) return null;
    final profile = await DropOffApi.courierProfile(id);
    final rates = (profile?['rates'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    if (rates.isEmpty) return null;
    return ('${match?['name'] ?? widget.courierName}', rates);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(String, List<Map<String, dynamic>>)?>(
      future: _future,
      builder: (context, snap) {
        final data = snap.data;
        if (snap.connectionState != ConnectionState.done || data == null) return const SizedBox.shrink();
        final (_, rates) = data;
        // Group by route for a compact table.
        final byRoute = <String, List<Map<String, dynamic>>>{};
        for (final r in rates) {
          byRoute.putIfAbsent('${r['from_city']} → ${r['to_city']}', () => []).add(r);
        }
        final routes = byRoute.keys.toList()..sort();
        String weightLabel(String w) => switch (w) {
              '0-5kg' => 'up to 5kg',
              '5-15kg' => '5–15kg',
              '15kg+' => 'over 15kg',
              _ => w,
            };
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionTitle('Counter fares recorded at the depot'),
          const Text(
            'Fares DropOff recorded at the counter — by staff checks or riders at drop-off. The depot confirms the final charge when your parcel arrives.',
            style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.45),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final route in routes) ...[
                  Text(route, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  const SizedBox(height: 4),
                  for (final r in (byRoute[route]!..sort((a, b) => '${a['weight_class']}'.compareTo('${b['weight_class']}'))))
                    Padding(
                      padding: const EdgeInsets.only(left: 10, bottom: 2),
                      child: Text(
                        '${weightLabel('${r['weight_class']}')} · ${r['service'] == 'standard' ? 'standard' : r['service']} · K${r['counter_price_zmw']}'
                        ' · recorded ${'${r['updated_at'] ?? ''}'.split(' ').first}',
                        style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 6),
        ]);
      },
    );
  }
}


class ReceiptViewer extends StatelessWidget {
  final String asset;
  final String title;
  /// SAMPLE overlay + blur. Default true — set false only for per-order, sender-owned captures.
  final bool sample;
  const ReceiptViewer({super.key, required this.asset, required this.title, this.sample = true});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(title, style: const TextStyle(fontSize: 14))),
        body: InteractiveViewer(minScale: 0.8, maxScale: 5, child: Center(child: SampleStamp(blurAndStamp: sample, child: Image.asset(asset)))),
      );
}
