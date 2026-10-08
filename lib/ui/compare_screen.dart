import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../core/models.dart';
import '../core/place.dart';
import '../core/platforms.dart';
import '../data/device/device_source.dart';
import '../theme/tokens.dart';
import 'location_picker.dart';
import 'results_screen.dart';
import 'voice_search.dart';
import 'widgets/common.dart';

class CompareScreen extends StatefulWidget {
  const CompareScreen({super.key, required this.incoming});
  final ValueNotifier<String?> incoming;

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  Vertical _vertical = Vertical.quick;
  bool _busy = false;
  String? _error;

  static const _examples = {
    Vertical.quick: ['Amul Taaza milk', 'Maggi noodles', 'Onion', 'Red Bull', 'Eggs', 'Bread'],
    Vertical.grocery: ['Basmati rice', 'Toor dal', 'Amul ghee', 'Tata Tea Gold'],
    Vertical.shopping: ['iPhone 16', 'Galaxy S25', 'boAt Airdopes', 'Sony WH-1000XM5'],
    Vertical.food: ['Chicken biryani', 'Margherita pizza', 'Masala dosa', 'Momos'],
  };

  @override
  void initState() {
    super.initState();
    widget.incoming.addListener(_onIncoming);
  }

  @override
  void dispose() {
    widget.incoming.removeListener(_onIncoming);
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onIncoming() {
    final text = widget.incoming.value;
    if (text == null) return;
    widget.incoming.value = null;
    _ctrl.text = text;
    _submit();
  }

  Future<void> _voice() async {
    _focus.unfocus();
    final said = await listenForSpeech(context);
    if (said == null || !mounted) return;
    _ctrl.text = said;
    _submit();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      setState(() => _error = 'Clipboard is empty. Copy a product link first.');
      return;
    }
    _ctrl.text = text.length > 2048 ? text.substring(0, 2048) : text;
    _submit();
  }

  Future<void> _submit([String? override]) async {
    if (_busy) return;
    final scope = AppScope.of(context);
    final input = override ?? _ctrl.text;
    if (override != null) _ctrl.text = override;
    _focus.unfocus();

    // Live prices depend on where you are; ask once, up front.
    if (scope.settings.dataMode == DataMode.device && scope.settings.place == null) {
      final p = await changeAppLocation(context);
      if (p == null || !mounted) return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await scope.repo.interpret(input, _vertical);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = r.error;
    });
    final q = r.query;
    if (q == null) return;

