import '../core/models.dart';
import '../core/platforms.dart';
import 'price_source.dart';

/// Offline, deterministic sample prices so the app is usable without a live
/// backend. Every result produced here is flagged `isSample` and the UI says
/// so — these numbers are illustrative, not real quotes.
class SamplePriceSource implements PriceSource {
  const SamplePriceSource();

  @override
  Future<List<Offer>> search(SearchQuery query, {required Set<String> platformIds, String? pincode}) async {
    final terms = _tokens(query.text);
    if (terms.isEmpty) return const [];

    final items =
        _catalog
            .where((i) => i.vertical == query.vertical)
            .map((i) {
              final hay = _tokens('${i.title} ${i.tags}');
              final hits = terms.where((t) => hay.any((h) => h.startsWith(t))).length;
              return (item: i, score: hits / terms.length);
            })
            .where((r) => r.score >= 0.5)
            .toList()
          ..sort((a, b) => b.score.compareTo(a.score));

    final offers = <Offer>[];
    for (final r in items.take(4)) {
      final item = r.item;
      for (final pid in platformIds) {
        final p = kPlatformById[pid];
        if (p == null || !p.verticals.contains(query.vertical)) continue;
        final h = _hash('${item.title}|$pid|${pincode ?? ''}');
        // Spread prices +-12% around the reference and round like real shelves.
        final factor = 0.88 + (h % 2400) / 10000;
        final price = (item.ref * factor).roundToDouble();
        final mrp = item.mrp ?? (item.ref * 1.08).roundToDouble();
        final eta = p.typicalEta == null ? null : (p.typicalEta! * (0.8 + (h % 50) / 100)).round();
        final fee = switch (query.vertical) {
          Vertical.quick => (h % 3 == 0) ? 0.0 : [15.0, 25.0, 30.0][h % 3],
          Vertical.food => [29.0, 35.0, 42.0, 0.0][h % 4],
          Vertical.grocery => (h % 2 == 0) ? 0.0 : 40.0,
          _ => (h % 4 == 0) ? 40.0 : 0.0,
        };
        offers.add(
          Offer(
            platformId: pid,
            title: item.title,
            packLabel: item.pack,
            price: price,
            mrp: mrp > price ? mrp : null,
            deliveryFee: fee,
            etaMinutes: eta,
            inStock: h % 9 != 0,
            seller: item.seller,
            url: p.searchUrl(item.title),
          ),
        );
      }
    }
    return offers;
  }

  static List<String> _tokens(String s) =>
      s.toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((t) => t.length >= 2).toList();

  /// FNV-1a — stable across runs, unlike String.hashCode.
  static int _hash(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }
}

class _Item {
  const _Item(this.vertical, this.title, this.pack, this.ref, {this.mrp, this.tags = '', this.seller});
  final Vertical vertical;
  final String title;
  final String? pack;
  final double ref;
  final double? mrp;
  final String tags;
  final String? seller;
}

