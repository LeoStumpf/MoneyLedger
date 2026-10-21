/// G52 step 6: a QR code painted from the pure-Dart `qr` encoder (BSD-3) —
/// no platform code, no image library. Always dark modules on a light
/// square with a 4-module quiet zone (camera apps need the contrast and the
/// margin, also in dark mode).
library;

import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

import '../theme/app_colors.dart';

/// The QR matrix of [data] (error correction M — an invite link of ~110
/// characters fits version 6). `true` = a dark module.
List<List<bool>> qrModules(String data) {
  final image = QrImage(
    QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M),
  );
  final n = image.moduleCount;
  return [
    for (var r = 0; r < n; r++)
      [for (var c = 0; c < n; c++) image.isDark(r, c)],
  ];
}

/// [data] as a square QR code of [size] logical pixels. [semanticLabel] is
/// what a screen reader says (the code itself means nothing to it).
class QrCodeView extends StatelessWidget {
  const QrCodeView({
    super.key,
    required this.data,
    required this.semanticLabel,
    this.size = 220,
  });

  final String data;
  final String semanticLabel;
  final double size;

  /// Light margin around the code, in modules (the spec's quiet zone).
  static const quietZone = 4;

  @override
  Widget build(BuildContext context) {
    final modules = qrModules(data);
    return Semantics(
      label: semanticLabel,
      image: true,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: CustomPaint(painter: _QrPainter(modules)),
        ),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.modules);

  final List<List<bool>> modules;

  @override
  void paint(Canvas canvas, Size size) {
    final n = modules.length + 2 * QrCodeView.quietZone;
    final cell = size.shortestSide / n;
    canvas.drawRect(
      Offset.zero & Size.square(size.shortestSide),
      Paint()..color = BrandColors.paper,
    );
    final dark = Paint()
      ..color = BrandColors.ink
      ..isAntiAlias = false;
    for (var r = 0; r < modules.length; r++) {
      for (var c = 0; c < modules.length; c++) {
        if (!modules[r][c]) continue;
        canvas.drawRect(
          Rect.fromLTWH(
            (c + QrCodeView.quietZone) * cell,
            (r + QrCodeView.quietZone) * cell,
            // A hair wider than the cell: no seams between modules.
            cell + 0.5,
            cell + 0.5,
          ),
          dark,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => !identical(old.modules, modules);
}
