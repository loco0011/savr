import 'dart:convert';

import '../../core/place.dart';

/// Builds the document-start script that hands the user's Savr location to a
/// platform's own website, so nobody has to set an address on each app.
///
/// Two layers:
/// 1. A `navigator.geolocation` shim that answers with the Savr location.
///    Sites that "detect my location" pick it up, and the WebView never
///    touches the phone's real GPS (geolocation stays off natively).
/// 2. Where the site keeps the delivery point in a cookie / localStorage
///    entry, that entry is pre-filled before the site's scripts run.
///
/// Only coordinates and a short address are written. Nothing is read back.
String locationScript(String platformId, Place p) {
  final loc = jsonEncode({
    'lat': p.lat,
    'lng': p.lng,
    'name': p.name,
    'address': p.address,
    'city': p.city ?? '',
    'pin': p.pincode ?? '',
  });
  final specific = switch (platformId) {
    'blinkit' => _blinkit,
    'instamart' || 'swiggy' => _swiggy,
    'zepto' => _zepto,
    'bbnow' || 'bigbasket' => _bigbasket,
    _ => '',
  };
  return '''
(function(){
  if (window.__savrLoc) return; window.__savrLoc = true;
  var L = $loc;
  function ck(k, v){ try { document.cookie = k + '=' + encodeURIComponent(v) + ';path=/;max-age=31536000;SameSite=Lax'; } catch(e) {} }
  function ls(k, v){ try { localStorage.setItem(k, typeof v === 'string' ? v : JSON.stringify(v)); } catch(e) {} }
  try {
    var pos = { coords: { latitude: L.lat, longitude: L.lng, accuracy: 25, altitude: null, altitudeAccuracy: null, heading: null, speed: null }, timestamp: Date.now() };
    var geo = {
      getCurrentPosition: function(ok){ setTimeout(function(){ ok(pos); }, 0); },
      watchPosition: function(ok){ setTimeout(function(){ ok(pos); }, 0); return 1; },
      clearWatch: function(){}
    };
    Object.defineProperty(Navigator.prototype, 'geolocation', { get: function(){ return geo; }, configurable: true });
    if (navigator.permissions && navigator.permissions.query) {
      var oq = navigator.permissions.query.bind(navigator.permissions);
      navigator.permissions.query = function(d){
        if (d && d.name === 'geolocation') return Promise.resolve({ state: 'granted', status: 'granted', onchange: null, addEventListener: function(){}, removeEventListener: function(){} });
        return oq(d);
      };
    }
  } catch(e) {}
  $specific
})();
''';
}

const _blinkit = r'''
  ck('gr_1_lat', L.lat); ck('gr_1_lon', L.lng);
  ck('gr_1_locality', L.name); ck('gr_1_landmark', 'undefined');
  ls('location', { coords: { isDefault: false, name: L.name, landmark: null, lat: L.lat, lon: L.lng, locality: L.name, cityName: L.city, isTopCity: true } });
''';

const _swiggy = r'''
  ck('userLocation', JSON.stringify({ address: L.address, lat: String(L.lat), lng: String(L.lng), id: '', annotation: '', name: '' }));
''';

const _zepto = r'''
  ck('latitude', L.lat); ck('longitude', L.lng);
''';

/// BigBasket keeps the delivery point as base64("lat|lng").
const _bigbasket = r'''
  try { document.cookie = '_bb_lat_long=' + btoa(L.lat + '|' + L.lng) + ';path=/;max-age=31536000;SameSite=Lax'; } catch(e) {}
  if (L.pin) ck('_bb_pin_code', L.pin);
''';
