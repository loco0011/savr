import '../core/link_parser.dart';
import '../core/models.dart';
import '../core/platforms.dart';
import '../state/settings.dart';
import 'device/device_source.dart';
import 'price_source.dart';
import 'remote_source.dart';
import 'sample_source.dart';
import 'title_resolver.dart';

/// Single entry point the UI uses for searches. Picks the configured source,
/// caches results briefly and records diagnostics for the admin panel.
class PriceRepository {
  PriceRepository(this.settings);

  final Settings settings;
  final _titles = TitleResolver();
  final _cache = <String, ({DateTime at, SearchResult result})>{};

  static const _ttl = Duration(minutes: 5);
  static const _maxCache = 50;

  final diagnostics = Diagnostics();

  /// Converts raw user input (name or pasted link) into a query.
  /// Returns null with [error] set if a link was pasted but isn't supported.
  Future<({SearchQuery? query, String? error})> interpret(String raw, Vertical selected) async {
    final input = raw.trim();
    if (input.isEmpty) return (query: null, error: null);

    if (LinkParser.looksLikeLink(input)) {
      var parsed = LinkParser.parse(input);
      if (parsed == null) {
        return (query: null, error: 'That link isn\'t from a supported app. Try searching by name.');
      }
      if (parsed.name == null) parsed = await _titles.resolve(parsed) ?? parsed;
      final name = parsed.name;
      if (name == null) {
        return (query: null, error: 'Couldn\'t read the product name from that link. Try typing it instead.');
      }
      return (
        query: SearchQuery(text: name, vertical: parsed.vertical, sourcePlatformId: parsed.platform.id),
        error: null,
      );
    }

    final text = sanitizeQuery(input);
    if (text.length < 2) return (query: null, error: 'Type at least 2 characters.');
    return (query: SearchQuery(text: text, vertical: selected), error: null);
  }

  Future<SearchResult> search(SearchQuery q) => searchStream(q).last;

  /// Emits partial results as each live platform answers, then the final
  /// one. Sample and server modes emit once.
  Stream<SearchResult> searchStream(SearchQuery q) async* {
    final platformIds = platformsFor(q.vertical).map((p) => p.id).where(settings.isPlatformEnabled).toSet();
    var mode = settings.dataMode;
    if (mode == DataMode.server && settings.backendUrl == null) mode = DataMode.device;

    // On-device fetching exists for some platforms only; other categories
    // fall back to clearly-labelled samples.
    final deviceIds = platformIds.where(DevicePriceSource.supports).toSet();
    if (mode == DataMode.device && deviceIds.isEmpty) mode = DataMode.sample;

    if (mode == DataMode.device) {
      final ready = deviceIds.where(settings.isLocationSet).toSet();
      final needsSetup = deviceIds.difference(ready).toList();
      if (ready.isEmpty) {
        yield SearchResult(
          query: q,
          offers: const [],
          isSample: false,
          needsSetup: needsSetup,
          notice: 'Set your location so Savr can fetch the prices you\'d actually see.',
        );
        return;
      }
      final place = settings.place;
      final key =
          'D|${q.text.toLowerCase()}|${ready.join(',')}|${place == null ? '-' : '${place.lat.toStringAsFixed(3)},${place.lng.toStringAsFixed(3)}'}';
      final hit = _cache[key];
      if (hit != null && DateTime.now().difference(hit.at) < _ttl) {
        yield hit.result;
        return;
      }

      final sw = Stopwatch()..start();
      late DeviceSearchResult r;
      await for (final part in const DevicePriceSource().searchStream(q.text, ready, place: place)) {
        r = part;
        if (!part.isComplete && part.offers.isNotEmpty) {
          yield SearchResult(
            query: q,
            offers: part.offers,
            isSample: false,
            live: part.live,
            failed: part.failed,
            pending: part.pending,
            needsSetup: needsSetup,
          );
        }
      }
      diagnostics.record(
        ok: r.live.isNotEmpty,
        ms: sw.elapsedMilliseconds,
        live: true,
        code: r.live.isEmpty ? 'device_failed' : null,
      );
      if (r.live.isEmpty) {
        throw const PriceSourceException(
          'Couldn\'t load prices from the apps. Check your connection and try again.',
          code: 'device_failed',
        );
      }
      final result = SearchResult(
        query: q,
        offers: r.offers,
        isSample: false,
        live: r.live,
        failed: r.failed,
        needsSetup: needsSetup,
        notice: r.offers.isEmpty ? 'No matching products found at your location.' : null,
      );
      _put(key, result);
      yield result;
      return;
    }
    yield await _searchOther(q, mode, platformIds);
  }

  Future<SearchResult> _searchOther(SearchQuery q, DataMode mode, Set<String> platformIds) async {

    final live = mode == DataMode.server;
    final key =
        '${live ? 'L' : 'S'}|${q.vertical.name}|${q.text.toLowerCase()}|${settings.pincode}|${platformIds.join(',')}';
    final hit = _cache[key];
    if (hit != null && DateTime.now().difference(hit.at) < _ttl) return hit.result;

    final PriceSource source = live
        ? RemotePriceSource(baseUrl: settings.backendUrl!, apiKey: await settings.readApiKey())
        : const SamplePriceSource();

    final sw = Stopwatch()..start();
    try {
      final offers = await source.search(q, platformIds: platformIds, pincode: settings.pincode);
      diagnostics.record(ok: true, ms: sw.elapsedMilliseconds, live: live);
      final result = SearchResult(
        query: q,
        offers: offers,
        isSample: !live,
        live: live ? offers.map((o) => o.platformId).toSet().toList() : const [],
        notice: offers.isEmpty
            ? (live
                  ? 'No matching products found.'
                  : 'No sample prices for this item. Open it directly on each app below.')
            : null,
      );
      _put(key, result);
      return result;
    } on PriceSourceException catch (e) {
      diagnostics.record(ok: false, ms: sw.elapsedMilliseconds, live: live, code: e.code);
      rethrow;
    }
  }

  void _put(String key, SearchResult r) {
    if (_cache.length >= _maxCache) _cache.remove(_cache.keys.first);
    _cache[key] = (at: DateTime.now(), result: r);
  }

  void clearCache() => _cache.clear();
  int get cacheSize => _cache.length;
}

class Diagnostics {
  int requests = 0;
  int failures = 0;
  int? lastLatencyMs;
  String? lastErrorCode;
  DateTime? lastAt;
  bool lastWasLive = false;

  void record({required bool ok, required int ms, required bool live, String? code}) {
    requests++;
    if (!ok) {
      failures++;
      lastErrorCode = code;
    }
    lastLatencyMs = ms;
    lastAt = DateTime.now();
    lastWasLive = live;
  }

  void reset() {
    requests = failures = 0;
    lastLatencyMs = null;
    lastErrorCode = null;
    lastAt = null;
  }
}
