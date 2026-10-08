// Diagnostic: which store / coordinates does Zepto's own search request use
// after Savr injects a location? Logs request URLs and location-related
// request header names/values only (never cookies or auth headers).
//   flutter test integration_test/zepto_store_probe_test.dart -d <device>
import 'dart:async';
import 'dart:collection';

import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:savr/core/place.dart';
import 'package:savr/data/device/location_injection.dart';
import 'package:savr/data/device/webview_runner.dart';

const _probe = r'''
(function(){
  var K = /store|lat|lon|lng|position|serviceab|pincode|geo/i;
  var SKIP = /cookie|auth|token|session|csrf/i;
  function log(m){ try { console.log('[probe] ' + m); } catch(e) {} }
  var of = window.fetch;
  if (of) window.fetch = function(input, init){
    try {
      var url = typeof input === 'string' ? input : (input && input.url);
      if (/search|store|serviceab|location|layout|get_page/i.test(url)) {
        var h = (init && init.headers) || (input && input.headers) || {};
        var pairs = [];
        var each = function(k, v){ if (K.test(k) && !SKIP.test(k)) pairs.push(k + '=' + v); };
        if (h.forEach) h.forEach(function(v, k){ each(k, v); }); else for (var k in h) each(k, h[k]);
        log('fetch ' + String(url).split('?')[0] + ' :: ' + pairs.join(' ') + ' :: ' + (/[?&](latitude|lat|store)/.test(url) ? String(url).split('?')[1] : ''));
      }
    } catch(e) {}
    return of.apply(this, arguments);
  };
  var oo = XMLHttpRequest.prototype.open, sh = XMLHttpRequest.prototype.setRequestHeader, os = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function(m, u){ this.__u = u; this.__h = []; return oo.apply(this, arguments); };
  XMLHttpRequest.prototype.setRequestHeader = function(k, v){ if (K.test(k) && !SKIP.test(k)) this.__h.push(k + '=' + v); return sh.apply(this, arguments); };
  XMLHttpRequest.prototype.send = function(){ if (/search|store|serviceab|location|layout|get_page/i.test(this.__u)) log('xhr ' + String(this.__u).split('?')[0] + ' :: ' + this.__h.join(' ')); return os.apply(this, arguments); };
})();
''';

const _places = [
  Place(name: 'Tollygunge', lat: 22.4986, lng: 88.3459, city: 'Kolkata'),
  Place(name: 'Koramangala', lat: 12.9352, lng: 77.6245, city: 'Bengaluru'),
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final place in _places) {
    testWidgets('zepto store @ ${place.name}', (tester) async {
      await CookieManager.instance().deleteAllCookies();
      await WebStorageManager.instance().deleteAllData();
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        final done = Completer<void>();
        final view = HeadlessInAppWebView(
          initialUrlRequest: URLRequest(url: WebUri('https://www.zepto.com/search?query=amul%20milk')),
          initialSettings: platformWebSettings(headless: true),
          initialUserScripts: UnmodifiableListView([
            UserScript(
              source: locationScript('zepto', place),
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              forMainFrameOnly: true,
            ),
            UserScript(source: _probe, injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START, forMainFrameOnly: true),
          ]),
          onConsoleMessage: (_, m) {
            if (m.message.startsWith('[probe]')) debugPrint('[zprobe] ${place.name} ${m.message.substring(8)}');
          },
        );
        await view.run();
        Timer(const Duration(seconds: 12), () => done.complete());
        await done.future;
        await view.dispose();
      });
    });
  }
}
