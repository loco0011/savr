import 'dart:async';

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../core/address.dart';
import '../core/app_launcher.dart';
import '../core/matcher.dart';
import '../core/models.dart';
import '../core/platforms.dart';
import '../data/device/device_source.dart';
import '../data/price_source.dart';
import '../theme/tokens.dart';
import 'location_picker.dart';
import 'widgets/common.dart';

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key, required this.query});
  final SearchQuery query;

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  SearchResult? _result;
  String? _error;
  bool _done = false;
  bool _started = false;
  DateTime? _checkedAt;
  StreamSubscription<SearchResult>? _sub;

  SortMode _sort = SortMode.priceLow;
  late OfferFilter _filter;
  bool _byProduct = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      final s = AppScope.of(context).settings;
      _filter = OfferFilter(includeFees: s.includeFees, inStockOnly: s.hideOutOfStock);
      _load();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// Platforms fetched live for this query (drives the status strip).
  List<String> _liveIds(AppScope scope) {
    if (scope.settings.dataMode != DataMode.device) return const [];
    return platformsFor(widget.query.vertical)
        .map((p) => p.id)
        .where((id) => scope.settings.isPlatformEnabled(id) && DevicePriceSource.supports(id))
        .where(scope.settings.isLocationSet)
        .toList();
  }

  Future<void> _load() {
    _sub?.cancel();
    final done = Completer<void>();
    setState(() {
      _result = null;
      _error = null;
      _done = false;
    });
    _sub = AppScope.of(context).repo.searchStream(widget.query).listen(
      (r) {
        if (mounted) setState(() => _result = r);
      },
      onError: (Object e) {
        if (!mounted) return;
        // Never surface raw exception text to users.
        setState(() => _error = e is PriceSourceException ? e.userMessage : 'Something went wrong. Please try again.');
      },
      onDone: () {
        if (mounted) {
          setState(() {
            _done = true;
            _checkedAt = DateTime.now();
          });
        }
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    return done.future;
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final q = widget.query;
    final source = q.sourcePlatformId == null ? null : kPlatformById[q.sourcePlatformId];
    final place = scope.settings.place;
    final sub = [
      if (source != null) 'From your ${source.name} link' else q.vertical.label,
      if (place != null) scope.settings.activeAddress?.title ?? place.name,
    ].join(' · ');
    final liveIds = _liveIds(scope);

    return Backdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(q.text, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(sub, style: context.t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
          actions: [
            ListenableBuilder(
              listenable: scope.settings,
              builder: (context, _) {
                final saved = scope.settings.isSaved(q.text);
                return IconButton(
                  tooltip: saved ? 'Remove from saved' : 'Save this search',
                  icon: Icon(
                    saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                    color: saved ? context.c.primary : null,
                  ),
                  onPressed: () {
                    final best = _result == null ? null : _bestOf(_result!.offers);
                    scope.settings.toggleSaved(
                      SavedSearch(
                        query: q.text,
                        vertical: q.vertical.name,
                        bestPrice: best?.price,
                        platformId: best?.platformId,
                        at: DateTime.now(),
                      ),
                    );
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        SnackBar(content: Text(saved ? 'Removed from saved' : 'Saved. Find it in your profile.')),
                      );
                  },
                );
              },
            ),
          ],
        ),
        body: _error != null
            ? _ErrorState(message: _error!, onRetry: _load)
            : _result == null
            ? _LoadingView(platformIds: liveIds)
            : RefreshIndicator(onRefresh: _load, child: _body(context, _result!, liveIds)),
      ),
    );
  }

  Widget _body(BuildContext context, SearchResult r, List<String> liveIds) {
    final settings = AppScope.of(context).settings;
    final visible = _filter.apply(r.offers, _sort);
    // Cluster in source (relevance) order so the sort mode doesn't change
    // which listings count as the same product; then filter+sort each group.
    final groups = ProductMatcher.group(
      r.offers,
    ).map((g) => _filter.apply(g, _sort)).where((g) => g.isNotEmpty).toList();
    final grouped = _byProduct && groups.length > 1;
    final top = grouped ? groups.first : visible;
    final topBest = _bestOf(top);
    final hasFees = r.offers.any((o) => o.deliveryFee != null);
    final visBest = _bestOf(visible);
    final visPrices = visible.where((o) => o.inStock).map((o) => o.effectivePrice(includeFees: _filter.includeFees));
    final visSpread = visBest == null || visPrices.isEmpty
        ? 0.0
        : visPrices.reduce((a, b) => a > b ? a : b) - visBest.effectivePrice(includeFees: _filter.includeFees);
    final streaming = !r.isComplete && !_done;
    String names(List<String> ids) => ids.map((id) => kPlatformById[id]?.name ?? id).join(', ');

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.xs, Space.lg, 0),
          sliver: SliverList.list(
            children: [
              if (liveIds.isNotEmpty && !r.isSample) ...[
                _StatusStrip(ids: liveIds, result: r, streaming: streaming),
                const SizedBox(height: Space.md),
              ],
              if (r.isSample) ...[
                const InfoBanner(
                  icon: Icons.science_outlined,
                  text: 'Sample prices for demonstration. Tap any offer to see the live price in that app.',
                ),
                const SizedBox(height: Space.md),
              ] else if (r.live.isNotEmpty && !streaming) ...[
                Text(
                  [
                    'Live at ${settings.activeAddress?.line ?? settings.place?.address ?? 'your location'}',
                    'checked ${TimeOfDay.fromDateTime(_checkedAt ?? DateTime.now()).format(context)}',
                    if (!hasFees) 'fees not included' else if (r.offers.any((o) => o.feeIsEstimate)) 'fees ≈ estimated',
                  ].join(' · '),
                  style: context.t.bodySmall!.copyWith(fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: Space.md),
              ],
              if (r.needsSetup.isNotEmpty && settings.place == null) ...[
                InfoBanner(
                  icon: Icons.add_location_alt_outlined,
                  text: 'Set your location to include ${names(r.needsSetup)}.',
                  action: TextButton(
                    onPressed: () async {
                      final p = await changeAppLocation(context);
                      if (p != null && mounted) _load();
                    },
                    child: const Text('Set'),
                  ),
                ),
                const SizedBox(height: Space.md),
              ],
              if (topBest != null) ...[
                _BestDeal(
                  offers: top,
                  best: topBest,
                  includeFees: _filter.includeFees,
                  title: grouped || top.length == 1 ? topBest.title : null,
                ),
                const SizedBox(height: Space.md),
              ],
              if (r.offers.isNotEmpty) ...[
                _Toolbar(
                  sort: _sort,
                  filter: _filter,
                  byProduct: _byProduct,
                  showGroupToggle: groups.length > 1,
                  showFees: hasFees,
                  showFast: widget.query.vertical == Vertical.quick || widget.query.vertical == Vertical.food,
                  onSort: (s) => setState(() => _sort = s),
                  onFilter: () => _openFilters(r),
                  onChanged: (f) => setState(() => _filter = f),
                  onGroup: (v) => setState(() => _byProduct = v),
                ),
                const SizedBox(height: Space.md),
              ],
              if (r.notice != null) ...[
                _Empty(text: r.notice!),
                const SizedBox(height: Space.lg),
              ] else if (visible.isEmpty && !streaming) ...[
                _EmptyFiltered(onReset: () => setState(() => _filter = OfferFilter(includeFees: _filter.includeFees))),
                const SizedBox(height: Space.lg),
              ],
            ],
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: Space.lg),
          sliver: grouped
              ? SliverList.separated(
                  itemCount: groups.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Space.md),
                  itemBuilder: (context, i) => _ProductCard(
                    offers: groups[i],
                    best: groups[i].map((o) => o.platformId).toSet().length > 1 ? _bestOf(groups[i]) : null,
                    includeFees: _filter.includeFees,
                    showUnit: settings.showUnitPrice,
                  ),
                )
              : SliverList.separated(
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
                  itemBuilder: (context, i) => _OfferTile(
                    offer: visible[i],
                    isBest: identical(visible[i], visBest),
                    savings: identical(visible[i], visBest) ? visSpread : 0,
                    includeFees: _filter.includeFees,
                    showUnit: settings.showUnitPrice,
                  ),
                ),
        ),
        if (streaming)
          const SliverPadding(
            padding: EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, 0),
            sliver: SliverToBoxAdapter(child: _CardSkeleton()),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.xl, Space.lg, Space.xxl),
          sliver: SliverToBoxAdapter(child: _OpenEverywhere(query: widget.query)),
        ),
      ],
    );
  }

  Offer? _bestOf(List<Offer> offers) {
    Offer? best;
    for (final o in offers) {
      if (!o.inStock) continue;
      if (best == null ||
          o.effectivePrice(includeFees: _filter.includeFees) < best.effectivePrice(includeFees: _filter.includeFees)) {
        best = o;
      }
    }
    return best;
  }

  Future<void> _openFilters(SearchResult r) async {
    final next = await showModalBottomSheet<OfferFilter>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FilterSheet(initial: _filter, offers: r.offers, vertical: r.query.vertical),
    );
    if (next != null) setState(() => _filter = next);
  }
}

