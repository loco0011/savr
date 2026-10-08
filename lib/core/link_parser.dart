import 'models.dart';
import 'platforms.dart';

class ParsedLink {
  const ParsedLink({required this.url, required this.platform, required this.vertical, this.name});
  final Uri url;
  final MarketPlatform platform;
  final Vertical vertical;

  /// Product / restaurant name recovered from the URL or the share text.
  /// Null when the link carries only an opaque id (e.g. short links).
  final String? name;
}

/// Turns pasted text ("Check out Amul Taaza on Blinkit https://blinkit.com/prn/…")
/// into a search query. Pure and synchronous — no network.
abstract final class LinkParser {
  static const _maxInput = 2048;
  static final _urlRe = RegExp(r'https?://[^\s<>"]+', caseSensitive: false);

  /// Returns the first URL in [input] if any, ignoring everything else.
  static Uri? extractUrl(String input) {
    final s = input.length > _maxInput ? input.substring(0, _maxInput) : input;
    final m = _urlRe.firstMatch(s);
    if (m == null) return null;
    // Trim trailing punctuation that share sheets often append.
    final raw = m.group(0)!.replaceAll(RegExp(r'[).,;!?\]]+$'), '');
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty) return null;
    return uri;
  }

  static bool looksLikeLink(String input) => extractUrl(input) != null;

  /// Parses [input]. Returns null if no URL from a supported platform is found.
  static ParsedLink? parse(String input) {
    final url = extractUrl(input);
    if (url == null) return null;
    // Only HTTPS links to known hosts are accepted (http is upgraded).
    final secure = url.scheme == 'http' ? url.replace(scheme: 'https') : url;
    if (!isTrustedPlatformUrl(secure)) return null;

    final platform = _resolvePlatform(secure);
    if (platform == null) return null;
    final vertical = platform.verticals.first;

    final fromPath = _nameFromPath(platform.id, secure.pathSegments);
    final fromText = _nameFromShareText(input, platform);
    return ParsedLink(url: secure, platform: platform, vertical: vertical, name: fromPath ?? fromText);
  }

  /// Several platforms share a host (swiggy.com hosts both food and
  /// Instamart), so pick by path first, then by host.
  static MarketPlatform? _resolvePlatform(Uri url) {
    final host = url.host.toLowerCase();
    final path = url.path.toLowerCase();
    if (host.endsWith('swiggy.com')) {
      return kPlatformById[path.startsWith('/instamart') ? 'instamart' : 'swiggy'];
    }
    if (host.endsWith('flipkart.com') && url.queryParameters['marketplace'] == 'HYPERLOCAL') {
      return kPlatformById['fkminutes'];
    }
    const preferred = ['blinkit', 'zepto', 'bigbasket', 'jiomart', 'dmart', 'amazon', 'flipkart'];
    for (final id in preferred) {
      if (kPlatformById[id]!.ownsHost(host)) return kPlatformById[id];
    }
    for (final p in kPlatforms) {
      if (p.ownsHost(host)) return p;
    }
    return null;
  }

  static String? _segmentAfter(List<String> segs, String key) {
    final i = segs.indexOf(key);
    return (i >= 0 && i + 1 < segs.length) ? segs[i + 1] : null;
  }

  static String? _nameFromPath(String platformId, List<String> segs) {
    if (segs.isEmpty) return null;
    String? slug;
    switch (platformId) {
      case 'blinkit':
        slug = _segmentAfter(segs, 'prn'); // /prn/{slug}/prid/{id}
      case 'zepto':
        slug = _segmentAfter(segs, 'pn'); // /pn/{slug}/pvid/{id}
      case 'amazon' || 'amazonnow' || 'amazonfresh':
        final dp = segs.indexOf('dp'); // /{slug}/dp/{asin}
        if (dp > 0) slug = segs[dp - 1];
      case 'flipkart' || 'fkminutes':
        final p = segs.indexOf('p'); // /{slug}/p/{itm}
        if (p > 0) slug = segs[p - 1];
      case 'bigbasket' || 'bbnow':
        slug = segs.length >= 3 && segs[0] == 'pd' ? segs[2] : null; // /pd/{id}/{slug}/
      case 'jiomart':
        if (segs.isNotEmpty && segs[0] == 'p' && segs.length >= 3) slug = segs[segs.length - 2];
      case 'meesho':
        final p = segs.indexOf('p');
        if (p > 0) slug = segs[p - 1];
      case 'myntra':
        if (segs.length >= 3 && segs.last == 'buy') slug = segs[segs.length - 3];
      case 'zomato':
        // /{city}/{restaurant}/order
        if (segs.length >= 2) slug = segs[1];
      case 'swiggy':
        // /restaurants/{name-area-city-id} or /city/{city}/{name-area-rest123}
        final r = segs.indexOf('restaurants');
        if (r >= 0 && r + 1 < segs.length) slug = segs[r + 1].replaceAll(RegExp(r'-\d+$'), '');
        if (segs.length >= 3 && segs[0] == 'city') slug = segs[2].replaceAll(RegExp(r'-rest\d+$'), '');
    }
    slug ??= _bestGenericSlug(segs);
    return _humanise(slug);
  }

  /// Picks the longest hyphenated, mostly-alphabetic path segment.
  static String? _bestGenericSlug(List<String> segs) {
    String? best;
    for (final s in segs) {
      if (!s.contains('-')) continue;
      final letters = s.replaceAll(RegExp(r'[^a-zA-Z]'), '').length;
      if (letters < s.length * 0.6) continue;
      if (best == null || s.length > best.length) best = s;
    }
    return best;
  }

  static String? _humanise(String? slug) {
    if (slug == null) return null;
    final words = Uri.decodeComponent(slug)
        .split(RegExp(r'[-_+\s]+'))
        .where((w) => w.isNotEmpty && !RegExp(r'^[0-9a-f]{8,}$', caseSensitive: false).hasMatch(w))
        .take(10)
        .toList();
    if (words.isEmpty) return null;
    final out = words.join(' ').trim();
    return out.length < 2 ? null : sanitizeQuery(out);
  }

  /// Share text from apps usually reads `Buy <name> on <App>: <link>`.
  static String? _nameFromShareText(String input, MarketPlatform p) {
    var t = input.replaceAll(_urlRe, ' ');
    t = t.replaceAll(RegExp(r'\b(check out|buy|order|get|this|on|at|from|via|now|link)\b', caseSensitive: false), ' ');
    t = t.replaceAll(RegExp(RegExp.escape(p.name), caseSensitive: false), ' ');
    t = sanitizeQuery(t);
    return t.length >= 3 ? t : null;
  }
}

/// Normalises a free-text query: strips control and markup characters,
/// collapses whitespace and caps the length. Applied to every query before it
/// is displayed, cached or sent to a backend.
String sanitizeQuery(String input) {
  var s = input.replaceAll(RegExp(r'[\u0000-\u001F\u007F<>{}\[\]\\^`|"]'), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (s.length > 120) s = s.substring(0, 120).trim();
  return s;
}
