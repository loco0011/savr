import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Hardened GET used for every outbound request.
///
/// * HTTPS only (OWASP M5 — insecure communication).
/// * Redirects are followed manually and each hop must pass [allowHost], so a
///   trusted short link can't bounce us to an arbitrary host.
/// * Hard timeout and response size cap to avoid hangs / memory exhaustion.
/// * No cookies, no credentials unless explicitly passed in [headers].
class SafeHttp {
  SafeHttp({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const maxBytes = 2 * 1024 * 1024;
  static const maxRedirects = 4;

  Future<({int status, String body, Uri finalUrl})> get(
    Uri url, {
    required bool Function(String host) allowHost,
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 12),
  }) async {
    var current = url;
    for (var hop = 0; hop <= maxRedirects; hop++) {
      if (current.scheme != 'https') throw const HttpException('Only HTTPS is allowed');
      if (!allowHost(current.host)) throw const HttpException('Host not allowed');

      final req = http.Request('GET', current)
        ..followRedirects = false
        ..headers.addAll({'Accept': 'application/json, text/html;q=0.8', ...headers});

      final res = await _client.send(req).timeout(timeout);
      if (res.isRedirect || (res.statusCode >= 300 && res.statusCode < 400)) {
        final loc = res.headers['location'];
        await res.stream.drain<void>();
        if (loc == null) throw const HttpException('Redirect without location');
        current = current.resolve(loc);
        continue;
      }

      final bytes = <int>[];
      await for (final chunk in res.stream.timeout(timeout)) {
        bytes.addAll(chunk);
        if (bytes.length > maxBytes) throw const HttpException('Response too large');
      }
      return (status: res.statusCode, body: utf8.decode(bytes, allowMalformed: true), finalUrl: current);
    }
    throw const HttpException('Too many redirects');
  }

  void close() => _client.close();
}
