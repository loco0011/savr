import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/link_parser.dart';
import '../core/models.dart';
import '../core/platforms.dart';
import 'price_source.dart';
import 'safe_http.dart';

/// Talks to a Savr-compatible aggregator backend (your own server, an n8n
/// webhook, an Apify actor behind a proxy, …). Contract — see README:
///
///   GET {base}/v1/search?q=&vertical=&platforms=a,b&pincode=
///   Authorization: Bearer {apiKey}
///   200 → { "offers": [ { "platform": "blinkit", "title": "…", "pack": "500 ml",
///            "price": 28, "mrp": 30, "deliveryFee": 0, "etaMinutes": 9,
///            "inStock": true, "url": "https://blinkit.com/…", "seller": null } ] }
///
/// The response is treated as untrusted input: every field is type-checked,
/// numbers are range-checked, unknown platforms are dropped and offer URLs are
/// kept only if they point at that platform's own HTTPS host.
class RemotePriceSource implements PriceSource {
  RemotePriceSource({required this.baseUrl, required this.apiKey, SafeHttp? http}) : _http = http ?? SafeHttp();

  final Uri baseUrl;
  final String? apiKey;
  final SafeHttp _http;

  static const _maxOffers = 300;

  @override
  Future<List<Offer>> search(SearchQuery query, {required Set<String> platformIds, String? pincode}) async {
    final url = baseUrl.replace(
      path: '${baseUrl.path.replaceAll(RegExp(r'/+$'), '')}/v1/search',
      queryParameters: {
        'q': sanitizeQuery(query.text),
        'vertical': query.vertical.name,
        'platforms': platformIds.join(','),
        if (pincode != null && RegExp(r'^\d{6}$').hasMatch(pincode)) 'pincode': pincode,
      },
    );

    final ({int status, String body, Uri finalUrl}) res;
    try {
      res = await _http.get(
        url,
        allowHost: (h) => h == baseUrl.host,
        headers: {if (apiKey != null && apiKey!.isNotEmpty) 'Authorization': 'Bearer $apiKey'},
      );
    } on TimeoutException {
      throw const PriceSourceException('The price server took too long to respond.', code: 'timeout');
    } on SocketException {
      throw const PriceSourceException('No internet connection.', code: 'offline');
    } on HandshakeException {
      throw const PriceSourceException('Secure connection to the price server failed.', code: 'tls');
    } on HttpException {
      throw const PriceSourceException('The price server could not be reached.', code: 'http');
    }

    if (res.status == 401 || res.status == 403) {
      throw const PriceSourceException('The price server rejected the API key.', code: 'auth');
    }
    if (res.status == 429) {
      throw const PriceSourceException('Too many requests. Try again in a moment.', code: 'rate');
    }
    if (res.status != 200) {
      throw PriceSourceException('The price server returned an error.', code: 'status_${res.status}');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(res.body);
    } on FormatException {
      throw const PriceSourceException('The price server sent an invalid response.', code: 'json');
    }
    if (decoded is! Map || decoded['offers'] is! List) {
      throw const PriceSourceException('The price server sent an invalid response.', code: 'shape');
    }

    final out = <Offer>[];
    for (final raw in (decoded['offers'] as List).take(_maxOffers)) {
      final o = _parseOffer(raw, platformIds);
      if (o != null) out.add(o);
    }
    return out;
  }

  /// Health check used by the admin panel.
  Future<int> ping() async {
    final url = baseUrl.replace(path: '${baseUrl.path.replaceAll(RegExp(r'/+$'), '')}/v1/health');
    final sw = Stopwatch()..start();
    final res = await _http.get(
      url,
      allowHost: (h) => h == baseUrl.host,
      headers: {if (apiKey != null && apiKey!.isNotEmpty) 'Authorization': 'Bearer $apiKey'},
      timeout: const Duration(seconds: 8),
    );
    if (res.status != 200) throw PriceSourceException('Health check failed (${res.status}).');
    return sw.elapsedMilliseconds;
  }

  static Offer? _parseOffer(Object? raw, Set<String> allowed) {
    if (raw is! Map) return null;
    final pid = raw['platform'];
    if (pid is! String || !allowed.contains(pid)) return null;
    final platform = kPlatformById[pid];
    if (platform == null) return null;

    final title = raw['title'];
    final price = _num(raw['price']);
    if (title is! String || price == null) return null;

    Uri? link;
    final u = raw['url'];
    if (u is String && u.length < 2048) {
      final parsed = Uri.tryParse(u);
      if (parsed != null && parsed.scheme == 'https' && platform.ownsHost(parsed.host)) link = parsed;
    }

    String? str(Object? v, int max) {
      if (v is! String) return null;
      final s = sanitizeQuery(v);
      if (s.isEmpty) return null;
      return s.length > max ? s.substring(0, max) : s;
    }

    final eta = _num(raw['etaMinutes'], max: 60 * 24 * 30);

    return Offer(
      platformId: pid,
      title: str(title, 160) ?? 'Untitled',
      packLabel: str(raw['pack'], 40),
      price: price,
      mrp: _num(raw['mrp']),
      deliveryFee: _num(raw['deliveryFee'], max: 10000) ?? 0,
      etaMinutes: eta?.round(),
      inStock: raw['inStock'] is bool ? raw['inStock'] as bool : true,
      url: link ?? platform.searchUrl(title),
      seller: str(raw['seller'], 80),
      group: str(raw['group'], 120),
    );
  }

  static double? _num(Object? v, {double max = 10000000}) {
    if (v is! num) return null;
    final d = v.toDouble();
    if (d.isNaN || d.isInfinite || d < 0 || d > max) return null;
    return d;
  }
}
