import '../../core/link_parser.dart';
import '../../core/models.dart';
import '../../core/platforms.dart';

/// Reads the JSON a platform's own website fetches while showing search
/// results in a hidden WebView, and turns it into [Offer]s.
///
/// Everything here is untrusted third-party data: walks are depth- and
/// size-limited, every field is type-checked and prices range-checked.
abstract class DeviceScraper {
  const DeviceScraper();

  String get platformId;
  MarketPlatform get platform => kPlatformById[platformId]!;

  /// The public search page to load.
  Uri entryUrl(String query);

  /// Home page used for the one-time "set your location" step.
  Uri get homeUrl;

  /// JS regex source (no slashes) for responses worth capturing.
  String get capturePattern;

  /// Feeds one captured response into [st].
  void ingest(Uri url, Object? json, ScrapeState st);
}

class ScrapeState {
  final Map<String, Offer> offers = {};
  int? etaMinutes;
  bool gotSearch = false;

  /// Set by a scraper when the site answered with a placeholder (e.g. while
  /// its bot check is still issuing a token) — the runner reloads once.
  bool placeholder = false;

  /// Offers with the ETA applied (ETA often arrives in a separate response).
  List<Offer> build() => [
    for (final o in offers.values)
      Offer(
        platformId: o.platformId,
        title: o.title,
        packLabel: o.packLabel,
        price: o.price,
        mrp: o.mrp,
        etaMinutes: o.etaMinutes ?? etaMinutes,
        inStock: o.inStock,
        url: o.url,
      ),
  ];
}

const deviceScrapers = <DeviceScraper>[
  BlinkitScraper(),
  ZeptoScraper(),
  InstamartScraper(),
  BigBasketScraper('bbnow'),
  BigBasketScraper('bigbasket'),
];
final deviceScraperById = {for (final s in deviceScrapers) s.platformId: s};

// ---------------------------------------------------------------------------

class BlinkitScraper extends DeviceScraper {
  const BlinkitScraper();

  @override
  String get platformId => 'blinkit';

  @override
  Uri entryUrl(String q) => Uri.https('blinkit.com', '/s/', {'q': q});

  @override
  Uri get homeUrl => Uri.https('blinkit.com', '/');

  @override
  String get capturePattern => r'blinkit\.com/v1/(layout/search|consumerweb/eta)';

  @override
  void ingest(Uri url, Object? json, ScrapeState st) {
    if (url.path.contains('/consumerweb/eta')) {
      if (json is Map) st.etaMinutes ??= _int(json['eta_in_minutes'], max: 600);
      return;
    }
    st.gotSearch = true;
    // Product cards carry a canonical "cart_item" object.
    walkMaps(json, (m) {
      final id = _int(m['product_id']);
      final name = _str(m['product_name']);
      final price = _price(m['price']);
      if (id == null || name == null || price == null) return false;
      final key = 'blinkit:$id';
      if (st.offers.containsKey(key)) return true;
      st.offers[key] = Offer(
        platformId: platformId,
        title: name,
        packLabel: _str(m['unit'], max: 40),
        price: price,
        mrp: _price(m['mrp']),
        inStock: (_int(m['inventory']) ?? 1) > 0,
        url: Uri.https('blinkit.com', '/prn/${_slug(name)}/prid/$id'),
      );
      return true;
    });
  }
}

class ZeptoScraper extends DeviceScraper {
  const ZeptoScraper();

  @override
  String get platformId => 'zepto';

  @override
  Uri entryUrl(String q) => Uri.https('www.zepto.com', '/search', {'query': q});

  @override
  Uri get homeUrl => Uri.https('www.zepto.com', '/');

  @override
  String get capturePattern => r'zepto\.com/(user-search-service/api/v\d+/search|lms/api/v\d+/get_page)';

  @override
  void ingest(Uri url, Object? json, ScrapeState st) {
    if (url.path.contains('get_page')) {
      walkMaps(json, (m) {
        final eta = _int(m['etaInMinutes'], max: 600);
        if (eta != null && eta > 0) st.etaMinutes ??= eta;
        return eta != null;
      });
      return;
    }
    st.gotSearch = true;
    walkMaps(json, (m) {
      final product = m['product'];
      final variant = m['productVariant'];
      if (product is! Map || variant is! Map) return false;
      final vid = _str(variant['id'], max: 64);
      final name = _str(product['name']);
      // Prices are in paise.
      final paise = _price(m['discountedSellingPrice']) ?? _price(m['sellingPrice']);
      if (vid == null || name == null || paise == null) return false;
      if (!RegExp(r'^[0-9a-fA-F-]{8,64}$').hasMatch(vid)) return true;
      final key = 'zepto:$vid';
      if (st.offers.containsKey(key)) return true;
      final mrp = _price(m['mrp']);
      st.offers[key] = Offer(
        platformId: platformId,
        title: name,
        packLabel: _str(variant['formattedPacksize'], max: 40),
        price: paise / 100,
        mrp: mrp == null ? null : mrp / 100,
        inStock: m['outOfStock'] != true,
        url: Uri.https('www.zepto.com', '/pn/${_slug(name)}/pvid/$vid'),
      );
      return true;
    });
  }
}

class InstamartScraper extends DeviceScraper {
  const InstamartScraper();

  @override
  String get platformId => 'instamart';

  @override
  Uri entryUrl(String q) => Uri.https('www.swiggy.com', '/instamart/search', {'custom_back': 'true', 'query': q});

  @override
  Uri get homeUrl => Uri.https('www.swiggy.com', '/instamart');

  @override
  String get capturePattern => r'swiggy\.com/api/instamart/search';

