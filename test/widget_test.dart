import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:savr/core/link_parser.dart';
import 'package:savr/core/models.dart';
import 'package:savr/core/platforms.dart';
import 'package:savr/data/sample_source.dart';
import 'package:savr/security/admin_auth.dart';
import 'package:savr/state/settings.dart';
import 'package:savr/ui/widgets/common.dart';

void main() {
  group('LinkParser', () {
    test('Blinkit product link', () {
      final r = LinkParser.parse('https://blinkit.com/prn/amul-taaza-toned-milk/prid/14639')!;
      expect(r.platform.id, 'blinkit');
      expect(r.vertical, Vertical.quick);
      expect(r.name, 'amul taaza toned milk');
    });

    test('Zepto link inside share text', () {
      final r = LinkParser.parse(
        'Check out this on Zepto! https://www.zepto.com/pn/maggi-masala-noodles/pvid/0a1b2c3d-1111-2222-3333-444455556666',
      )!;
      expect(r.platform.id, 'zepto');
      expect(r.name, 'maggi masala noodles');
    });

    test('Swiggy Instamart vs Swiggy food on same host', () {
      expect(LinkParser.parse('https://www.swiggy.com/instamart/item/ABC123')!.platform.id, 'instamart');
      expect(
        LinkParser.parse('https://www.swiggy.com/restaurants/meghana-foods-koramangala-bangalore-12345')!.platform.id,
        'swiggy',
      );
    });

    test('Amazon dp link', () {
      final r = LinkParser.parse('https://www.amazon.in/Apple-iPhone-16-128-GB/dp/B0DGJH8RYG?ref=xyz')!;
      expect(r.platform.id, 'amazon');
      expect(r.name, 'Apple iPhone 16 128 GB');
    });

    test('http is upgraded, unknown and lookalike hosts rejected', () {
      expect(LinkParser.parse('http://blinkit.com/prn/x-y/prid/1')!.url.scheme, 'https');
      expect(LinkParser.parse('https://evil.example.com/prn/x/prid/1'), isNull);
      expect(LinkParser.parse('https://blinkit.com.evil.io/prn/x/prid/1'), isNull);
      expect(LinkParser.parse('https://notblinkit.com/prn/x/prid/1'), isNull);
    });

    test('non-https schemes are never trusted', () {
      expect(isTrustedPlatformUrl(Uri.parse('javascript:alert(1)')), isFalse);
      expect(isTrustedPlatformUrl(Uri.parse('intent://blinkit.com#Intent;end')), isFalse);
      expect(isTrustedPlatformUrl(Uri.parse('http://blinkit.com/')), isFalse);
    });

    test('sanitizeQuery strips markup and caps length', () {
      expect(sanitizeQuery('  <script>milk</script>\n'), 'script milk /script');
      expect(sanitizeQuery('a' * 500).length, 120);
    });
  });

  group('Quantity & unit price', () {
    test('parses common pack labels', () {
      expect(Quantity.parse('500 ml')!.amount, 500);
      expect(Quantity.parse('1.5 kg')!.amount, 1500);
      expect(Quantity.parse('4 x 70 g')!.amount, 280);
      expect(Quantity.parse('1 L')!.unit, BaseUnit.millilitre);
      expect(Quantity.parse('6 pcs')!.unit, BaseUnit.piece);
      expect(Quantity.parse('family pack'), isNull);
    });

    test('unit price per 100 ml', () {
      const o = Offer(platformId: 'zepto', title: 'Milk', price: 28, packLabel: '500 ml');
      expect(o.unitPrice!.value, closeTo(5.6, 0.001));
      expect(o.unitPrice!.per, '100 ml');
    });
  });

  group('OfferFilter', () {
    const offers = [
      Offer(platformId: 'blinkit', title: 'A', price: 30, deliveryFee: 15, etaMinutes: 9),
      Offer(platformId: 'zepto', title: 'A', price: 40, deliveryFee: 0, etaMinutes: 7, mrp: 50),
      Offer(platformId: 'instamart', title: 'A', price: 20, inStock: false, etaMinutes: 12),
    ];

    test('out of stock sinks; fees change ranking', () {
      final withFees = const OfferFilter(includeFees: true).apply(offers, SortMode.priceLow);
      expect(withFees.map((o) => o.platformId), ['zepto', 'blinkit', 'instamart']);
      final noFees = const OfferFilter(includeFees: false).apply(offers, SortMode.priceLow);
      expect(noFees.map((o) => o.platformId), ['blinkit', 'zepto', 'instamart']);
    });

    test('filters by platform, stock and ETA', () {
      expect(const OfferFilter(inStockOnly: true).apply(offers, SortMode.priceLow).length, 2);
      expect(const OfferFilter(platforms: {'zepto'}).apply(offers, SortMode.priceLow).single.platformId, 'zepto');
      expect(const OfferFilter(maxEta: 8).apply(offers, SortMode.fastest).single.platformId, 'zepto');
    });

    test('discount sort', () {
      expect(const OfferFilter().apply(offers, SortMode.discount).first.platformId, 'zepto');
    });
  });

  test('Indian rupee grouping', () {
    expect(inr(28), '₹28');
    expect(inr(1234567), '₹12,34,567');
    expect(inr(99.5), '₹99.50');
  });

  test('backend URL validation rejects insecure or credentialed URLs', () {
    expect(Settings.validateBackendUrl('https://api.example.com'), isNotNull);
    expect(Settings.validateBackendUrl('http://api.example.com'), isNull);
    expect(Settings.validateBackendUrl('https://user:pw@api.example.com'), isNull);
    expect(Settings.validateBackendUrl('https://api.example.com/?k=1'), isNull);
    expect(Settings.validateBackendUrl('javascript:alert(1)'), isNull);
  });

  test('sample source only returns enabled platforms of the vertical', () async {
    final offers = await const SamplePriceSource().search(
      const SearchQuery(text: 'amul milk', vertical: Vertical.quick),
      platformIds: {'blinkit', 'zepto', 'amazon'},
    );
    expect(offers, isNotEmpty);
    expect(offers.map((o) => o.platformId).toSet(), {'blinkit', 'zepto'});
  });

  group('AdminAuth', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    test('rejects weak passcodes', () {
      expect(AdminAuth.validateNew('12345'), isNotNull);
      expect(AdminAuth.validateNew('123456'), isNotNull);
      expect(AdminAuth.validateNew('999999'), isNotNull);
      expect(AdminAuth.validateNew('tulip-42'), isNull);
    });

    test('set, verify, lock-out', () async {
      final a = AdminAuth(iterations: 1000);
      expect(await a.isConfigured, isFalse);
      await a.setPasscode('tulip-42');
      expect(a.isUnlocked, isTrue);
      a.lock();
      expect(a.isUnlocked, isFalse);

      expect(await a.verify('tulip-42'), isNull);
      expect(a.isUnlocked, isTrue);
      a.lock();

      for (var i = 0; i < AdminAuth.freeAttempts; i++) {
        expect(await a.verify('wrong-pass'), isNotNull);
      }
      expect(await a.lockRemaining(), isNotNull);
      // Even the right passcode is refused during lock-out.
      expect(await a.verify('tulip-42'), contains('Too many attempts'));
      expect(a.isUnlocked, isFalse);
    });
  });
}
