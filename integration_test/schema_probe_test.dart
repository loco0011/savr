// Diagnostic: discovers the JSON shape of BigBasket / Flipkart Minutes search
// responses (fresh anonymous session) so scrapers can be written for them.
// Logs URL paths, key skeletons and one sample product map; no cookies.
//   flutter test integration_test/schema_probe_test.dart -d <device>
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:savr/core/place.dart';
import 'package:savr/data/device/location_injection.dart';
import 'package:savr/data/device/webview_runner.dart';

const _home = Place(name: 'Baguiati', lat: 22.6133, lng: 88.4304, city: 'Kolkata', pincode: '700059');

String _hook(String pattern) =>
    '''
(function(){
  var P = new RegExp(${jsonEncode(pattern)});
  function send(u,t){ if(!u||!t||t.length>4000000||!P.test(u)) return; try { window.flutter_inappwebview.callHandler('probe', u, t); } catch(e) {} }
  var of = window.fetch;
  if (of) window.fetch = function(){ return of.apply(this, arguments).then(function(r){ try { if (P.test(r.url)) r.clone().text().then(function(t){ send(r.url, t); }); } catch(e) {} return r; }); };
  var oo = XMLHttpRequest.prototype.open, os = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function(m,u){ this.__u = u; return oo.apply(this, arguments); };
  XMLHttpRequest.prototype.send = function(){ var x = this; x.addEventListener('load', function(){ try { if (x.responseType === '' || x.responseType === 'text') send(x.responseURL || String(x.__u), x.responseText); } catch(e) {} }); return os.apply(this, arguments); };
})();
''';

String _skeleton(Object? o, [int depth = 0]) {
  if (depth > 3) return '…';
  if (o is Map) return '{${o.keys.take(14).map((k) => '$k:${_skeleton(o[k], depth + 1)}').join(',')}}';
  if (o is List) return o.isEmpty ? '[]' : '[${o.length}×${_skeleton(o.first, depth + 1)}]';
  return o.runtimeType.toString();
}

/// First map that looks like a product (has a name-ish and a price-ish key).
Map? _product(Object? o, [int depth = 0]) {
  if (depth > 30) return null;
  if (o is Map) {
    final keys = o.keys.map((k) => '$k'.toLowerCase()).toSet();
    final named = keys.any((k) => k == 'desc' || k == 'name' || k == 'title' || k == 'product_name');
    final priced = keys.any((k) => k.contains('price') || k == 'mrp' || k == 'sp' || k == 'pricing');
    if (named && priced) return o;
    for (final v in o.values) {
      final r = _product(v, depth + 1);
      if (r != null) return r;
    }
  } else if (o is List) {
    for (final v in o.take(50)) {
      final r = _product(v, depth + 1);
      if (r != null) return r;
    }
  }
  return null;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final sites = {
    'bigbasket': (
      'https://www.bigbasket.com/ps/?q=amul%20milk&nc=as',
      r'bigbasket\.com/(listing-svc|product|ui-svc|mapi|search)',
    ),
    'fkminutes': (
      'https://www.flipkart.com/search?q=amul%20milk&marketplace=HYPERLOCAL',
      r'flipkart\.com/(api|.*page/fetch|.*search)',
    ),
  };

  for (final MapEntry(key: id, value: (url, pattern)) in sites.entries) {
    testWidgets('schema $id', (tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        var n = 0;
        final view = HeadlessInAppWebView(
          initialUrlRequest: URLRequest(url: WebUri(url)),
          initialSettings: platformWebSettings(headless: true),
          initialUserScripts: UnmodifiableListView([
            UserScript(
              source: locationScript(id, _home),
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              forMainFrameOnly: true,
            ),
            UserScript(source: _hook(pattern), injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START, forMainFrameOnly: true),
          ]),
          onLoadStop: (_, u) => debugPrint('[schema] $id loaded $u'),
          onWebViewCreated: (c) => c.addJavaScriptHandler(
            handlerName: 'probe',
            callback: (args) {
              if (n++ > 8 || args.length != 2) return null;
              final u = Uri.tryParse('${args[0]}');
              final body = '${args[1]}';
              Object? j;
              try {
                j = jsonDecode(body);
              } catch (_) {
                debugPrint('[schema] $id ${u?.path} non-json ${body.length}B');
                return null;
              }
              debugPrint('[schema] $id ${u?.path}?${u?.query.split('&').take(4).join('&')} ${body.length}B');
              final sk = _skeleton(j);
              debugPrint('[schema] $id skel ${sk.length > 900 ? sk.substring(0, 900) : sk}');
              final p = _product(j);
              if (p != null) {
                final s = jsonEncode(p);
                debugPrint('[schema] $id product ${s.length > 1500 ? s.substring(0, 1500) : s}');
              }
              return null;
            },
          ),
        );
        await view.run();
        await Future<void>.delayed(const Duration(seconds: 14));
        await view.dispose();
      });
    });
  }
}
