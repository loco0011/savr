import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../core/address.dart';
import '../core/app_launcher.dart';
import '../core/models.dart';
import '../core/platforms.dart';
import '../data/device/scrapers.dart';
import '../theme/tokens.dart';
import 'address_editor.dart';
import 'admin/admin_gate.dart';
import 'connect_screen.dart';
import 'location_picker.dart';
import 'login_screen.dart';
import 'results_screen.dart';
import 'widgets/common.dart';

/// Account, addresses, saved searches and every setting.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const _tapsToUnlock = 7;
  static const _tapWindow = Duration(seconds: 3);

  int _taps = 0;
  DateTime _firstTap = DateTime.fromMillisecondsSinceEpoch(0);

  void _onVersionTap() {
    final now = DateTime.now();
    if (now.difference(_firstTap) > _tapWindow) {
      _taps = 0;
      _firstTap = now;
    }
    _taps++;
    HapticFeedback.selectionClick();
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    if (_taps >= _tapsToUnlock) {
      _taps = 0;
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AdminGate()));
    } else if (_taps >= 4) {
      final left = _tapsToUnlock - _taps;
      messenger.showSnackBar(
        SnackBar(content: Text('$left tap${left == 1 ? '' : 's'} away'), duration: const Duration(milliseconds: 700)),
      );
    }
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('Your saved addresses and searches stay on this phone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Log out')),
        ],
      ),
    );
    if (ok == true && mounted) AppScope.of(context).settings.logOut();
  }

  Future<void> _deleteAddress(SavedAddress a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${a.title}?'),
        content: Text(a.line),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true && mounted) AppScope.of(context).settings.deleteAddress(a.id);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final s = scope.settings;
    final c = context.c;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => ListView(
        padding: EdgeInsets.zero,
        children: [
          _Header(onLogout: _confirmLogout),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, Space.xxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ---- Addresses
                SectionLabel(
                  'Saved addresses',
                  trailing: TextButton.icon(
                    onPressed: () => editAddress(context),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add'),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  ),
                ),
                if (s.addresses.isEmpty)
                  _EmptyCard(
                    icon: Icons.add_home_work_outlined,
                    title: 'Add your home or work address',
                    body: 'Drop an exact pin so prices, stock and delivery time match what the apps show you.',
                    onTap: () => editAddress(context),
                  )
                else
                  Surface(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < s.addresses.length; i++) ...[
                          if (i > 0) const Divider(indent: 60),
                          AddressTile(
                            address: s.addresses[i],
                            active: s.addresses[i].id == s.activeAddressId,
                            onTap: () => applyAddress(context, s.addresses[i]),
                            trailing: PopupMenuButton<String>(
                              icon: Icon(Icons.more_vert_rounded, color: c.inkMuted),
                              onSelected: (v) => v == 'edit'
                                  ? editAddress(context, existing: s.addresses[i])
                                  : _deleteAddress(s.addresses[i]),
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'edit', child: Text('Edit')),
                                PopupMenuItem(value: 'delete', child: Text('Delete')),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: Space.xl),

                // ---- Saved searches
                const SectionLabel('Saved searches'),
                if (s.savedSearches.isEmpty)
                  const _EmptyCard(
                    icon: Icons.bookmark_border_rounded,
                    title: 'Nothing saved yet',
                    body: 'Tap the bookmark on any results page to re-check its price in one tap.',
                  )
                else
                  Surface(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < s.savedSearches.length && i < 6; i++) ...[
                          if (i > 0) const Divider(indent: 60),
                          _SavedRow(search: s.savedSearches[i]),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: Space.xl),

                // ---- Preferences
                const SectionLabel('Preferences'),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_rounded), label: Text('Auto')),
                      ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_rounded), label: Text('Light')),
                      ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_rounded), label: Text('Dark')),
                    ],
                    selected: {s.themeMode},
                    onSelectionChanged: (v) => s.themeMode = v.first,
                  ),
                ),
                const SizedBox(height: Space.md),
                _Group(
                  children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.inventory_2_outlined),
                      title: const Text('Hide out-of-stock items'),
                      subtitle: const Text('Default for every search'),
                      value: s.hideOutOfStock,
                      onChanged: (v) => s.hideOutOfStock = v,
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.local_shipping_outlined),
                      title: const Text('Include delivery fee'),
                      subtitle: const Text('Rank offers by what you actually pay'),
                      value: s.includeFees,
                      onChanged: (v) => s.includeFees = v,
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.scale_outlined),
                      title: const Text('Show price per unit'),
                      subtitle: const Text('Per 100 g, 100 ml or piece'),
                      value: s.showUnitPrice,
                      onChanged: (v) => s.showUnitPrice = v,
                    ),
                  ],
                ),
                const SizedBox(height: Space.xl),

                // ---- Apps
                const SectionLabel('Apps on this phone'),
                const _AppsCard(),
                const SizedBox(height: Space.md),
                _Group(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.storefront_outlined),
                      title: const Text('Fine-tune address on each app'),
                      subtitle: Text(
                        s.place != null
                            ? 'Optional. Your address is applied to all ${deviceScrapers.length} live apps automatically'
                            : 'Set an address first',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () =>
                          Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ConnectScreen())),
                    ),
                  ],
                ),
                const SizedBox(height: Space.xl),

                // ---- Privacy & about
                const SectionLabel('Privacy & about'),
                _Group(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.history_rounded),
                      title: const Text('Clear search history'),
                      subtitle: Text(s.recent.isEmpty ? 'Nothing saved' : '${s.recent.length} recent searches'),
                      enabled: s.recent.isNotEmpty,
                      onTap: () {
                        s.clearRecent();
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Search history cleared')));
                      },
                    ),
                    const ListTile(
                      leading: Icon(Icons.shield_outlined),
                      title: Text('Your data stays on this phone'),
                      subtitle: Text('No tracking. Savr never sees your logins or payments on other apps.'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.info_outline_rounded),
                      title: const Text('Version'),
                      trailing: Text(scope.version, style: context.t.bodyMedium!.copyWith(color: c.inkMuted)),
                      onTap: _onVersionTap,
                    ),
                    ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: const Text('Open-source licences'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () =>
                          showLicensePage(context: context, applicationName: 'Savr', applicationVersion: scope.version),
                    ),
                  ],
                ),
                const SizedBox(height: Space.lg),
                Text(
                  'Prices are read live from each app\'s website for your address and can differ from the app '
                  '(app-only offers, memberships, fees). Savr is not affiliated with the apps it compares; all '
                  'trademarks belong to their owners.',
                  style: context.t.bodySmall!.copyWith(fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onLogout});
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).settings;
    final top = MediaQuery.paddingOf(context).top;
    final name = s.displayName;
    final initials = name
        ?.trim()
        .split(RegExp(r'[\s@._-]+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
    const white70 = Color(0xC7FFFFFF);
    return Container(
      padding: EdgeInsets.fromLTRB(Space.lg, top + Space.lg, Space.lg, Space.lg),
      decoration: BoxDecoration(
        gradient: context.c.hero,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(Radii.xxl)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                ),
                child: initials == null || initials.isEmpty
                    ? const Icon(Icons.person_rounded, color: Colors.white, size: 30)
                    : Text(initials, style: context.t.titleLarge!.copyWith(color: Colors.white)),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name ?? 'Guest',
                      style: context.t.titleLarge!.copyWith(color: Colors.white),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      s.isLoggedIn
                          ? (s.activeAddress == null ? 'No address yet' : 'Delivering to ${s.activeAddress!.title}')
                          : 'Log in to keep your addresses & savings',
                      style: context.t.bodySmall!.copyWith(color: white70),
                    ),
                  ],
                ),
              ),
              if (s.isLoggedIn)
                IconButton(
                  tooltip: 'Log out',
                  onPressed: onLogout,
                  icon: const Icon(Icons.logout_rounded, color: Colors.white),
                )
              else
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF07402F)),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const LoginScreen()),
                  ),
                  child: const Text('Log in'),
                ),
            ],
          ),
          const SizedBox(height: Space.lg),
          Container(
            padding: const EdgeInsets.symmetric(vertical: Space.md),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(Radii.lg),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: Row(
              children: [
                _Stat(value: inr(s.totalSaved.roundToDouble()), label: 'saved with Savr'),
                _divider(),
                _Stat(value: '${s.dealsOpened}', label: 'deals opened'),
                _divider(),
                _Stat(value: '${s.savedSearches.length}', label: 'saved searches'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(width: 1, height: 32, color: Colors.white.withValues(alpha: 0.18));
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: context.t.titleMedium!.copyWith(color: Colors.white, fontWeight: FontWeight.w700, fontFeatures: tabular),
          maxLines: 1,
        ),
        Text(
          label,
          textAlign: TextAlign.center,
          style: context.t.labelSmall!.copyWith(color: const Color(0xC7FFFFFF), letterSpacing: 0),
        ),
      ],
    ),
  );
}

