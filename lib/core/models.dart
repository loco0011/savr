enum Vertical {
  quick('Q-Com', 'Delivered in minutes'),
  grocery('Grocery', 'Scheduled grocery delivery'),
  shopping('Shopping', 'Online marketplaces'),
  food('Food', 'Restaurant delivery'),
  ride('Rides', 'Cabs, autos and bikes');

  const Vertical(this.label, this.blurb);
  final String label;
  final String blurb;

  /// Verticals that use the product search screen.
  static const searchable = [quick, grocery, shopping, food];
}

/// Base unit a pack size is normalised to for per-unit comparison.
enum BaseUnit { gram, millilitre, piece }

class Quantity {
  const Quantity(this.amount, this.unit);
  final double amount;
  final BaseUnit unit;

  /// Parses labels such as "500 g", "1.5 kg", "2 x 200 ml", "1 ltr x 12",
  /// "1 pack (200 ml)", "6 pcs". Weight/volume wins over piece counts.
  static Quantity? parse(String? label) {
    if (label == null) return null;
    final s = label.toLowerCase().replaceAll(',', '').trim();
    const num = r'(\d+(?:\.\d+)?)';
    const unit = r'(kg|kgs|gms|gm|g|grams?|ml|ltr|litres?|liters?|l|pcs|pc|pieces?|units?|n)\b';

    // "2 x 200 ml"
    final countFirst = RegExp(r'(\d+)\s*[x×]\s*' + num + r'\s*' + unit).firstMatch(s);
    if (countFirst != null) {
      return _make(double.parse(countFirst.group(2)!) * double.parse(countFirst.group(1)!), countFirst.group(3)!);
    }
    // "1 ltr x 12"
    final countLast = RegExp(num + r'\s*' + unit + r'\s*[x×]\s*(\d+)').firstMatch(s);
    if (countLast != null) {
      return _make(double.parse(countLast.group(1)!) * double.parse(countLast.group(3)!), countLast.group(2)!);
    }
    Quantity? piece;
    for (final m in RegExp(num + r'\s*' + unit).allMatches(s)) {
      final q = _make(double.parse(m.group(1)!), m.group(2)!);
      if (q == null) continue;
      if (q.unit != BaseUnit.piece) return q;
      piece ??= q;
    }
    return piece;
  }

  static Quantity? _make(double v, String unit) => switch (unit) {
    'g' || 'gm' || 'gms' || 'gram' || 'grams' => Quantity(v, BaseUnit.gram),
    'kg' || 'kgs' => Quantity(v * 1000, BaseUnit.gram),
    'ml' => Quantity(v, BaseUnit.millilitre),
    'l' || 'ltr' || 'litre' || 'liter' || 'litres' || 'liters' => Quantity(v * 1000, BaseUnit.millilitre),
    'pc' || 'pcs' || 'piece' || 'pieces' || 'unit' || 'units' || 'n' => Quantity(v, BaseUnit.piece),
    _ => null,
  };

  @override
  bool operator ==(Object other) => other is Quantity && other.unit == unit && (other.amount - amount).abs() < 0.5;

  @override
  int get hashCode => Object.hash(unit, amount.round());

  /// Normalised pack label used by the pack-size filter: "500 ml", "1 L",
  /// "1.5 kg", "6 pc".
  String get label {
    String n(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
    return switch (unit) {
      BaseUnit.gram => amount >= 1000 ? '${n(amount / 1000)} kg' : '${n(amount)} g',
      BaseUnit.millilitre => amount >= 1000 ? '${n(amount / 1000)} L' : '${n(amount)} ml',
      BaseUnit.piece => '${n(amount)} pc',
    };
  }
}

/// Multi-word brands that the first word alone would split.
const _multiWordBrands = [
  'mother dairy',
  'country delight',
  'tata sampann',
  'tata salt',
  'tata tea',
  'red bull',
  'coca cola',
  'paper boat',
  'fortune foods',
  'b natural',
  'id fresh',
  'sleepy owl',
  'blue tokai',
];

/// Best-effort brand from a product title ("Amul Taaza Toned Milk" → "Amul").
String? brandOf(String title) {
  final t = title.trim();
  if (t.isEmpty) return null;
  final lower = t.toLowerCase();
  for (final b in _multiWordBrands) {
    if (lower.startsWith('$b ') || lower == b) {
      return b.split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
    }
  }
  final first = t.split(RegExp(r'\s+')).first.replaceAll(RegExp(r"[^A-Za-z0-9&'-]"), '');
  if (first.length < 2 || RegExp(r'^\d').hasMatch(first)) return null;
  return '${first[0].toUpperCase()}${first.substring(1).toLowerCase()}';
}

class Offer {
  const Offer({
    required this.platformId,
    required this.title,
    required this.price,
    this.packLabel,
    this.mrp,
    this.deliveryFee,
    this.etaMinutes,
    this.inStock = true,
    this.url,
    this.seller,
    this.group,
    this.feeIsEstimate = false,
  });

