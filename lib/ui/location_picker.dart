import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../app_scope.dart';
import '../core/address.dart';
import '../core/place.dart';
import '../data/geo.dart';
import '../theme/tokens.dart';
import 'address_editor.dart';
import 'widgets/common.dart';

/// Lets the user pick a saved address (or add one) as the app-wide
/// location. Returns the chosen place.
Future<Place?> changeAppLocation(BuildContext context) async {
  final settings = AppScope.of(context).settings;
  if (settings.addresses.isEmpty) {
    final a = await editAddress(context);
    return a?.pin;
  }
  final a = await showModalBottomSheet<SavedAddress>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _AddressSheet(),
  );
  return a?.pin;
}

/// Makes [a] the active address (saving it first if [save]) and resets the
/// platforms' browser data when the location really changed.
Future<void> applyAddress(BuildContext context, SavedAddress a, {bool save = false}) async {
  final scope = AppScope.of(context);
  final changed = save ? scope.settings.saveAddress(a) : scope.settings.useAddress(a);
  if (!changed) return;
  // Sites cache the store for the old address; start them fresh so the new
  // pin is the only location they see.
  scope.repo.clearCache();
  try {
    await CookieManager.instance().deleteAllCookies();
    await WebStorageManager.instance().deleteAllData();
  } catch (_) {
    // Not fatal: the injected location still applies on the next load.
  }
}

class _AddressSheet extends StatelessWidget {
  const _AddressSheet();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = AppScope.of(context).settings;
    final list = s.addresses;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
          children: [
            Text('Deliver to', style: context.t.titleMedium),
            const SizedBox(height: 2),
            Text('Prices, stock and delivery time depend on this address.', style: context.t.bodySmall),
            const SizedBox(height: Space.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final a = await editAddress(context, useGps: true);
                      if (context.mounted) Navigator.pop(context, a);
                    },
                    icon: Icon(Icons.my_location_rounded, size: 18, color: c.primary),
                    label: const Text('Current location'),
                  ),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () async {
                      final a = await editAddress(context);
                      if (context.mounted) Navigator.pop(context, a);
                    },
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add address'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.lg),
            const SectionLabel('Saved addresses'),
            Surface(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < list.length; i++) ...[
                    if (i > 0) const Divider(indent: 60),
                    AddressTile(
                      address: list[i],
                      active: list[i].id == s.activeAddressId,
                      onTap: () async {
                        await applyAddress(context, list[i]);
                        if (context.mounted) Navigator.pop(context, list[i]);
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One saved address row: label icon, title, full line, active tick.
class AddressTile extends StatelessWidget {
  const AddressTile({super.key, required this.address, required this.active, this.onTap, this.trailing});
  final SavedAddress address;
  final bool active;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.md),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: active ? c.primarySoft : c.surfaceAlt, shape: BoxShape.circle),
              child: Icon(addressIcon(address.label), size: 18, color: active ? c.primary : c.inkMuted),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: Text(address.title, style: context.t.titleSmall, overflow: TextOverflow.ellipsis)),
                      if (active) ...[const SizedBox(width: 6), const Tag('IN USE')],
                    ],
                  ),
                  Text(address.line, style: context.t.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// Full-screen place search with "use current location" and recents.
Future<Place?> pickPlace(
  BuildContext context, {
  required String title,
  String? subtitle,
  String hint = 'Search area, street or landmark',
  bool allowCurrent = true,
}) => Navigator.of(context).push<Place>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _PickerScreen(title: title, subtitle: subtitle, hint: hint, allowCurrent: allowCurrent),
  ),
);

class _PickerScreen extends StatefulWidget {
  const _PickerScreen({required this.title, required this.hint, required this.allowCurrent, this.subtitle});
  final String title;
  final String? subtitle;
  final String hint;
  final bool allowCurrent;

  @override
  State<_PickerScreen> createState() => _PickerScreenState();
}

class _PickerScreenState extends State<_PickerScreen> {
  final _ctrl = TextEditingController();
  List<Place> _results = const [];
  bool _searching = false;
  bool _locating = false;
  String? _error;
  int _seq = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Typing only resets the list; the search itself runs on submit (the
  /// geocoder's usage policy doesn't allow search-as-you-type).
  void _onChanged(String v) {
    _seq++;
    setState(() {
      _results = const [];
      _searching = false;
      _error = null;
    });
  }

  Future<void> _search(String v) async {
    if (v.trim().length < 2) return;
    FocusScope.of(context).unfocus();
    final scope = AppScope.of(context);
    final my = ++_seq;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final r = await scope.geo.search(v, near: scope.settings.place);
      if (!mounted || my != _seq) return;
      setState(() {
        _results = r;
        _error = r.isEmpty ? 'No places found. Try a nearby landmark or area name.' : null;
      });
    } on GeoException catch (e) {
      if (mounted && my == _seq) setState(() => _error = e.userMessage);
    } finally {
      if (mounted && my == _seq) setState(() => _searching = false);
    }
  }

