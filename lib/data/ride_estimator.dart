import '../core/place.dart';
import '../core/platforms.dart';

enum RideClass {
  bike('Bike'),
  auto('Auto'),
  hatch('Mini'),
  sedan('Sedan'),
  suv('SUV');

  const RideClass(this.label);
  final String label;
}

/// Time-of-day demand band. Picked automatically from the clock; the user
/// can override it (e.g. when it's raining).
enum TimeBand {
  normal('Normal'),
  peak('Peak / rain'),
  night('Night');

  const TimeBand(this.label);
  final String label;

  static TimeBand at(DateTime t) {
    final h = t.hour;
    if (h >= 23 || h < 5) return night;
    final weekday = t.weekday <= DateTime.friday;
    if (weekday && ((h >= 8 && h < 11) || (h >= 17 && h < 21))) return peak;
    return normal;
  }
}

class RideQuote {
  const RideQuote({
    required this.platform,
    required this.product,
    required this.rideClass,
    required this.low,
    required this.high,
    required this.pickupMinutes,
  });
  final MarketPlatform platform;
  final String product;
  final RideClass rideClass;
  final double low;
  final double high;
  final int pickupMinutes;

  double get mid => (low + high) / 2;
}

class _Rate {
  const _Rate(this.product, this.cls, this.base, this.perKm, this.perMin, this.minFare, this.pickup);
  final String product;
  final RideClass cls;
  final double base, perKm, perMin, minFare;
  final int pickup;
}

/// Ride apps expose no public quote API in India (live fares need a login in
/// each app), so fares are estimated from approximate published rate cards,
/// the real road distance and a traffic-adjusted trip time. The UI always
/// labels them as estimates and hands off to the app for the exact price.
abstract final class RideEstimator {
  static const _rates = <String, List<_Rate>>{
    'uber': [
      _Rate('Uber Moto', RideClass.bike, 20, 6.5, 1.0, 25, 4),
      _Rate('Uber Auto', RideClass.auto, 30, 13, 1.0, 35, 5),
      _Rate('Uber Go', RideClass.hatch, 50, 14, 1.5, 80, 6),
      _Rate('Uber Premier', RideClass.sedan, 60, 17, 1.8, 100, 7),
      _Rate('Uber XL', RideClass.suv, 80, 22, 2.2, 140, 10),
    ],
    'ola': [
      _Rate('Ola Bike', RideClass.bike, 20, 6, 1.0, 25, 5),
      _Rate('Ola Auto', RideClass.auto, 30, 13, 1.0, 35, 5),
      _Rate('Ola Mini', RideClass.hatch, 50, 13.5, 1.5, 80, 7),
      _Rate('Ola Prime Sedan', RideClass.sedan, 60, 16, 1.8, 100, 8),
      _Rate('Ola Prime SUV', RideClass.suv, 80, 21, 2.0, 140, 11),
    ],
    'rapido': [
      _Rate('Rapido Bike', RideClass.bike, 15, 5.5, 0.8, 20, 3),
      _Rate('Rapido Auto', RideClass.auto, 25, 12, 1.0, 30, 4),
      _Rate('Rapido Cab Economy', RideClass.hatch, 45, 13, 1.3, 75, 6),
      _Rate('Rapido Cab Premium', RideClass.sedan, 55, 15.5, 1.5, 95, 7),
    ],
    'nammayatri': [
      _Rate('Namma Yatri Auto', RideClass.auto, 30, 15, 0, 30, 5),
      _Rate('Namma Yatri Cab', RideClass.hatch, 45, 14, 1.2, 80, 8),
    ],
    'indrive': [
      _Rate('inDrive Moto', RideClass.bike, 15, 5.5, 0.8, 20, 5),
      _Rate('inDrive Car', RideClass.hatch, 45, 12, 1.0, 70, 7),
    ],
    'yatrisathi': [
      _Rate('Yatri Sathi Auto', RideClass.auto, 30, 14, 0, 30, 5),
      _Rate('Yatri Sathi Cab', RideClass.hatch, 50, 13, 1.0, 80, 7),
      _Rate('Yatri Sathi XL', RideClass.suv, 80, 19, 1.5, 130, 10),
    ],
    'meru': [
      _Rate('Meru Sedan', RideClass.sedan, 70, 18, 1.5, 120, 9),
      _Rate('Meru SUV', RideClass.suv, 90, 22, 2.0, 160, 12),
    ],
  };

