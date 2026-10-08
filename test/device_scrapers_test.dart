import 'package:flutter_test/flutter_test.dart';
import 'package:savr/core/matcher.dart';
import 'package:savr/core/models.dart';
import 'package:savr/data/device/scrapers.dart';

// Fixtures mirror the response shapes captured from each site's own search
// page (Oct 2026), trimmed to the fields Savr reads.

final _blinkitSearch = {
  'response': {
    'snippets': [
      {
        'data': {
          'name': {'text': 'Amul Taaza Toned Milk'},
          'atc_action': {
            'add_to_cart': {
              'cart_item': {
                'product_id': 19512,
                'product_name': 'Amul Taaza Toned Milk',
                'price': 29,
                'mrp': 30,
                'unit': '500 ml',
                'inventory': 12,
              },
            },
          },
          // Same item repeated under a different action — must dedupe.
          'rfc_action': {
            'remove_from_cart': {
              'cart_item': {'product_id': 19512, 'product_name': 'Amul Taaza Toned Milk', 'price': 29, 'unit': '500 ml'},
            },
          },
        },
      },
      {
        'data': {
          'atc_action': {
            'add_to_cart': {
              'cart_item': {
                'product_id': 560899,
                'product_name': 'Mother Dairy Full Cream Milk',
                'price': 72,
                'mrp': 72,
                'unit': '1 ltr',
                'inventory': 0,
              },
            },
          },
        },
      },
    ],
  },
};

final _zeptoSearch = {
  'layout': [
    {
      'data': {
        'resolver': {
          'data': {
            'items': [
              {
                'productResponse': {
                  'storeId': 'b4dc8d65-ed2e-4142-81b6-373982b13500',
                  'discountedSellingPrice': 2800,
                  'sellingPrice': 2800,
                  'mrp': 2900,
                  'outOfStock': false,
                  'product': {'name': 'Amul Taaza Homogenised Toned Milk (Tetra Pack)', 'brand': 'Amul'},
                  'productVariant': {
                    'id': '2a231315-2b07-4de0-af4a-3a4f9c48ad0c',
                    'formattedPacksize': '1 pack (500 ml)',
                    'mrp': 2900,
                  },
                },
              },
            ],
          },
        },
      },
    },
  ],
};

final _instamartSearch = {
  'data': {
    'cards': [
      {
        'card': {
          'card': {
            'gridElements': {
              'infoWithStyle': {
                'items': [
                  {
                    'productId': 'BQ5YQH8TEN',
                    'displayName': 'Amul Taaza Toned Milk',
                    'variations': [
                      {
                        'skuId': 'RZISMDH80O',
                        'displayName': 'Amul Taaza Toned Milk',
                        'quantityDescription': '500 ml',
                        'price': {
                          'mrp': {'currencyCode': 'INR', 'units': '30', 'nanos': 0},
                          'offerPrice': {'currencyCode': 'INR', 'units': '27', 'nanos': 0},
                        },
                        'inventory': {'inStock': true},
                      },
                    ],
                  },
                ],
              },
            },
          },
        },
      },
    ],
  },
};

