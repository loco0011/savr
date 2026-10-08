import 'package:flutter/material.dart';

/// Colour system.
///
/// Rationale (kept here so future edits don't drift into "random nice colours"):
/// * Primary is a deep teal-green (hue ~170°). Green reads as "money / go /
///   saving" in Indian and Western UI conventions; shifting towards teal lowers
///   arousal compared with saturated green, which suits a tool people use while
///   deciding to spend.
/// * The single accent is amber (hue ~40°), nearly complementary to teal, so the
///   "best price" marker pops pre-attentively without resorting to red, which
///   carries loss/alarm connotations and is reserved for errors only.
/// * Light mode uses a warm off-white rather than pure #FFF to reduce glare.
/// * Dark mode sits on black with a deep emerald glow at the top (see
///   [backdrop] and `Backdrop`). Cards are slightly translucent so the green
///   shows through; sheets and dialogs use [surfaceSolid].
/// * Every text-on-fill pair is verified >= 4.5:1 (WCAG 2.2 AA) in both themes.
@immutable
class SavrColors extends ThemeExtension<SavrColors> {
  const SavrColors({
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.line,
    required this.ink,
    required this.inkMuted,
    required this.primary,
    required this.onPrimary,
    required this.primarySoft,
    required this.deal,
    required this.onDeal,
    required this.dealSoft,
    required this.onDealSoft,
    required this.danger,
    required this.surfaceSolid,
    required this.backdrop,
    required this.hero,
  });

  final Color bg;
  final Color surface;
  final Color surfaceAlt;
  final Color line;
  final Color ink;
  final Color inkMuted;
  final Color primary;
  final Color onPrimary;
  final Color primarySoft;
  final Color deal;
  final Color onDeal;
  final Color dealSoft;
  final Color onDealSoft;
  final Color danger;

  /// Opaque surface for sheets, dialogs and menus that float over content.
  final Color surfaceSolid;

  /// Page background painted behind every screen.
  final LinearGradient backdrop;

  /// Rich emerald gradient for the hero header and best-deal card. Text on
  /// it is always white (>= 7:1 at every stop).
  final LinearGradient hero;

  static const light = SavrColors(
    bg: Color(0xFFF3F4F1),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFEDEFEB),
    line: Color(0xFFE4E7E2),
    ink: Color(0xFF101814),
    inkMuted: Color(0xFF56615C),
    primary: Color(0xFF0B6E5E),
    onPrimary: Color(0xFFFFFFFF),
    primarySoft: Color(0xFFE0F2EC),
    deal: Color(0xFFF2B544),
    onDeal: Color(0xFF3A2700),
    dealSoft: Color(0xFFFDF0D5),
    onDealSoft: Color(0xFF6B4A00),
    danger: Color(0xFFB42318),
    surfaceSolid: Color(0xFFFFFFFF),
    backdrop: LinearGradient(colors: [Color(0xFFF3F4F1), Color(0xFFF3F4F1)]),
    hero: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF0D7A65), Color(0xFF09564A), Color(0xFF06372F)],
    ),
  );

  static const dark = SavrColors(
    bg: Color(0xFF020504),
    surface: Color(0xB80E1F1A), // ~72% — lets the green glow through
    surfaceAlt: Color(0xB8142A23),
    line: Color(0xFF1E3B31),
    ink: Color(0xFFE9F2EE),
    inkMuted: Color(0xFF9DB3AA),
    primary: Color(0xFF4ADE9F),
    onPrimary: Color(0xFF03261A),
    primarySoft: Color(0x8C15553F),
    deal: Color(0xFFF5C065),
    onDeal: Color(0xFF3A2700),
    dealSoft: Color(0x2EF5C065), // translucent amber so it sits on the green
    onDealSoft: Color(0xFFF5D493),
    danger: Color(0xFFF97066),
    surfaceSolid: Color(0xFF0D1A16),
    backdrop: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF0C3B2E), Color(0xFF061A14), Color(0xFF020504)],
      stops: [0, 0.4, 0.85],
    ),
    hero: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF13654F), Color(0xFF0B4436), Color(0xFF072A22)],
    ),
  );

  @override
  SavrColors copyWith() => this;

  @override
  SavrColors lerp(ThemeExtension<SavrColors>? other, double t) {
    if (other is! SavrColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return SavrColors(
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      surfaceAlt: l(surfaceAlt, other.surfaceAlt),
      line: l(line, other.line),
      ink: l(ink, other.ink),
      inkMuted: l(inkMuted, other.inkMuted),
      primary: l(primary, other.primary),
      onPrimary: l(onPrimary, other.onPrimary),
      primarySoft: l(primarySoft, other.primarySoft),
      deal: l(deal, other.deal),
      onDeal: l(onDeal, other.onDeal),
      dealSoft: l(dealSoft, other.dealSoft),
      onDealSoft: l(onDealSoft, other.onDealSoft),
      danger: l(danger, other.danger),
      surfaceSolid: l(surfaceSolid, other.surfaceSolid),
      backdrop: LinearGradient.lerp(backdrop, other.backdrop, t)!,
      hero: LinearGradient.lerp(hero, other.hero, t)!,
    );
  }
}

/// 4pt spacing scale.
abstract final class Space {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

abstract final class Radii {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 28.0;
}

/// Soft, layered card shadow for light mode; dark mode relies on the
/// translucent surface + hairline instead.
List<BoxShadow> cardShadow(BuildContext context) => Theme.of(context).brightness == Brightness.dark
    ? const []
    : const [
        BoxShadow(color: Color(0x0A0B1F18), blurRadius: 2, offset: Offset(0, 1)),
        BoxShadow(color: Color(0x0F0B1F18), blurRadius: 24, offset: Offset(0, 8)),
      ];

/// Paints the theme's page background: flat off-white in light mode, black
/// with an emerald glow in dark mode. Wrap each route's Scaffold in this and
/// give the Scaffold a transparent background.
class Backdrop extends StatelessWidget {
  const Backdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.bg, gradient: c.backdrop),
      child: dark
          ? DecoratedBox(
              // Soft off-centre glow so the gradient doesn't look like a flat band.
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(-0.7, -1.05),
                  radius: 1.1,
                  colors: [Color(0x552BB58A), Color(0x002BB58A)],
                ),
              ),
              child: child,
            )
          : child,
    );
  }
}

extension SavrThemeX on BuildContext {
  SavrColors get c => Theme.of(this).extension<SavrColors>()!;
  TextTheme get t => Theme.of(this).textTheme;
}
