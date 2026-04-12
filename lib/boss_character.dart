import 'dart:math';
import 'dart:ui';

import 'package:flame/cache.dart';
import 'package:flame/components.dart';

import 'game_constants.dart';
import 'multiplayer/room_models.dart';

/// 보스 — 체력·공격 배율 적용된 거대 캐릭터. 걷기 / 펀치 / 킥 모션.
class BossCharacter extends SpriteAnimationComponent {
  BossCharacter._({
    required SpriteAnimation walk,
    required SpriteAnimation punch,
    required SpriteAnimation kick,
    required super.size,
  })  : _walkAnim = walk,
        _punchAnim = punch,
        _kickAnim = kick,
        maxHp = (kDefaultMaxHp * kBossHpMultiplier).round(),
        hp = (kDefaultMaxHp * kBossHpMultiplier).round(),
        super(animation: walk, anchor: Anchor.center);

  final SpriteAnimation _walkAnim;
  final SpriteAnimation _punchAnim;
  final SpriteAnimation _kickAnim;

  final int maxHp;
  int hp;
  double attackCooldown = 0;

  /// 스프라이트 중심 기준 월드 위치.
  final Vector2 worldCenter = Vector2.zero();
  Vector2? worldHalfBounds;

  final Random _rng = Random();
  final Vector2 _moveDir = Vector2(1, 0);
  double _dirTimeLeft = 0;

  static const double _minDirSec = 0.55;
  static const double _maxDirSec = 1.65;
  static const double _chaseDist = 260;

  bool _attacking = false;

  bool get isAlive => hp > 0;

  bool get isAttacking => _attacking;
  AvatarAction get action => _attacking ? AvatarAction.kick : AvatarAction.walk;

  int get attackDamage => (1 * kBossDamageMultiplier).ceil();

  bool beginAttackToward(Vector2 targetWorld) {
    if (!isAlive || _attacking) return false;
    final dx = targetWorld.x - worldCenter.x;
    if (dx.abs() > 0.01) {
      scale.x = dx > 0 ? 1.0 : -1.0;
    }
    scale.y = 1;
    _attacking = true;
    animation = _rng.nextBool() ? _kickAnim : _punchAnim;
    animationTicker?.reset();
    playing = true;
    return true;
  }

  void finishAttackIfNeeded() {
    if (!_attacking) return;
    if (animationTicker?.done() != true) return;
    _attacking = false;
    animation = _walkAnim;
    animationTicker?.reset();
    playing = false;
  }

  static Future<BossCharacter> load(Images images) async {
    Future<SpriteAnimation> strip(
      String asset,
      double stepTime, {
      bool loop = true,
    }) async {
      final image = await images.load(asset);
      final frameW = image.width / kManWalkFrameCount;
      final frameH = image.height.toDouble();
      final data = SpriteAnimationData.sequenced(
        amount: kManWalkFrameCount,
        stepTime: stepTime,
        textureSize: Vector2(frameW.toDouble(), frameH),
        amountPerRow: kManWalkFrameCount,
        loop: loop,
      );
      return SpriteAnimation.fromFrameData(image, data);
    }

    final walk = await strip(kManSpriteAsset, kManWalkStepTime * 0.85);
    final punch =
        await strip(kManPunchAsset, kPunchAnimStepTime, loop: false);
    final kick = await strip(kManKickAsset, kKickAnimStepTime, loop: false);

    final baseW = walk.frames.first.sprite.srcSize.x;
    final baseH = walk.frames.first.sprite.srcSize.y;
    const scale = 2.4;

    final b = BossCharacter._(
      walk: walk,
      punch: punch,
      kick: kick,
      size: Vector2(baseW * scale, baseH * scale),
    );
    b.paint.colorFilter = const ColorFilter.mode(
      Color(0xFFE53935),
      BlendMode.srcATop,
    );
    b.playing = true;
    return b;
  }

  void _pickWanderDir() {
    switch (_rng.nextInt(4)) {
      case 0:
        _moveDir.setValues(0, -1);
        break;
      case 1:
        _moveDir.setValues(0, 1);
        break;
      case 2:
        _moveDir.setValues(-1, 0);
        break;
      default:
        _moveDir.setValues(1, 0);
    }
  }

  /// 플레이어를 향해 추적하거나 배회. 공격 모션 중에는 이동하지 않는다.
  void stepMovement(double dt, Vector2 playerWorld) {
    if (!isAlive || _attacking) return;

    _dirTimeLeft -= dt;
    if (_dirTimeLeft <= 0) {
      final dist = worldCenter.distanceTo(playerWorld);
      if (dist > _chaseDist) {
        final to = playerWorld - worldCenter;
        if (to.length2 > 0.01) {
          _moveDir.setFrom(to.normalized());
        }
      } else {
        _pickWanderDir();
      }
      _dirTimeLeft =
          _minDirSec + _rng.nextDouble() * (_maxDirSec - _minDirSec);
    }

    worldCenter.add(_moveDir * kBossMoveSpeed * dt);
    final hb = worldHalfBounds;
    if (hb != null) {
      worldCenter.x = worldCenter.x.clamp(-hb.x, hb.x);
      worldCenter.y = worldCenter.y.clamp(-hb.y, hb.y);
    }

    if (_moveDir.x.abs() > 0.1) {
      scale.x = _moveDir.x > 0 ? 1.0 : -1.0;
    }
    scale.y = 1.0;
    playing = true;
  }

  void takeDamage(int amount) {
    if (!isAlive || amount <= 0) return;
    hp = (hp - amount).clamp(0, maxHp);
    if (!isAlive) {
      playing = false;
      opacity = 0.35;
    }
  }

  void syncScreen(Vector2 cameraTopLeft) {
    position = worldCenter - cameraTopLeft;
  }
}