  final String platformId;
  final String title;
  final String? packLabel;
  final double price;
  final double? mrp;

  /// Delivery + handling for a single-item order. Null when unknown.
  final double? deliveryFee;

  /// True when [deliveryFee] comes from typical fee rules (see fees.dart),
  /// not from the app itself.
  final bool feeIsEstimate;

  Offer copyWith({double? deliveryFee, bool? feeIsEstimate}) => Offer(
    platformId: platformId,
    title: title,
    price: price,
    packLabel: packLabel,
    mrp: mrp,
    deliveryFee: deliveryFee ?? this.deliveryFee,
    etaMinutes: etaMinutes,
    inStock: inStock,
    url: url,
    seller: seller,
    group: group,
    feeIsEstimate: feeIsEstimate ?? this.feeIsEstimate,
  );
  final int? etaMinutes;
  final bool inStock;
  final Uri? url;

  /// Restaurant name for food, seller for marketplaces.
  final String? seller;

  /// Identifies the same product across platforms (supplied by the backend,
  /// since titles differ per store). Falls back to the normalised title.
  final String? group;

  String get groupKey => group ?? title.toLowerCase().replaceAll(RegExp(r"[^a-z0-9]+"), " ").trim();

  double effectivePrice({required bool includeFees}) => includeFees ? price + (deliveryFee ?? 0) : price;

  int? get discountPercent {
    final m = mrp;
    if (m == null || m <= price || m <= 0) return null;
    return ((m - price) / m * 100).round();
  }

  Quantity? get quantity => Quantity.parse(packLabel);

  /// Price per 100 g / 100 ml / 1 piece.
  ({double value, String per})? get unitPrice {
    final q = quantity;
    if (q == null || q.amount <= 0) return null;
    return switch (q.unit) {
      BaseUnit.gram => (value: price / q.amount * 100, per: '100 g'),
      BaseUnit.millilitre => (value: price / q.amount * 100, per: '100 ml'),
      BaseUnit.piece => (value: price / q.amount, per: 'pc'),
    };
  }
}

enum SortMode {
  priceLow('Lowest price'),
  unitPrice('Lowest per unit'),
  fastest('Fastest delivery'),
  discount('Biggest discount'),
  priceHigh('Highest price');

  const SortMode(this.label);
  final String label;
}

class OfferFilter {
  const OfferFilter({
    this.platforms = const {},
    this.inStockOnly = false,
    this.maxEta,
    this.maxPrice,
    this.includeFees = true,
    this.brands = const {},
    this.packs = const {},
    this.minDiscount = 0,
  });

  /// Empty means "all".
  final Set<String> platforms;
  final bool inStockOnly;

  /// Offers whose app doesn't report an ETA are kept (unknown ≠ slow).
  final int? maxEta;
  final double? maxPrice;
  final bool includeFees;

  /// Brand names from [brandOf]; empty means all.
  final Set<String> brands;

  /// Normalised pack labels from [Quantity.label]; empty means all.
  final Set<String> packs;

  /// Minimum discount off MRP, in percent.
  final int minDiscount;

  /// Number of narrowing filters set (in-stock is a separate toggle).
  int get activeCount =>
      (platforms.isNotEmpty ? 1 : 0) +
      (maxEta != null ? 1 : 0) +
      (maxPrice != null ? 1 : 0) +
      (brands.isNotEmpty ? 1 : 0) +
      (packs.isNotEmpty ? 1 : 0) +
      (minDiscount > 0 ? 1 : 0);

  bool get isActive => activeCount > 0 || inStockOnly;

