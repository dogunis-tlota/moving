import 'dart:ui';

import 'package:flame/cache.dart';
import 'package:flame/components.dart';

import 'game_constants.dart';

/// 보스 — 체력·공격 배율 적용된 거대 캐릭터.
class BossCharacter extends SpriteAnimationComponent {
  BossCharacter._({required super.animation, required super.size})
      : maxHp = (kDefaultMaxHp * kBossHpMultiplier).round(),
        hp = (kDefaultMaxHp * kBossHpMultiplier).round(),
        super(anchor: Anchor.center);

  final int maxHp;
  int hp;
  double attackCooldown = 0;

  bool get isAlive => hp > 0;

  int get attackDamage => (1 * kBossDamageMultiplier).ceil();

  static Future<BossCharacter> load(Images images) async {
    final image = await images.load(kManSpriteAsset);
    final frameW = image.width / kManWalkFrameCount;
    final frameH = image.height.toDouble();
    final data = SpriteAnimationData.sequenced(
      amount: kManWalkFrameCount,
      stepTime: kManWalkStepTime * 0.85,
      textureSize: Vector2(frameW.toDouble(), frameH),
      amountPerRow: kManWalkFrameCount,
    );
    final baseW = frameW.toDouble();
    final baseH = frameH;
    const scale = 2.4;
    final b = BossCharacter._(
      animation: SpriteAnimation.fromFrameData(image, data),
      size: Vector2(baseW * scale, baseH * scale),
    );
    b.paint.colorFilter = const ColorFilter.mode(
      Color(0xFFE53935),
      BlendMode.srcATop,
    );
    b.playing = true;
    return b;
  }

  void takeDamage(int amount) {
    if (!isAlive || amount <= 0) return;
    hp = (hp - amount).clamp(0, maxHp);
    if (!isAlive) {
      playing = false;
      opacity = 0.35;
    }
  }

  void syncScreen(Vector2 cameraTopLeft, Vector2 worldCenter) {
    position = worldCenter - cameraTopLeft;
  }
}
