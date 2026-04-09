import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import 'game_constants.dart';

/// 필드에 배치되는 상점 구멍·보스 문 (월드 좌표).
class WorldPortals {
  WorldPortals(Random rng, {double spread = 3200, double minFromOrigin = 420}) {
    shopHoleCenters = [];
    for (var i = 0; i < 3; i++) {
      Vector2 p;
      do {
        p = Vector2(
          rng.nextDouble() * spread - spread / 2,
          rng.nextDouble() * spread - spread / 2,
        );
      } while (p.length < minFromOrigin);
      shopHoleCenters.add(p);
    }
    do {
      bossDoorWorldCenter = Vector2(
        rng.nextDouble() * spread - spread / 2,
        rng.nextDouble() * spread - spread / 2,
      );
    } while (bossDoorWorldCenter.length < minFromOrigin);
  }

  late List<Vector2> shopHoleCenters;
  late Vector2 bossDoorWorldCenter;

  final Paint _holeFill = Paint()..color = const Color(0xFF15221A);
  final Paint _holeBorder = Paint()
    ..color = const Color(0xFF0D0D0D)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3;
  final Paint _doorFill = Paint()..color = const Color(0xFF5D3F28);
  final Paint _doorBorder = Paint()
    ..color = const Color(0xFF2E1F14)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 4;

  void renderPortals(Canvas canvas, Vector2 cameraTopLeft, Vector2 viewSize) {
    for (final h in shopHoleCenters) {
      final sc = h - cameraTopLeft;
      if (sc.x < -kShopHoleRadius * 2 ||
          sc.y < -kShopHoleRadius * 2 ||
          sc.x > viewSize.x + kShopHoleRadius * 2 ||
          sc.y > viewSize.y + kShopHoleRadius * 2) {
        continue;
      }
      final o = Offset(sc.x, sc.y);
      canvas.drawCircle(o, kShopHoleRadius, _holeFill);
      canvas.drawCircle(o, kShopHoleRadius, _holeBorder);
    }

    final door = bossDoorWorldCenter - cameraTopLeft;
    if (door.x > -kBossDoorWidth &&
        door.y > -kBossDoorHeight &&
        door.x < viewSize.x + kBossDoorWidth &&
        door.y < viewSize.y + kBossDoorHeight) {
      final rect = Rect.fromCenter(
        center: Offset(door.x, door.y),
        width: kBossDoorWidth,
        height: kBossDoorHeight,
      );
      canvas.drawRect(rect, _doorFill);
      canvas.drawRect(rect, _doorBorder);

      final tp = TextPainter(
        text: const TextSpan(
          text: 'Boss',
          style: TextStyle(
            color: Color(0xFFFFE0B2),
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(door.x - tp.width / 2, door.y - kBossDoorHeight / 2 - 28),
      );
    }
  }

  bool collidesShop(Vector2 playerWorld) => shopHoleCenters
      .any((h) => playerWorld.distanceTo(h) < kShopHoleRadius + 28);

  bool collidesBossDoor(Vector2 playerWorld) =>
      playerWorld.distanceTo(bossDoorWorldCenter) < kBossDoorTriggerRadius;
}
