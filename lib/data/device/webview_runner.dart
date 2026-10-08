import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/models.dart';
import '../../core/place.dart';
import '../../core/platforms.dart';
import 'location_injection.dart';
import 'scrapers.dart';

/// Settings shared by the hidden scraper and the visible "set location"
/// browser: no file/content access, no popups, no mixed content, no
/// third-party schemes.
InAppWebViewSettings platformWebSettings({required bool headless}) => InAppWebViewSettings(
  javaScriptEnabled: true,
  domStorageEnabled: true,
  databaseEnabled: true,
  allowFileAccess: false,
  allowContentAccess: false,
  allowFileAccessFromFileURLs: false,
  allowUniversalAccessFromFileURLs: false,
  mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
  supportMultipleWindows: false,
  javaScriptCanOpenWindowsAutomatically: false,
  geolocationEnabled: false,
  useShouldOverrideUrlLoading: true,
  blockNetworkImage: headless, // saves data; prices don't need pictures
  isInspectable: kDebugMode,
  thirdPartyCookiesEnabled: true, // bot-check tokens live on sibling hosts
);

/// Only HTTPS pages on the platform's own hosts may load in the main frame.
/// Anything else (intent://, market://, other sites) is cancelled.
NavigationActionPolicy guardNavigation(MarketPlatform p, NavigationAction a) {
  final u = a.request.url;
  if (!a.isForMainFrame) return NavigationActionPolicy.ALLOW;
  if (u == null || u.scheme != 'https' || !p.ownsHost(u.host)) return NavigationActionPolicy.CANCEL;
  return NavigationActionPolicy.ALLOW;
}

/// Injected at document start. Mirrors fetch/XHR responses whose URL matches
/// the platform pattern to the 'savr' handler. Read-only: it never alters
/// requests, reads cookies or touches the page's DOM.
String _hookScript(String pattern) =>
    '''
(function(){
  if (window.__savrHooked) return; window.__savrHooked = true;
  var P = new RegExp(${jsonEncode(pattern)});
  var MAX = 4000000, q = [], ready = false;
  function deliver(u,t){ try { window.flutter_inappwebview.callHandler('savr', u, t); } catch(e) {} }
  function send(u,t){ if(!u||!t||t.length>MAX||!P.test(u)) return; if(ready) deliver(u,t); else q.push([u,t]); }
  window.addEventListener('flutterInAppWebViewPlatformReady', function(){ ready = true; while(q.length) deliver.apply(null, q.shift()); });
  var of = window.fetch;
  if (of) window.fetch = function(){ return of.apply(this, arguments).then(function(r){ try { if (P.test(r.url)) r.clone().text().then(function(t){ send(r.url, t); }); } catch(e) {} return r; }); };
  var oo = XMLHttpRequest.prototype.open, os = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function(m,u){ this.__savrUrl = u; return oo.apply(this, arguments); };
  XMLHttpRequest.prototype.send = function(){ var x = this; x.addEventListener('load', function(){ try { if (x.responseType === '' || x.responseType === 'text') send(x.responseURL || String(x.__savrUrl), x.responseText); } catch(e) {} }); return os.apply(this, arguments); };
})();
''';

class ScrapeOutcome {
  const ScrapeOutcome({required this.offers, required this.ok, this.reason});
  final List<Offer> offers;
  final bool ok;
  final String? reason;
}

/// Loads [scraper]'s search page for [query] in a headless WebView and
/// collects offers. Finishes [settle] after the first search payload (so the
/// ETA / second page can arrive) or at [timeout].
Future<ScrapeOutcome> runScraper(
  DeviceScraper scraper,
  String query, {
  Place? place,
  Duration timeout = const Duration(seconds: 14),
  Duration settle = const Duration(milliseconds: 700),
}) async {
  final st = ScrapeState();
  final done = Completer<void>();
  Timer? settleTimer;
  InAppWebViewController? controller;
  var retried = false;
  final platform = scraper.platform;
  const maxPayload = 4000000;
  // Debug builds only: trace the page lifecycle to diagnose platform changes.
  void log(String m) {
    if (kDebugMode) debugPrint('[savr:${scraper.platformId}] $m');
  }

  void finishSoon() {
    settleTimer ??= Timer(settle, () {
      if (!done.isCompleted) done.complete();
    });
  }

  final view = HeadlessInAppWebView(
    initialUrlRequest: URLRequest(url: WebUri.uri(scraper.entryUrl(query))),
    initialSettings: platformWebSettings(headless: true),
    initialUserScripts: UnmodifiableListView([
      if (place != null)
        UserScript(
          source: locationScript(scraper.platformId, place),
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          forMainFrameOnly: true,
        ),
      UserScript(
        source: _hookScript(scraper.capturePattern),
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        forMainFrameOnly: true,
      ),
    ]),
    shouldOverrideUrlLoading: (_, action) async {
      final policy = guardNavigation(platform, action);
      if (policy == NavigationActionPolicy.CANCEL) log('blocked navigation to ${action.request.url}');
      return policy;
    },
    onLoadStop: (_, url) => log('loaded $url'),
    onReceivedError: (_, req, err) {
      if (req.isForMainFrame ?? false) log('error ${err.type} ${err.description} for ${req.url}');
    },
    onReceivedHttpError: (_, req, res) {
      if (req.isForMainFrame ?? false) log('http ${res.statusCode} for ${req.url}');
    },
    onConsoleMessage: (_, msg) {
      if (msg.messageLevel == ConsoleMessageLevel.ERROR) log('console: ${msg.message}');
    },
    onWebViewCreated: (c) {
      controller = c;
      c.addJavaScriptHandler(
        handlerName: 'savr',
        callback: (args) {
          // The page's own scripts could call this handler too, so the
          // arguments are validated like any other untrusted input.
          if (args.length != 2 || args[0] is! String || args[1] is! String) return null;
          final body = args[1] as String;
          if (body.length > maxPayload) return null;
          final url = Uri.tryParse(args[0] as String);
          if (url == null || url.scheme != 'https' || !platform.ownsHost(url.host)) return null;
          log('captured ${url.path} (${body.length} bytes)${body.length < 200 ? ': $body' : ''}');
          Object? json;
          try {
            json = jsonDecode(body);
          } on FormatException {
            return null;
          }
          scraper.ingest(url, json, st);
          if (st.gotSearch && st.offers.isNotEmpty) {
            finishSoon();
          } else if (st.placeholder && !retried) {
            // On a brand-new session the first search can be answered with a
            // placeholder while the site's bot check issues its token. The
            // token exists by now, so one reload gets the real results.
            retried = true;
            log('placeholder response, reloading once');
            Timer(const Duration(milliseconds: 1200), () => controller?.reload());
          }
          return null;
        },
      );
    },
  );

  try {
    await view.run();
    await done.future.timeout(timeout, onTimeout: () {});
  } catch (_) {
    // Fall through: whatever was captured is still returned.
  } finally {
    settleTimer?.cancel();
    await view.dispose();
  }

  final offers = st.build();
  if (offers.isNotEmpty) return ScrapeOutcome(offers: offers, ok: true);
  return ScrapeOutcome(offers: const [], ok: st.gotSearch, reason: st.gotSearch ? 'no_results' : 'timeout');
}
