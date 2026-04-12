import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'game_constants.dart';

/// 방 인덱스(0…8)마다 다른 하늘·지평선·길 색을 쓴다.
class MapBackdrop {
  MapBackdrop._();

  static double get horizonFraction => kFieldHorizonFraction;

  static BackdropPalette specForRoom(int roomPaletteIndex) {
    switch (roomPaletteIndex % 9) {
      case 0:
        return BackdropPalette(
          skyTop: const Color(0xFF6BB8FF),
          skyBottom: const Color(0xFFFFD4A8),
          groundTop: const Color(0xFF6A9E52),
          groundBottom: const Color(0xFF2D5A22),
          paintHorizonExtra: _silhouetteCity,
        );
      case 1:
        return BackdropPalette(
          skyTop: const Color(0xFF87CEEB),
          skyBottom: const Color(0xFFB8E0C8),
          groundTop: const Color(0xFF5FA060),
          groundBottom: const Color(0xFF245018),
          paintHorizonExtra: _silhouetteForest,
        );
      case 2:
        return BackdropPalette(
          skyTop: const Color(0xFF4DA6FF),
          skyBottom: const Color(0xFF7EC8E8),
          groundTop: const Color(0xFFC4A574),
          groundBottom: const Color(0xFF3D5C3A),
          paintHorizonExtra: _silhouetteSea,
        );
      case 3:
        return BackdropPalette(
          skyTop: const Color(0xFF8EC5FC),
          skyBottom: const Color(0xFFE0F2F5),
          groundTop: const Color(0xFF5E8F6B),
          groundBottom: const Color(0xFF284A2E),
          paintHorizonExtra: _silhouetteLake,
        );
      case 4:
        return BackdropPalette(
          skyTop: const Color(0xFFB0B8C4),
          skyBottom: const Color(0xFFD8DEE6),
          groundTop: const Color(0xFF7A7568),
          groundBottom: const Color(0xFF3A3830),
          paintHorizonExtra: _silhouetteConstruction,
        );
      case 5:
        return BackdropPalette(
          skyTop: const Color(0xFF9FD3FF),
          skyBottom: const Color(0xFFFFE8C4),
          groundTop: const Color(0xFF6EB545),
          groundBottom: const Color(0xFF2E6B24),
          paintHorizonExtra: _silhouettePark,
        );
      case 6:
        return BackdropPalette(
          skyTop: const Color(0xFFFFB8A8),
          skyBottom: const Color(0xFFFFE0C8),
          groundTop: const Color(0xFF6FA85C),
          groundBottom: const Color(0xFF355A28),
          paintHorizonExtra: _silhouetteSuburb,
        );
      case 7:
        return BackdropPalette(
          skyTop: const Color(0xFF5C3D7A),
          skyBottom: const Color(0xFFFF8A65),
          groundTop: const Color(0xFF5D7A4E),
          groundBottom: const Color(0xFF283D22),
          paintHorizonExtra: _silhouetteMountains,
        );
      default:
        return BackdropPalette(
          skyTop: const Color(0xFF8A9EAE),
          skyBottom: const Color(0xFFD7CCC8),
          groundTop: const Color(0xFF6D7A68),
          groundBottom: const Color(0xFF2E3328),
          paintHorizonExtra: _silhouetteIndustrial,
        );
    }
  }

  /// 상단 지평선 구역만 (건물·숲·바다 등).
  static void paintHorizonBand(
    Canvas canvas,
    Rect rect,
    int roomPaletteIndex,
    double cameraWorldX,
  ) {
    final s = specForRoom(roomPaletteIndex);
    final g = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [s.skyTop, s.skyBottom],
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = g);
    s.paintHorizonExtra(canvas, rect, cameraWorldX * 0.06);
  }

  /// 하단 필드 (캐릭터가 걷는 길).
  static void paintGroundBand(
    Canvas canvas,
    Rect rect,
    int roomPaletteIndex,
  ) {
    final s = specForRoom(roomPaletteIndex);
    final g = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [s.groundTop, s.groundBottom],
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = g);
    _paintPathLanes(canvas, rect);
  }
}

