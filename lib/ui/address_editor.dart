import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../app_scope.dart';
import '../core/address.dart';
import '../core/place.dart';
import '../data/geo.dart';
import '../theme/tokens.dart';
import 'location_picker.dart';
import 'widgets/common.dart';

/// Opens the map-pin address editor. Returns the saved address, already
/// stored and made active, or null if cancelled.
Future<SavedAddress?> editAddress(BuildContext context, {SavedAddress? existing, Place? start, bool useGps = false}) =>
    Navigator.of(context).push<SavedAddress>(
      MaterialPageRoute(builder: (_) => AddressEditor(existing: existing, start: start, useGps: useGps)),
    );

class AddressEditor extends StatefulWidget {
  const AddressEditor({super.key, this.existing, this.start, this.useGps = false});
  final SavedAddress? existing;
  final Place? start;
  final bool useGps;

  @override
  State<AddressEditor> createState() => _AddressEditorState();
}

class _AddressEditorState extends State<AddressEditor> {
  static const _india = LatLng(22.5726, 88.3639); // fallback centre (Kolkata)

  final _map = MapController();
  final _flat = TextEditingController();
  final _building = TextEditingController();
  final _landmark = TextEditingController();
  final _custom = TextEditingController();
  final _form = GlobalKey<FormState>();

