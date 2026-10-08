import '../core/link_parser.dart';
import '../core/platforms.dart';
import 'safe_http.dart';

/// Recovers a product name for links whose URL has no readable slug (short
/// links like amzn.in/d/xyz). Only fetches HTTPS URLs on platform hosts, and
/// only reads `og:title` / `<title>` — nothing is executed or rendered.
class TitleResolver {
  TitleResolver({SafeHttp? http}) : _http = http ?? SafeHttp();
  final SafeHttp _http;

  Future<ParsedLink?> resolve(ParsedLink link) async {
    try {
      final res = await _http.get(
        link.url,
        allowHost: (h) => kPlatforms.any((p) => p.ownsHost(h)),
        headers: {'User-Agent': 'Mozilla/5.0 (Linux; Android 14) Savr/1.0'},
        timeout: const Duration(seconds: 8),
      );
      if (res.status != 200) return null;

      // The redirect target often has the slug we couldn't see before.
      final reparsed = LinkParser.parse(res.finalUrl.toString());
      if (reparsed?.name != null) return reparsed;

      final title = _extractTitle(res.body);
      if (title == null) return null;
      return ParsedLink(
        url: res.finalUrl,
        platform: reparsed?.platform ?? link.platform,
        vertical: link.vertical,
        name: title,
      );
    } catch (_) {
      return null;
    }
  }

  static String? _extractTitle(String html) {
    final og = RegExp(
      r'''<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']{3,200})["']''',
      caseSensitive: false,
    ).firstMatch(html);
    final t =
        og?.group(1) ?? RegExp(r'<title[^>]*>([^<]{3,200})</title>', caseSensitive: false).firstMatch(html)?.group(1);
    if (t == null) return null;
    var s = _decodeEntities(t);
    // Drop store suffixes like " | Blinkit" or ": Amazon.in: Electronics".
    s = s.split(RegExp(r'\s[|:–-]\s')).first;
    s = s.replaceFirst(RegExp(r'^(buy|order)\s+', caseSensitive: false), '');
    s = s.replaceFirst(RegExp(r'\s+online.*$', caseSensitive: false), '');
    s = sanitizeQuery(s);
    return s.length >= 3 ? s : null;
  }

  static String _decodeEntities(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ');
}