// ---------------------------------------------------------------------------
// Loading

class _LoadingView extends StatelessWidget {
  const _LoadingView({required this.platformIds});
  final List<String> platformIds;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(Space.lg, Space.xs, Space.lg, Space.lg),
    physics: const NeverScrollableScrollPhysics(),
    children: [
      if (platformIds.isNotEmpty) ...[
        _StatusStrip(ids: platformIds, result: null, streaming: true),
        const SizedBox(height: Space.md),
      ],
      Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: context.c.primary),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              platformIds.isEmpty
                  ? 'Finding prices…'
                  : 'Checking ${platformIds.length} apps near ${AppScope.of(context).settings.place?.name ?? 'you'}…',
              style: context.t.bodySmall,
            ),
          ),
        ],
      ),
      const SizedBox(height: Space.md),
      Shimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SkeletonBox(height: 148, radius: Radii.xl),
            const SizedBox(height: Space.md),
            Row(
              children: const [
                SkeletonBox(width: 110, height: 32, radius: 16),
                SizedBox(width: Space.sm),
                SkeletonBox(width: 84, height: 32, radius: 16),
                SizedBox(width: Space.sm),
                SkeletonBox(width: 120, height: 32, radius: 16),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: Space.md),
      const _CardSkeleton(),
      const SizedBox(height: Space.md),
      const _CardSkeleton(),
    ],
  );
}

