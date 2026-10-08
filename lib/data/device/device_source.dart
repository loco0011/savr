import 'dart:async';

import '../../core/fees.dart';
import '../../core/matcher.dart';
import '../../core/models.dart';
import '../../core/place.dart';
import 'scrapers.dart';
import 'webview_runner.dart';

class DeviceSearchResult {
  const DeviceSearchResult({required this.offers, required this.live, required this.failed, this.pending = const []});
  final List<Offer> offers;

  /// Platforms that answered.
  final List<String> live;

  /// Platforms that timed out or were blocked.
  final List<String> failed;

  /// Platforms still loading (only in partial results).
  final List<String> pending;

  bool get isComplete => pending.isEmpty;
}

/// Fetches live prices on the phone by loading each platform's own search
/// page in a hidden WebView (see [runScraper]). Runs platforms in parallel.
class DevicePriceSource {
  const DevicePriceSource();

  static bool supports(String platformId) => deviceScraperById.containsKey(platformId);

  /// Emits a growing result each time one platform finishes, so the UI can
  /// show the fastest app's prices without waiting for the slowest.
  Stream<DeviceSearchResult> searchStream(String query, Set<String> platformIds, {Place? place}) {
    final scrapers = platformIds.map((id) => deviceScraperById[id]).whereType<DeviceScraper>().toList();
    final ctrl = StreamController<DeviceSearchResult>();
    final offers = <Offer>[];
    final live = <String>[];
    final failed = <String>[];
    final pending = scrapers.map((s) => s.platformId).toList();
    if (scrapers.isEmpty) {
      ctrl
        ..add(const DeviceSearchResult(offers: [], live: [], failed: []))
        ..close();
      return ctrl.stream;
    }

    for (final s in scrapers) {
      runScraper(s, query, place: place)
          .catchError((Object _) => const ScrapeOutcome(offers: [], ok: false, reason: 'error'))
          .then((o) {
            pending.remove(s.platformId);
            (o.ok ? live : failed).add(s.platformId);
            // Platforms return loosely related items too ("milk" → milk
            // cookies); keep those that match the query and cap per platform.
            final relevant = o.offers.where((x) => ProductMatcher.relevance(query, x.title) >= 0.5).take(24);
            offers.addAll(withEstimatedFees(relevant.toList()));
            if (ctrl.isClosed) return;
            ctrl.add(
              DeviceSearchResult(
                offers: List.unmodifiable(offers),
                live: List.unmodifiable(live),
                failed: List.unmodifiable(failed),
                pending: List.unmodifiable(pending),
              ),
            );
            if (pending.isEmpty) ctrl.close();
          });
    }
    return ctrl.stream;
  }

  Future<DeviceSearchResult> search(String query, Set<String> platformIds, {Place? place}) =>
      searchStream(query, platformIds, place: place).last;
}
