import '../core/models.dart';

abstract interface class PriceSource {
  /// Returns offers for [query] across [platformIds]. Never throws for "no
  /// results"; throws [PriceSourceException] for transport/config failures.
  Future<List<Offer>> search(SearchQuery query, {required Set<String> platformIds, String? pincode});
}

class PriceSourceException implements Exception {
  const PriceSourceException(this.userMessage, {this.code});

  /// Safe to show to users — never contains server response bodies or stack traces.
  final String userMessage;
  final String? code;

  @override
  String toString() => 'PriceSourceException($code)';
}