/// Skeleton shaped like a [_ProductCard].
class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget row() => const Padding(
      padding: EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SkeletonBox(width: 30, height: 30, radius: 9),
          SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 90, height: 12),
                SizedBox(height: 6),
                SkeletonBox(width: 60, height: 10),
              ],
            ),
          ),
          SkeletonBox(width: 56, height: 18),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.xs),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.xl),
        border: Border.all(color: c.line),
      ),
      child: Shimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SkeletonBox(width: 220, height: 15),
            const SizedBox(height: 6),
            const SkeletonBox(width: 120, height: 11),
            const SizedBox(height: Space.sm),
            row(),
            row(),
          ],
        ),
      ),
    );
  }
}

/// One pill per live platform: spinner while loading, then a count or ✕.
class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.ids, required this.result, required this.streaming});
  final List<String> ids;
  final SearchResult? result;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final r = result;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (final id in ids)
            Padding(
              padding: const EdgeInsets.only(right: Space.sm),
              child: Builder(
                builder: (context) {
                  final p = kPlatformById[id]!;
                  final failed = r?.failed.contains(id) ?? false;
                  final done = r != null && (r.live.contains(id) || failed || (r.isComplete && !streaming));
                  final n = r?.offers.where((o) => o.platformId == id).length ?? 0;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    padding: const EdgeInsets.fromLTRB(5, 5, 10, 5),
                    decoration: ShapeDecoration(
                      color: done && !failed ? c.primarySoft : c.surface,
                      shape: StadiumBorder(side: BorderSide(color: done && !failed ? Colors.transparent : c.line)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PlatformBadge(p, size: 20),
                        const SizedBox(width: 6),
                        Text(p.id == 'instamart' ? 'Instamart' : p.name, style: context.t.labelMedium),
                        const SizedBox(width: 6),
                        if (!done)
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 1.6, color: c.inkMuted),
                          )
                        else if (failed)
                          Icon(Icons.error_outline_rounded, size: 14, color: c.danger)
                        else
                          Text(
                            '$n',
                            style: context.t.labelMedium!.copyWith(
                              color: c.primary,
                              fontWeight: FontWeight.w700,
                              fontFeatures: tabular,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Results

class _BestDeal extends StatelessWidget {
  const _BestDeal({required this.offers, required this.best, required this.includeFees, this.title});
  final List<Offer> offers;
  final Offer best;
  final bool includeFees;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final inStock = offers.where((o) => o.inStock).map((o) => o.effectivePrice(includeFees: includeFees));
    final hi = inStock.isEmpty ? null : inStock.reduce((a, b) => a > b ? a : b);
    final bestPrice = best.effectivePrice(includeFees: includeFees);
    final save = hi == null ? 0.0 : hi - bestPrice;
    final p = kPlatformById[best.platformId]!;
    const white70 = Color(0xC7FFFFFF);
    return Container(
      decoration: BoxDecoration(
        gradient: c.hero,
        borderRadius: BorderRadius.circular(Radii.xl),
        boxShadow: const [BoxShadow(color: Color(0x2606372F), blurRadius: 24, offset: Offset(0, 10))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.xl),
          onTap: best.url == null
              ? null
              : () {
                  if (save >= 1) AppScope.of(context).settings.recordDeal(save);
                  openPlatformUrl(context, best.url!, platformId: best.platformId, productName: best.title);
                },
          child: Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.workspace_premium_rounded, size: 16, color: c.deal),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'BEST PRICE',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.t.labelSmall!.copyWith(color: c.deal, letterSpacing: 1.1, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    if (save >= 1)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: ShapeDecoration(color: c.deal, shape: const StadiumBorder()),
                        child: Text(
                          'Save ${inr(save)}',
                          style: context.t.labelMedium!.copyWith(
                            color: c.onDeal,
                            fontWeight: FontWeight.w700,
                            fontFeatures: tabular,
                          ),
                        ),
                      ),
                  ],
                ),
                if (title != null) ...[
                  const SizedBox(height: Space.sm),
                  Text(
                    [title!, ?best.packLabel].join(' · '),
                    style: context.t.bodyMedium!.copyWith(color: white70),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: Space.xs),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      inr(best.price),
                      style: context.t.headlineMedium!.copyWith(
                        color: Colors.white,
                        fontSize: 34,
                        fontFeatures: tabular,
                        height: 1.05,
                      ),
                    ),
                    if (best.mrp != null && best.mrp! > best.price) ...[
                      const SizedBox(width: Space.sm),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Text(
                          inr(best.mrp!),
                          style: context.t.bodySmall!.copyWith(
                            color: white70,
                            decoration: TextDecoration.lineThrough,
                            decorationColor: white70,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    if (best.deliveryFee != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            FeeBadge(best.deliveryFee, estimate: best.feeIsEstimate, color: white70),
                            if (includeFees && best.deliveryFee! > 0)
                              Text(
                                '${best.feeIsEstimate ? '≈' : ''}${inr(bestPrice)} total',
                                style: context.t.labelSmall!.copyWith(color: Colors.white, letterSpacing: 0),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: Space.md),
                Row(
                  children: [
                    PlatformBadge(p, size: 26),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Text(
                        [p.name, if (best.etaMinutes != null) eta(best.etaMinutes!)].join(' · '),
                        style: context.t.labelLarge!.copyWith(color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: const ShapeDecoration(color: Colors.white, shape: StadiumBorder()),
                      child: OpenHint(best.platformId, color: const Color(0xFF07402F)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One product compared across apps: header, then one dense row per app.
class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.offers, required this.best, required this.includeFees, required this.showUnit});
  final List<Offer> offers;
  final Offer? best;
  final bool includeFees;
  final bool showUnit;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final f = offers.first;
    final apps = offers.map((o) => o.platformId).toSet().length;
    final prices = offers.where((o) => o.inStock).map((o) => o.effectivePrice(includeFees: includeFees)).toList()
      ..sort();
    return Surface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.md + 2, Space.md, Space.md + 2, Space.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(f.title, style: context.t.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(
                        [?f.packLabel, apps > 1 ? 'on $apps apps' : '1 app'].join(' · '),
                        style: context.t.bodySmall!.copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (prices.length > 1 && prices.last - prices.first >= 1)
                  Container(
                    margin: const EdgeInsets.only(left: Space.sm),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(6)),
                    child: Text(
                      'Δ ${inr(prices.last - prices.first)}',
                      style: context.t.labelSmall!.copyWith(color: c.inkMuted, fontFeatures: tabular, letterSpacing: 0),
                    ),
                  ),
              ],
            ),
          ),
          for (var i = 0; i < offers.length; i++) ...[
            if (i > 0) Divider(indent: Space.md + 2 + 30 + Space.md, color: c.line.withValues(alpha: 0.7)),
            _OfferRow(
              offer: offers[i],
              isBest: identical(offers[i], best),
              savings: identical(offers[i], best) && prices.length > 1 ? prices.last - prices.first : 0,
              includeFees: includeFees,
              showUnit: showUnit,
            ),
          ],
          const SizedBox(height: Space.xs),
        ],
      ),
    );
  }
}

class _OfferRow extends StatelessWidget {
  const _OfferRow({
    required this.offer,
    required this.isBest,
    required this.includeFees,
    required this.showUnit,
    this.savings = 0,
  });

  /// Rupees saved vs the priciest app, recorded when this row is opened.
  final double savings;
  final Offer offer;
  final bool isBest;
  final bool includeFees;
  final bool showUnit;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.t;
    final p = kPlatformById[offer.platformId]!;
    final unit = showUnit ? offer.unitPrice : null;
    final off = offer.discountPercent;
    final sub = <String>[
      if (offer.etaMinutes != null) eta(offer.etaMinutes!),
      if (unit != null) '${inr(unit.value)}/${unit.per}',
    ];
    return Opacity(
      opacity: offer.inStock ? 1 : 0.5,
      child: InkWell(
        onTap: offer.url == null
            ? null
            : () {
                if (savings >= 1) AppScope.of(context).settings.recordDeal(savings);
                openPlatformUrl(context, offer.url!, platformId: offer.platformId, productName: offer.title);
              },
        child: Container(
          color: isBest ? c.dealSoft : null,
          padding: const EdgeInsets.fromLTRB(Space.md + 2, 9, Space.md, 9),
          child: Row(
            children: [
              PlatformBadge(p, size: 30),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 2,
                      children: [
                        Text(
                          p.id == 'instamart' ? 'Instamart' : p.name,
                          style: t.labelLarge!.copyWith(fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (isBest) const Tag('LOWEST', strong: true),
                        if (!offer.inStock)
                          Text('Out of stock', style: t.labelSmall!.copyWith(color: c.danger, letterSpacing: 0)),
                      ],
                    ),
                    if (sub.isNotEmpty)
                      Text(
                        sub.join(' · '),
                        style: t.bodySmall!.copyWith(fontSize: 12, fontFeatures: tabular),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: Space.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    inr(offer.price),
                    style: t.titleMedium!.copyWith(fontWeight: FontWeight.w700, fontFeatures: tabular),
                  ),
                  if (offer.mrp != null && offer.mrp! > offer.price)
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: inr(offer.mrp!),
                            style: const TextStyle(decoration: TextDecoration.lineThrough),
                          ),
                          if (off != null && off > 0)
                            TextSpan(
                              text: '  $off%',
                              style: TextStyle(color: c.primary, fontWeight: FontWeight.w600),
                            ),
                        ],
                      ),
                      style: t.bodySmall!.copyWith(fontSize: 11.5, fontFeatures: tabular),
                    ),
                  if (offer.deliveryFee != null) ...[
                    const SizedBox(height: 2),
                    FeeBadge(offer.deliveryFee, estimate: offer.feeIsEstimate),
                  ],
                ],
              ),
              const SizedBox(width: 2),
              Icon(Icons.chevron_right_rounded, size: 20, color: c.inkMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ungrouped list item: a single offer with its own title.
class _OfferTile extends StatelessWidget {
  const _OfferTile({
    required this.offer,
    required this.isBest,
    required this.includeFees,
    required this.showUnit,
    this.savings = 0,
  });
  final double savings;
  final Offer offer;
  final bool isBest;
  final bool includeFees;
  final bool showUnit;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final p = kPlatformById[offer.platformId]!;
    final unit = showUnit ? offer.unitPrice : null;
    final meta = <String>[
      p.id == 'instamart' ? 'Instamart' : p.name,
      ?offer.packLabel,
      if (offer.etaMinutes != null) eta(offer.etaMinutes!),
      if (unit != null) '${inr(unit.value)}/${unit.per}',
    ];
    return Opacity(
      opacity: offer.inStock ? 1 : 0.5,
      child: Surface(
        highlight: isBest,
        radius: Radii.lg,
        padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.sm, Space.md),
        onTap: offer.url == null
            ? null
            : () {
                if (savings >= 1) AppScope.of(context).settings.recordDeal(savings);
                openPlatformUrl(context, offer.url!, platformId: offer.platformId, productName: offer.title);
              },
        child: Row(
          children: [
            PlatformBadge(p, size: 34),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(offer.title, style: t.titleSmall!.copyWith(fontSize: 14), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    meta.join(' · '),
                    style: t.bodySmall!.copyWith(fontSize: 12, fontFeatures: tabular),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: Space.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(inr(offer.price), style: t.titleMedium!.copyWith(fontWeight: FontWeight.w700, fontFeatures: tabular)),
                if (isBest) const Tag('LOWEST', strong: true) else if (!offer.inStock)
                  Text('Out of stock', style: t.labelSmall!.copyWith(color: context.c.danger, letterSpacing: 0)),
                if (offer.deliveryFee != null) ...[
                  const SizedBox(height: 2),
                  FeeBadge(offer.deliveryFee, estimate: offer.feeIsEstimate),
                ],
              ],
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: context.c.inkMuted),
          ],
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.sort,
    required this.filter,
    required this.byProduct,
    required this.showGroupToggle,
    required this.showFees,
    required this.showFast,
    required this.onSort,
    required this.onFilter,
    required this.onChanged,
    required this.onGroup,
  });

  final SortMode sort;
  final OfferFilter filter;
  final bool byProduct;
  final bool showGroupToggle;
  final bool showFees;
  final bool showFast;
  final ValueChanged<SortMode> onSort;
  final VoidCallback onFilter;
  final ValueChanged<OfferFilter> onChanged;
  final ValueChanged<bool> onGroup;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final n = filter.activeCount;
    Widget gap() => const SizedBox(width: Space.sm);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          ActionChip(
            avatar: Icon(Icons.tune_rounded, size: 17, color: n == 0 ? c.primary : c.onPrimary),
            label: Text(n == 0 ? 'Filters' : 'Filters · $n', style: n == 0 ? null : TextStyle(color: c.onPrimary)),
            backgroundColor: n == 0 ? null : c.primary,
            side: n == 0 ? null : BorderSide(color: c.primary),
            onPressed: onFilter,
          ),
          gap(),
          PopupMenuButton<SortMode>(
            initialValue: sort,
            onSelected: onSort,
            position: PopupMenuPosition.under,
            itemBuilder: (_) => [for (final s in SortMode.values) PopupMenuItem(value: s, child: Text(s.label))],
            child: Chip(
              avatar: Icon(Icons.swap_vert_rounded, size: 18, color: c.primary),
              label: Text(sort.label),
            ),
          ),
          gap(),
          FilterChip(
            avatar: Icon(Icons.inventory_2_outlined, size: 16, color: filter.inStockOnly ? c.primary : c.inkMuted),
            label: const Text('In stock'),
            selected: filter.inStockOnly,
            onSelected: (v) => onChanged(filter.copyWith(inStockOnly: v)),
          ),
          if (showFast) ...[
            gap(),
            FilterChip(
              avatar: Icon(Icons.bolt_rounded, size: 16, color: filter.maxEta == 15 ? c.primary : c.inkMuted),
              label: const Text('15 min'),
              selected: filter.maxEta == 15,
              onSelected: (v) => onChanged(filter.copyWith(maxEta: () => v ? 15 : null)),
            ),
          ],
          gap(),
          FilterChip(
            avatar: Icon(Icons.percent_rounded, size: 16, color: filter.minDiscount > 0 ? c.primary : c.inkMuted),
            label: const Text('On offer'),
            selected: filter.minDiscount > 0,
            onSelected: (v) => onChanged(filter.copyWith(minDiscount: v ? 1 : 0)),
          ),
          if (showGroupToggle) ...[
            gap(),
            FilterChip(label: const Text('Group by product'), selected: byProduct, onSelected: onGroup),
          ],
          if (showFees) ...[
            gap(),
            FilterChip(
              label: const Text('Incl. delivery fee'),
              selected: filter.includeFees,
              onSelected: (v) => onChanged(filter.copyWith(includeFees: v)),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.initial, required this.offers, required this.vertical});
  final OfferFilter initial;
  final List<Offer> offers;
  final Vertical vertical;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late OfferFilter f = widget.initial;

  List<(String, int?)> get _etaOptions => switch (widget.vertical) {
    Vertical.quick => [('Any', null), ('10 min', 10), ('15 min', 15), ('30 min', 30)],
    Vertical.food => [('Any', null), ('30 min', 30), ('45 min', 45), ('60 min', 60)],
    _ => [('Any', null), ('Today', 720), ('2 days', 2880), ('4 days', 5760)],
  };

  static const _discounts = [('Any', 0), ('On offer', 1), ('10%+', 10), ('20%+', 20), ('30%+', 30)];

  /// Values of [key] across the offers, most common first.
  List<String> _top(String? Function(Offer) key, {int max = 12}) {
    final counts = <String, int>{};
    for (final o in widget.offers) {
      final k = key(o);
      if (k != null) counts[k] = (counts[k] ?? 0) + 1;
    }
    final list = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return list.take(max).toList();
  }

  /// Result count with the draft filter, for the button label.
  int get _count => f.apply(widget.offers, SortMode.priceLow).length;

  Widget _chips(
    List<String> values,
    Set<String> selected,
    void Function(Set<String>) set, {
    Widget? Function(String)? avatar,
  }) => Wrap(
    spacing: Space.sm,
    runSpacing: Space.sm,
    children: [
      for (final v in values)
        FilterChip(
          avatar: avatar?.call(v),
          label: Text(v),
          selected: selected.contains(v),
          onSelected: (on) {
            final next = {...selected};
            on ? next.add(v) : next.remove(v);
            setState(() => set(next));
          },
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final platformIds = widget.offers.map((o) => o.platformId).toSet().toList();
    final brands = _top((o) => brandOf(o.title));
    final packs = _top((o) => o.quantity?.label, max: 10);
    final prices = widget.offers.map((o) => o.effectivePrice(includeFees: f.includeFees)).toList();
    final lo = prices.isEmpty ? 0.0 : prices.reduce((a, b) => a < b ? a : b).floorToDouble();
    final hi = prices.isEmpty ? 0.0 : prices.reduce((a, b) => a > b ? a : b).ceilToDouble();
    final cap = (f.maxPrice ?? hi).clamp(lo, hi);
    String name(String id) => kPlatformById[id]!.name;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (context, scroll) => SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.sm, Space.sm),
              child: Row(
                children: [
                  Expanded(child: Text('Filters', style: context.t.titleMedium)),
                  TextButton(onPressed: () => setState(() => f = f.cleared()), child: const Text('Reset')),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('In stock only', style: context.t.titleSmall),
                    subtitle: const Text('Hide items the app says are sold out'),
                    value: f.inStockOnly,
                    onChanged: (v) => setState(() => f = f.copyWith(inStockOnly: v)),
                  ),
                  const SizedBox(height: Space.sm),
                  const SectionLabel('Apps'),
                  _chips(
                    platformIds.map(name).toList(),
                    f.platforms.map(name).toSet(),
                    (names) => f = f.copyWith(platforms: platformIds.where((id) => names.contains(name(id))).toSet()),
                    avatar: (n) => PlatformBadge(kPlatforms.firstWhere((p) => p.name == n), size: 18),
                  ),
                  if (brands.length > 1) ...[
                    const SizedBox(height: Space.lg),
                    const SectionLabel('Brand'),
                    _chips(brands, f.brands, (s) => f = f.copyWith(brands: s)),
                  ],
                  if (packs.length > 1) ...[
                    const SizedBox(height: Space.lg),
                    const SectionLabel('Pack size'),
                    _chips(packs, f.packs, (s) => f = f.copyWith(packs: s)),
                  ],
                  const SizedBox(height: Space.lg),
                  const SectionLabel('Delivery within'),
                  Wrap(
                    spacing: Space.sm,
                    children: [
                      for (final (label, v) in _etaOptions)
                        ChoiceChip(
                          label: Text(label),
                          selected: f.maxEta == v,
                          onSelected: (_) => setState(() => f = f.copyWith(maxEta: () => v)),
                        ),
                    ],
                  ),
                  const SizedBox(height: Space.lg),
                  const SectionLabel('Discount'),
                  Wrap(
                    spacing: Space.sm,
                    children: [
                      for (final (label, v) in _discounts)
                        ChoiceChip(
                          label: Text(label),
                          selected: f.minDiscount == v,
                          onSelected: (_) => setState(() => f = f.copyWith(minDiscount: v)),
                        ),
                    ],
                  ),
                  if (hi > lo) ...[
                    const SizedBox(height: Space.lg),
                    SectionLabel(
                      'Max price',
                      trailing: Text(inr(cap), style: context.t.labelMedium!.copyWith(fontFeatures: tabular)),
                    ),
                    Slider(
                      min: lo,
                      max: hi,
                      value: cap,
                      onChanged: (v) =>
                          setState(() => f = f.copyWith(maxPrice: () => v >= hi ? null : v.roundToDouble())),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.md),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, f),
                  child: Text(_count == 0 ? 'No matches, adjust filters' : 'Show $_count results'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpenEverywhere extends StatelessWidget {
  const _OpenEverywhere({required this.query});
  final SearchQuery query;

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    final ps = platformsFor(query.vertical).where((p) => settings.isPlatformEnabled(p.id)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Check in each app'),
        LayoutBuilder(
          builder: (context, box) {
            final w = (box.maxWidth - Space.sm) / 2;
            return Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final p in ps)
                  SizedBox(
                    width: w,
                    child: Surface(
                      radius: Radii.lg,
                      padding: const EdgeInsets.all(Space.sm + 2),
                      onTap: () => openPlatformUrl(context, p.searchUrl(query.text), platformId: p.id),
                      child: Row(
                        children: [
                          PlatformBadge(p, size: 30),
                          const SizedBox(width: Space.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.name,
                                  style: context.t.labelMedium!.copyWith(fontWeight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                OpenHint(p.id),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: Space.sm),
        ValueListenableBuilder(
          valueListenable: AppLauncher.installed,
          builder: (context, _, _) => Text(
            'Links open in the app when it\'s installed, otherwise on the web.',
            style: context.t.bodySmall!.copyWith(fontSize: 11.5),
          ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Surface(
    child: Row(
      children: [
        Icon(Icons.search_off_rounded, color: context.c.inkMuted),
        const SizedBox(width: Space.md),
        Expanded(child: Text(text, style: context.t.bodyMedium)),
      ],
    ),
  );
}

class _EmptyFiltered extends StatelessWidget {
  const _EmptyFiltered({required this.onReset});
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('No offers match these filters.', style: context.t.bodyMedium),
      TextButton(
        onPressed: onReset,
        style: TextButton.styleFrom(padding: EdgeInsets.zero),
        child: const Text('Clear filters'),
      ),
    ],
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: context.c.surfaceAlt, shape: BoxShape.circle),
            child: Icon(Icons.cloud_off_rounded, size: 30, color: context.c.inkMuted),
          ),
          const SizedBox(height: Space.lg),
          Text(message, textAlign: TextAlign.center, style: context.t.bodyMedium),
          const SizedBox(height: Space.lg),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}
