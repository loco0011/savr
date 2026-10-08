import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/address.dart';
import '../core/link_parser.dart';
import '../core/models.dart';
import '../core/place.dart';

/// User + admin settings.
///
/// Non-sensitive preferences live in SharedPreferences. Anything secret (API
/// key) lives only in the platform keystore via flutter_secure_storage and is
/// never cached in memory longer than a request (OWASP MASVS-STORAGE-1).
class Settings extends ChangeNotifier {
  Settings._(this._prefs);

  static const _secure = FlutterSecureStorage();
  static const _kApiKey = 'savr.backend.apiKey';

  final SharedPreferences _prefs;

  static Future<Settings> load() async => Settings._(await SharedPreferences.getInstance());

  // ---- Appearance ----------------------------------------------------------
  ThemeMode get themeMode => ThemeMode.values.byName(_prefs.getString('themeMode') ?? 'system');
  set themeMode(ThemeMode m) => _set(() => _prefs.setString('themeMode', m.name));

  // ---- Location ------------------------------------------------------------
  /// The one location the whole app uses: live prices on every platform and
  /// the default ride pickup.
  Place? get place => Place.decode(_prefs.getString('place'));

  /// Saves [p], remembers it in recents and syncs the pincode. Returns true
  /// when the location actually changed.
  bool setPlace(Place p) {
    final changed = place != p;
    _prefs.setString('place', p.encode());
    if (p.pincode != null) _prefs.setString('pincode', p.pincode!);
    addRecentPlace(p);
    return changed;
  }

  List<Place> get recentPlaces =>
      (_prefs.getStringList('recentPlaces') ?? const [])
          .map(Place.decode)
          .whereType<Place>()
          .where((p) => p.name != 'Current location') // legacy unnamed GPS points
          .toList();

  void addRecentPlace(Place p) {
    final list = [p, ...recentPlaces.where((r) => r != p)].take(5).map((x) => x.encode()).toList();
    _set(() => _prefs.setStringList('recentPlaces', list));
  }

  // ---- Account (demo) ------------------------------------------------------
  /// Signed-in user id. Demo only: any id/password is accepted and nothing
  /// leaves the phone. The password is never stored.
  /// TODO(backend): replace with real authentication.
  String? get userId => _prefs.getString('account.id');
  String? get displayName => _prefs.getString('account.name') ?? userId;
  bool get isLoggedIn => userId != null;

  /// First launch shows the welcome / login screen once.
  bool get onboarded => _prefs.getBool('onboarded') ?? false;
  void markOnboarded() => _set(() => _prefs.setBool('onboarded', true));

  void logIn(String id, {String? name}) {
    _prefs.setString('account.id', id);
    if (name != null && name.isNotEmpty) _prefs.setString('account.name', name);
    _set(() => _prefs.setBool('onboarded', true));
  }

  void logOut() {
    _prefs.remove('account.name');
    _set(() => _prefs.remove('account.id'));
  }

  // ---- Saved addresses -----------------------------------------------------
  List<SavedAddress> get addresses =>
      (_prefs.getStringList('addresses') ?? const []).map(SavedAddress.decode).whereType<SavedAddress>().toList();

  String? get activeAddressId => _prefs.getString('activeAddress');

  SavedAddress? get activeAddress {
    final id = activeAddressId;
    return id == null ? null : addresses.where((a) => a.id == id).firstOrNull;
  }

  /// Adds or replaces [a] (by id) and makes it the active address. Returns
  /// true when the live-price location changed.
  bool saveAddress(SavedAddress a) {
    final list = [for (final x in addresses) x.id == a.id ? a : x];
    if (!list.any((x) => x.id == a.id)) list.insert(0, a);
    _prefs.setStringList('addresses', list.take(12).map((x) => x.encode()).toList());
    return useAddress(a);
  }

  bool useAddress(SavedAddress a) {
    _prefs.setString('activeAddress', a.id);
    return setPlace(a.pin);
  }

  void deleteAddress(String id) {
    _prefs.setStringList('addresses', addresses.where((a) => a.id != id).map((x) => x.encode()).toList());
    if (activeAddressId == id) _prefs.remove('activeAddress');
    notifyListeners();
  }

  // ---- Saved searches & savings --------------------------------------------
  List<SavedSearch> get savedSearches =>
      (_prefs.getStringList('savedSearches') ?? const []).map(SavedSearch.decode).whereType<SavedSearch>().toList();

  bool isSaved(String query) => savedSearches.any((s) => s.query.toLowerCase() == query.toLowerCase());

  void toggleSaved(SavedSearch s) {
    final rest = savedSearches.where((x) => x.query.toLowerCase() != s.query.toLowerCase()).toList();
    final list = isSaved(s.query) ? rest : [s, ...rest].take(30).toList();
    _set(() => _prefs.setStringList('savedSearches', list.map((x) => jsonEncode(x.toJson())).toList()));
  }

