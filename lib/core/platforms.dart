import 'dart:ui' show Color;

import 'models.dart';

/// A marketplace / service Savr can compare.
///
/// [hosts] is the allowlist used everywhere a URL is trusted: link parsing,
/// title fetching and opening offers. A URL whose host is not listed for its
/// platform is never opened or fetched.
class MarketPlatform {
  const MarketPlatform({
    required this.id,
    required this.name,
    required this.verticals,
    required this.hosts,
    required this.brand,
    required this.search,
    this.typicalEta,
  });

  final String id;
  final String name;
  final Set<Vertical> verticals;
  final Set<String> hosts;

  /// Only used for the small identity dot next to the name, never for text.
  final Color brand;

  /// Builds the public search page URL for a query.
  final Uri Function(String query) search;

  /// Typical delivery window in minutes, used for sample data only.
  final int? typicalEta;

  bool ownsHost(String host) {
    final h = host.toLowerCase();
    return hosts.any((allowed) => h == allowed || h.endsWith('.$allowed'));
  }

  Uri searchUrl(String query) => search(query.trim());
}

Uri _u(String base, Map<String, String> qp) => Uri.parse(base).replace(queryParameters: qp);

String _slug(String q) => q.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');

final List<MarketPlatform> kPlatforms = [
  // Quick commerce
  MarketPlatform(
    id: 'blinkit',
    name: 'Blinkit',
    verticals: {Vertical.quick},
    hosts: {'blinkit.com', 'blinkit.onelink.me'},
    brand: const Color(0xFFF8CB46),
    typicalEta: 10,
    search: (q) => _u('https://blinkit.com/s/', {'q': q}),
  ),
  MarketPlatform(
    id: 'zepto',
    name: 'Zepto',
    verticals: {Vertical.quick},
    hosts: {'zepto.com', 'zeptonow.com', 'zepto.co.in', 'zeptonow.onelink.me'},
    brand: const Color(0xFF5E17EB),
    typicalEta: 10,
    search: (q) => _u('https://www.zepto.com/search', {'query': q}),
  ),
  MarketPlatform(
    id: 'instamart',
    name: 'Swiggy Instamart',
    verticals: {Vertical.quick},
    hosts: {'swiggy.com', 'swiggy.onelink.me'},
    brand: const Color(0xFFFC8019),
    typicalEta: 12,
    search: (q) => _u('https://www.swiggy.com/instamart/search', {'query': q}),
  ),
  MarketPlatform(
    id: 'bbnow',
    name: 'BB Now',
    verticals: {Vertical.quick},
    hosts: {'bigbasket.com', 'bigbasket.onelink.me'},
    brand: const Color(0xFF84C225),
    typicalEta: 15,
    search: (q) => _u('https://www.bigbasket.com/ps/', {'q': q, 'nc': 'as'}),
  ),
  MarketPlatform(
    id: 'fkminutes',
    name: 'Flipkart Minutes',
    verticals: {Vertical.quick},
    hosts: {'flipkart.com', 'dl.flipkart.com', 'fkrt.it'},
    brand: const Color(0xFF2874F0),
    typicalEta: 13,
    search: (q) => _u('https://www.flipkart.com/search', {'q': q, 'marketplace': 'HYPERLOCAL'}),
  ),
  MarketPlatform(
    id: 'amazonnow',
    name: 'Amazon Now',
    verticals: {Vertical.quick},
    hosts: {'amazon.in', 'amzn.in', 'amzn.to'},
    brand: const Color(0xFFFF9900),
    typicalEta: 15,
    search: (q) => _u('https://www.amazon.in/s', {'k': q}),
  ),
  // Grocery
  MarketPlatform(
    id: 'bigbasket',
    name: 'BigBasket',
    verticals: {Vertical.grocery},
    hosts: {'bigbasket.com', 'bigbasket.onelink.me'},
    brand: const Color(0xFF84C225),
    typicalEta: 240,
    search: (q) => _u('https://www.bigbasket.com/ps/', {'q': q}),
  ),
  MarketPlatform(
    id: 'jiomart',
    name: 'JioMart',
    verticals: {Vertical.quick, Vertical.grocery, Vertical.shopping},
    hosts: {'jiomart.com'},
    brand: const Color(0xFF0078AD),
    typicalEta: 180,
    search: (q) => Uri.parse('https://www.jiomart.com/search/${Uri.encodeComponent(q)}'),
  ),
  MarketPlatform(
    id: 'dmart',
    name: 'DMart Ready',
    verticals: {Vertical.grocery},
    hosts: {'dmart.in'},
    brand: const Color(0xFF00843D),
    typicalEta: 1440,
    search: (q) => _u('https://www.dmart.in/search', {'searchTerm': q}),
  ),
  MarketPlatform(
    id: 'amazonfresh',
    name: 'Amazon Fresh',
    verticals: {Vertical.grocery},
    hosts: {'amazon.in', 'amzn.in', 'amzn.to'},
    brand: const Color(0xFF5EA03E),
    typicalEta: 180,
    search: (q) => _u('https://www.amazon.in/s', {'k': q, 'i': 'nowstore'}),
  ),
  // Shopping
  MarketPlatform(
    id: 'amazon',
    name: 'Amazon',
    verticals: {Vertical.shopping},
    hosts: {'amazon.in', 'amzn.in', 'amzn.to'},
    brand: const Color(0xFFFF9900),
    typicalEta: 2880,
    search: (q) => _u('https://www.amazon.in/s', {'k': q}),
  ),
  MarketPlatform(
    id: 'flipkart',
    name: 'Flipkart',
    verticals: {Vertical.shopping},
    hosts: {'flipkart.com', 'dl.flipkart.com', 'fkrt.it'},
    brand: const Color(0xFF2874F0),
    typicalEta: 2880,
    search: (q) => _u('https://www.flipkart.com/search', {'q': q}),
  ),
  MarketPlatform(
    id: 'myntra',
    name: 'Myntra',
    verticals: {Vertical.shopping},
    hosts: {'myntra.com', 'myntr.it'},
    brand: const Color(0xFFFF3F6C),
    typicalEta: 4320,
    search: (q) => _u('https://www.myntra.com/${_slug(q)}', {'rawQuery': q}),
  ),
  MarketPlatform(
    id: 'meesho',
    name: 'Meesho',
    verticals: {Vertical.shopping},
    hosts: {'meesho.com'},
    brand: const Color(0xFF9F2089),
    typicalEta: 7200,
    search: (q) => _u('https://www.meesho.com/search', {'q': q}),
  ),
  MarketPlatform(
    id: 'ajio',
    name: 'AJIO',
    verticals: {Vertical.shopping},
    hosts: {'ajio.com'},
    brand: const Color(0xFF2C4152),
    typicalEta: 5760,
    search: (q) => _u('https://www.ajio.com/search/', {'text': q}),
  ),
  MarketPlatform(
    id: 'croma',
    name: 'Croma',
    verticals: {Vertical.shopping},
    hosts: {'croma.com'},
    brand: const Color(0xFF12DAA8),
    typicalEta: 2880,
    search: (q) => _u('https://www.croma.com/searchB', {'q': '$q:relevance'}),
  ),
  MarketPlatform(
    id: 'tatacliq',
    name: 'Tata CLiQ',
    verticals: {Vertical.shopping},
    hosts: {'tatacliq.com'},
    brand: const Color(0xFFDA1C5C),
    typicalEta: 4320,
    search: (q) => _u('https://www.tatacliq.com/search/', {'searchCategory': 'all', 'text': q}),
  ),
  MarketPlatform(
    id: 'nykaa',
    name: 'Nykaa',
    verticals: {Vertical.shopping},
    hosts: {'nykaa.com', 'nykaafashion.com'},
    brand: const Color(0xFFFC2779),
    typicalEta: 4320,
    search: (q) => _u('https://www.nykaa.com/search/result/', {'q': q}),
  ),
  // Food
  MarketPlatform(
    id: 'swiggy',
    name: 'Swiggy',
    verticals: {Vertical.food},
    hosts: {'swiggy.com', 'swiggy.onelink.me'},
    brand: const Color(0xFFFC8019),
    typicalEta: 32,
    search: (q) => _u('https://www.swiggy.com/search', {'query': q}),
  ),
  MarketPlatform(
    id: 'zomato',
    name: 'Zomato',
    verticals: {Vertical.food},
    hosts: {'zomato.com', 'zoma.to'},
    brand: const Color(0xFFE23744),
    typicalEta: 34,
    search: (q) => _u('https://www.zomato.com/search', {'q': q}),
  ),
  MarketPlatform(
    id: 'magicpin',
    name: 'magicpin',
    verticals: {Vertical.food},
    hosts: {'magicpin.in'},
    brand: const Color(0xFFEF4F5F),
    typicalEta: 38,
    search: (q) => _u('https://magicpin.in/search/', {'q': q}),
  ),
  MarketPlatform(
    id: 'eatsure',
    name: 'EatSure',
    verticals: {Vertical.food},
    hosts: {'eatsure.com'},
    brand: const Color(0xFFE5242B),
    typicalEta: 35,
    search: (q) => Uri.parse('https://www.eatsure.com/'),
  ),
  MarketPlatform(
    id: 'dominos',
    name: "Domino's",
    verticals: {Vertical.food},
    hosts: {'dominos.co.in'},
    brand: const Color(0xFF006491),
    typicalEta: 30,
    search: (q) => Uri.parse('https://pizzaonline.dominos.co.in/'),
  ),
  MarketPlatform(
    id: 'pizzahut',
    name: 'Pizza Hut',
    verticals: {Vertical.food},
    hosts: {'pizzahut.co.in'},
    brand: const Color(0xFFC8102E),
    typicalEta: 35,
    search: (q) => Uri.parse('https://www.pizzahut.co.in/'),
  ),
  MarketPlatform(
    id: 'kfc',
    name: 'KFC',
    verticals: {Vertical.food},
    hosts: {'kfc.co.in'},
    brand: const Color(0xFFA3080C),
    typicalEta: 35,
    search: (q) => Uri.parse('https://online.kfc.co.in/'),
  ),
  MarketPlatform(
    id: 'mcdelivery',
    name: 'McDelivery',
    verticals: {Vertical.food},
    hosts: {'mcdelivery.co.in'},
    brand: const Color(0xFFFFC72C),
    typicalEta: 35,
    search: (q) => Uri.parse('https://www.mcdelivery.co.in/'),
  ),
  // Rides — search() opens the booking page; drop location is added by the
  // ride screen through [rideDeepLink].
  MarketPlatform(
    id: 'uber',
    name: 'Uber',
    verticals: {Vertical.ride},
    hosts: {'uber.com'},
    brand: const Color(0xFF000000),
    search: (q) =>
        _u('https://m.uber.com/ul/', {'action': 'setPickup', 'pickup': 'my_location', 'dropoff[formatted_address]': q}),
  ),
  MarketPlatform(
    id: 'ola',
    name: 'Ola',
    verticals: {Vertical.ride},
    hosts: {'olacabs.com'},
    brand: const Color(0xFF1C1C1C),
    search: (q) => _u('https://book.olacabs.com/', {'drop_name': q}),
  ),
  MarketPlatform(
    id: 'rapido',
    name: 'Rapido',
    verticals: {Vertical.ride},
    hosts: {'rapido.bike'},
    brand: const Color(0xFFF9C935),
    search: (q) => Uri.parse('https://www.rapido.bike/'),
  ),
  MarketPlatform(
    id: 'nammayatri',
    name: 'Namma Yatri',
    verticals: {Vertical.ride},
    hosts: {'nammayatri.in'},
    brand: const Color(0xFFFCC32C),
    search: (q) => Uri.parse('https://nammayatri.in/'),
  ),
  MarketPlatform(
    id: 'indrive',
    name: 'inDrive',
    verticals: {Vertical.ride},
    hosts: {'indrive.com'},
    brand: const Color(0xFFC1F11D),
    search: (q) => Uri.parse('https://indrive.com/'),
  ),
  MarketPlatform(
    id: 'yatrisathi',
    name: 'Yatri Sathi',
    verticals: {Vertical.ride},
    hosts: {'yatrisathi.in'},
    brand: const Color(0xFF2F6DE1),
    search: (q) => Uri.parse('https://yatrisathi.in/'),
  ),
  MarketPlatform(
    id: 'meru',
    name: 'Meru',
    verticals: {Vertical.ride},
    hosts: {'meru.in'},
    brand: const Color(0xFF7AB800),
    search: (q) => Uri.parse('https://www.meru.in/'),
  ),
];

final Map<String, MarketPlatform> kPlatformById = {for (final p in kPlatforms) p.id: p};

List<MarketPlatform> platformsFor(Vertical v) => kPlatforms.where((p) => p.verticals.contains(v)).toList();

/// True if [url] is HTTPS and belongs to any known platform.
bool isTrustedPlatformUrl(Uri url) => url.scheme == 'https' && kPlatforms.any((p) => p.ownsHost(url.host));
