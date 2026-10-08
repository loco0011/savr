import 'models.dart';

/// Matches the same product across platforms whose titles differ, e.g.
/// "Amul Taaza Toned Milk" (Blinkit) vs "Amul Taaza Homogenised Toned Milk
/// (Tetra Pack)" (Zepto). Offers match when their pack sizes are equal and
/// their name tokens overlap enough.
abstract final class ProductMatcher {
  static const threshold = 0.6;

  static const _noise = {
    'pack',
    'of',
    'the',
    'and',
    'with',
    'fresh',
    'homogenised',
    'homogenized',
    'tetra',
    'pouch',
    'bottle',
    'jar',
    'box',
    'combo',
    'new',
    'combi',
    'tub',
    'can',
    'carton',
    'pet',
    'refill',
    'variant',
    'flavour',
    'flavor',
    'x',
    'pc',
    'pcs',
    'g',
    'gm',
    'kg',
    'ml',
    'l',
    'ltr',
    'litre',
    'liter',
  };

  static Set<String> tokens(String title) => title
      .toLowerCase()
      .replaceAll(RegExp(r'\([^)]*\)'), ' ') // drop "(Tetra Pack)", "(90 Days Shelf Life)"
      .split(RegExp(r'[^a-z0-9]+'))
      .where((t) => t.length > 1 && !_noise.contains(t) && !RegExp(r'^\d+([.]\d+)?$').hasMatch(t))
      .toSet();

  static double similarity(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final inter = a.intersection(b).length;
    // Overlap coefficient: forgiving when one title is a longer variant of the other.
    final overlap = inter / (a.length < b.length ? a.length : b.length);
    final jaccard = inter / a.union(b).length;
    return (overlap + jaccard) / 2;
  }

  /// Fraction of query words found at the start of title words.
  static double relevance(String query, String title) {
    final q = query.toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((t) => t.length > 1).toList();
    if (q.isEmpty) return 0;
    final t = title.toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((t) => t.isNotEmpty).toList();
    return q.where((w) => t.any((x) => x.startsWith(w))).length / q.length;
  }

  /// Groups offers. Explicit `group` keys (from a backend) win; the rest are
  /// clustered greedily in input order, which preserves source relevance.
  /// Groups found on more platforms come first.
  static List<List<Offer>> group(List<Offer> offers) {
    final explicit = <String, List<Offer>>{};
    final clusters = <({Set<String> tokens, Quantity? qty, List<Offer> items})>[];

    for (final o in offers) {
      if (o.group != null) {
        explicit.putIfAbsent(o.group!, () => []).add(o);
        continue;
      }
      final tk = tokens(o.title);
      final qty = o.quantity;
      ({Set<String> tokens, Quantity? qty, List<Offer> items})? best;
      var bestScore = threshold;
      for (final c in clusters) {
        if (c.qty != qty) continue;
        final s = similarity(tk, c.tokens);
        if (s >= bestScore) {
          best = c;
          bestScore = s;
        }
      }
      if (best != null) {
        best.items.add(o);
      } else {
        clusters.add((tokens: tk, qty: qty, items: [o]));
      }
    }

    final all = [...explicit.values, ...clusters.map((c) => c.items)];
    final order = {for (var i = 0; i < all.length; i++) all[i]: i};
    int platforms(List<Offer> g) => g.map((o) => o.platformId).toSet().length;
    all.sort((a, b) {
      final p = platforms(b).compareTo(platforms(a));
      return p != 0 ? p : order[a]!.compareTo(order[b]!);
    });
    return all;
  }
}