  /// Rupees saved by picking the cheapest app (vs the priciest) on deals the
  /// user opened from Savr.
  double get totalSaved => _prefs.getDouble('savings.total') ?? 0;
  int get dealsOpened => _prefs.getInt('savings.deals') ?? 0;

  void recordDeal(double saved) {
    if (!saved.isFinite || saved < 0 || saved > 100000) return;
    _prefs.setDouble('savings.total', totalSaved + saved);
    _set(() => _prefs.setInt('savings.deals', dealsOpened + 1));
  }

  // ---- Result defaults -----------------------------------------------------
  bool get hideOutOfStock => _prefs.getBool('hideOutOfStock') ?? true;
  set hideOutOfStock(bool v) => _set(() => _prefs.setBool('hideOutOfStock', v));

  String? get pincode => _prefs.getString('pincode');
  bool setPincode(String? v) {
    if (v == null || v.isEmpty) {
      _set(() => _prefs.remove('pincode'));
      return true;
    }
    if (!RegExp(r'^[1-9]\d{5}$').hasMatch(v)) return false;
    _set(() => _prefs.setString('pincode', v));
    return true;
  }

  // ---- Comparison defaults -------------------------------------------------
  bool get includeFees => _prefs.getBool('includeFees') ?? true;
  set includeFees(bool v) => _set(() => _prefs.setBool('includeFees', v));

  bool get showUnitPrice => _prefs.getBool('showUnitPrice') ?? true;
  set showUnitPrice(bool v) => _set(() => _prefs.setBool('showUnitPrice', v));

  // ---- Platforms (admin) ---------------------------------------------------
  Set<String> get _disabled => (_prefs.getStringList('disabledPlatforms') ?? const []).toSet();
  bool isPlatformEnabled(String id) => !_disabled.contains(id);
  void setPlatformEnabled(String id, bool on) {
    final d = _disabled;
    on ? d.remove(id) : d.add(id);
    _set(() => _prefs.setStringList('disabledPlatforms', d.toList()));
  }

  // ---- Data source (admin) -------------------------------------------------
  DataMode get dataMode {
    final raw = _prefs.getString('dataMode');
    return DataMode.values.where((m) => m.name == raw).firstOrNull ?? DataMode.device;
  }

  set dataMode(DataMode m) => _set(() => _prefs.setString('dataMode', m.name));

  // ---- On-device fetching: per-platform location step ----------------------
  /// When the user last chose a delivery address on that platform's own site.
  DateTime? locationSetAt(String platformId) {
    final ms = _prefs.getInt('locSet.$platformId');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// A platform is ready once the Savr location is set (it's injected into
  /// the site), or after the older manual per-site step.
  bool isLocationSet(String platformId) => place != null || locationSetAt(platformId) != null;

  void markLocationSet(String platformId, bool set) => _set(
    () => set
        ? _prefs.setInt('locSet.$platformId', DateTime.now().millisecondsSinceEpoch)
        : _prefs.remove('locSet.$platformId'),
  );

  Uri? get backendUrl {
    final s = _prefs.getString('backendUrl');
    return s == null ? null : validateBackendUrl(s);
  }

  /// Returns an error message, or null on success.
  String? setBackendUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      _set(() => _prefs.remove('backendUrl'));
      return null;
    }
    final u = validateBackendUrl(trimmed);
    if (u == null) return 'Enter a valid https:// URL without credentials.';
    _set(() => _prefs.setString('backendUrl', u.toString()));
    return null;
  }

  static Uri? validateBackendUrl(String s) {
    if (s.length > 512) return null;
    final u = Uri.tryParse(s);
    if (u == null || u.scheme != 'https' || u.host.isEmpty) return null;
    if (u.userInfo.isNotEmpty || u.hasFragment || u.hasQuery) return null;
    return u;
  }

  Future<String?> readApiKey() => _secure.read(key: _kApiKey);
  Future<bool> get hasApiKey async => (await readApiKey())?.isNotEmpty ?? false;
  Future<void> writeApiKey(String? v) async {
    if (v == null || v.isEmpty) {
      await _secure.delete(key: _kApiKey);
    } else {
      await _secure.write(key: _kApiKey, value: v);
    }
    notifyListeners();
  }

  // ---- Recent searches -----------------------------------------------------
  List<String> get recent => _prefs.getStringList('recent') ?? const [];
  void addRecent(String q) {
    final clean = sanitizeQuery(q);
    if (clean.isEmpty) return;
    final list = [clean, ...recent.where((r) => r.toLowerCase() != clean.toLowerCase())].take(8).toList();
    _set(() => _prefs.setStringList('recent', list));
  }

  void clearRecent() => _set(() => _prefs.remove('recent'));

  /// Wipes every preference and secret. Used by the admin "factory reset".
  Future<void> resetAll() async {
    await _prefs.clear();
    await _secure.deleteAll();
    notifyListeners();
  }

  void _set(Future<bool> Function() write) {
    write();
    notifyListeners();
  }
}