/// 한 방에 쓰이는 하늘·땅 색과 지평선 실루엣.
class BackdropPalette {
  const BackdropPalette({
    required this.skyTop,
    required this.skyBottom,
    required this.groundTop,
    required this.groundBottom,
    required this.paintHorizonExtra,
  });

  final Color skyTop;
  final Color skyBottom;
  final Color groundTop;
  final Color groundBottom;
  final void Function(Canvas canvas, Rect r, double parallaxX) paintHorizonExtra;
}

void _paintPathLanes(Canvas canvas, Rect rect) {
  final w = rect.width;
  final h = rect.height;
  if (w <= 0 || h <= 0) return;
  final lane = Paint()..color = const Color(0x12000000);
  const step = 72.0;
  var x = rect.left + (w % step) / 2;
  while (x < rect.right) {
    canvas.drawRect(
      Rect.fromLTRB(x, rect.top, x + step * 0.48, rect.bottom),
      lane,
    );
    x += step;
  }
  final edge = Paint()
    ..color = const Color(0x18FFFFFF)
    ..strokeWidth = 2;
  canvas.drawLine(
    Offset(rect.left, rect.top),
    Offset(rect.right, rect.top),
    edge,
  );
}

double _cityRndHeight(double i, double px) =>
    0.6 + 0.08 * math.sin(i * 2.1 + px * 0.01);

void _silhouetteCity(Canvas canvas, Rect r, double px) {
  final base = r.bottom - 4;
  final p = Paint()..color = const Color(0x66000000);
  var x = r.left - 40 + px % 80;
  while (x < r.right + 60) {
    final w = 28 + (x * 0.07).abs() % 22;
    final h = r.height * _cityRndHeight(x * 0.02, px);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(x, base - h, x + w, base),
        const Radius.circular(2),
      ),
      p,
    );
    x += w + 6;
  }
}

void _silhouetteForest(Canvas canvas, Rect r, double px) {
  final p = Paint()..color = const Color(0x70004020);
  var x = r.left - 20 + px % 40;
  while (x < r.right + 30) {
    final w = 36 + (x * 0.05).abs() % 18;
    final peakY = r.bottom -
        r.height * (0.75 + 0.1 * math.sin(x * 0.03));
    final path = Path()
      ..moveTo(x + w / 2, peakY)
      ..lineTo(x + w, r.bottom)
      ..lineTo(x, r.bottom)
      ..close();
    canvas.drawPath(path, p);
    x += w * 0.72;
  }
}

