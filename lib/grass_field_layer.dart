import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import 'game_constants.dart';
import 'world_walls.dart';

/// 잔디 운동장 배경.
class GrassFieldLayer extends PositionComponent {
  GrassFieldLayer() : super(position: Vector2.zero());

  Vector2 cameraTopLeft = Vector2.zero();

  static const Color _grassTop = Color(0xFF5BA84A);
  static const Color _grassBottom = Color(0xFF2E6B24);
  static const Color _mowStripe = Color(0x18000000);
  static const Color _line = Color(0xE6FFFFFF);
  static const Color _lineBold = Color(0xFFFFFFFF);

  static const double _grid = 96;
  static const double _lineWidth = 1.5;
  static const double _centerWidth = 3.5;

  static const Color _curtain = Color(0xCC000000);
  static const Color _border = Color(0xFFFFFFFF);
  static const Color _wallFill = Color(0xFF6D4C41);
  static const Color _wallStroke = Color(0xFF3E2723);

  @override
  void render(Canvas canvas) {
    if (size.x <= 0 || size.y <= 0) return;
    final rect = size.toRect();

    final grassPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [_grassTop, _grassBottom],
      ).createShader(rect);
    canvas.drawRect(rect, grassPaint);

    final cx = cameraTopLeft.x;
    final cy = cameraTopLeft.y;

    var bandY = (cy / _grid).floorToDouble() * _grid;
    while (bandY < cy + size.y + _grid) {
      final idx = (bandY / _grid).round();
      if (idx.isOdd) {
        final top = bandY - cy;
        final bottom = bandY + _grid - cy;
        canvas.drawRect(
          Rect.fromLTRB(0, top, size.x, bottom),
          Paint()..color = _mowStripe,
        );
      }
      bandY += _grid;
    }

    final thin = Paint()
      ..color = _line
      ..strokeWidth = _lineWidth
      ..style = PaintingStyle.stroke;

    var wx = (cx / _grid).floorToDouble() * _grid;
    while (wx < cx + size.x + _grid) {
      final sx = wx - cx;
      canvas.drawLine(Offset(sx, 0), Offset(sx, size.y), thin);
      wx += _grid;
    }

    var wy = (cy / _grid).floorToDouble() * _grid;
    while (wy < cy + size.y + _grid) {
      final sy = wy - cy;
      canvas.drawLine(Offset(0, sy), Offset(size.x, sy), thin);
      wy += _grid;
    }

    final bold = Paint()
      ..color = _lineBold
      ..strokeWidth = _centerWidth
      ..style = PaintingStyle.stroke;

    final centerX = -cx;
    if (centerX >= -_centerWidth && centerX <= size.x + _centerWidth) {
      canvas.drawLine(Offset(centerX, 0), Offset(centerX, size.y), bold);
    }
    final centerY = -cy;
    if (centerY >= -_centerWidth && centerY <= size.y + _centerWidth) {
      canvas.drawLine(Offset(0, centerY), Offset(size.x, centerY), bold);
    }

    // 월드 경계(벽/장막) — 맵 바깥은 어둡게 처리.
    final halfW = kMapWidth / 2;
    final halfH = kMapHeight / 2;
    final left = (-halfW) - cx;
    final right = (halfW) - cx;
    final top = (-halfH) - cy;
    final bottom = (halfH) - cy;

    final curtainPaint = Paint()..color = _curtain;
    if (left > 0) {
      canvas.drawRect(Rect.fromLTWH(0, 0, left, size.y), curtainPaint);
    }
    if (right < size.x) {
      canvas.drawRect(
        Rect.fromLTWH(right, 0, size.x - right, size.y),
        curtainPaint,
      );
    }
    if (top > 0) {
      canvas.drawRect(Rect.fromLTWH(0, 0, size.x, top), curtainPaint);
    }
    if (bottom < size.y) {
      canvas.drawRect(
        Rect.fromLTWH(0, bottom, size.x, size.y - bottom),
        curtainPaint,
      );
    }

    final border = Paint()
      ..color = _border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawRect(Rect.fromLTRB(left, top, right, bottom), border);

    final wallPaint = Paint()..color = _wallFill;
    final wallStroke = Paint()
      ..color = _wallStroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final w in kInteriorWorldWalls) {
      final r = Rect.fromLTRB(
        w.left - cx,
        w.top - cy,
        w.right - cx,
        w.bottom - cy,
      );
      if (r.right < 0 || r.left > size.x || r.bottom < 0 || r.top > size.y) {
        continue;
      }
      canvas.drawRect(r, wallPaint);
      canvas.drawRect(r, wallStroke);
    }
  }
}
