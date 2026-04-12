import 'dart:math' show min;

import 'dart:ui' show Offset, Rect;

import 'package:flame/components.dart';

import 'game_constants.dart';

/// 맵 중앙 원점 기준(플레이어 `manWorldPos`와 동일) 내부 벽 AABB 목록.
final List<Rect> kInteriorWorldWalls = _buildWalls();

List<Rect> _buildWalls() {
  final hw = kMapWidth / 2;
  final hh = kMapHeight / 2;
  void addCenter(double cx, double cy, double w, double h, List<Rect> out) {
    out.add(Rect.fromCenter(center: Offset(cx, cy), width: w, height: h));
  }

  final out = <Rect>[];
  // 세로 벽 둘
  addCenter(-hw * 0.55, 0, 72, hh * 1.1, out);
  addCenter(hw * 0.52, -hh * 0.12, 68, hh * 0.85, out);
  // 가로 벽 둘
  addCenter(0, -hh * 0.48, hw * 0.42, 56, out);
  addCenter(-hw * 0.08, hh * 0.38, hw * 0.5, 52, out);
  // 작은 블록
  addCenter(hw * 0.22, hh * 0.08, 100, 72, out);
  addCenter(-hw * 0.28, -hh * 0.22, 88, 64, out);
  return out;
}

bool worldWallOverlapsAabb(
  double centerX,
  double centerY,
  double halfW,
  double halfH,
) {
  final left = centerX - halfW;
  final right = centerX + halfW;
  final top = centerY - halfH;
  final bottom = centerY + halfH;
  for (final w in kInteriorWorldWalls) {
    if (right >= w.left &&
        left <= w.right &&
        bottom >= w.top &&
        top <= w.bottom) {
      return true;
    }
  }
  return false;
}

/// 축 분리 이동: 한 축씩 밀어 넣어 벽에 걸리지 않게 함.
void resolveWorldWallsForCenter(
  Vector2 center,
  double halfW,
  double halfH,
) {
  if (!worldWallOverlapsAabb(center.x, center.y, halfW, halfH)) return;
  const step = 6.0;
  const maxIt = 48;
  for (var i = 0; i < maxIt; i++) {
    if (!worldWallOverlapsAabb(center.x, center.y, halfW, halfH)) break;
    center.x += step;
    if (!worldWallOverlapsAabb(center.x, center.y, halfW, halfH)) break;
    center.x -= 2 * step;
    if (!worldWallOverlapsAabb(center.x, center.y, halfW, halfH)) break;
    center.x += step;
    center.y += step;
    if (!worldWallOverlapsAabb(center.x, center.y, halfW, halfH)) break;
    center.y -= 2 * step;
    if (!worldWallOverlapsAabb(center.x, center.y, halfW, halfH)) break;
    center.y += step;
  }
}

/// `delta`만큼 이동 시도 후 벽과 겹치면 해당 축만 롤백.
void tryMoveWithWorldWalls(
  Vector2 center,
  double dx,
  double dy,
  double halfW,
  double halfH,
) {
  final ox = center.x;
  center.x += dx;
  if (worldWallOverlapsAabb(center.x, center.y, halfW, halfH)) {
    center.x = ox;
  }
  final oy = center.y;
  center.y += dy;
  if (worldWallOverlapsAabb(center.x, center.y, halfW, halfH)) {
    center.y = oy;
  }
}

/// 가로 넉백: [dxWorld]만큼 작은 스텝으로 이동하며 내부 벽에 닿으면 멈춤.
void applyHorizontalKnockback(
  Vector2 center,
  double dxWorld,
  double halfW,
  double halfH,
  double mapHalfW,
) {
  if (dxWorld.abs() < 0.001) return;
  final dir = dxWorld.sign;
  var left = dxWorld.abs();
  const step = 4.0;
  while (left > 0.0001) {
    final s = min(step, left);
    final nx = center.x + dir * s;
    if (!worldWallOverlapsAabb(nx, center.y, halfW, halfH)) {
      center.x = nx;
      left -= s;
    } else {
      break;
    }
  }
  center.x = center.x.clamp(-mapHalfW, mapHalfW);
}