  @override
  void ingest(Uri url, Object? json, ScrapeState st) {
    if (json is! Map || json['data'] == null) {
      st.placeholder = true; // answered before the bot check cleared
      return;
    }
    st.gotSearch = true;
    walkMaps(json, (m) {
      final variations = m['variations'];
      if (variations is! List || m['productId'] == null) return false;
      final pid = _str(m['productId'], max: 40);
      // Exact product page when the id looks sane; otherwise a search.
      final productUrl = pid != null && RegExp(r'^[A-Za-z0-9_-]{4,40}$').hasMatch(pid)
          ? Uri.https('www.swiggy.com', '/instamart/item/$pid')
          : null;
      for (final v in variations.take(8)) {
        if (v is! Map) continue;
        final sku = _str(v['skuId'], max: 40);
        final name = _str(v['displayName']);
        final price = v['price'];
        if (sku == null || name == null || price is! Map) continue;
        final offer = _rupees(price['offerPrice']);
        if (offer == null) continue;
        final key = 'instamart:$sku';
        if (st.offers.containsKey(key)) continue;
        final inv = v['inventory'];
        st.offers[key] = Offer(
          platformId: platformId,
          title: name,
          packLabel: _str(v['quantityDescription'], max: 40),
          price: offer,
          mrp: _rupees(price['mrp']),
          inStock: inv is Map ? inv['inStock'] != false : true,
          url: productUrl ?? platform.searchUrl(name),
        );
      }
      return true;
    });
  }

  /// {"currencyCode":"INR","units":"924","nanos":0}
  static double? _rupees(Object? money) {
    if (money is! Map) return null;
    final units = money['units'];
    final n = units is String ? double.tryParse(units) : (units is num ? units.toDouble() : null);
    if (n == null) return null;
    final nanos = money['nanos'];
    final total = n + (nanos is num ? nanos / 1e9 : 0);
    return _price(total);
  }
}

/// BigBasket's search page reads `listing-svc/v2/products`. The same
/// listing serves BB Now (quick) and scheduled BigBasket (grocery), so one
/// class covers both platform ids.
class BigBasketScraper extends DeviceScraper {
  const BigBasketScraper(this.platformId);

  @override
  final String platformId;

  @override
  Uri entryUrl(String q) => Uri.https('www.bigbasket.com', '/ps/', {'q': q, 'nc': 'as'});

  @override
  Uri get homeUrl => Uri.https('www.bigbasket.com', '/');

  @override
  String get capturePattern => r'bigbasket\.com/listing-svc/v2/products';

  @override
  void ingest(Uri url, Object? json, ScrapeState st) {
    st.gotSearch = true;
    walkMaps(json, (m) {
      final desc = _str(m['desc']);
      final pricing = m['pricing'];
      final id = _str(m['id'], max: 20);
      if (desc == null || pricing is! Map || id == null || !RegExp(r'^\d{1,12}$').hasMatch(id)) return false;
      final discount = pricing['discount'];
      if (discount is! Map) return true;
      final prim = discount['prim_price'];
      final sp = _price(_num(prim is Map ? prim['sp'] : null));
      if (sp == null) return true;
      final key = '$platformId:$id';
      if (st.offers.containsKey(key)) return true;
      // Titles omit the brand ("Taaza Homogenised Toned Milk"); prefix it.
      final brand = m['brand'] is Map ? _str((m['brand'] as Map)['name'], max: 40) : null;
      final title = brand != null && !desc.toLowerCase().startsWith(brand.toLowerCase()) ? '$brand $desc' : desc;
      final avail = m['availability'];
      final path = _str(m['absolute_url'], max: 200);
      st.offers[key] = Offer(
        platformId: platformId,
        title: title,
        packLabel: _str(m['w'], max: 40),
        price: sp,
        mrp: _price(_num(discount['mrp'])),
        inStock: avail is Map ? avail['avail_status'] == '001' && avail['not_for_sale'] != true : true,
        url: path != null && path.startsWith('/pd/') ? Uri.parse('https://www.bigbasket.com$path') : platform.searchUrl(title),
      );
      return true;
    });
  }

  /// BigBasket sends prices as strings ("77").
  static num? _num(Object? v) => v is num ? v : (v is String ? num.tryParse(v) : null);
}

// ---------------------------------------------------------------------------

/// Visits every map in [root] depth-first. [visit] returns true when it
/// consumed the map (children are then skipped). Bounded so a hostile or
/// pathological payload can't hang the app.
void walkMaps(Object? root, bool Function(Map<dynamic, dynamic>) visit, {int maxDepth = 48, int maxNodes = 200000}) {
  var nodes = 0;
  void go(Object? o, int depth) {
    if (depth > maxDepth || ++nodes > maxNodes) return;
    if (o is Map) {
      if (visit(o)) return;
      for (final v in o.values) {
        go(v, depth + 1);
      }
    } else if (o is List) {
      for (final v in o) {
        go(v, depth + 1);
      }
    }
  }

  go(root, 0);
}

String? _str(Object? v, {int max = 160}) {
  if (v is! String) return null;
  final s = sanitizeQuery(v);
  if (s.isEmpty) return null;
  return s.length > max ? s.substring(0, max) : s;
}

int? _int(Object? v, {int max = 1 << 40}) {
  final n = v is num ? v : (v is String ? num.tryParse(v) : null);
  if (n == null || n < 0 || n > max) return null;
  return n.toInt();
}

double? _price(Object? v) {
  if (v is! num) return null;
  final d = v.toDouble();
  if (d.isNaN || d <= 0 || d > 100000000) return null;
  return d;
}

String _slug(String s) {
  final out = s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  return out.isEmpty ? 'item' : (out.length > 80 ? out.substring(0, 80) : out);
}