  /// City-only services. Unknown cities show everything.
  static const _onlyIn = <String, List<String>>{
    'yatrisathi': ['kolkata', 'howrah', 'bidhannagar', 'salt lake', 'new town', 'siliguri', 'durgapur', 'asansol'],
  };

  static bool availableIn(String platformId, String? city) {
    final only = _onlyIn[platformId];
    if (only == null) return true;
    final c = (city ?? '').toLowerCase();
    return c.isNotEmpty && only.any(c.contains);
  }

  /// Rate cards differ by city; relative to Bengaluru.
  static double cityFactor(String? city) {
    final c = (city ?? '').toLowerCase();
    if (c.contains('kolkata') || c.contains('howrah') || c.contains('bidhannagar')) return 0.88;
    if (c.contains('mumbai') || c.contains('thane')) return 1.06;
    if (c.contains('delhi') || c.contains('gurugram') || c.contains('gurgaon') || c.contains('noida')) return 0.95;
    if (c.contains('hyderabad') || c.contains('chennai')) return 0.95;
    if (c.contains('pune')) return 0.97;
    return 1.0;
  }

  /// Trip time in city traffic, from the router's empty-road time.
  static double trafficMinutes(double km, double freeFlowMinutes, TimeBand band) {
    final factor = switch (band) {
      TimeBand.peak => 1.9,
      TimeBand.normal => 1.45,
      TimeBand.night => 1.1,
    };
    final floor = km * (band == TimeBand.night ? 1.6 : 2.2);
    final m = freeFlowMinutes * factor;
    return m > floor ? m : floor;
  }

  static List<RideQuote> estimate({
    required double km,
    required double minutes,
    required TimeBand band,
    required Set<String> platformIds,
    String? city,
  }) {
    final cf = cityFactor(city);
    final out = <RideQuote>[];
    for (final MapEntry(key: pid, value: rates) in _rates.entries) {
      if (!platformIds.contains(pid) || !availableIn(pid, city)) continue;
      final p = kPlatformById[pid]!;
      for (final r in rates) {
        // Namma Yatri is zero-commission and doesn't surge in the same way.
        final surge = switch (band) {
          TimeBand.peak => pid == 'nammayatri' ? 1.05 : 1.35,
          TimeBand.night => pid == 'nammayatri' ? 1.1 : 1.2,
          TimeBand.normal => 1.0,
        };
        var fare = (r.base + r.perKm * km + r.perMin * minutes) * surge * cf;
        if (fare < r.minFare) fare = r.minFare;
        out.add(
          RideQuote(
            platform: p,
            product: r.product,
            rideClass: r.cls,
            low: (fare * 0.92).roundToDouble(),
            high: (fare * 1.08).roundToDouble(),
            pickupMinutes: band == TimeBand.peak ? r.pickup + 4 : r.pickup,
          ),
        );
      }
    }
    out.sort((a, b) => a.mid.compareTo(b.mid));
    return out;
  }

  /// Booking link with pickup and drop prefilled where the app supports it.
  /// [native] is an allowlisted custom scheme tried first (see AppLauncher).
  static ({Uri web, Uri? native}) bookingLink(String platformId, Place from, Place to) {
    String f(double v) => v.toStringAsFixed(6);
    switch (platformId) {
      case 'uber':
        return (
          web: Uri.https('m.uber.com', '/ul/', {
            'action': 'setPickup',
            'pickup[latitude]': f(from.lat),
            'pickup[longitude]': f(from.lng),
            'pickup[nickname]': from.name,
            'pickup[formatted_address]': from.address,
            'dropoff[latitude]': f(to.lat),
            'dropoff[longitude]': f(to.lng),
            'dropoff[nickname]': to.name,
            'dropoff[formatted_address]': to.address,
          }),
          native: null,
        );
      case 'ola':
        final qp = {
          'lat': f(from.lat),
          'lng': f(from.lng),
          'drop_lat': f(to.lat),
          'drop_lng': f(to.lng),
          'pickup_name': from.name,
          'drop_name': to.name,
        };
        return (
          web: Uri.https('book.olacabs.com', '/', qp),
          native: Uri(scheme: 'olacabs', host: 'app', path: '/launch', queryParameters: {...qp, 'utm_source': 'savr'}),
        );
      default:
        return (web: kPlatformById[platformId]!.searchUrl(to.name), native: null);
    }
  }
}
