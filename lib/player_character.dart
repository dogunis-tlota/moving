import 'package:flame/cache.dart';
import 'package:flame/components.dart';

import 'boss_character.dart';
import 'game_constants.dart';
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

  bool get isAttacking => _attacking;

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
    );

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
    required double range,
    required int damage,
  }) {
    if (npc == null || !npc.isAlive) return;
    final d = playerWorldCenter.distanceTo(npc.worldCenter);
    if (d > range) return;
    final dx = npc.worldCenter.x - playerWorldCenter.x;
    if (dx.abs() >= 0.01 && dx.sign != facingX.sign) return;
    npc.takeDamage(damage);
  }

  void _tryHitBoss(
    Vector2 playerWorldCenter,
    double facingX,
    Vector2? bossWorld,
    BossCharacter? boss, {
    required double range,
    required int damage,
  }) {
    if (bossWorld == null || boss == null || !boss.isAlive) return;
    if (playerWorldCenter.distanceTo(bossWorld) > range) return;
    final dx = bossWorld.x - playerWorldCenter.x;
    if (dx.abs() >= 0.01 && dx.sign != facingX.sign) return;
    boss.takeDamage(damage);
  }

  /// 1키 — 펀치.
  bool tryPunch(
    Vector2 playerWorldCenter,
    double facingX, {
    NpcCharacter? npc,
    BossCharacter? boss,
    Vector2? bossWorldCenter,
    required int damage,
  }) {
    if (_attacking) return false;
    _attacking = true;
    animation = _punchAnim;
    animationTicker?.reset();
    playing = true;
    _tryHitNpc(
      playerWorldCenter,
      facingX,
      npc,
      range: kPunchHitRange,
      damage: damage,
    );
    _tryHitBoss(
      playerWorldCenter,
      facingX,
      bossWorldCenter,
      boss,
      range: kPunchHitRange,
      damage: damage,
    );
    return true;
  }

  /// 2키 — 킥.
  bool tryKick(
    Vector2 playerWorldCenter,
    double facingX, {
    NpcCharacter? npc,
    BossCharacter? boss,
    Vector2? bossWorldCenter,
    required int damage,
  }) {
    if (_attacking) return false;
    _attacking = true;
    animation = _kickAnim;
    animationTicker?.reset();
    playing = true;
    _tryHitNpc(
      playerWorldCenter,
      facingX,
      npc,
      range: kKickHitRange,
      damage: damage,
    );
    _tryHitBoss(
      playerWorldCenter,
      facingX,
      bossWorldCenter,
      boss,
      range: kKickHitRange,
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
  }

  void takeDamage(int amount) {
    if (amount <= 0) return;
    health = (health - amount).clamp(0, kDefaultMaxHp);
  }

  void healFull() {
    health = kDefaultMaxHp;
  }
}
