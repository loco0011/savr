import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:savr/app_scope.dart';
import 'package:savr/core/models.dart';
import 'package:savr/core/place.dart';
import 'package:savr/data/geo.dart';
import 'package:savr/data/repository.dart';
import 'package:savr/security/admin_auth.dart';
import 'package:savr/state/settings.dart';
import 'package:savr/theme/app_theme.dart';
import 'package:savr/ui/results_screen.dart';

const _q = SearchQuery(text: 'amul milk', vertical: Vertical.quick);

/// Offers shaped like the real scrapers' output (no fees, Instamart has no ETA).
final _im = [
  for (var i = 0; i < 6; i++)
    Offer(platformId: 'instamart', title: 'Amul Taaza Toned Milk', packLabel: '${500 * (i + 1)} ml',
        price: 29.0 * (i + 1), mrp: 30.0 * (i + 1), url: Uri.parse('https://www.swiggy.com/instamart/search?query=x')),
];
final _zp = [
  Offer(platformId: 'zepto', title: 'Amul Taaza Homogenised Toned Milk (Tetra Pack)', packLabel: '1 pack (200 ml)',
      price: 17, mrp: 18, etaMinutes: 10, url: Uri.parse('https://www.zepto.com/pn/x/pvid/0a1b2c3d-1111')),
  Offer(platformId: 'zepto', title: 'Amul Taaza Toned Milk', packLabel: '500 ml', price: 28, etaMinutes: 10,
      inStock: false, url: Uri.parse('https://www.zepto.com/pn/y/pvid/0a1b2c3d-2222')),
];
final _bl = [
  Offer(platformId: 'blinkit', title: 'Amul Taaza Toned Milk', packLabel: '500 ml', price: 30, mrp: 30, etaMinutes: 8,
      url: Uri.parse('https://blinkit.com/prn/amul/prid/1')),
];

class _FakeRepo extends PriceRepository {
  _FakeRepo(super.settings);
  @override
  Stream<SearchResult> searchStream(SearchQuery q) async* {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    yield SearchResult(query: q, offers: _im, isSample: false, live: const ['instamart'], pending: const ['blinkit', 'zepto']);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    yield SearchResult(query: q, offers: [..._im, ..._zp], isSample: false, live: const ['instamart', 'zepto'], pending: const ['blinkit']);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    yield SearchResult(query: q, offers: [..._im, ..._zp, ..._bl], isSample: false, live: const ['instamart', 'zepto', 'blinkit']);
  }
}

void main() {
  for (final b in Brightness.values) {
    testWidgets('live-shaped streaming results render ($b)', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = await Settings.load();
      settings.setPlace(const Place(name: 'Baguiati', lat: 22.61, lng: 88.43, city: 'Bidhannagar'));
      await tester.binding.setSurfaceSize(const Size(384, 832));
      final errors = <FlutterErrorDetails>[];
      final old = FlutterError.onError;
      FlutterError.onError = errors.add;
      await tester.pumpWidget(AppScope(
        settings: settings,
        repo: _FakeRepo(settings),
        admin: AdminAuth(),
        version: 't',
        geo: GeoService(),
        child: MaterialApp(
          theme: buildTheme(b),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.4)),
            child: child!,
          ),
          home: const ResultsScreen(query: _q),
        ),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      FlutterError.onError = old;
      for (final e in errors.take(3)) {
        debugPrint('ERROR: ${e.exceptionAsString()}\n${e.stack.toString().split('\n').take(12).join('\n')}');
      }
      expect(errors, isEmpty);
      expect(find.text('BEST PRICE'), findsOneWidget);
    });
  }
}
