import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../security/native_bridge.dart';
import 'platforms.dart';

/// Android package of each platform's own app. Listed in the manifest's
/// `<queries>` too, so Savr may check whether they're installed.
const kAndroidPackages = <String, String>{
  'blinkit': 'com.grofers.customerapp',
  'zepto': 'com.zeptoconsumerapp',
  'instamart': 'in.swiggy.android',
  'swiggy': 'in.swiggy.android',
  'bbnow': 'com.bigbasket.mobileapp',
  'bigbasket': 'com.bigbasket.mobileapp',
  'fkminutes': 'com.flipkart.android',
  'flipkart': 'com.flipkart.android',
  'amazonnow': 'in.amazon.mShop.android.shopping',
  'amazonfresh': 'in.amazon.mShop.android.shopping',
  'amazon': 'in.amazon.mShop.android.shopping',
  'jiomart': 'com.jpl.jiomart',
  'myntra': 'com.myntra.android',
  'meesho': 'com.meesho.supply',
  'ajio': 'com.ril.ajio',
  'nykaa': 'com.fsn.nykaa',
  'tatacliq': 'com.tul.tatacliq',
  'zomato': 'com.application.zomato',
  'magicpin': 'com.magicpin.local',
  'uber': 'com.ubercab',
  'ola': 'com.olacabs.customer',
  'rapido': 'com.rapido.passenger',
  'nammayatri': 'in.juspay.nammayatri',
  'indrive': 'sinet.startup.inDriver',
  'meru': 'com.winit.merucab',
  'dominos': 'com.Dominos',
  'eatsure': 'com.done.faasos',
};

/// Custom schemes Savr may open, per platform. Anything else is refused.
const _nativeSchemes = <String, String>{'ola': 'olacabs'};

enum LaunchResult {
  /// The exact page (product / booking) opened inside the app.
  app,

  /// Only the app's home screen could be opened.
  appHome,
  web,
  blocked,
  failed,
}

/// Opens a platform link in its own app when installed, otherwise the web.
///
/// Order: allowlisted custom scheme (e.g. Ola's, which carries the drop
/// point) → the link aimed at the app's own package (lands on the product
/// page even without verified App Links) → verified app link → the app's
/// home screen → the browser.
abstract final class AppLauncher {
  static final installed = ValueNotifier<Set<String>>(const {});

  /// Refreshes which platform apps are on the phone. Cheap; call on start
  /// and on resume.
  static Future<void> refresh() async {
    final pkgs = await NativeBridge.installedPackages(kAndroidPackages.values.toSet().toList());
    installed.value = {
      for (final MapEntry(key: id, value: pkg) in kAndroidPackages.entries)
        if (pkgs.contains(pkg)) id,
    };
  }

  static bool hasApp(String platformId) => installed.value.contains(platformId);

  static Future<LaunchResult> open(String platformId, Uri web, {Uri? native}) async {
    final p = kPlatformById[platformId];
    if (p == null || web.scheme != 'https' || !p.ownsHost(web.host)) return LaunchResult.blocked;

    if (hasApp(platformId)) {
      final pkg = kAndroidPackages[platformId];
      if (native != null && native.scheme == _nativeSchemes[platformId]) {
        if (await _try(native, LaunchMode.externalNonBrowserApplication)) return LaunchResult.app;
      }
      if (pkg != null && await NativeBridge.openInPackage(web, pkg)) return LaunchResult.app;
      if (await _try(web, LaunchMode.externalNonBrowserApplication)) return LaunchResult.app;
      if (pkg != null && await NativeBridge.launchPackage(pkg)) return LaunchResult.appHome;
    }
    if (await _try(web, LaunchMode.externalApplication)) return LaunchResult.web;
    return LaunchResult.failed;
  }

  static Future<bool> _try(Uri u, LaunchMode mode) async {
    try {
      return await launchUrl(u, mode: mode);
    } catch (_) {
      return false;
    }
  }
}
