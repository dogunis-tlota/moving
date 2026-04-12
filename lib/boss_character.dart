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
  double? worldPathMinY;
  double? worldPathMaxY;

  final Random _rng = Random();
  final Vector2 _moveDir = Vector2(1, 0);
  double _dirTimeLeft = 0;

  static const double _minDirSec = 0.55;
  static const double _maxDirSec = 1.65;
  static const double _chaseDist = 260;

  bool _attacking = false;

  /// 펀치 기절 등.
  double stunSecRemaining = 0;

  bool get isAlive => hp > 0;

  bool get isAttacking => _attacking;
  AvatarAction get action => _attacking ? AvatarAction.kick : AvatarAction.walk;

  /// 필드 보스는 [kBossFieldPowerMultiplier] 추가 적용.
  int get attackDamage => max(
        1,
        (1 * kBossDamageMultiplier * kBossFieldPowerMultiplier).round(),
      );

  /// `true`면 항상 플레이어 방향 추적(필드 보스).
  bool fieldAggressiveChase = false;

  /// 필드에서 플레이어와 동일한 기준 속도로 맞춤(매 프레임 갱신).
  double chaseSpeedWorld = kPlayerFieldMoveSpeed;

  static const Color _bodyTint = Color(0xFFE53935);

  void addStun(double seconds) {
    if (!isAlive || seconds <= 0) return;
    stunSecRemaining = max(stunSecRemaining, seconds);
  }

  bool beginAttackToward(Vector2 targetWorld) {
    if (!isAlive || stunSecRemaining > 0 || _attacking) return false;
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

  /// 플레이어 표시 크기의 [kBossFieldSizeVsPlayer]배. 필드 보스 전용.
  static Future<BossCharacter> loadForField(
    Images images,
    Vector2 playerDisplaySize,
  ) async {
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

    final sz = Vector2(
      playerDisplaySize.x * kBossFieldSizeVsPlayer,
      playerDisplaySize.y * kBossFieldSizeVsPlayer,
    );

    final b = BossCharacter._(
      walk: walk,
      punch: punch,
      kick: kick,
      size: sz,
    );
    b.fieldAggressiveChase = true;
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
  /// [speedFactor] 보스전 감속 등(예: 0.5).
  void stepMovement(
    double dt,
    Vector2 playerWorld, {
    double speedFactor = 1.0,
  }) {
    if (!isAlive) return;

    if (stunSecRemaining > 0) {
      stunSecRemaining = (stunSecRemaining - dt).clamp(0.0, 999.0);
      if (stunSecRemaining > 0) {
        paint.colorFilter = const ColorFilter.mode(
          Color(0xFF000000),
          BlendMode.srcATop,
        );
        _attacking = false;
        animation = _walkAnim;
        playing = false;
        return;
      }
      paint.colorFilter = const ColorFilter.mode(_bodyTint, BlendMode.srcATop);
    }

    if (_attacking) return;

    _dirTimeLeft -= dt;
    if (_dirTimeLeft <= 0) {
      final dist = worldCenter.distanceTo(playerWorld);
      if (fieldAggressiveChase || dist > _chaseDist) {
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

    worldCenter.add(_moveDir * chaseSpeedWorld * speedFactor * dt);
    final hb = worldHalfBounds;
    if (hb != null) {
      worldCenter.x = worldCenter.x.clamp(-hb.x, hb.x);
      final pyMin = worldPathMinY;
      final pyMax = worldPathMaxY;
      if (pyMin != null && pyMax != null) {
        worldCenter.y = worldCenter.y.clamp(pyMin, pyMax);
      } else {
        worldCenter.y = worldCenter.y.clamp(-hb.y, hb.y);
      }
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
    }
  }

  void syncScreen(Vector2 cameraTopLeft) {
    position = worldCenter - cameraTopLeft;
  }
}
