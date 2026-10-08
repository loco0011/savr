import 'package:flutter/material.dart';

/// The Savr mark: a falling price line ending in an amber "deal" dot, on a
/// black-to-emerald gradient. Shared by the in-app logo and the launcher-icon
/// generator so they never drift apart.
abstract final class BrandMark {
  static const gradientStart = Color(0xFF1F8F6F);
  static const gradientEnd = Color(0xFF03110C);
  static const glow = Color(0x664ADE9F);
  static const line = Color(0xFFFFFFFF);
  static const dot = Color(0xFFF5C065);

  /// Price-line points in a 108-unit box (the Android adaptive-icon grid),
  /// kept inside the 66-unit safe zone.
  static const points = [Offset(32, 42), Offset(49, 60), Offset(60, 50), Offset(76, 66)];
  static const strokeWidth = 8.0;
  static const dotRadius = 7.0;

  static Gradient background() => const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [gradientStart, Color(0xFF0A3D2F), gradientEnd],
    stops: [0, 0.45, 1],
  );

  /// Paints the full mark into [rect]. [radiusFraction] rounds the corners
  /// (0 for the square adaptive-icon background).
  static void paint(Canvas canvas, Rect rect, {double radiusFraction = 0.3, bool withBackground = true}) {
    final s = rect.width / 108;
    if (withBackground) {
      final rr = RRect.fromRectAndRadius(rect, Radius.circular(rect.width * radiusFraction));
      canvas.save();
      canvas.clipRRect(rr);
      canvas.drawRect(rect, Paint()..shader = background().createShader(rect));
      // Soft glow behind the line so the gradient doesn't read as flat.
      canvas.drawRect(
        rect,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(-0.45, -0.55),
            radius: 0.9,
            colors: [glow, Color(0x004ADE9F)],
          ).createShader(rect),
      );
      canvas.restore();
    }
    final path = Path()..moveTo(rect.left + points[0].dx * s, rect.top + points[0].dy * s);
    for (final p in points.skip(1)) {
      path.lineTo(rect.left + p.dx * s, rect.top + p.dy * s);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth * s
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    final end = points.last;
    canvas.drawCircle(Offset(rect.left + end.dx * s, rect.top + end.dy * s), dotRadius * s, Paint()..color = dot);
  }
}

class BrandMarkPainter extends CustomPainter {
  const BrandMarkPainter({this.radiusFraction = 0.3});
  final double radiusFraction;

  @override
  void paint(Canvas canvas, Size size) => BrandMark.paint(canvas, Offset.zero & size, radiusFraction: radiusFraction);

  @override
  bool shouldRepaint(BrandMarkPainter old) => old.radiusFraction != radiusFraction;
}
