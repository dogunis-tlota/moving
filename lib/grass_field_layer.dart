import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import 'dungeon_layout.dart';
import 'game_constants.dart';
import 'map_backdrop.dart';
import 'world_walls.dart';

/// 잔디 운동장 배경. 맵 세로의 상단 [MapBackdrop.horizonFraction]은 하늘·지평선,
/// 하단은 캐릭터가 걷는 길(잔디·포장 느낌).
class GrassFieldLayer extends PositionComponent {
  GrassFieldLayer() : super(position: Vector2.zero());

  Vector2 cameraTopLeft = Vector2.zero();

  /// 방마다 다른 배경 (0…8, `ry*3+rx`).
  int roomPaletteIndex = 4;

  /// 이웃이 있는 변에만 출입구(테두리 갭).
  bool doorNorth = false;
  bool doorSouth = false;
  bool doorEast = false;
  bool doorWest = false;

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

  static const Color _letterboxFill = Color(0xFF252420);

  @override
  void render(Canvas canvas) {
    if (size.x <= 0 || size.y <= 0) return;
    final rect = size.toRect();
    canvas.drawRect(rect, Paint()..color = _letterboxFill);

    final cx = cameraTopLeft.x;
    final cy = cameraTopLeft.y;

    final halfW = kMapWidth / 2;
    final halfH = kMapHeight / 2;
    final left = (-halfW) - cx;
    final right = (halfW) - cx;
    final top = (-halfH) - cy;
    final bottom = (halfH) - cy;
    final mapH = bottom - top;
    if (mapH <= 1) return;

    final horizonY = top + mapH * MapBackdrop.horizonFraction;
    final horizonRect = Rect.fromLTRB(left, top, right, horizonY);
    final groundRect = Rect.fromLTRB(left, horizonY, right, bottom);

    canvas.save();
    canvas.clipRect(horizonRect);
    MapBackdrop.paintHorizonBand(canvas, horizonRect, roomPaletteIndex, cx);
    canvas.restore();

    canvas.save();
    canvas.clipRect(groundRect);
    MapBackdrop.paintGroundBand(canvas, groundRect, roomPaletteIndex);
    _drawMowStripes(canvas, cy, groundRect);
    _drawGrid(canvas, cx, cy, groundRect);
    _drawCenterLines(canvas, cx, cy, groundRect);
    canvas.restore();

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
    _strokeBorderWithDoorGaps(
      canvas,
      cx,
      cy,
      left,
      horizonY,
      right,
      bottom,
      border,
    );

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

  void _drawMowStripes(Canvas canvas, double cy, Rect clip) {
    var bandY = (cy / _grid).floorToDouble() * _grid;
    while (bandY < clip.bottom + cy + _grid) {
      final idx = (bandY / _grid).round();
      if (idx.isOdd) {
        final top = bandY - cy;
        final bottom = bandY + _grid - cy;
        final t = top.clamp(clip.top, clip.bottom);
        final b = bottom.clamp(clip.top, clip.bottom);
        if (b > t) {
          canvas.drawRect(
            Rect.fromLTRB(clip.left, t, clip.right, b),
            Paint()..color = _mowStripe,
          );
        }
      }
      bandY += _grid;
    }
  }

  void _drawGrid(Canvas canvas, double cx, double cy, Rect clip) {
    final thin = Paint()
      ..color = _line
      ..strokeWidth = _lineWidth
      ..style = PaintingStyle.stroke;

    var wx = (cx / _grid).floorToDouble() * _grid;
    while (wx < clip.right + cx + _grid) {
      final sx = wx - cx;
      if (sx >= clip.left - 1 && sx <= clip.right + 1) {
        final t = clip.top;
        final b = clip.bottom;
        canvas.drawLine(Offset(sx, t), Offset(sx, b), thin);
      }
      wx += _grid;
    }

    var wy = (cy / _grid).floorToDouble() * _grid;
    while (wy < clip.bottom + cy + _grid) {
      final sy = wy - cy;
      if (sy >= clip.top - 1 && sy <= clip.bottom + 1) {
        final l = clip.left;
        final r = clip.right;
        canvas.drawLine(Offset(l, sy), Offset(r, sy), thin);
      }
      wy += _grid;
    }
  }

  void _drawCenterLines(Canvas canvas, double cx, double cy, Rect clip) {
    final bold = Paint()
      ..color = _lineBold
      ..strokeWidth = _centerWidth
      ..style = PaintingStyle.stroke;

    final centerX = -cx;
    if (centerX >= clip.left - _centerWidth &&
        centerX <= clip.right + _centerWidth) {
      canvas.drawLine(
        Offset(centerX, clip.top),
        Offset(centerX, clip.bottom),
        bold,
      );
    }
    final centerY = -cy;
    if (centerY >= clip.top - _centerWidth &&
        centerY <= clip.bottom + _centerWidth) {
      canvas.drawLine(
        Offset(clip.left, centerY),
        Offset(clip.right, centerY),
        bold,
      );
    }
  }

  /// 출입구: 북·남은 가로선, 동·서는 **길(horizonY~bottom)** 구간만.
  /// [pathTop] = 길의 북쪽 경계(상단 1/4 아래) 화면 Y.
  void _strokeBorderWithDoorGaps(
    Canvas canvas,
    double cx,
    double cy,
    double left,
    double pathTop,
    double right,
    double bottom,
    Paint paint,
  ) {
    final g = kDoorGapHalfWorld;
    final pathMidY = kPathMidWorldY;
    final y0w = pathMidY - g;
    final y1w = pathMidY + g;
    final y0s = y0w - cy;
    final y1s = y1w - cy;

    void line(double x1, double y1, double x2, double y2) {
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
    }

    // 북: 길의 북쪽 끝(1/4 분계선)
    if (doorNorth) {
      final nx0 = -g - cx;
      final nx1 = g - cx;
      if (left < nx0) {
        line(left, pathTop, nx0, pathTop);
      }
      if (nx1 < right) {
        line(nx1, pathTop, right, pathTop);
      }
    } else {
      line(left, pathTop, right, pathTop);
    }

    if (doorSouth) {
      final nx0 = -g - cx;
      final nx1 = g - cx;
      if (left < nx0) {
        line(left, bottom, nx0, bottom);
      }
      if (nx1 < right) {
        line(nx1, bottom, right, bottom);
      }
    } else {
      line(left, bottom, right, bottom);
    }

    if (doorWest) {
      if (pathTop < y0s) {
        line(left, pathTop, left, y0s);
      }
      if (y1s < bottom) {
        line(left, y1s, left, bottom);
      }
    } else {
      line(left, pathTop, left, bottom);
    }

    if (doorEast) {
      if (pathTop < y0s) {
        line(right, pathTop, right, y0s);
      }
      if (y1s < bottom) {
        line(right, y1s, right, bottom);
      }
    } else {
      line(right, pathTop, right, bottom);
    }
  }

  /// [DungeonLayout]과 동기화.
  void syncDoorsForRoom(int rx, int ry) {
    doorNorth = DungeonLayout.hasNorth(rx, ry);
    doorSouth = DungeonLayout.hasSouth(rx, ry);
    doorEast = DungeonLayout.hasEast(rx, ry);
    doorWest = DungeonLayout.hasWest(rx, ry);
    roomPaletteIndex = ry * DungeonLayout.size + rx;
  }
}
