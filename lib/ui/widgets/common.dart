import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_launcher.dart';
import '../../core/platforms.dart';
import '../../theme/brand_mark.dart';
import '../../theme/tokens.dart';

/// Formats rupees with Indian digit grouping: 123456.5 → ₹1,23,456.50.
String inr(double v, {bool forceDecimals = false}) {
  final whole = v.truncate();
  final paise = ((v - whole) * 100).round();
  final digits = whole.abs().toString();
  String grouped;
  if (digits.length <= 3) {
    grouped = digits;
  } else {
    final last3 = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    grouped = '${parts.join(',')},$last3';
  }
  final dec = (paise != 0 || forceDecimals) ? '.${paise.toString().padLeft(2, '0')}' : '';
  return '${v < 0 ? '-' : ''}₹$grouped$dec';
}

String eta(int minutes) {
  if (minutes < 60) return '$minutes min';
  if (minutes < 60 * 24) {
    final h = (minutes / 60).round();
    return '$h hr';
  }
  final d = (minutes / (60 * 24)).round();
  return '$d day${d == 1 ? '' : 's'}';
}

const tabular = [FontFeature.tabularFigures()];

/// Opens a platform link in that platform's app when installed, otherwise
/// in the browser. Refuses anything that isn't HTTPS on a known platform
/// host, so a malicious backend response or pasted text can't make the app
/// open arbitrary schemes (intent://, javascript:, file:, …).
///
/// [productName] is copied to the clipboard when the app could only be
/// opened on its home screen, so the user can paste it into the app's search.
Future<void> openPlatformUrl(
  BuildContext context,
  Uri url, {
  String? platformId,
  Uri? native,
  String? productName,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final id =
      platformId ?? kPlatforms.where((p) => url.scheme == 'https' && p.ownsHost(url.host)).firstOrNull?.id;
  if (id == null || !isTrustedPlatformUrl(url)) {
    messenger.showSnackBar(const SnackBar(content: Text('That link was blocked for your safety.')));
    return;
  }
  final r = await AppLauncher.open(id, url, native: native);
  if (r == LaunchResult.appHome && productName != null) {
    await Clipboard.setData(ClipboardData(text: productName));
    messenger.showSnackBar(
      SnackBar(content: Text('${kPlatformById[id]!.name} opened. "$productName" is copied, paste it in search.')),
    );
  } else if (r == LaunchResult.blocked) {
    messenger.showSnackBar(const SnackBar(content: Text('That link was blocked for your safety.')));
  } else if (r == LaunchResult.failed) {
    messenger.showSnackBar(const SnackBar(content: Text('Couldn\'t open the app or browser.')));
  }
}

/// "Open in app" / "Open on web", depending on whether the app is installed.
class OpenHint extends StatelessWidget {
  const OpenHint(this.platformId, {super.key, this.color});
  final String platformId;
  final Color? color;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: AppLauncher.installed,
    builder: (context, apps, _) {
      final app = apps.contains(platformId);
      final col = color ?? context.c.primary;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(app ? 'Open app' : 'Open web', style: context.t.labelSmall!.copyWith(color: col, letterSpacing: 0.1)),
          const SizedBox(width: 2),
          Icon(app ? Icons.arrow_outward_rounded : Icons.language_rounded, size: 13, color: col),
        ],
      );
    },
  );
}

/// Small identity dot in the platform's brand colour.
class PlatformDot extends StatelessWidget {
  const PlatformDot(this.platform, {super.key, this.size = 10});
  final MarketPlatform platform;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: platform.brand,
      shape: BoxShape.circle,
      border: Border.all(color: context.c.ink.withValues(alpha: 0.12)),
    ),
  );
}

/// Rounded-square monogram in the platform's brand colour, e.g. a yellow
/// "B" for Blinkit. Text colour is picked for contrast.
class PlatformBadge extends StatelessWidget {
  const PlatformBadge(this.platform, {super.key, this.size = 36});
  final MarketPlatform platform;
  final double size;

  String get _mono {
    final words = platform.name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (platform.id == 'instamart') return 'IM';
    if (platform.id == 'fkminutes') return 'FM';
    if (platform.id == 'bbnow') return 'BB';
    if (words.length > 1 && words[1][0].toUpperCase() == words[1][0]) return '${words[0][0]}${words[1][0]}';
    return words.first[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final bg = platform.brand;
    final fg = bg.computeLuminance() > 0.45 ? const Color(0xFF14110A) : Colors.white;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.all(color: context.c.ink.withValues(alpha: 0.08)),
      ),
      child: Text(
        _mono,
        style: TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w700,
          fontSize: size * (_mono.length > 1 ? 0.34 : 0.44),
          letterSpacing: -0.3,
          color: fg,
          height: 1,
        ),
      ),
    );
  }
}

