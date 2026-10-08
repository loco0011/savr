import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:savr/core/address.dart';
import 'package:savr/core/models.dart';
import 'package:savr/core/place.dart';
import 'package:savr/state/settings.dart';

const _offers = [
  Offer(platformId: 'blinkit', title: 'Amul Taaza Toned Milk', packLabel: '500 ml', price: 29, mrp: 30, etaMinutes: 8),
  Offer(platformId: 'zepto', title: 'Amul Taaza Toned Milk', packLabel: '1 ltr', price: 56, mrp: 70, etaMinutes: 20),
  Offer(platformId: 'instamart', title: 'Mother Dairy Toned Milk', packLabel: '500 ml', price: 28, inStock: false),
  Offer(platformId: 'instamart', title: 'Country Delight Cow Milk', packLabel: '450 ml', price: 47),
];

const _home = Place(name: 'Baguiati', lat: 22.6133, lng: 88.4304, city: 'Kolkata', pincode: '700059');

void main() {
  group('Filters', () {
    List<String> titles(OfferFilter f) => f.apply(_offers, SortMode.priceLow).map((o) => '${o.platformId}:${o.price}').toList();

    test('in stock only removes sold-out offers everywhere', () {
      expect(titles(const OfferFilter(inStockOnly: true)), isNot(contains('instamart:28.0')));
      expect(titles(const OfferFilter()), contains('instamart:28.0'));
    });

    test('brand, pack size and discount', () {
      expect(brandOf('Mother Dairy Toned Milk'), 'Mother Dairy');
      expect(brandOf('Amul Taaza Toned Milk'), 'Amul');
      expect(brandOf('500 ml milk'), isNull);
      expect(titles(const OfferFilter(brands: {'Amul'})), ['blinkit:29.0', 'zepto:56.0']);
      expect(Quantity.parse('1 ltr')!.label, '1 L');
      expect(titles(const OfferFilter(packs: {'500 ml'})).length, 2);
      expect(titles(const OfferFilter(minDiscount: 10)), ['zepto:56.0']);
    });

    test('unknown ETA is kept when filtering by delivery time', () {
      final r = titles(const OfferFilter(maxEta: 15));
      expect(r, contains('blinkit:29.0'));
      expect(r, isNot(contains('zepto:56.0')));
      expect(r, contains('instamart:47.0'));
    });

    test('active count and clearing keep the stock toggle', () {
      const f = OfferFilter(inStockOnly: true, brands: {'Amul'}, minDiscount: 10, maxEta: 15);
      expect(f.activeCount, 3);
      final c = f.cleared();
      expect(c.activeCount, 0);
      expect(c.inStockOnly, isTrue);
    });
  });

  group('Profile data', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('address round-trips and becomes the live location', () async {
      final s = await Settings.load();
      const a = SavedAddress(id: 'a1', label: AddressLabel.home, place: _home, flat: 'Flat 4B', landmark: 'Near the park');
      expect(SavedAddress.decode(a.encode())!.line, 'Flat 4B, Baguiati, Kolkata 700059');
      expect(s.saveAddress(a), isTrue);
      expect(s.activeAddress!.id, 'a1');
      expect(s.place, _home);
      s.deleteAddress('a1');
      expect(s.addresses, isEmpty);
      expect(s.activeAddress, isNull);
    });

    test('demo login never stores a password; saved searches and savings', () async {
      final s = await Settings.load();
      s.logIn('sambit@example.com', name: 'Sambit');
      expect(s.isLoggedIn, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where((k) => k.contains('pass')), isEmpty);

      s.toggleSaved(SavedSearch(query: 'Amul milk', vertical: 'quick', bestPrice: 29, at: DateTime(2026)));
      expect(s.isSaved('amul MILK'), isTrue);
      s.toggleSaved(SavedSearch(query: 'amul milk', vertical: 'quick', at: DateTime(2026)));
      expect(s.savedSearches, isEmpty);

      s.recordDeal(18);
      s.recordDeal(-5); // ignored
      expect(s.totalSaved, 18);
      expect(s.dealsOpened, 1);
      s.logOut();
      expect(s.isLoggedIn, isFalse);
    });

    test('rejects malformed stored addresses', () {
      expect(SavedAddress.decode('{"id":"x","place":{"name":"a","lat":200,"lng":1}}'), isNull);
      expect(SavedAddress.decode('nope'), isNull);
    });
  });
}