class _SavedRow extends StatelessWidget {
  const _SavedRow({required this.search});
  final SavedSearch search;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final p = search.platformId == null ? null : kPlatformById[search.platformId];
    final vertical = Vertical.values.where((v) => v.name == search.vertical).firstOrNull ?? Vertical.quick;
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ResultsScreen(query: SearchQuery(text: search.query, vertical: vertical)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.md),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: c.primarySoft, shape: BoxShape.circle),
              child: Icon(Icons.bookmark_rounded, size: 18, color: c.primary),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(search.query, style: context.t.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    search.bestPrice == null
                        ? vertical.label
                        : 'Was ${inr(search.bestPrice!)}${p == null ? '' : ' on ${p.name}'} · tap to re-check',
                    style: context.t.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.refresh_rounded, color: c.primary, size: 20),
          ],
        ),
      ),
    );
  }
}

class _AppsCard extends StatelessWidget {
  const _AppsCard();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: AppLauncher.installed,
    builder: (context, apps, _) {
      final ps = kPlatforms.where((p) => kAndroidPackages.containsKey(p.id) && !p.id.endsWith('now')).toList();
      final installed = ps.where((p) => apps.contains(p.id)).toList();
      return Surface(
        padding: const EdgeInsets.all(Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              installed.isEmpty ? 'No comparison apps found' : '${installed.length} apps installed',
              style: context.t.titleSmall,
            ),
            Text(
              'Results open straight in these apps. Others open on the web.',
              style: context.t.bodySmall,
            ),
            if (installed.isNotEmpty) ...[
              const SizedBox(height: Space.md),
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  for (final p in installed)
                    Tooltip(message: p.name, child: PlatformBadge(p, size: 34)),
                ],
              ),
            ],
          ],
        ),
      );
    },
  );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.icon, required this.title, required this.body, this.onTap});
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Surface(
      onTap: onTap,
      padding: const EdgeInsets.all(Space.md),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(Radii.md)),
            child: Icon(icon, color: c.inkMuted),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.t.titleSmall),
                Text(body, style: context.t.bodySmall),
              ],
            ),
          ),
          if (onTap != null) Icon(Icons.chevron_right_rounded, color: c.inkMuted),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Surface(
    padding: const EdgeInsets.symmetric(vertical: Space.xs),
    child: Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const Divider(indent: Space.lg, endIndent: Space.lg),
          children[i],
        ],
      ],
    ),
  );
}