void main() {
  group('BlinkitScraper', () {
    test('parses cart items, dedupes, maps stock and builds product URL', () {
      final st = ScrapeState();
      const BlinkitScraper().ingest(
        Uri.parse('https://blinkit.com/v1/layout/search?q=milk'),
        _blinkitSearch,
        st,
      );
      const BlinkitScraper().ingest(
        Uri.parse('https://blinkit.com/v1/consumerweb/eta'),
        {'eta_in_minutes': 11},
        st,
      );
      final offers = st.build();
      expect(offers, hasLength(2));
      final taaza = offers.first;
      expect(taaza.price, 29);
      expect(taaza.mrp, 30);
      expect(taaza.packLabel, '500 ml');
      expect(taaza.etaMinutes, 11);
      expect(taaza.url.toString(), 'https://blinkit.com/prn/amul-taaza-toned-milk/prid/19512');
      expect(offers.last.inStock, isFalse);
    });
  });

  group('ZeptoScraper', () {
    test('converts paise to rupees and builds pvid URL', () {
      final st = ScrapeState();
      const ZeptoScraper().ingest(
        Uri.parse('https://bff-gateway.zepto.com/user-search-service/api/v3/search'),
        _zeptoSearch,
        st,
      );
      final o = st.build().single;
      expect(o.price, 28);
      expect(o.mrp, 29);
      expect(o.quantity, const Quantity(500, BaseUnit.millilitre));
      expect(o.url!.path, '/pn/amul-taaza-homogenised-toned-milk-tetra-pack/pvid/2a231315-2b07-4de0-af4a-3a4f9c48ad0c');
    });

    test('rejects non-uuid variant ids (no path injection into URLs)', () {
      final st = ScrapeState();
      final evil = {
        'productResponse': {
          'discountedSellingPrice': 100,
          'product': {'name': 'X'},
          'productVariant': {'id': '../../evil?x=1'},
        },
      };
      const ZeptoScraper().ingest(Uri.parse('https://bff-gateway.zepto.com/user-search-service/api/v3/search'), evil, st);
      expect(st.build(), isEmpty);
    });
  });

  group('InstamartScraper', () {
    test('parses variations and ignores placeholder responses', () {
      final st = ScrapeState();
      const InstamartScraper().ingest(Uri.parse('https://www.swiggy.com/api/instamart/search/v2'), {'statusCode': 1}, st);
      expect(st.gotSearch, isFalse);
      const InstamartScraper().ingest(Uri.parse('https://www.swiggy.com/api/instamart/search/v2'), _instamartSearch, st);
      final o = st.build().single;
      expect(o.price, 27);
      expect(o.mrp, 30);
      expect(o.url!.host, 'www.swiggy.com');
    });
  });

  test('untrusted numbers are range-checked', () {
    final st = ScrapeState();
    const BlinkitScraper().ingest(Uri.parse('https://blinkit.com/v1/layout/search'), {
      'a': {'product_id': 1, 'product_name': 'Free', 'price': -5},
      'b': {'product_id': 2, 'product_name': 'Huge', 'price': 1e12},
      'c': {'product_id': 3, 'product_name': 'NaN', 'price': double.nan},
    }, st);
    expect(st.build(), isEmpty);
  });

  test('walkMaps is bounded on deeply nested input', () {
    Object deep = {'product_id': 1, 'product_name': 'Deep', 'price': 10};
    for (var i = 0; i < 500; i++) {
      deep = {'n': deep};
    }
    final st = ScrapeState();
    const BlinkitScraper().ingest(Uri.parse('https://blinkit.com/v1/layout/search'), deep, st);
    expect(st.build(), isEmpty); // beyond maxDepth, never reached
  });

  group('ProductMatcher', () {
    test('groups the same SKU across platforms despite different titles', () {
      const offers = [
        Offer(platformId: 'blinkit', title: 'Amul Taaza Toned Milk', packLabel: '500 ml', price: 29),
        Offer(platformId: 'zepto', title: 'Amul Taaza Homogenised Toned Milk (Tetra Pack)', packLabel: '1 pack (500 ml)', price: 28),
        Offer(platformId: 'instamart', title: 'Amul Taaza Toned Milk', packLabel: '500 ml', price: 27),
        Offer(platformId: 'blinkit', title: 'Amul Taaza Toned Milk', packLabel: '1 ltr', price: 59),
        Offer(platformId: 'blinkit', title: 'Amul Gold Full Cream Milk', packLabel: '500 ml', price: 34),
      ];
      final groups = ProductMatcher.group(offers);
      expect(groups.first.map((o) => o.platformId).toSet(), {'blinkit', 'zepto', 'instamart'});
      expect(groups, hasLength(3)); // 500 ml Taaza, 1 L Taaza, Gold
    });

    test('relevance filters loosely related items', () {
      expect(ProductMatcher.relevance('amul milk', 'Amul Taaza Toned Milk'), 1);
      expect(ProductMatcher.relevance('amul milk', "Let's Try Jowar Millet Cookies"), lessThan(0.5));
    });
  });

  group('Quantity formats from live sites', () {
    test('parses platform-specific pack labels', () {
      expect(Quantity.parse('1 pack (200 ml)'), const Quantity(200, BaseUnit.millilitre));
      expect(Quantity.parse('1 ltr x 12'), const Quantity(12000, BaseUnit.millilitre));
      expect(Quantity.parse('2 x 200 ml'), const Quantity(400, BaseUnit.millilitre));
      expect(Quantity.parse('500 g x 2'), const Quantity(1000, BaseUnit.gram));
      expect(Quantity.parse('6 pcs'), const Quantity(6, BaseUnit.piece));
    });
  });
}
