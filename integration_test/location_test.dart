// Checks that the Savr location is picked up by each live platform without
// the manual "set address" step. Run on a device:
//   flutter test integration_test/location_test.dart -d <device>
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:savr/core/place.dart';
import 'package:savr/data/device/scrapers.dart';
import 'package:savr/data/device/webview_runner.dart';

const _places = [
  Place(name: 'Tollygunge', lat: 22.4986, lng: 88.3459, city: 'Kolkata', state: 'West Bengal', pincode: '700033'),
  Place(name: 'Koramangala', lat: 12.9352, lng: 77.6245, city: 'Bengaluru', state: 'Karnataka', pincode: '560034'),
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final place in _places) {
    for (final scraper in deviceScrapers) {
      testWidgets('${scraper.platform.name} @ ${place.name}', (tester) async {
        // Fresh session each time so only the injected location applies.
        await CookieManager.instance().deleteAllCookies();
        await WebStorageManager.instance().deleteAllData();
        await tester.pumpWidget(const SizedBox());
        final sw = Stopwatch()..start();
        final out = await tester.runAsync(
          () => runScraper(scraper, 'amul milk', place: place, timeout: const Duration(seconds: 25)),
        );
        final top = out!.offers.take(3).map((o) => '${o.title} ₹${o.price}').join(' | ');
        debugPrint(
          '[savrloc] ${scraper.platformId}@${place.name}: ok=${out.ok} reason=${out.reason} '
          'n=${out.offers.length} eta=${out.offers.firstOrNull?.etaMinutes} ${sw.elapsedMilliseconds}ms :: $top',
        );
      });
    }
  }
}
