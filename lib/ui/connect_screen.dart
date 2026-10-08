import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../app_scope.dart';
import '../data/device/location_injection.dart';
import '../data/device/scrapers.dart';
import '../data/device/webview_runner.dart';
import '../theme/tokens.dart';
import 'widgets/common.dart';

/// Lists the platforms Savr can read live prices from and lets the user set
/// their delivery address on each one's own website, once.
class ConnectScreen extends StatelessWidget {
  const ConnectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final s = scope.settings;
    return Backdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Live prices')),
        body: ListenableBuilder(
          listenable: s,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.xxl),
            children: [
              Text('Set your delivery address on each app', style: context.t.titleMedium),
              const SizedBox(height: Space.xs),
              Text(
                'Prices and stock depend on the store near you. Pick your address once on each app\'s own site; '
                'Savr then reads the same prices you\'d see there. No login needed — Savr never sees passwords or payment details.',
                style: context.t.bodySmall,
              ),
              const SizedBox(height: Space.lg),
              Surface(
                padding: const EdgeInsets.symmetric(vertical: Space.xs),
                child: Column(
                  children: [
                    for (final sc in deviceScrapers.where((x) => s.isPlatformEnabled(x.platformId))) ...[
                      if (sc != deviceScrapers.first) const Divider(indent: Space.lg, endIndent: Space.lg),
                      ListTile(
                        leading: PlatformDot(sc.platform, size: 12),
                        minLeadingWidth: 12,
                        title: Text(sc.platform.name),
                        subtitle: Text(
                          s.isLocationSet(sc.platformId) ? 'Address set' : 'Not set — tap to choose',
                          style: context.t.bodySmall!.copyWith(
                            color: s.isLocationSet(sc.platformId) ? context.c.primary : context.c.inkMuted,
                          ),
                        ),
                        trailing: Icon(
                          s.isLocationSet(sc.platformId) ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
                          color: s.isLocationSet(sc.platformId) ? context.c.primary : context.c.inkMuted,
                        ),
                        onTap: () => Navigator.of(
                          context,
                        ).push(MaterialPageRoute<void>(builder: (_) => PlatformBrowserScreen(scraper: sc))),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: Space.lg),
              const InfoBanner(
                icon: Icons.shield_outlined,
                text:
                    'Each app opens in a locked-down browser inside Savr: only that app\'s own website can load, '
                    'and nothing you type there is read by Savr.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PlatformBrowserScreen extends StatefulWidget {
  const PlatformBrowserScreen({super.key, required this.scraper});
  final DeviceScraper scraper;

  @override
  State<PlatformBrowserScreen> createState() => _PlatformBrowserScreenState();
}

class _PlatformBrowserScreenState extends State<PlatformBrowserScreen> {
  double _progress = 0;

  @override
  Widget build(BuildContext context) {
    final p = widget.scraper.platform;
    final c = context.c;
    return Backdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text('Choose address on ${p.name}'),
          bottom: _progress < 1
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(2),
                  child: LinearProgressIndicator(value: _progress, minHeight: 2),
                )
              : null,
        ),
        body: InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri.uri(widget.scraper.homeUrl)),
          initialSettings: platformWebSettings(headless: false),
          // Pre-fill the Savr location so "detect my location" on the site
          // picks it up; the user only confirms the exact address.
          initialUserScripts: UnmodifiableListView([
            if (AppScope.of(context).settings.place case final place?)
              UserScript(
                source: locationScript(p.id, place),
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                forMainFrameOnly: true,
              ),
          ]),
          shouldOverrideUrlLoading: (_, action) async => guardNavigation(p, action),
          onProgressChanged: (_, v) => setState(() => _progress = v / 100),
        ),
        bottomNavigationBar: SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.md),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border(top: BorderSide(color: c.line)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Use ${p.name}\'s location button to pick your address, then tap Done.',
                    style: context.t.bodySmall,
                  ),
                ),
                const SizedBox(width: Space.md),
                FilledButton(
                  onPressed: () {
                    final scope = AppScope.of(context);
                    scope.settings.markLocationSet(p.id, true);
                    scope.repo.clearCache();
                    Navigator.pop(context);
                  },
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