    if (q.vertical != _vertical && Vertical.searchable.contains(q.vertical)) setState(() => _vertical = q.vertical);
    scope.settings.addRecent(q.text);
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ResultsScreen(query: q)));
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final c = context.c;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: ListenableBuilder(
        listenable: scope.settings,
        builder: (context, _) {
          final s = scope.settings;
          final platforms = platformsFor(_vertical).where((p) => s.isPlatformEnabled(p.id)).toList();
          final liveCount = s.dataMode == DataMode.device
              ? platforms.where((p) => DevicePriceSource.supports(p.id)).length
              : 0;
          return ListView(
            padding: EdgeInsets.zero,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              _Hero(
                ctrl: _ctrl,
                focus: _focus,
                busy: _busy,
                vertical: _vertical,
                place: s.place,
                liveCount: liveCount,
                onSubmit: _submit,
                onVoice: _voice,
                addressLabel: s.activeAddress?.title,
                onVertical: (v) => setState(() => _vertical = v),
                onLocation: () => changeAppLocation(context),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, Space.xxl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_error != null) ...[
                      Text(_error!, style: context.t.bodySmall!.copyWith(color: c.danger)),
                      const SizedBox(height: Space.md),
                    ],
                    if (s.place == null && s.dataMode == DataMode.device) ...[
                      _SetLocationCard(onTap: () => changeAppLocation(context)),
                      const SizedBox(height: Space.lg),
                    ],
                    if (s.recent.isNotEmpty) ...[
                      SectionLabel(
                        'Recent',
                        trailing: InkWell(
                          onTap: s.clearRecent,
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Text('Clear', style: context.t.labelMedium!.copyWith(color: c.primary)),
                          ),
                        ),
                      ),
                      _ChipRow(items: s.recent, icon: Icons.history_rounded, onTap: _submit),
                      const SizedBox(height: Space.lg),
                    ],
                    const SectionLabel('Popular right now'),
                    _ChipRow(items: _examples[_vertical]!, icon: Icons.trending_up_rounded, onTap: _submit),
                    const SizedBox(height: Space.lg),
                    _AppsCard(platforms: platforms, liveCount: liveCount),
                    const SizedBox(height: Space.md),
                    _ShareTip(onPaste: _paste),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.ctrl,
    required this.focus,
    required this.busy,
    required this.vertical,
    required this.place,
    required this.liveCount,
    required this.onSubmit,
    required this.onVoice,
    this.addressLabel,
    required this.onVertical,
    required this.onLocation,
  });

  final TextEditingController ctrl;
  final FocusNode focus;
  final bool busy;
  final Vertical vertical;
  final Place? place;
  final int liveCount;
  final void Function([String?]) onSubmit;
  final VoidCallback onVoice;
  final String? addressLabel;
  final ValueChanged<Vertical> onVertical;
  final VoidCallback onLocation;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final top = MediaQuery.paddingOf(context).top;
    return Container(
      padding: EdgeInsets.fromLTRB(Space.lg, top + Space.md, Space.lg, Space.lg),
      decoration: BoxDecoration(
        gradient: c.hero,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(Radii.xxl)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SavrMark(size: 26),
              const SizedBox(width: Space.sm),
              Text('Savr', style: context.t.titleLarge!.copyWith(color: Colors.white)),
              const Spacer(),
              LocationPill(place: place, label: addressLabel, onTap: onLocation, onDark: true),
            ],
          ),
          const SizedBox(height: Space.xl),
          Text(
            'Compare before\nyou check out.',
            style: context.t.headlineMedium!.copyWith(color: Colors.white, fontSize: 28),
          ),
          const SizedBox(height: Space.xs),
          Text(
            liveCount > 0
                ? 'Live prices from $liveCount apps near ${place?.name ?? 'you'}'
                : 'Search by name, or paste a product link from any app.',
            style: context.t.bodyMedium!.copyWith(color: Colors.white.withValues(alpha: 0.78)),
          ),
          const SizedBox(height: Space.lg),
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.lg),
              boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 8))],
            ),
            child: TextField(
              controller: ctrl,
              focusNode: focus,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => onSubmit(),
              maxLength: 2048,
              buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
              decoration: InputDecoration(
                hintText: 'Search a product or paste a link',
                fillColor: dark ? c.surfaceSolid : Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Radii.lg),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Radii.lg),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: Icon(Icons.search_rounded, color: c.inkMuted),
                suffixIcon: busy
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : IconButton(
                        tooltip: 'Search by voice',
                        onPressed: onVoice,
                        icon: Icon(Icons.mic_rounded, color: c.primary),
                      ),
              ),
            ),
          ),
          const SizedBox(height: Space.md),
          // Centred when the pills fit; scrolls if a large font makes them wider.
          LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: box.maxWidth),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final v in Vertical.searchable) ...[
                      if (v != Vertical.searchable.first) const SizedBox(width: Space.sm),
                      _HeroPill(label: v.label, selected: v == vertical, onTap: () => onVertical(v)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 180),
    decoration: ShapeDecoration(
      color: selected ? Colors.white : Colors.white.withValues(alpha: 0.12),
      shape: StadiumBorder(side: BorderSide(color: Colors.white.withValues(alpha: selected ? 0 : 0.2))),
    ),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Text(
          label,
          style: context.t.labelMedium!.copyWith(
            color: selected ? const Color(0xFF07402F) : Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );
}

class _SetLocationCard extends StatelessWidget {
  const _SetLocationCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Surface(
      highlight: true,
      onTap: onTap,
      padding: const EdgeInsets.all(Space.md),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: c.dealSoft, borderRadius: BorderRadius.circular(Radii.md)),
            child: Icon(Icons.add_location_alt_rounded, color: c.onDealSoft),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Set your location once', style: context.t.titleSmall),
                const SizedBox(height: 2),
                Text('Savr uses it on every app to show the prices you\'d pay.', style: context.t.bodySmall),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: c.inkMuted),
        ],
      ),
    );
  }
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.items, required this.onTap, this.icon});
  final List<String> items;
  final void Function(String) onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    clipBehavior: Clip.none,
    child: Row(
      children: [
        for (final s in items)
          Padding(
            padding: const EdgeInsets.only(right: Space.sm),
            child: ActionChip(
              avatar: icon == null ? null : Icon(icon, size: 15, color: context.c.inkMuted),
              label: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(s, overflow: TextOverflow.ellipsis),
              ),
              onPressed: () => onTap(s),
            ),
          ),
      ],
    ),
  );
}

class _AppsCard extends StatelessWidget {
  const _AppsCard({required this.platforms, required this.liveCount});
  final List<MarketPlatform> platforms;
  final int liveCount;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    const size = 34.0, overlap = 22.0;
    final shown = platforms.take(7).toList();
    return Surface(
      padding: const EdgeInsets.all(Space.md),
      child: Row(
        children: [
          SizedBox(
            width: size + overlap * (shown.length - 1),
            height: size,
            child: Stack(
              children: [
                for (var i = 0; i < shown.length; i++)
                  Positioned(
                    left: i * overlap,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(size * 0.34),
                        border: Border.all(color: c.surfaceSolid, width: 2),
                      ),
                      child: PlatformBadge(shown[i], size: size - 4),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Comparing ${platforms.length} apps', style: context.t.titleSmall),
                Text(
                  liveCount > 0 ? '$liveCount with live prices · rest open in app' : 'Tap any result to open the app',
                  style: context.t.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareTip extends StatelessWidget {
  const _ShareTip({required this.onPaste});
  final VoidCallback onPaste;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Surface(
      padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.sm, Space.md),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: c.primarySoft, borderRadius: BorderRadius.circular(Radii.md)),
            child: Icon(Icons.ios_share_rounded, size: 18, color: c.primary),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(
              'Got a product link? Share it to Savr from any app, or paste it here.',
              style: context.t.bodySmall,
            ),
          ),
          TextButton.icon(
            onPressed: onPaste,
            icon: const Icon(Icons.content_paste_rounded, size: 16),
            label: const Text('Paste'),
          ),
        ],
      ),
    );
  }
}
