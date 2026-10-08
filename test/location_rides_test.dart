import 'package:flutter_test/flutter_test.dart';
import 'package:savr/core/place.dart';
import 'package:savr/data/device/location_injection.dart';
import 'package:savr/data/ride_estimator.dart';

const _tolly = Place(name: 'Tollygunge', lat: 22.4986, lng: 88.3459, city: 'Kolkata', state: 'West Bengal', pincode: '700033');
const _park = Place(name: 'Park Street', lat: 22.5535, lng: 88.3524, city: 'Kolkata');

void main() {
  group('Place', () {
    test('round-trips through storage', () {
      final p = Place.decode(_tolly.encode())!;
      expect(p, _tolly);
      expect(p.pincode, '700033');
      expect(p.subtitle, 'Kolkata, West Bengal 700033');
    });

    test('rejects bad coordinates, names and pincodes', () {
      expect(Place.fromJson({'name': 'x', 'lat': 91, 'lng': 0}), isNull);
      expect(Place.fromJson({'name': 'x', 'lat': double.nan, 'lng': 0}), isNull);
      expect(Place.fromJson({'name': '', 'lat': 1, 'lng': 1}), isNull);
      expect(Place.fromJson({'name': 'x', 'lat': '1', 'lng': 1}), isNull);
      expect(Place.fromJson({'name': 'x', 'lat': 1, 'lng': 1, 'pincode': '12'})!.pincode, isNull);
      expect(Place.decode('not json'), isNull);
    });

    test('great-circle distance', () {
      expect(_tolly.kmTo(_park), closeTo(6.2, 0.4));
    });
  });

  group('Location script', () {
    test('JSON-encodes user text so it cannot break out of the script', () {
      const evil = Place(name: 'x"};alert(1);//', lat: 1, lng: 1);
      final s = locationScript('blinkit', evil);
      // The double quote is escaped, so the value stays inside the JSON string.
      expect(s, contains(r'"name":"x\"};alert(1);//"'));
      expect(s, isNot(contains('"x"};alert')));
    });

    test('adds site-specific storage only for known platforms', () {
      expect(locationScript('blinkit', _tolly), contains('gr_1_lat'));
      expect(locationScript('instamart', _tolly), contains('userLocation'));
      expect(locationScript('amazon', _tolly), isNot(contains('gr_1_lat')));
    });
  });

  group('Rides', () {
    test('time bands', () {
      expect(TimeBand.at(DateTime(2026, 10, 5, 9)), TimeBand.peak); // Monday
      expect(TimeBand.at(DateTime(2026, 10, 4, 9)), TimeBand.normal); // Sunday
      expect(TimeBand.at(DateTime(2026, 10, 5, 23, 30)), TimeBand.night);
    });

    test('longer and peak trips cost more; Kolkata cheaper than Mumbai', () {
      List<double> mids(double km, TimeBand b, String city) => RideEstimator.estimate(
        km: km,
        minutes: RideEstimator.trafficMinutes(km, km * 2, b),
        band: b,
        platformIds: {'uber'},
        city: city,
      ).map((q) => q.mid).toList();
      final short = mids(5, TimeBand.normal, 'Kolkata');
      expect(mids(15, TimeBand.normal, 'Kolkata').first, greaterThan(short.first));
      expect(mids(5, TimeBand.peak, 'Kolkata').first, greaterThan(short.first));
      expect(mids(10, TimeBand.normal, 'Mumbai').first, greaterThan(mids(10, TimeBand.normal, 'Kolkata').first));
    });

    test('booking links prefill both points on trusted hosts', () {
      final uber = RideEstimator.bookingLink('uber', _tolly, _park);
      expect(uber.web.host, 'm.uber.com');
      expect(uber.web.queryParameters['dropoff[nickname]'], 'Park Street');
      final ola = RideEstimator.bookingLink('ola', _tolly, _park);
      expect(ola.web.host, 'book.olacabs.com');
      expect(ola.native!.scheme, 'olacabs');
      expect(ola.native!.queryParameters['drop_lat'], '22.553500');
    });
  });
}