const _catalog = <_Item>[
  // Quick commerce
  _Item(Vertical.quick, 'Amul Taaza Toned Milk', '500 ml', 28, mrp: 28, tags: 'dairy doodh'),
  _Item(Vertical.quick, 'Amul Gold Full Cream Milk', '1 L', 70, mrp: 70, tags: 'dairy doodh'),
  _Item(Vertical.quick, 'Mother Dairy Toned Milk', '500 ml', 29, tags: 'dairy doodh'),
  _Item(Vertical.quick, 'Amul Butter Pasteurised', '100 g', 58, mrp: 60, tags: 'dairy makhan'),
  _Item(Vertical.quick, 'Britannia Brown Bread', '400 g', 55, tags: 'bakery'),
  _Item(Vertical.quick, 'Farm Fresh Eggs', '6 pcs', 54, tags: 'anda'),
  _Item(Vertical.quick, 'Aashirvaad Shudh Chakki Atta', '5 kg', 265, mrp: 310, tags: 'flour wheat'),
  _Item(Vertical.quick, 'Tata Salt Iodised', '1 kg', 28, mrp: 28),
  _Item(Vertical.quick, 'Fortune Sunlite Refined Sunflower Oil', '1 L', 155, mrp: 190, tags: 'cooking'),
  _Item(Vertical.quick, 'Maggi 2-Minute Masala Noodles', '4 x 70 g', 56, mrp: 60, tags: 'instant'),
  _Item(Vertical.quick, 'Lay\'s India\'s Magic Masala Chips', '52 g', 20, mrp: 20, tags: 'snacks lays'),
  _Item(Vertical.quick, 'Coca-Cola Soft Drink', '750 ml', 40, mrp: 40, tags: 'coke cold drink'),
  _Item(Vertical.quick, 'Onion', '1 kg', 38, tags: 'pyaz vegetables'),
  _Item(Vertical.quick, 'Tomato Hybrid', '500 g', 22, tags: 'tamatar vegetables'),
  _Item(Vertical.quick, 'Banana Robusta', '6 pcs', 48, tags: 'kela fruit'),
  _Item(Vertical.quick, 'Surf Excel Easy Wash Detergent Powder', '1 kg', 135, mrp: 150, tags: 'laundry'),
  _Item(Vertical.quick, 'Colgate Strong Teeth Toothpaste', '200 g', 110, mrp: 128, tags: 'oral'),
  _Item(Vertical.quick, 'Red Bull Energy Drink', '250 ml', 125, mrp: 125, tags: 'redbull'),
  // Grocery
  _Item(Vertical.grocery, 'Aashirvaad Shudh Chakki Atta', '10 kg', 495, mrp: 590, tags: 'flour wheat'),
  _Item(Vertical.grocery, 'India Gate Basmati Rice Classic', '5 kg', 899, mrp: 1150, tags: 'chawal'),
  _Item(Vertical.grocery, 'Tata Sampann Toor Dal', '1 kg', 185, mrp: 220, tags: 'arhar pulses'),
  _Item(Vertical.grocery, 'Fortune Sunlite Refined Sunflower Oil', '5 L', 720, mrp: 925, tags: 'cooking'),
  _Item(Vertical.grocery, 'Amul Pure Ghee', '1 L', 610, mrp: 650, tags: 'dairy'),
  _Item(Vertical.grocery, 'Tata Tea Gold', '1 kg', 560, mrp: 650, tags: 'chai'),
  _Item(Vertical.grocery, 'Surf Excel Matic Liquid Front Load', '2 L', 420, mrp: 540, tags: 'detergent laundry'),
  // Shopping
  _Item(Vertical.shopping, 'Apple iPhone 16 (128 GB) Black', '1 pc', 69900, mrp: 79900, tags: 'mobile phone'),
  _Item(Vertical.shopping, 'Samsung Galaxy S25 (256 GB)', '1 pc', 74999, mrp: 80999, tags: 'mobile phone'),
  _Item(Vertical.shopping, 'OnePlus Nord CE4 (128 GB)', '1 pc', 22999, mrp: 24999, tags: 'mobile phone'),
  _Item(Vertical.shopping, 'boAt Airdopes 141 TWS Earbuds', '1 pc', 1099, mrp: 4490, tags: 'earphones audio'),
  _Item(Vertical.shopping, 'Sony WH-1000XM5 Headphones', '1 pc', 26990, mrp: 34990, tags: 'audio'),
  _Item(Vertical.shopping, 'Nike Revolution 7 Running Shoes', '1 pc', 3295, mrp: 3695, tags: 'footwear sneakers'),
  _Item(Vertical.shopping, 'Levi\'s Men 511 Slim Fit Jeans', '1 pc', 2199, mrp: 3599, tags: 'denim clothing'),
  _Item(Vertical.shopping, 'Philips HL7756 Mixer Grinder 750 W', '1 pc', 3999, mrp: 6295, tags: 'kitchen appliance'),
  // Food
  _Item(Vertical.food, 'Chicken Dum Biryani', '1 plate', 349, tags: 'biryani', seller: 'Behrouz Biryani'),
  _Item(Vertical.food, 'Hyderabadi Chicken Biryani', '1 plate', 289, tags: 'biryani', seller: 'Paradise'),
  _Item(Vertical.food, 'Paneer Butter Masala', '1 portion', 259, tags: 'curry veg', seller: 'Punjabi Rasoi'),
  _Item(Vertical.food, 'Margherita Pizza (Medium)', '1 pc', 299, tags: 'pizza', seller: 'Domino\'s Pizza'),
  _Item(Vertical.food, 'McAloo Tikki Burger', '1 pc', 64, tags: 'burger', seller: 'McDonald\'s'),
  _Item(Vertical.food, 'Masala Dosa', '1 plate', 129, tags: 'south indian dosa', seller: 'A2B'),
  _Item(Vertical.food, 'Veg Momos (8 pcs)', '8 pcs', 129, tags: 'momo', seller: 'Wow! Momo'),
];
