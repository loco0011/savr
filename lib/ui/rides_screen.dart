import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../core/models.dart';
import '../core/place.dart';
import '../core/platforms.dart';
import '../data/geo.dart';
import '../data/ride_estimator.dart';
import '../theme/tokens.dart';
import 'location_picker.dart';
import 'widgets/common.dart';

class RidesScreen extends StatefulWidget {
  const RidesScreen({super.key});

  @override
  State<RidesScreen> createState() => _RidesScreenState();
}

class _RidesScreenState extends State<RidesScreen> {
  /// Null means "use the app location".
  Place? _from;
  Place? _to;
  RouteInfo? _route;
  bool _routing = false;
  String? _error;
  TimeBand? _bandOverride;
  RideClass? _class;
  bool _sortByPickup = false;
  int _seq = 0;
  Place? _routedFrom;

  Place? _pickup(AppScope s) => _from ?? s.settings.place;

  Future<void> _pickFrom() async {
    final p = await pickPlace(context, title: 'Pickup', hint: 'Search pickup point');
    if (p == null || !mounted) return;
    setState(() => _from = p);
    _computeRoute();
  }

  Future<void> _pickTo() async {
    final p = await pickPlace(context, title: 'Where to?', hint: 'Search destination, e.g. Tollygunge', allowCurrent: false);
    if (p == null || !mounted) return;
    setState(() => _to = p);
    _computeRoute();
  }

  void _swap() {
    final scope = AppScope.of(context);
    final from = _pickup(scope);
    if (from == null || _to == null) return;
    setState(() {
      _from = _to;
      _to = from;
    });
    _computeRoute();
  }