void _silhouetteSea(Canvas canvas, Rect r, double px) {
  final wave = Paint()
    ..color = const Color(0x88FFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.2;
  var y = r.bottom - r.height * 0.35;
  for (var i = 0; i < 4; i++) {
    final path = Path();
    var x = r.left;
    path.moveTo(x, y);
    while (x < r.right) {
      x += 18;
      path.lineTo(x, y + 3 * math.sin((x + px) * 0.04 + i));
    }
    canvas.drawPath(path, wave);
    y += 10;
  }
  final deep = Paint()..color = const Color(0x400069A8);
  canvas.drawRect(
    Rect.fromLTRB(r.left, r.bottom - r.height * 0.22, r.right, r.bottom),
    deep,
  );
}

void _silhouetteLake(Canvas canvas, Rect r, double px) {
  final hill = Paint()..color = const Color(0x556A9E7A);
  canvas.drawOval(
    Rect.fromCenter(
      center: Offset(r.center.dx + px * 0.3, r.bottom),
      width: r.width * 1.4,
      height: r.height * 0.85,
    ),
    hill,
  );
  final reed = Paint()
    ..color = const Color(0x88306040)
    ..strokeWidth = 2;
  var x = r.left + px % 24;
  while (x < r.right) {
    canvas.drawLine(
      Offset(x, r.bottom),
      Offset(x - 3, r.bottom - r.height * 0.45),
      reed,
    );
    x += 14;
  }
}

void _silhouetteConstruction(Canvas canvas, Rect r, double px) {
  final dark = Paint()..color = const Color(0x771A1A1A);
  final crane = Paint()
    ..color = const Color(0x99303030)
    ..strokeWidth = 4
    ..style = PaintingStyle.stroke;
  canvas.drawRect(
    Rect.fromLTRB(r.left + 40, r.bottom - r.height * 0.5, r.right - 30, r.bottom),
    dark,
  );
  final cx = r.center.dx + px * 0.5;
  canvas.drawLine(Offset(cx, r.top + 8), Offset(cx, r.bottom - 6), crane);
  canvas.drawLine(
    Offset(cx - 50, r.top + 28),
    Offset(cx + 70, r.top + 18),
    crane,
  );
  canvas.drawLine(
    Offset(cx + 70, r.top + 18),
    Offset(cx + 70, r.bottom - 10),
    crane..strokeWidth = 3,
  );
}

void _silhouettePark(Canvas canvas, Rect r, double px) {
  final hill = Paint()..color = const Color(0x556FA85C);
  final path = Path();
  var x = r.left;
  path.moveTo(x, r.bottom);
  while (x < r.right) {
    x += 40;
    path.lineTo(
      x,
      r.bottom - r.height * (0.35 + 0.12 * math.sin((x + px) * 0.025)),
    );
  }
  path.lineTo(r.right, r.bottom);
  path.close();
  canvas.drawPath(path, hill);
}

void _silhouetteSuburb(Canvas canvas, Rect r, double px) {
  final body = Paint()..color = const Color(0x66806050);
  final roofPaint = Paint()..color = const Color(0x77907060);
  var x = r.left - 10 + px % 35;
  while (x < r.right + 20) {
    final w = 52 + (x % 17);
    final roof = r.height * 0.42;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(x, r.bottom - roof * 0.55 - 8, x + w, r.bottom),
        const Radius.circular(3),
      ),
      body,
    );
    final roofPath = Path()
      ..moveTo(x - 4, r.bottom - roof * 0.55)
      ..lineTo(x + w / 2, r.top + r.height * 0.15)
      ..lineTo(x + w + 4, r.bottom - roof * 0.55)
      ..close();
    canvas.drawPath(roofPath, roofPaint);
    x += w + 16;
  }
}

void _silhouetteMountains(Canvas canvas, Rect r, double px) {
  final p = Paint()..color = const Color(0x88302050);
  final path = Path();
  var x = r.left - 60;
  path.moveTo(x, r.bottom);
  var i = 0;
  while (x < r.right + 80) {
    final peak = r.height * (0.55 + 0.15 * math.sin(i * 1.7 + px * 0.02));
    path.lineTo(x + 55, r.bottom - peak);
    x += 55;
    i++;
  }
  path.lineTo(x, r.bottom);
  path.close();
  canvas.drawPath(path, p);
}

void _silhouetteIndustrial(Canvas canvas, Rect r, double px) {
  final smoke = Paint()..color = const Color(0x55909090);
  final stack = Paint()..color = const Color(0x88404040);
  final rects = [
    Rect.fromLTRB(r.left + 30, r.bottom - r.height * 0.62, r.left + 70, r.bottom),
    Rect.fromLTRB(r.center.dx - 20, r.bottom - r.height * 0.48, r.center.dx + 25, r.bottom),
    Rect.fromLTRB(r.right - 90, r.bottom - r.height * 0.55, r.right - 35, r.bottom),
  ];
  for (final rect in rects) {
    canvas.drawRect(rect, stack);
  }
  for (var i = 0; i < 8; i++) {
    final ox = r.left + i * 55.0 + px % 30;
    canvas.drawCircle(
      Offset(ox + (i % 3) * 8, r.top + 12 + i * 3.0),
      6 + i * 0.8,
      smoke,
    );
  }
}
