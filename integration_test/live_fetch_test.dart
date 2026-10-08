// Network smoke test for on-device price fetching. Run on a device/emulator:
//   flutter test integration_test/live_fetch_test.dart -d <device>
// Fails when a platform changes its site enough to break Savr's scraper.
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:savr/data/device/scrapers.dart';
import 'package:savr/data/device/webview_runner.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Start from a brand-new browser session, like a first-time user.
  setUpAll(() async {
    await CookieManager.instance().deleteAllCookies();
    await WebStorageManager.instance().deleteAllData();
  });

  for (final scraper in deviceScrapers) {
    testWidgets('${scraper.platform.name} returns live offers', (tester) async {
      await tester.pumpWidget(const SizedBox());
      final sw = Stopwatch()..start();
      final out = await tester.runAsync(() => runScraper(scraper, 'amul milk', timeout: const Duration(seconds: 30)));
      debugPrint('[savr] ${scraper.platformId}: ok=${out!.ok} reason=${out.reason} '
          'offers=${out.offers.length} in ${sw.elapsedMilliseconds}ms');
      for (final o in out.offers.take(4)) {
        debugPrint('[savr]   ${o.title} | ${o.packLabel} | ₹${o.price} (mrp ${o.mrp}) eta=${o.etaMinutes} stock=${o.inStock}');
      }
      expect(out.offers, isNotEmpty);
    });
  }
}