class PlatformLabel extends StatelessWidget {
  const PlatformLabel(this.platform, {super.key, this.style});
  final MarketPlatform platform;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      PlatformDot(platform),
      const SizedBox(width: Space.sm),
      Flexible(
        child: Text(platform.name, style: style ?? context.t.labelMedium, overflow: TextOverflow.ellipsis),
      ),
    ],
  );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Space.sm + 2),
    child: Row(
      children: [
        Expanded(
          child: Text(text, style: context.t.titleSmall!.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.1)),
        ),
        ?trailing,
      ],
    ),
  );
}

/// The logo mark, identical to the launcher icon.
class SavrMark extends StatelessWidget {
  const SavrMark({super.key, this.size = 28});
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: const BrandMarkPainter());
}

/// Neutral, non-alarming notice used for "sample prices" and estimates.
class InfoBanner extends StatelessWidget {
  const InfoBanner({super.key, required this.text, this.icon = Icons.info_outline_rounded, this.action});
  final String text;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(Space.md, Space.sm + 2, Space.sm, Space.sm + 2),
    decoration: BoxDecoration(color: context.c.dealSoft, borderRadius: BorderRadius.circular(Radii.md)),
    child: Row(
      children: [
        Icon(icon, size: 18, color: context.c.onDealSoft),
        const SizedBox(width: Space.sm),
        Expanded(
          child: Text(text, style: context.t.bodySmall!.copyWith(color: context.c.onDealSoft)),
        ),
        if (action != null) ...[const SizedBox(width: Space.xs), action!],
      ],
    ),
  );
}

class Surface extends StatelessWidget {
  const Surface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Space.lg),
    this.onTap,
    this.highlight = false,
    this.radius = Radii.xl,
  });
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final bool highlight;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: highlight ? c.deal : c.line, width: highlight ? 1.5 : 1),
    );
    return DecoratedBox(
      decoration: ShapeDecoration(shape: shape, shadows: cardShadow(context)),
      child: Material(
        color: c.surface,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.strong = false});
  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: strong ? c.deal : c.primarySoft, borderRadius: BorderRadius.circular(6)),
      child: Text(
        text,
        style: context.t.labelSmall!.copyWith(color: strong ? c.onDeal : c.primary, letterSpacing: 0.2, fontSize: 10.5),
      ),
    );
  }
}

/// Sweeping highlight over skeleton shapes. Wrap a group of [SkeletonBox]es.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});
  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat();

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = dark ? const Color(0xFF243D35) : const Color(0xFFE3E7E1);
    final hi = dark ? const Color(0xFF3E6255) : const Color(0xFFF8F9F7);
    return AnimatedBuilder(
      animation: _a,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (r) {
          final x = _a.value * 2.4 - 1.2;
          return LinearGradient(
            begin: Alignment(x - 0.6, -0.3),
            end: Alignment(x + 0.6, 0.3),
            colors: [base, hi, base],
            stops: const [0.1, 0.5, 0.9],
          ).createShader(r);
        },
        child: child,
      ),
      child: widget.child,
    );
  }
}

class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, required this.height, this.radius = 8});
  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(radius)),
  );
}

/// Delivery icon + fee for an offer: "≈₹39" (estimated), "₹25" or "Free".
/// Shows nothing when the fee is unknown.
class FeeBadge extends StatelessWidget {
  const FeeBadge(this.fee, {super.key, this.estimate = false, this.color});
  final double? fee;
  final bool estimate;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final f = fee;
    if (f == null) return const SizedBox.shrink();
    final col = color ?? (f == 0 ? context.c.primary : context.c.inkMuted);
    final text = f == 0 ? 'Free' : '${estimate ? '≈' : '+'}${inr(f)}';
    return Tooltip(
      message: estimate ? 'Estimated delivery + handling for this item alone' : 'Delivery + handling',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.delivery_dining_rounded, size: 14, color: col),
          const SizedBox(width: 3),
          Text(
            text,
            style: context.t.labelSmall!.copyWith(color: col, letterSpacing: 0, fontFeatures: tabular),
          ),
        ],
      ),
    );
  }
}
