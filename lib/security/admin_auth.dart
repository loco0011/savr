import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Gate for the hidden admin panel.
///
/// The 7-tap gesture only *reveals* the gate — it is not a security control.
/// Access requires a passcode the owner sets on first use:
/// * No hard-coded credentials (OWASP M1 / A07).
/// * Stored as PBKDF2-HMAC-SHA512 with a 16-byte random salt and 210k
///   iterations (OWASP Password Storage Cheat Sheet), in the platform keystore.
/// * Constant-time comparison.
/// * Exponential lock-out after repeated failures, persisted so it survives
///   app restarts.
/// * Session auto-expires after [idleTimeout] or when the app is backgrounded.
class AdminAuth extends ChangeNotifier {
  AdminAuth({FlutterSecureStorage? storage, this.iterations = 210000})
    : _store = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _store;
  final int iterations;

  static const _kHash = 'savr.admin.hash';
  static const _kFails = 'savr.admin.fails';
  static const _kLockUntil = 'savr.admin.lockUntil';
  static const minLength = 6;
  static const freeAttempts = 3;
  static const idleTimeout = Duration(minutes: 3);

  DateTime? _unlockedAt;
  DateTime _lastActivity = DateTime.fromMillisecondsSinceEpoch(0);

  bool get isUnlocked {
    if (_unlockedAt == null) return false;
    if (DateTime.now().difference(_lastActivity) > idleTimeout) {
      lock();
      return false;
    }
    return true;
  }

  void touch() {
    if (_unlockedAt != null) _lastActivity = DateTime.now();
  }

  void lock() {
    if (_unlockedAt == null) return;
    _unlockedAt = null;
    notifyListeners();
  }

  Future<bool> get isConfigured async => (await _store.read(key: _kHash)) != null;

  /// Remaining lock-out, or null if attempts are allowed now.
  Future<Duration?> lockRemaining() async {
    final until = int.tryParse(await _store.read(key: _kLockUntil) ?? '');
    if (until == null) return null;
    final left = DateTime.fromMillisecondsSinceEpoch(until).difference(DateTime.now());
    return left.isNegative ? null : left;
  }

  static String? validateNew(String pass) {
    if (pass.length < minLength) return 'Use at least $minLength characters.';
    if (pass.length > 64) return 'Use 64 characters or fewer.';
    if (RegExp(r'^(\d)\1+$').hasMatch(pass)) return 'Avoid repeated characters.';
    const weak = ['123456', '1234567', '12345678', '654321', '000000', '111111', 'password', 'qwerty', 'admin123'];
    if (weak.contains(pass.toLowerCase())) return 'That passcode is too common.';
    return null;
  }

  Future<void> setPasscode(String pass) async {
    final err = validateNew(pass);
    if (err != null) throw ArgumentError(err);
    final salt = _randomBytes(16);
    final hash = await _derive(pass, salt, iterations);
    await _store.write(
      key: _kHash,
      value: jsonEncode({
        'v': 1,
        'alg': 'pbkdf2-sha512',
        'it': iterations,
        's': base64Encode(salt),
        'h': base64Encode(hash),
      }),
    );
    await _resetFailures();
    _grant();
  }

  /// Returns null on success, else a user-facing reason.
  Future<String?> verify(String pass) async {
    final left = await lockRemaining();
    if (left != null) return 'Too many attempts. Try again in ${_fmt(left)}.';

    final raw = await _store.read(key: _kHash);
    if (raw == null) return 'No passcode set.';
    final rec = jsonDecode(raw) as Map<String, dynamic>;
    final salt = base64Decode(rec['s'] as String);
    final expected = base64Decode(rec['h'] as String);
    final actual = await _derive(pass, salt, rec['it'] as int, sha512: rec['alg'] != 'pbkdf2-sha256');

    if (_constantTimeEquals(actual, expected)) {
      await _resetFailures();
      _grant();
      return null;
    }

    final fails = (int.tryParse(await _store.read(key: _kFails) ?? '') ?? 0) + 1;
    await _store.write(key: _kFails, value: '$fails');
    if (fails >= freeAttempts) {
      // 30s, 60s, 120s … capped at 1 hour.
      final secs = min(3600, 30 * pow(2, fails - freeAttempts).toInt());
      final until = DateTime.now().add(Duration(seconds: secs));
      await _store.write(key: _kLockUntil, value: '${until.millisecondsSinceEpoch}');
      return 'Incorrect passcode. Locked for ${_fmt(Duration(seconds: secs))}.';
    }
    return 'Incorrect passcode. ${freeAttempts - fails} attempt${freeAttempts - fails == 1 ? '' : 's'} left before lock-out.';
  }

  Future<void> changePasscode(String newPass) async {
    if (!isUnlocked) throw StateError('Locked');
    await setPasscode(newPass);
  }

  /// Removes the admin passcode. Used by factory reset only.
  Future<void> clear() async {
    await _store.delete(key: _kHash);
    await _resetFailures();
    lock();
  }

  void _grant() {
    _unlockedAt = DateTime.now();
    _lastActivity = _unlockedAt!;
    notifyListeners();
  }

  Future<void> _resetFailures() async {
    await _store.delete(key: _kFails);
    await _store.delete(key: _kLockUntil);
  }

  /// PBKDF2 runs in a background isolate so the work factor doesn't jank the UI.
  static Future<List<int>> _derive(String pass, List<int> salt, int iterations, {bool sha512 = true}) =>
      Isolate.run(() async {
        final kdf = Pbkdf2(macAlgorithm: sha512 ? Hmac.sha512() : Hmac.sha256(), iterations: iterations, bits: 256);
        final key = await kdf.deriveKeyFromPassword(password: pass, nonce: salt);
        return key.extractBytes();
      });

  static List<int> _randomBytes(int n) {
    final r = Random.secure();
    return List<int>.generate(n, (_) => r.nextInt(256));
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  static String _fmt(Duration d) =>
      d.inMinutes >= 1 ? '${d.inMinutes + (d.inSeconds % 60 > 0 ? 1 : 0)} min' : '${d.inSeconds.clamp(1, 59)} s';
}
