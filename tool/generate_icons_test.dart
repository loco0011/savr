// Regenerates launcher PNGs and the Play Store icon from BrandMark.
// Run explicitly (not part of `flutter test`):
//   flutter test tool/generate_icons_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:savr/theme/brand_mark.dart';

Future<void> _render(String path, int px, {required double radius, double inset = 0}) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  final pad = px * inset;
  BrandMark.paint(canvas, Rect.fromLTWH(pad, pad, px - 2 * pad, px - 2 * pad), radiusFraction: radius);
  final img = await rec.endRecording().toImage(px, px);
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  testWidgets('generate icons', (t) async {
    await t.runAsync(() async {
      // Legacy launcher icons (Android < 8): rounded square with a small margin.
      const densities = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192};
      for (final MapEntry(key: d, value: px) in densities.entries) {
        await _render('android/app/src/main/res/mipmap-$d/ic_launcher.png', px, radius: 0.24, inset: 0.04);
      }
      // Play Store listing: full-bleed square, Play applies its own mask.
      await _render('branding/play_store_icon.png', 512, radius: 0);
      // Preview of the round/squircle look for docs.
      await _render('branding/icon_preview.png', 256, radius: 0.3);
    });
  });
}
