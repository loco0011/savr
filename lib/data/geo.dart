import 'dart:convert';

import 'package:geolocator/geolocator.dart';

import '../core/place.dart';
import 'safe_http.dart';

/// Road route between two places.
class RouteInfo {
  const RouteInfo({required this.km, required this.freeFlowMinutes, required this.isRoad});
  final double km;

  /// Driving time with empty roads; callers add traffic.
  final double freeFlowMinutes;

  /// False when the routing service was unreachable and [km] is a
  /// straight-line estimate scaled for city roads.
  final bool isRoad;
}

class GeoException implements Exception {
  const GeoException(this.userMessage);
  final String userMessage;
}

/// Place search, reverse geocoding, GPS and road distance.
///
/// Uses OpenStreetMap's public services: Nominatim for search and OSRM for
/// routing. Only the typed text or coordinates are sent; no identifiers.
/// Nominatim's usage policy allows ~1 request/s and no search-as-you-type,
/// so searches run on submit and are cached. For a public launch, self-host
/// both or move to a paid provider.
class GeoService {
  GeoService({SafeHttp? http}) : _http = http ?? SafeHttp();

  final SafeHttp _http;

  static const _nominatim = 'nominatim.openstreetmap.org';
  static const _osrm = 'router.project-osrm.org';
  static const _headers = {'User-Agent': 'Savr/1.0 (in.ekrion.savr)', 'Accept-Language': 'en'};

  final _searchCache = <String, List<Place>>{};
  DateTime _lastNominatim = DateTime.fromMillisecondsSinceEpoch(0);

  bool _allow(String h) => h == _nominatim || h == _osrm;

  /// Places in India matching [query], nearest to [near] first.
  Future<List<Place>> search(String query, {Place? near}) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    final key = q.toLowerCase();
    final hit = _searchCache[key];
    if (hit != null) return _nearFirst(hit, near);
    final res = await _nominatimGet('/search', {
      'q': q.length > 100 ? q.substring(0, 100) : q,
      'format': 'jsonv2',
      'addressdetails': '1',
      'countrycodes': 'in',
      'limit': '8',
    });
    final out = <Place>[];
    if (res is List) {
      for (final r in res.take(10)) {
        final p = _place(r);
        if (p != null && !out.any((o) => o.name == p.name && o.subtitle == p.subtitle)) out.add(p);
      }
    }
    if (_searchCache.length > 40) _searchCache.remove(_searchCache.keys.first);
    _searchCache[key] = out;
    return _nearFirst(out, near);
  }

  List<Place> _nearFirst(List<Place> list, Place? near) {
    if (near == null || list.length < 2) return list;
    // Keep relevance order but lift results within 60 km of the user.
    final close = list.where((p) => p.kmTo(near) < 60).toList();
    return [...close, ...list.where((p) => !close.contains(p))];
  }

  Future<Place?> reverse(double lat, double lng) async {
    final res = await _nominatimGet('/reverse', {
      'lat': lat.toStringAsFixed(6),
      'lon': lng.toStringAsFixed(6),
      'format': 'jsonv2',
      'addressdetails': '1',
      'zoom': '16',
    });
    final p = _place(res);
    if (p == null) return null;
    // Keep the exact GPS point; the name comes from the nearest feature.
    return Place(name: p.name, lat: lat, lng: lng, area: p.area, city: p.city, state: p.state, pincode: p.pincode);
  }

  /// The phone's position, named by reverse geocoding.
  Future<Place> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const GeoException('Turn on location services to use your current location.');
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      throw const GeoException('Location permission is off. Search for your area instead.');
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 12)),
    );
    // Name the point; one retry because a fresh GPS fix often comes right
    // after the network wakes up.
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final p = await reverse(pos.latitude, pos.longitude);
        if (p != null) return p;
      } catch (_) {
        // Retry once, then fall back.
      }
    }
    return _pinOnly(pos);
  }

  /// Never labelled "Current location": the app always shows where the
  /// chosen point is.
  Place _pinOnly(Position pos) => Place(
    name: 'Pinned ${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}',
    lat: pos.latitude,
    lng: pos.longitude,
  );

  /// Driving distance and free-flow time. Falls back to a straight-line
  /// estimate (×1.35 for city roads) if the router can't be reached.
  Future<RouteInfo> route(Place from, Place to) async {
    final straight = from.kmTo(to);
    try {
      final res = await _get(
        Uri.https(_osrm, '/route/v1/driving/${from.lng},${from.lat};${to.lng},${to.lat}', {'overview': 'false'}),
      );
      final routes = res is Map ? res['routes'] : null;
      final r = routes is List && routes.isNotEmpty ? routes.first : null;
      final m = r is Map ? r['distance'] : null, s = r is Map ? r['duration'] : null;
      if (m is num && s is num && m >= 0 && m < 3e6 && s >= 0 && s < 3e5) {
        return RouteInfo(km: m / 1000, freeFlowMinutes: s / 60, isRoad: true);
      }
    } catch (_) {
      // Fall through to the estimate.
    }
    final km = straight * 1.35;
    return RouteInfo(km: km, freeFlowMinutes: km / 30 * 60, isRoad: false);
  }

  /// Spaces Nominatim calls at least 1 s apart (usage policy).
  Future<Object?> _nominatimGet(String path, Map<String, String> qp) async {
    final wait = const Duration(milliseconds: 1100) - DateTime.now().difference(_lastNominatim);
    if (wait > Duration.zero) await Future<void>.delayed(wait);
    _lastNominatim = DateTime.now();
    return _get(Uri.https(_nominatim, path, qp));
  }

  Future<Object?> _get(Uri url) async {
    try {
      final r = await _http.get(url, allowHost: _allow, headers: _headers, timeout: const Duration(seconds: 8));
      if (r.status != 200) throw const GeoException('Location search is unavailable right now.');
      return jsonDecode(r.body);
    } on GeoException {
      rethrow;
    } catch (_) {
      throw const GeoException('Couldn\'t reach location search. Check your connection.');
    }
  }

  /// One Nominatim jsonv2 result → place. Every field is type-checked.
  static Place? _place(Object? r) {
    if (r is! Map) return null;
    final lat = double.tryParse('${r['lat']}'), lng = double.tryParse('${r['lon']}');
    if (lat == null || lng == null) return null;
    final a = r['address'] is Map ? r['address'] as Map : const {};
    if (a['country_code'] is String && a['country_code'] != 'in') return null;
    String? s(Object? v) => v is String && v.isNotEmpty ? v : null;
    final area = s(a['suburb']) ?? s(a['neighbourhood']) ?? s(a['quarter']) ?? s(a['city_district']);
    final city = s(a['city']) ?? s(a['town']) ?? s(a['village']) ?? s(a['state_district']) ?? s(a['county']);
    final road = s(a['road']);
    final name = s(r['name']) ?? area ?? road ?? city;
    return Place.fromJson({
      'name': name,
      'lat': lat,
      'lng': lng,
      'area': area,
      'city': city,
      'state': s(a['state']),
      'pincode': s(a['postcode'])?.replaceAll(' ', ''),
    });
  }
}
