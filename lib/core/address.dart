import 'dart:convert';

import 'link_parser.dart';
import 'place.dart';

enum AddressLabel {
  home('Home'),
  work('Work'),
  other('Other');

  const AddressLabel(this.title);
  final String title;
}

/// A delivery address the user saved: an exact map pin plus the details a
/// rider needs (flat, building, landmark). The pin is what live prices use.
class SavedAddress {
  const SavedAddress({
    required this.id,
    required this.label,
    required this.place,
    this.flat,
    this.building,
    this.landmark,
    this.customName,
  });

  final String id;
  final AddressLabel label;
  final Place place;
  final String? flat;
  final String? building;
  final String? landmark;

  /// Name for an "Other" address, e.g. "Mom's place".
  final String? customName;

  String get title => label == AddressLabel.other && customName != null ? customName! : label.title;

  /// "Flat 4B, Sunrise Apartments, Baguiati, Kolkata 700059".
  String get line => [?flat, ?building, place.name, if (place.subtitle.isNotEmpty) place.subtitle].join(', ');

  /// The place handed to platforms; its name stays the area so headers read
  /// naturally ("Baguiati"), while the coordinates are the exact pin.
  Place get pin => place;

  SavedAddress copyWith({
    AddressLabel? label,
    Place? place,
    String? flat,
    String? building,
    String? landmark,
    String? customName,
  }) => SavedAddress(
    id: id,
    label: label ?? this.label,
    place: place ?? this.place,
    flat: flat ?? this.flat,
    building: building ?? this.building,
    landmark: landmark ?? this.landmark,
    customName: customName ?? this.customName,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label.name,
    'place': place.toJson(),
    'flat': flat,
    'building': building,
    'landmark': landmark,
    'customName': customName,
  };

  String encode() => jsonEncode(toJson());

  static SavedAddress? decode(String s) {
    if (s.length > 8192) return null;
    try {
      final j = jsonDecode(s);
      if (j is! Map) return null;
      final place = Place.fromJson(j['place']);
      final id = j['id'];
      if (place == null || id is! String || id.isEmpty || id.length > 40) return null;
      return SavedAddress(
        id: id,
        label: AddressLabel.values.where((l) => l.name == j['label']).firstOrNull ?? AddressLabel.other,
        place: place,
        flat: cleanField(j['flat']),
        building: cleanField(j['building']),
        landmark: cleanField(j['landmark']),
        customName: cleanField(j['customName'], max: 30),
      );
    } on FormatException {
      return null;
    }
  }

  /// Trims, strips markup and caps a free-text field. Empty → null.
  static String? cleanField(Object? v, {int max = 80}) {
    if (v is! String) return null;
    final s = sanitizeQuery(v);
    if (s.isEmpty) return null;
    return s.length > max ? s.substring(0, max) : s;
  }
}

/// A search the user starred, with the best price when it was saved.
class SavedSearch {
  const SavedSearch({required this.query, required this.vertical, this.bestPrice, this.platformId, required this.at});
  final String query;
  final String vertical;
  final double? bestPrice;
  final String? platformId;
  final DateTime at;

  Map<String, Object?> toJson() => {
    'q': query,
    'v': vertical,
    'p': bestPrice,
    'pid': platformId,
    'at': at.millisecondsSinceEpoch,
  };

  static SavedSearch? decode(String s) {
    try {
      final j = jsonDecode(s);
      if (j is! Map || j['q'] is! String || j['v'] is! String || j['at'] is! int) return null;
      final q = SavedAddress.cleanField(j['q'], max: 120);
      if (q == null) return null;
      final p = j['p'];
      return SavedSearch(
        query: q,
        vertical: j['v'] as String,
        bestPrice: p is num && p > 0 && p < 1e8 ? p.toDouble() : null,
        platformId: j['pid'] is String ? j['pid'] as String : null,
        at: DateTime.fromMillisecondsSinceEpoch(j['at'] as int),
      );
    } on FormatException {
      return null;
    }
  }
}
