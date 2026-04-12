import 'package:flame/cache.dart';
import 'package:flame/components.dart';

import 'boss_character.dart';
import 'game_constants.dart';
import 'multiplayer/room_models.dart';
import 'npc_character.dart';

/// 플레이어 스프라이트: 걷기 / 펀치 / 킥 애니메이션 전환.
class PlayerCharacter extends SpriteAnimationComponent {
  PlayerCharacter._({
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

  int health = kDefaultMaxHp;

  bool _attacking = false;
  AvatarAction _action = AvatarAction.idle;

  bool get isAttacking => _attacking;
  AvatarAction get action => _action;

  static Future<PlayerCharacter> load(Images images) async {
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
      final fw = image.width / kManWalkFrameCount;
      final fh = image.height.toDouble();
      final data = SpriteAnimationData.sequenced(
        amount: kManWalkFrameCount,
        stepTime: stepTime,
        textureSize: Vector2(fw.toDouble(), fh),
        amountPerRow: kManWalkFrameCount,
        loop: loop,
      );
      return SpriteAnimation.fromFrameData(image, data);
    }

    final walk = await strip(kManSpriteAsset, kManWalkStepTime);
    final punch = await strip(kManPunchAsset, kPunchAnimStepTime, loop: false);
    final kick = await strip(kManKickAsset, kKickAnimStepTime, loop: false);

    final frameSize = Vector2(
      walk.frames.first.sprite.srcSize.x,
      walk.frames.first.sprite.srcSize.y,
    )..scale(kCharacterScale);

    return PlayerCharacter._(
      walk: walk,
      punch: punch,
      kick: kick,
      size: frameSize,
    );
  }

  void _tryHitNpc(
    Vector2 playerWorldCenter,
    double facingX,
    NpcCharacter? npc, {
    required double reachSpriteWidths,
    required int damage,
  }) {
    if (npc == null || !npc.isAlive) return;
    final d = playerWorldCenter.distanceTo(npc.worldCenter);
    final halfSum = (size.x + npc.size.x) * 0.5;
    final closeRange = halfSum + size.x * reachSpriteWidths;
    if (d > closeRange) return;
    final dx = npc.worldCenter.x - playerWorldCenter.x;
    if (dx.abs() >= 0.01 && dx.sign != facingX.sign) return;
    npc.takeDamage(damage);
  }

  void _tryHitNpcs(
    Vector2 playerWorldCenter,
    double facingX,
    List<NpcCharacter>? npcs, {
    required double reachSpriteWidths,
    required int damage,
  }) {
    if (npcs == null) return;
    for (final npc in npcs) {
      _tryHitNpc(
        playerWorldCenter,
        facingX,
        npc,
        reachSpriteWidths: reachSpriteWidths,
        damage: damage,
      );
    }
  }

  void _tryHitBoss(
    Vector2 playerWorldCenter,
    double facingX,
    Vector2? bossWorld,
    BossCharacter? boss, {
    required double reachSpriteWidths,
    required int damage,
  }) {
    if (bossWorld == null || boss == null || !boss.isAlive) return;
    final halfSum = (size.x + boss.size.x) * 0.5;
    final closeRange = halfSum + size.x * reachSpriteWidths;
    if (playerWorldCenter.distanceTo(bossWorld) > closeRange) return;
    final dx = bossWorld.x - playerWorldCenter.x;
    if (dx.abs() >= 0.01 && dx.sign != facingX.sign) return;
    boss.takeDamage(damage);
  }

  /// 1키 — 펀치.
  bool tryPunch(
    Vector2 playerWorldCenter,
    double facingX, {
    List<NpcCharacter>? npcs,
    BossCharacter? boss,
    Vector2? bossWorldCenter,
    required int damage,
  }) {
    if (_attacking) return false;
    _attacking = true;
    _action = AvatarAction.punch;
    animation = _punchAnim;
    animationTicker?.reset();
    playing = true;
    _tryHitNpcs(
      playerWorldCenter,
      facingX,
      npcs,
      reachSpriteWidths: kPunchReachSpriteWidths,
      damage: damage,
    );
    _tryHitBoss(
      playerWorldCenter,
      facingX,
      bossWorldCenter,
      boss,
      reachSpriteWidths: kPunchReachSpriteWidths,
      damage: damage,
    );
    return true;
  }

  /// 2키 — 킥.
  bool tryKick(
    Vector2 playerWorldCenter,
    double facingX, {
    List<NpcCharacter>? npcs,
    BossCharacter? boss,
    Vector2? bossWorldCenter,
    required int damage,
  }) {
    if (_attacking) return false;
    _attacking = true;
    _action = AvatarAction.kick;
    animation = _kickAnim;
    animationTicker?.reset();
    playing = true;
    _tryHitNpcs(
      playerWorldCenter,
      facingX,
      npcs,
      reachSpriteWidths: kKickReachSpriteWidths,
      damage: damage,
    );
    _tryHitBoss(
      playerWorldCenter,
      facingX,
      bossWorldCenter,
      boss,
      reachSpriteWidths: kKickReachSpriteWidths,
      damage: damage,
    );
    return true;
  }

  void finishAttackIfNeeded() {
    if (!_attacking) return;
    if (animationTicker?.done() != true) return;
    _attacking = false;
    animation = _walkAnim;
    animationTicker?.reset();
    playing = false;
    _action = AvatarAction.idle;
  }

  void playRemoteAction(AvatarAction action) {
    if (action == AvatarAction.punch) {
      _attacking = true;
      _action = AvatarAction.punch;
      animation = _punchAnim;
      animationTicker?.reset();
      playing = true;
      return;
    }
    if (action == AvatarAction.kick) {
      _attacking = true;
      _action = AvatarAction.kick;
      animation = _kickAnim;
      animationTicker?.reset();
      playing = true;
      return;
    }
    if (action == AvatarAction.grab) {
      _attacking = true;
      _action = AvatarAction.grab;
      animation = _punchAnim;
      animationTicker?.reset();
      playing = true;
      return;
    }
    _attacking = false;
    _action = action;
    animation = _walkAnim;
    if (action == AvatarAction.idle) {
      playing = false;
      animationTicker?.currentIndex = 0;
    } else {
      playing = true;
    }
  }

  void takeDamage(int amount) {
    if (amount <= 0) return;
    health = (health - amount).clamp(0, kDefaultMaxHp);
  }

  void healFull() {
    health = kDefaultMaxHp;
  }
}