  late LatLng _center;
  Place? _resolved;
  bool _resolving = false;
  bool _locating = false;
  String? _error;
  AddressLabel _label = AddressLabel.home;
  Timer? _debounce;
  int _seq = 0;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final e = widget.existing;
    final start = e?.place ?? widget.start ?? AppScope.of(context).settings.place;
    _center = start == null ? _india : LatLng(start.lat, start.lng);
    _resolved = start;
    if (e != null) {
      _flat.text = e.flat ?? '';
      _building.text = e.building ?? '';
      _landmark.text = e.landmark ?? '';
      _custom.text = e.customName ?? '';
      _label = e.label;
    } else {
      // Don't default to a label that's already used.
      final used = AppScope.of(context).settings.addresses.map((a) => a.label).toSet();
      _label = AddressLabel.values.firstWhere((l) => !used.contains(l), orElse: () => AddressLabel.other);
    }
    if (widget.useGps || start == null) WidgetsBinding.instance.addPostFrameCallback((_) => _gps());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [_flat, _building, _landmark, _custom]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _gps() async {
    setState(() {
      _locating = true;
      _error = null;
    });
    try {
      final p = await AppScope.of(context).geo.current();
      if (!mounted) return;
      _moveTo(p);
    } on GeoException catch (e) {
      if (mounted) setState(() => _error = e.userMessage);
    } catch (_) {
      if (mounted) setState(() => _error = 'Couldn\'t get your location. Search instead or move the map.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _search() async {
    final p = await pickPlace(context, title: 'Search area', hint: 'Area, street, building or landmark', allowCurrent: false);
    if (p != null && mounted) _moveTo(p);
  }

  void _moveTo(Place p) {
    _center = LatLng(p.lat, p.lng);
    _map.move(_center, 17.5);
    setState(() => _resolved = p);
  }

  void _onMoveEnd(LatLng c) {
    final moved = _resolved == null ? 1e9 : _resolved!.kmTo(Place(name: 'x', lat: c.latitude, lng: c.longitude));
    _center = c;
    if (moved < 0.015) return; // under 15 m: keep the name
    _debounce?.cancel();
    setState(() => _resolving = true);
    _debounce = Timer(const Duration(milliseconds: 650), () => _resolve(c));
  }

  Future<void> _resolve(LatLng c) async {
    final my = ++_seq;
    try {
      final p = await AppScope.of(context).geo.reverse(c.latitude, c.longitude);
      if (!mounted || my != _seq) return;
      setState(() {
        _resolved = p ?? Place(name: 'Pinned location', lat: c.latitude, lng: c.longitude);
        _error = null;
      });
    } on GeoException catch (e) {
      if (mounted && my == _seq) setState(() => _error = e.userMessage);
    } finally {
      if (mounted && my == _seq) setState(() => _resolving = false);
    }
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final base = _resolved ?? Place(name: 'Pinned location', lat: _center.latitude, lng: _center.longitude);
    // The exact pin, named after the resolved area.
    final pin = Place(
      name: base.name,
      lat: _center.latitude,
      lng: _center.longitude,
      area: base.area,
      city: base.city,
      state: base.state,
      pincode: base.pincode,
    );
    final a = SavedAddress(
      id: widget.existing?.id ?? DateTime.now().microsecondsSinceEpoch.toRadixString(36),
      label: _label,
      place: pin,
      flat: SavedAddress.cleanField(_flat.text),
      building: SavedAddress.cleanField(_building.text),
      landmark: SavedAddress.cleanField(_landmark.text),
      customName: _label == AddressLabel.other ? SavedAddress.cleanField(_custom.text, max: 30) : null,
    );
    applyAddress(context, a, save: true);
    Navigator.pop(context, a);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Backdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(widget.existing == null ? 'Add address' : 'Edit address')),
        body: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _map,
                    options: MapOptions(
                      initialCenter: _center,
                      initialZoom: _resolved == null ? 11 : 17.5,
                      minZoom: 4,
                      maxZoom: 19,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                      ),
                      onMapEvent: (e) {
                        if (e is MapEventMoveEnd || e is MapEventFlingAnimationEnd || e is MapEventDoubleTapZoomEnd) {
                          _onMoveEnd(e.camera.center);
                        }
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'in.ekrion.savr',
                        tileBuilder: dark ? darkModeTileBuilder : null,
                      ),
                      const SimpleAttributionWidget(source: Text('OpenStreetMap contributors')),
                    ],
                  ),
                  // Fixed centre pin: move the map under it.
                  IgnorePointer(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 44),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: c.ink,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Delivering here',
                                style: context.t.labelSmall!.copyWith(color: c.bg, letterSpacing: 0.2),
                              ),
                            ),
                            Icon(Icons.location_on_rounded, size: 44, color: c.primary),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: Space.md,
                    left: Space.md,
                    right: Space.md,
                    child: Material(
                      color: c.surfaceSolid,
                      elevation: 3,
                      shape: const StadiumBorder(),
                      child: InkWell(
                        customBorder: const StadiumBorder(),
                        onTap: _search,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: 12),
                          child: Row(
                            children: [
                              Icon(Icons.search_rounded, color: c.inkMuted, size: 20),
                              const SizedBox(width: Space.sm),
                              Text('Search area, street or building', style: context.t.bodyMedium!.copyWith(color: c.inkMuted)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: Space.md,
                    bottom: Space.md,
                    child: FloatingActionButton.extended(
                      heroTag: 'gps',
                      onPressed: _locating ? null : _gps,
                      backgroundColor: c.surfaceSolid,
                      foregroundColor: c.primary,
                      icon: _locating
                          ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: c.primary))
                          : const Icon(Icons.my_location_rounded),
                      label: const Text('Current location'),
                    ),
                  ),
                ],
              ),
            ),
            _DetailsPanel(
              form: _form,
              resolved: _resolved,
              resolving: _resolving,
              error: _error,
              flat: _flat,
              building: _building,
              landmark: _landmark,
              custom: _custom,
              label: _label,
              onLabel: (l) => setState(() => _label = l),
              onSave: _save,
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailsPanel extends StatelessWidget {
  const _DetailsPanel({
    required this.form,
    required this.resolved,
    required this.resolving,
    required this.error,
    required this.flat,
    required this.building,
    required this.landmark,
    required this.custom,
    required this.label,
    required this.onLabel,
    required this.onSave,
  });

  final GlobalKey<FormState> form;
  final Place? resolved;
  final bool resolving;
  final String? error;
  final TextEditingController flat, building, landmark, custom;
  final AddressLabel label;
  final ValueChanged<AddressLabel> onLabel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final maxH = MediaQuery.sizeOf(context).height * 0.5;
    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: BoxDecoration(
        color: c.surfaceSolid,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.xxl)),
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 20, offset: Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, Space.lg),
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.location_on_rounded, color: c.primary),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: resolving || resolved == null
                          ? const Shimmer(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [SkeletonBox(width: 140, height: 14), SizedBox(height: 6), SkeletonBox(width: 220, height: 11)],
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(resolved!.name, style: context.t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                                if (resolved!.subtitle.isNotEmpty)
                                  Text(resolved!.subtitle, style: context.t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                              ],
                            ),
                    ),
                  ],
                ),
                if (error != null) ...[
                  const SizedBox(height: Space.sm),
                  Text(error!, style: context.t.bodySmall!.copyWith(color: c.danger)),
                ],
                const SizedBox(height: Space.md),
                TextFormField(
                  controller: flat,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 80,
                  buildCounter: _noCounter,
                  decoration: const InputDecoration(labelText: 'Flat / house no. & floor *', isDense: true),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Needed so riders reach your door' : null,
                ),
                const SizedBox(height: Space.sm),
                TextFormField(
                  controller: building,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 80,
                  buildCounter: _noCounter,
                  decoration: const InputDecoration(labelText: 'Building / street (optional)', isDense: true),
                ),
                const SizedBox(height: Space.sm),
                TextFormField(
                  controller: landmark,
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: 80,
                  buildCounter: _noCounter,
                  decoration: const InputDecoration(labelText: 'Landmark (optional)', isDense: true),
                ),
                const SizedBox(height: Space.md),
                Text('Save as', style: context.t.labelMedium),
                const SizedBox(height: Space.xs),
                Wrap(
                  spacing: Space.sm,
                  children: [
                    for (final l in AddressLabel.values)
                      ChoiceChip(
                        avatar: Icon(_labelIcon(l), size: 16),
                        label: Text(l.title),
                        selected: l == label,
                        onSelected: (_) => onLabel(l),
                      ),
                  ],
                ),
                if (label == AddressLabel.other) ...[
                  const SizedBox(height: Space.sm),
                  TextFormField(
                    controller: custom,
                    maxLength: 30,
                    buildCounter: _noCounter,
                    decoration: const InputDecoration(labelText: 'Name, e.g. Mom\'s place', isDense: true),
                  ),
                ],
                const SizedBox(height: Space.lg),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: resolving ? null : onSave,
                    child: const Text('Save address & use it'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget? _noCounter(BuildContext _, {required int currentLength, required bool isFocused, int? maxLength}) =>
      null;
}

IconData _labelIcon(AddressLabel l) => switch (l) {
  AddressLabel.home => Icons.home_rounded,
  AddressLabel.work => Icons.work_rounded,
  AddressLabel.other => Icons.place_rounded,
};

IconData addressIcon(AddressLabel l) => _labelIcon(l);
