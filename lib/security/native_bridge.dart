import 'dart:async';

import 'package:flutter/services.dart';

/// Thin wrapper over the Android MethodChannel in MainActivity.kt.
/// All calls are no-ops on platforms that don't implement the channel.
abstract final class NativeBridge {
  static const _ch = MethodChannel('in.savr/native');
  static final _shared = StreamController<String>.broadcast();
  static bool _init = false;

  /// Text shared to Savr from another app ("Share → Savr" in Blinkit etc).
  static Stream<String> get sharedText {
    if (!_init) {
      _init = true;
      _ch.setMethodCallHandler((call) async {
        if (call.method == 'sharedText' && call.arguments is String) _shared.add(call.arguments as String);
      });
    }
    return _shared.stream;
  }

  static Future<String?> initialSharedText() async {
    try {
      return await _ch.invokeMethod<String>('initialSharedText');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Which of [packages] are installed and launchable.
  static Future<Set<String>> installedPackages(List<String> packages) async {
    try {
      final r = await _ch.invokeListMethod<String>('installedPackages', packages);
      return {...?r};
    } on MissingPluginException {
      return const {};
    } on PlatformException {
      return const {};
    }
  }

  /// Opens [url] inside [package] (e.g. a Blinkit product page in the
  /// Blinkit app). False if that app can't handle the link.
  static Future<bool> openInPackage(Uri url, String package) async {
    try {
      return await _ch.invokeMethod<bool>('openInPackage', {'url': url.toString(), 'package': package}) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Opens an installed app's launcher screen. False if it isn't installed.
  static Future<bool> launchPackage(String package) async {
    try {
      return await _ch.invokeMethod<bool>('launchPackage', package) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static int _secureHolders = 0;

  /// Blocks screenshots / recents thumbnails (FLAG_SECURE) while any holder
  /// (admin gate, admin panel) is on screen. Reference-counted so route
  /// replacement order can't briefly clear the flag.
  static void acquireSecure() {
    if (_secureHolders++ == 0) _setSecure(true);
  }

  static void releaseSecure() {
    if (_secureHolders == 0) return;
    if (--_secureHolders == 0) _setSecure(false);
  }

  static Future<void> _setSecure(bool on) async {
    try {
      await _ch.invokeMethod<void>('setSecure', on);
    } on MissingPluginException {
      // Not Android.
    } on PlatformException {
      // Ignore.
    }
  }
}
