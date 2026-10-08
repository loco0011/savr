import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app.dart';
import 'app_scope.dart';
import 'data/geo.dart';
import 'data/repository.dart';
import 'security/admin_auth.dart';
import 'state/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['Inter'], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });

  final settings = await Settings.load();
  final info = await PackageInfo.fromPlatform();

  runApp(
    AppScope(
      settings: settings,
      repo: PriceRepository(settings),
      admin: AdminAuth(),
      version: '${info.version} (${info.buildNumber})',
      geo: GeoService(),
      child: const SavrApp(),
    ),
  );
}
