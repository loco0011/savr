import 'dart:convert';
import 'dart:math' as math;

import 'link_parser.dart';

/// A location the user picked once in Savr (search or GPS). Used for every
/// live price lookup and as the default ride pickup.
class Place {
  const Place({
    required this.name,
    required this.lat,
    required this.lng,
    this.area,
    this.city,
    this.state,
    this.pincode,
  });

  /// Short label, e.g. "Tollygunge".
  final String name;
  final double lat;
  final double lng;

  /// Neighbourhood / district when [name] is a street or landmark.
  final String? area;
  final String? city;
  final String? state;
  final String? pincode;

  /// "Kolkata, West Bengal 700033" style second line.
  String get subtitle {
    final parts = <String>[
      if (area != null && area != name) area!,
      if (city != null && city != name) city!,
      if (state != null && state != city) state!,
    ];
    final s = parts.join(', ');
    return pincode == null ? s : (s.isEmpty ? pincode! : '$s $pincode');
  }

  /// One-line address handed to platform websites.
  String get address => [name, if (subtitle.isNotEmpty) subtitle].join(', ');

  static bool validCoords(double lat, double lng) =>
      lat.isFinite && lng.isFinite && lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;

  Map<String, Object?> toJson() => {
    'name': name,
    'lat': lat,
    'lng': lng,
    'area': area,
    'city': city,
    'state': state,
    'pincode': pincode,
  };

  String encode() => jsonEncode(toJson());

  /// Parses stored or third-party JSON; returns null if anything is off.
  static Place? fromJson(Object? j) {
    if (j is! Map) return null;
    final lat = j['lat'], lng = j['lng'];
    if (lat is! num || lng is! num) return null;
    if (!validCoords(lat.toDouble(), lng.toDouble())) return null;
    final name = _s(j['name']);
    if (name == null) return null;
    final pin = _s(j['pincode']);
    return Place(
      name: name,
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      area: _s(j['area']),
      city: _s(j['city']),
      state: _s(j['state']),
      pincode: pin != null && RegExp(r'^[1-9]\d{5}$').hasMatch(pin) ? pin : null,
    );
  }

  static Place? decode(String? s) {
    if (s == null || s.length > 4096) return null;
    try {
      return fromJson(jsonDecode(s));
    } on FormatException {
      return null;
    }
  }

  static String? _s(Object? v) {
    if (v is! String) return null;
    final t = sanitizeQuery(v);
    if (t.isEmpty) return null;
    return t.length > 80 ? t.substring(0, 80) : t;
  }

  /// Great-circle distance in km.
  double kmTo(Place o) {
    const r = 6371.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(o.lat - lat), dLng = rad(o.lng - lng);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(lat)) * math.cos(rad(o.lat)) * math.sin(dLng / 2) * math.sin(dLng / 2);
    return 2 * r * math.asin(math.sqrt(a));
  }

  @override
  bool operator ==(Object other) =>
      other is Place && (other.lat - lat).abs() < 1e-5 && (other.lng - lng).abs() < 1e-5 && other.name == name;

  @override
  int get hashCode => Object.hash(name, (lat * 1e4).round(), (lng * 1e4).round());
}
