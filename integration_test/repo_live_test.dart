// End-to-end live search through PriceRepository (what the results screen
// uses), with a Savr location set. Run on a device:
//   flutter test integration_test/repo_live_test.dart -d <device>
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:savr/core/models.dart';
import 'package:savr/core/place.dart';
import 'package:savr/data/repository.dart';
import 'package:savr/state/settings.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('live search streams offers for a set location', (tester) async {
    // In-memory prefs: the app's real settings are left alone.
    SharedPreferences.setMockInitialValues({});
    final settings = await Settings.load();
    settings.setPlace(
      const Place(name: 'Baguiati', lat: 22.6133, lng: 88.4304, city: 'Bidhannagar', state: 'West Bengal', pincode: '700101'),
    );
    final repo = PriceRepository(settings);
    await tester.pumpWidget(const SizedBox());

    final parts = await tester.runAsync(() async {
      final out = <SearchResult>[];
      try {
        await for (final r in repo.searchStream(
          const SearchQuery(text: 'amul milk', vertical: Vertical.quick),
        )) {
          out.add(r);
          debugPrint(
            '[savrrepo] part offers=${r.offers.length} live=${r.live} failed=${r.failed} '
            'pending=${r.pending} needsSetup=${r.needsSetup} notice=${r.notice}',
          );
        }
      } catch (e) {
        debugPrint('[savrrepo] error $e');
      }
      return out;
    });
    expect(parts, isNotEmpty);
    expect(parts!.last.offers, isNotEmpty);
  });
}