  Future<void> _computeRoute() async {
    final scope = AppScope.of(context);
    final from = _pickup(scope), to = _to;
    if (from == null || to == null) return;
    final my = ++_seq;
    setState(() {
      _routing = true;
      _error = null;
      _route = null;
    });
    _routedFrom = from;
    final r = await scope.geo.route(from, to);
    if (!mounted || my != _seq) return;
    setState(() {
      _routing = false;
      if (r.km < 0.2) {
        _error = 'Pickup and drop are the same place.';
      } else if (r.km > 150) {
        _error = 'That\'s an outstation trip. Ride apps price those differently; check in the app.';
        _route = r;
      } else {
        _route = r;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final c = context.c;
    return ListenableBuilder(
      listenable: scope.settings,
      builder: (context, _) {
        final from = _pickup(scope);
        // The app location changed while a route was shown: redo it.
        if (_to != null && from != null && _routedFrom != null && from != _routedFrom && !_routing) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _computeRoute());
        }
        final band = _bandOverride ?? TimeBand.at(DateTime.now());
        final route = _route;
        final enabled = platformsFor(Vertical.ride).map((p) => p.id).where(scope.settings.isPlatformEnabled).toSet();
        List<RideQuote> quotes = const [];
        double? minutes;
        if (route != null && from != null && _to != null) {
          minutes = RideEstimator.trafficMinutes(route.km, route.freeFlowMinutes, band);
          quotes = RideEstimator.estimate(
            km: route.km,
            minutes: minutes,
            band: band,
            platformIds: enabled,
            city: from.city ?? _to!.city,
          );
          if (_class != null) quotes = quotes.where((q) => q.rideClass == _class).toList();
          if (_sortByPickup) quotes.sort((a, b) => a.pickupMinutes.compareTo(b.pickupMinutes));
        }
        final cheapest = quotes.isEmpty ? null : quotes.reduce((a, b) => a.mid <= b.mid ? a : b);

        return SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.xxl),
            children: [
              Text('Rides', style: context.t.headlineMedium),
              const SizedBox(height: 2),
              Text('Compare fares across Uber, Ola, Rapido and more.', style: context.t.bodySmall),
              const SizedBox(height: Space.lg),
              _RouteCard(
                from: from,
                fromIsApp: _from == null,
                to: _to,
                onFrom: _pickFrom,
                onTo: _pickTo,
                onSwap: _swap,
              ),
              if (_error != null) ...[
                const SizedBox(height: Space.md),
                Text(_error!, style: context.t.bodySmall!.copyWith(color: c.danger)),
              ],
              const SizedBox(height: Space.md),
              if (_to == null)
                _NoDrop(recent: scope.settings.recentPlaces.where((p) => p != from).take(4).toList(), onPick: (p) {
                  setState(() => _to = p);
                  _computeRoute();
                }, onSearch: _pickTo)
              else if (_routing)
                const _RidesSkeleton()
              else if (route != null) ...[
                _TripSummary(route: route, minutes: minutes!, band: band, auto: _bandOverride == null),
                const SizedBox(height: Space.md),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  child: Row(
                    children: [
                      for (final b in TimeBand.values) ...[
                        ChoiceChip(
                          label: Text(b.label),
                          selected: band == b,
                          onSelected: (_) => setState(() => _bandOverride = b == TimeBand.at(DateTime.now()) ? null : b),
                        ),
                        const SizedBox(width: Space.sm),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: Space.sm),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: const Text('All'),
                        selected: _class == null,
                        onSelected: (_) => setState(() => _class = null),
                      ),
                      for (final rc in RideClass.values) ...[
                        const SizedBox(width: Space.sm),
                        ChoiceChip(
                          label: Text(rc.label),
                          selected: _class == rc,
                          onSelected: (_) => setState(() => _class = rc),
                        ),
                      ],
                      const SizedBox(width: Space.sm),
                      FilterChip(
                        avatar: Icon(Icons.bolt_rounded, size: 16, color: c.primary),
                        label: const Text('Fastest pickup'),
                        selected: _sortByPickup,
                        onSelected: (v) => setState(() => _sortByPickup = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.md),
                Surface(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < quotes.length; i++) ...[
                        if (i > 0) Divider(indent: 66, color: c.line.withValues(alpha: 0.7)),
                        _RideRow(
                          quote: quotes[i],
                          isBest: identical(quotes[i], cheapest),
                          onTap: () {
                            final l = RideEstimator.bookingLink(quotes[i].platform.id, from!, _to!);
                            openPlatformUrl(context, l.web, platformId: quotes[i].platform.id, native: l.native);
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: Space.md),
                const InfoBanner(
                  icon: Icons.calculate_outlined,
                  text:
                      'Estimated from each app\'s rate card, the road distance and typical traffic. Ride apps only show '
                      'live fares inside their app; tap one to open it with your pickup and drop.',
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({
    required this.from,
    required this.fromIsApp,
    required this.to,
    required this.onFrom,
    required this.onTo,
    required this.onSwap,
  });
  final Place? from;
  final bool fromIsApp;
  final Place? to;
  final VoidCallback onFrom;
  final VoidCallback onTo;
  final VoidCallback onSwap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget stop({
      required Widget marker,
      required String label,
      required Place? place,
      required String empty,
      required VoidCallback onTap,
    }) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        child: Row(
          children: [
            SizedBox(width: 24, child: Center(child: marker)),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: context.t.labelSmall!.copyWith(letterSpacing: 0.6)),
                  const SizedBox(height: 2),
                  Text(
                    place?.name ?? empty,
                    style: context.t.titleSmall!.copyWith(color: place == null ? c.inkMuted : c.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (place != null && place.subtitle.isNotEmpty)
                    Text(place.subtitle, style: context.t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return Surface(
      padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.sm, Space.sm),
      child: Row(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned(
                  left: 11.25,
                  top: 34,
                  bottom: 34,
                  child: Container(width: 1.5, color: c.line),
                ),
                Column(
                  children: [
                    stop(
                      marker: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: c.primary, width: 3.5),
                        ),
                      ),
                      label: fromIsApp ? 'PICKUP · YOUR LOCATION' : 'PICKUP',
                      place: from,
                      empty: 'Choose pickup',
                      onTap: onFrom,
                    ),
                    Divider(indent: 36, color: c.line.withValues(alpha: 0.7)),
                    stop(
                      marker: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(color: c.deal, borderRadius: BorderRadius.circular(3)),
                      ),
                      label: 'DROP',
                      place: to,
                      empty: 'Where to?',
                      onTap: onTo,
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Swap',
            onPressed: from != null && to != null ? onSwap : null,
            icon: Icon(Icons.swap_vert_rounded, color: c.primary),
            style: IconButton.styleFrom(backgroundColor: c.primarySoft),
          ),
        ],
      ),
    );
  }
}

class _TripSummary extends StatelessWidget {
  const _TripSummary({required this.route, required this.minutes, required this.band, required this.auto});
  final RouteInfo route;
  final double minutes;
  final TimeBand band;
  final bool auto;

  @override
  Widget build(BuildContext context) {
    Widget stat(IconData icon, String value, String label) => Expanded(
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.white.withValues(alpha: 0.8)),
          const SizedBox(width: Space.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: context.t.titleMedium!.copyWith(color: Colors.white, fontWeight: FontWeight.w700, fontFeatures: tabular),
              ),
              Text(label, style: context.t.labelSmall!.copyWith(color: Colors.white.withValues(alpha: 0.75), letterSpacing: 0)),
            ],
          ),
        ],
      ),
    );
    final km = route.km < 10 ? route.km.toStringAsFixed(1) : route.km.round().toString();
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(gradient: context.c.hero, borderRadius: BorderRadius.circular(Radii.xl)),
      child: Row(
        children: [
          stat(Icons.route_rounded, '$km km', route.isRoad ? 'by road' : 'approx.'),
          stat(Icons.schedule_rounded, '~${minutes.round()} min', 'with traffic'),
          stat(Icons.wb_twilight_rounded, band.label.split(' ').first, auto ? 'right now' : 'chosen'),
        ],
      ),
    );
  }
}

class _RideRow extends StatelessWidget {
  const _RideRow({required this.quote, required this.isBest, required this.onTap});
  final RideQuote quote;
  final bool isBest;
  final VoidCallback onTap;

  IconData get _icon => switch (quote.rideClass) {
    RideClass.bike => Icons.two_wheeler_rounded,
    RideClass.auto => Icons.electric_rickshaw_rounded,
    RideClass.suv => Icons.airport_shuttle_rounded,
    _ => Icons.local_taxi_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: isBest ? c.dealSoft : null,
        padding: const EdgeInsets.fromLTRB(Space.md, 10, Space.md, 10),
        child: Row(
          children: [
            SizedBox(
              width: 42,
              height: 42,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(Radii.md)),
                    child: Icon(_icon, color: c.ink, size: 22),
                  ),
                  Positioned(right: -2, bottom: -2, child: PlatformBadge(quote.platform, size: 18)),
                ],
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(quote.product, style: context.t.titleSmall, overflow: TextOverflow.ellipsis),
                      ),
                      if (isBest) ...[const SizedBox(width: 6), const Tag('CHEAPEST', strong: true)],
                    ],
                  ),
                  Text('Pickup ~${quote.pickupMinutes} min', style: context.t.bodySmall!.copyWith(fontSize: 12)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${inr(quote.low)}–${quote.high.round()}',
                  style: context.t.titleSmall!.copyWith(fontWeight: FontWeight.w700, fontFeatures: tabular),
                ),
                const SizedBox(height: 2),
                OpenHint(quote.platform.id),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NoDrop extends StatelessWidget {
  const _NoDrop({required this.recent, required this.onPick, required this.onSearch});
  final List<Place> recent;
  final ValueChanged<Place> onPick;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Surface(
          onTap: onSearch,
          padding: const EdgeInsets.all(Space.md),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: c.primarySoft, borderRadius: BorderRadius.circular(Radii.md)),
                child: Icon(Icons.search_rounded, color: c.primary),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Enter a destination', style: context.t.titleSmall),
                    Text(
                      'We\'ll work out the road distance and compare every app.',
                      style: context.t.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (recent.isNotEmpty) ...[
          const SizedBox(height: Space.lg),
          const SectionLabel('Recent places'),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final p in recent)
                ActionChip(
                  avatar: Icon(Icons.place_outlined, size: 16, color: c.inkMuted),
                  label: Text(p.name),
                  onPressed: () => onPick(p),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _RidesSkeleton extends StatelessWidget {
  const _RidesSkeleton();

  @override
  Widget build(BuildContext context) => Shimmer(
    child: Column(
      children: [
        const SkeletonBox(height: 78, radius: Radii.xl),
        const SizedBox(height: Space.md),
        for (var i = 0; i < 5; i++)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                SkeletonBox(width: 40, height: 40, radius: 12),
                SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [SkeletonBox(width: 120, height: 13), SizedBox(height: 6), SkeletonBox(width: 80, height: 10)],
                  ),
                ),
                SkeletonBox(width: 70, height: 16),
              ],
            ),
          ),
      ],
    ),
  );
}
