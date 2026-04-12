import 'dart:math';
import 'dart:ui';

import 'package:flame/cache.dart';
import 'package:flame/components.dart';

import 'game_constants.dart';
import 'multiplayer/room_models.dart';
import 'world_walls.dart';

/// 운동장에서 배회하는 NPC — 걷기 / 펀치 / 킥 애니메이션.
/// 월드 기준 위치는 스프라이트 **중심** (플레이어 `manWorldPos`와 동일한 기준).
class NpcCharacter extends SpriteAnimationComponent {
  NpcCharacter._({
    required SpriteAnimation walk,
    required SpriteAnimation punch,
    required SpriteAnimation kick,
    required super.size,
  })  : _walkAnim = walk,
        _punchAnim = punch,
        _kickAnim = kick,
        super(animation: walk, anchor: Anchor.center);

  final SpriteAnimation _walkAnim;
  final SpriteAnimation _punchAnim;
  final SpriteAnimation _kickAnim;

  /// 걷는 속도 (월드 픽셀/초). 층에 따라 스폰 시 조정.
  double wanderSpeed = 90;

  /// 최대 체력(피해 클램프·HP바 세그먼트). 층에 따라 스폰 시 조정.
  int maxHp = kDefaultMaxHp;

  static const double _minDirectionSeconds = 0.7;
  static const double _maxDirectionSeconds = 2.2;

  final Random _rng = Random();
  Vector2 worldCenter = Vector2(150, -80);
  Vector2? worldHalfBounds;
  bool isNetworkDriven = false;
  Color tintColor = const Color(0xFF7EB6FF);
  final Vector2 _dir = Vector2(1, 0);
  double _directionTimeLeft = 0;

  int health = kDefaultMaxHp;

  /// 필드에서 이 NPC가 플레이어를 다시 때리기까지 남은 시간(초).
  double nextAttackIn = 0;

  bool _attacking = false;
  /// 이번에 시작한 근접 공격이 킥인지(넉백 판정용).
  bool _openingAttackIsKick = false;

  bool get isAlive => health > 0;

  bool get isAttacking => _attacking;
  AvatarAction get action => _attacking ? AvatarAction.kick : AvatarAction.walk;

  /// 방금 `beginAttackToward`로 시작한 공격이 킥인지.
  bool get openingAttackIsKick => _openingAttackIsKick;

  /// 플레이어 쪽을 보며 펀치 또는 킥 모션을 시작한다. 이미 공격 중이면 false.
  bool beginAttackToward(Vector2 targetWorld) {
    if (!isAlive || _attacking) return false;
    final dx = targetWorld.x - worldCenter.x;
    if (dx.abs() > 0.01) {
      scale.x = dx > 0 ? 1.0 : -1.0;
    }
    scale.y = 1;
    _attacking = true;
    _openingAttackIsKick = _rng.nextBool();
    animation = _openingAttackIsKick ? _kickAnim : _punchAnim;
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

  void playRemoteAction(
    AvatarAction action, {
    required double facingX,
    required Vector2 targetWorld,
  }) {
    if (!isAlive) return;
    if (facingX.abs() > 0.01) {
      scale.x = facingX > 0 ? 1.0 : -1.0;
    }
    scale.y = 1.0;
    switch (action) {
      case AvatarAction.punch:
        _attacking = true;
        animation = _punchAnim;
        animationTicker?.reset();
        playing = true;
        break;
      case AvatarAction.kick:
        _attacking = true;
        animation = _kickAnim;
        animationTicker?.reset();
        playing = true;
        break;
      case AvatarAction.grab:
        _attacking = true;
        animation = _punchAnim;
        animationTicker?.reset();
        playing = true;
        break;
      case AvatarAction.walk:
        _attacking = false;
        animation = _walkAnim;
        playing = true;
        break;
      case AvatarAction.idle:
        _attacking = false;
        animation = _walkAnim;
        playing = false;
        animationTicker?.currentIndex = 0;
        break;
    }
    if (_attacking) {
      final dx = targetWorld.x - worldCenter.x;
      if (dx.abs() > 0.01) {
        scale.x = dx > 0 ? 1.0 : -1.0;
      }
    }
  }

  static Future<NpcCharacter> load(Images images) async {
    Future<SpriteAnimation> strip(
      String asset,
      double stepTime, {
      bool loop = true,
    }) async {
      final image = await images.load(asset);
      assert(
        image.width % kManWalkFrameCount == 0,
        '$asset width must divide by $kManWalkFrameCount.',
      );
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

    final walk = await strip(kManSpriteAsset, kManWalkStepTime);
    final punch =
        await strip(kManPunchAsset, kPunchAnimStepTime, loop: false);
    final kick = await strip(kManKickAsset, kKickAnimStepTime, loop: false);

    final frameSize = Vector2(
      walk.frames.first.sprite.srcSize.x,
      walk.frames.first.sprite.srcSize.y,
    )..scale(kCharacterScale);

    final npc = NpcCharacter._(
      walk: walk,
      punch: punch,
      kick: kick,
      size: frameSize,
    );
    npc.paint.colorFilter = ColorFilter.mode(npc.tintColor, BlendMode.srcATop);
    return npc;
  }

  void takeDamage(int amount) {
    if (!isAlive || amount <= 0) return;
    health = (health - amount).clamp(0, maxHp);
    if (!isAlive) {
      playing = false;
      opacity = 0.45;
    }
  }

  void _pickNewDirection() {
    switch (_rng.nextInt(4)) {
      case 0:
        _dir.setValues(0, -1);
        break;
      case 1:
        _dir.setValues(0, 1);
        break;
      case 2:
        _dir.setValues(-1, 0);
        break;
      default:
        _dir.setValues(1, 0);
    }
    _directionTimeLeft =
        _minDirectionSeconds +
        _rng.nextDouble() * (_maxDirectionSeconds - _minDirectionSeconds);
  }

  @override
  void onMount() {
    super.onMount();
    _pickNewDirection();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!isAlive) return;

    if (_attacking) return;
    if (isNetworkDriven) return;

    _directionTimeLeft -= dt;
    if (_directionTimeLeft <= 0) {
      _pickNewDirection();
    }

    final move = _dir * wanderSpeed * dt;
    final hw = size.x * 0.36;
    final hh = size.y * 0.38;
    tryMoveWithWorldWalls(worldCenter, move.x, move.y, hw, hh);
    final hb = worldHalfBounds;
    if (hb != null) {
      worldCenter.x = worldCenter.x.clamp(-hb.x, hb.x);
      worldCenter.y = worldCenter.y.clamp(-hb.y, hb.y);
    }

    if (_dir.x.abs() > 0.1) {
      scale.x = _dir.x > 0 ? 1.0 : -1.0;
    }
    scale.y = 1.0;
    playing = true;
  }

  void syncScreenPosition(Vector2 cameraTopLeft) {
    position = worldCenter - cameraTopLeft;
  }
}
