// Real ResultsScreen + real live fetching on a device, to catch problems
// that only appear when the two run together.
//   flutter test integration_test/results_screen_live_test.dart -d <device>
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('results screen shows live offers', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await Settings.load();
    settings.setPlace(
      const Place(name: 'Baguiati', lat: 22.6133, lng: 88.4304, city: 'Bidhannagar', state: 'West Bengal'),
    );
    final errors = <String>[];
    final old = FlutterError.onError;
    FlutterError.onError = (d) {
      errors.add(d.exceptionAsString().split('\n').first);
      old?.call(d);
    };
    await tester.pumpWidget(
      AppScope(
        settings: settings,
        repo: PriceRepository(settings),
        admin: AdminAuth(),
        version: 't',
        geo: GeoService(),
        child: MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: const ResultsScreen(query: SearchQuery(text: 'amul milk', vertical: Vertical.quick)),
        ),
      ),
    );
    for (var s = 1; s <= 20; s++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
      await tester.pump();
      final prices = find.textContaining('₹').evaluate().length;
      final best = find.text('BEST PRICE').evaluate().length;
      final err = find.text('Try again').evaluate().length;
      debugPrint('[savrui] t=${s}s rupeeTexts=$prices best=$best errorState=$err errors=${errors.length}');
      if (prices > 0 && s >= 12) break;
    }
    FlutterError.onError = old;
    for (final e in errors.toSet().take(5)) {
      debugPrint('[savrui] flutter error: $e');
    }
    expect(find.textContaining('₹'), findsWidgets);
  });
}
