import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:savr/app_scope.dart';
import 'package:savr/core/models.dart';
import 'package:savr/data/geo.dart';
import 'package:savr/data/repository.dart';
import 'package:savr/security/admin_auth.dart';
import 'package:savr/state/settings.dart';
import 'package:savr/theme/app_theme.dart';
import 'package:savr/ui/results_screen.dart';

void main() {
  for (final b in Brightness.values) {
    testWidgets('results render without layout errors ($b)', (tester) async {
      SharedPreferences.setMockInitialValues({'dataMode': 'sample'});
      final settings = await Settings.load();
      await tester.binding.setSurfaceSize(const Size(384, 832));
      await tester.pumpWidget(
        AppScope(
          settings: settings,
          repo: PriceRepository(settings),
          admin: AdminAuth(),
          version: 't',
          geo: GeoService(),
          child: MaterialApp(
            theme: buildTheme(b),
            home: const ResultsScreen(query: SearchQuery(text: 'amul milk', vertical: Vertical.quick)),
          ),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
      expect(find.textContaining('₹'), findsWidgets);
      expect(find.text('BEST PRICE'), findsOneWidget);
    });
  }
}