  Future<void> _useCurrent() async {
    setState(() {
      _locating = true;
      _error = null;
    });
    try {
      final p = await AppScope.of(context).geo.current();
      if (mounted) Navigator.pop(context, p);
    } on GeoException catch (e) {
      if (mounted) setState(() => _error = e.userMessage);
    } catch (_) {
      if (mounted) setState(() => _error = 'Couldn\'t get your location. Search for your area instead.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final recents = AppScope.of(context).settings.recentPlaces;
    final typing = _ctrl.text.trim().length >= 2;
    return Backdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title),
              if (widget.subtitle != null) Text(widget.subtitle!, style: context.t.bodySmall),
            ],
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.xxl),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            TextField(
              controller: _ctrl,
              autofocus: true,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              onSubmitted: _search,
              maxLength: 100,
              buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
              decoration: InputDecoration(
                hintText: widget.hint,
                prefixIcon: Icon(Icons.search_rounded, color: c.inkMuted),
                suffixIcon: _ctrl.text.trim().length < 2
                    ? null
                    : Padding(
                        padding: const EdgeInsets.all(6),
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 36),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                          ),
                          onPressed: () => _search(_ctrl.text),
                          child: const Text('Search'),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: Space.md),
            if (widget.allowCurrent)
              Surface(
                padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.md),
                onTap: _locating ? null : _useCurrent,
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(color: c.primarySoft, shape: BoxShape.circle),
                      child: _locating
                          ? Padding(
                              padding: const EdgeInsets.all(9),
                              child: CircularProgressIndicator(strokeWidth: 2, color: c.primary),
                            )
                          : Icon(Icons.my_location_rounded, size: 18, color: c.primary),
                    ),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Use current location', style: context.t.titleSmall!.copyWith(color: c.primary)),
                          Text('Using GPS', style: context.t.bodySmall),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: c.inkMuted),
                  ],
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: Space.md),
              Text(_error!, style: context.t.bodySmall!.copyWith(color: c.danger)),
            ],
            const SizedBox(height: Space.lg),
            if (typing) ...[
              if (_searching && _results.isEmpty)
                const _ResultsSkeleton()
              else if (_results.isNotEmpty) ...[
                const SectionLabel('Results'),
                _PlaceList(places: _results, icon: Icons.place_outlined),
              ],
            ] else if (recents.isNotEmpty) ...[
              const SectionLabel('Recent'),
              _PlaceList(places: recents, icon: Icons.history_rounded),
            ],
            const SizedBox(height: Space.lg),
            Text(
              'Place search by OpenStreetMap. Only what you type is sent.',
              style: context.t.bodySmall!.copyWith(fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceList extends StatelessWidget {
  const _PlaceList({required this.places, required this.icon});
  final List<Place> places;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Surface(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < places.length; i++) ...[
            if (i > 0) const Divider(indent: 60),
            InkWell(
              onTap: () => Navigator.pop(context, places[i]),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.md),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(color: c.surfaceAlt, shape: BoxShape.circle),
                      child: Icon(icon, size: 18, color: c.inkMuted),
                    ),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(places[i].name, style: context.t.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                          if (places[i].subtitle.isNotEmpty)
                            Text(
                              places[i].subtitle,
                              style: context.t.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ResultsSkeleton extends StatelessWidget {
  const _ResultsSkeleton();

  @override
  Widget build(BuildContext context) => Shimmer(
    child: Column(
      children: [
        for (var i = 0; i < 4; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            child: Row(
              children: [
                const SkeletonBox(width: 36, height: 36, radius: 18),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 120.0 + i * 30, height: 13),
                      const SizedBox(height: 6),
                      const SkeletonBox(width: 180, height: 11),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

/// Pill showing the chosen location's name. Used in headers.
class LocationPill extends StatelessWidget {
  const LocationPill({super.key, required this.place, required this.onTap, this.onDark = false, this.label});

  /// Saved-address label ("Home"); shown above the area name.
  final String? label;
  final Place? place;
  final VoidCallback onTap;

  /// White-on-gradient variant for the hero header.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fg = onDark ? Colors.white : c.ink;
    final muted = onDark ? Colors.white.withValues(alpha: 0.75) : c.inkMuted;
    return Material(
      color: onDark ? Colors.white.withValues(alpha: 0.14) : c.surface,
      shape: StadiumBorder(side: BorderSide(color: onDark ? Colors.white.withValues(alpha: 0.22) : c.line)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_on_rounded, size: 16, color: onDark ? const Color(0xFFF5C065) : c.primary),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label ?? place?.name ?? 'Set location',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.t.labelMedium!.copyWith(color: fg, fontWeight: FontWeight.w700),
                    ),
                    if ((label != null && place != null) || (place?.city != null && place!.city != place!.name))
                      Text(
                        label != null ? place!.name : place!.city!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.t.labelSmall!.copyWith(color: muted, letterSpacing: 0, fontSize: 10.5),
                      ),
                  ],
                ),
              ),
              Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: muted),
            ],
          ),
        ),
      ),
    );
  }
}