  /// Clears every narrowing filter but keeps the fee and stock toggles.
  OfferFilter cleared() => OfferFilter(includeFees: includeFees, inStockOnly: inStockOnly);

  OfferFilter copyWith({
    Set<String>? platforms,
    bool? inStockOnly,
    int? Function()? maxEta,
    double? Function()? maxPrice,
    bool? includeFees,
    Set<String>? brands,
    Set<String>? packs,
    int? minDiscount,
  }) => OfferFilter(
    platforms: platforms ?? this.platforms,
    inStockOnly: inStockOnly ?? this.inStockOnly,
    maxEta: maxEta != null ? maxEta() : this.maxEta,
    maxPrice: maxPrice != null ? maxPrice() : this.maxPrice,
    includeFees: includeFees ?? this.includeFees,
    brands: brands ?? this.brands,
    packs: packs ?? this.packs,
    minDiscount: minDiscount ?? this.minDiscount,
  );

  List<Offer> apply(List<Offer> offers, SortMode sort) {
    final out = offers.where((o) {
      if (platforms.isNotEmpty && !platforms.contains(o.platformId)) return false;
      if (inStockOnly && !o.inStock) return false;
      final eta = o.etaMinutes;
      if (maxEta != null && eta != null && eta > maxEta!) return false;
      if (maxPrice != null && o.effectivePrice(includeFees: includeFees) > maxPrice!) return false;
      if (brands.isNotEmpty && !brands.contains(brandOf(o.title))) return false;
      if (packs.isNotEmpty && !packs.contains(o.quantity?.label)) return false;
      if (minDiscount > 0 && (o.discountPercent ?? 0) < minDiscount) return false;
      return true;
    }).toList();

    int byPrice(Offer a, Offer b) =>
        a.effectivePrice(includeFees: includeFees).compareTo(b.effectivePrice(includeFees: includeFees));

    // Out-of-stock always sinks to the bottom regardless of sort.
    int stock(Offer a, Offer b) => (a.inStock ? 0 : 1) - (b.inStock ? 0 : 1);

    int cmp(Offer a, Offer b) {
      switch (sort) {
        case SortMode.priceLow:
          return byPrice(a, b);
        case SortMode.priceHigh:
          return byPrice(b, a);
        case SortMode.unitPrice:
          final ua = a.unitPrice?.value ?? double.infinity;
          final ub = b.unitPrice?.value ?? double.infinity;
          final r = ua.compareTo(ub);
          return r != 0 ? r : byPrice(a, b);
        case SortMode.fastest:
          final r = (a.etaMinutes ?? 1 << 20).compareTo(b.etaMinutes ?? 1 << 20);
          return r != 0 ? r : byPrice(a, b);
        case SortMode.discount:
          final r = (b.discountPercent ?? 0).compareTo(a.discountPercent ?? 0);
          return r != 0 ? r : byPrice(a, b);
      }
    }

    out.sort((a, b) {
      final s = stock(a, b);
      return s != 0 ? s : cmp(a, b);
    });
    return out;
  }
}

/// What the user asked for, after URL parsing.
class SearchQuery {
  const SearchQuery({required this.text, required this.vertical, this.sourcePlatformId});
  final String text;
  final Vertical vertical;

  /// Set when the query came from a pasted product link.
  final String? sourcePlatformId;
}

enum DataMode {
  device('On this phone', 'Live prices fetched by the app from each platform'),
  server('Price server', 'Live prices from your own backend'),
  sample('Sample data', 'Offline illustrative prices');

  const DataMode(this.label, this.blurb);
  final String label;
  final String blurb;
}

class SearchResult {
  const SearchResult({
    required this.query,
    required this.offers,
    required this.isSample,
    this.notice,
    this.live = const [],
    this.failed = const [],
    this.needsSetup = const [],
    this.pending = const [],
  });
  final SearchQuery query;
  final List<Offer> offers;
  final bool isSample;
  final String? notice;

  /// Platform ids that returned live data.
  final List<String> live;

  /// Platform ids that timed out or were blocked.
  final List<String> failed;

  /// Platform ids that need the one-time location step before they can be searched.
  final List<String> needsSetup;

  /// Platform ids still loading while results stream in.
  final List<String> pending;

  bool get isComplete => pending.isEmpty;
}
