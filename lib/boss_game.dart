import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'boss_character.dart';
import 'game_constants.dart';
import 'game_session.dart';
import 'player_character.dart';

/// 검정 배경 보스 방.
class BossGame extends FlameGame with KeyboardEvents {
  BossGame({
    required this.session,
    required this.onBossDefeated,
    required this.onPlayerDied,
  });

  final GameSession session;
  final void Function() onBossDefeated;
  final void Function() onPlayerDied;

  late PlayerCharacter player;
  late BossCharacter boss;
  late RectangleComponent _bg;

  final Vector2 playerWorldPos = Vector2.zero();
  final Vector2 bossWorldPos = Vector2(0, -220);
  Vector2 velocity = Vector2.zero();
  double facingX = 1;
  double bossAttackCd = 0;

  bool _resolved = false;

  Vector2 _cam() => playerWorldPos - size / 2 + player.size / 2;

  @override
  Future<void> onLoad() async {
    _bg = RectangleComponent(
      size: size.clone(),
      paint: Paint()..color = const Color(0xFF050508),
      priority: -10,
    );
    add(_bg);

    player = await PlayerCharacter.load(images);
    boss = await BossCharacter.load(images);
    player.position = size / 2;
    add(boss);
    add(player);
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (isLoaded) {
      _bg.size.setFrom(size);
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!isLoaded || _resolved) return;

    player.finishAttackIfNeeded();

    if (!player.isAttacking) {
      playerWorldPos.add(velocity * dt * session.stats.speedMultiplier);
    }

    final cam = _cam();
    boss.syncScreen(cam, bossWorldPos);
    player.scale = Vector2(facingX, 1);
    player.position = size / 2;

    if (!boss.isAlive) {
      if (!_resolved) {
        _resolved = true;
        onBossDefeated();
      }
    } else {
      bossAttackCd -= dt;
      if (bossAttackCd <= 0 &&
          playerWorldPos.distanceTo(bossWorldPos) < kKickHitRange + 60) {
        bossAttackCd = kNpcAttackCooldownSec * 1.1;
        player.takeDamage(boss.attackDamage);
        if (player.health <= 0 && !_resolved) {
          _resolved = true;
          onPlayerDied();
        }
      }
    }

    if (!player.isAttacking) {
      final moving = velocity.length2 > 1;
      player.playing = moving;
      if (!moving) {
        player.animationTicker?.currentIndex = 0;
      }
      if (velocity.x.abs() > 0.5) {
        facingX = velocity.x > 0 ? 1.0 : -1.0;
      }
    }
  }

  @override
  KeyEventResult onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    if (!isLoaded || _resolved) return KeyEventResult.ignored;

    if (event is KeyDownEvent) {
      final k = event.logicalKey;
      if (k == LogicalKeyboardKey.digit1 || k == LogicalKeyboardKey.numpad1) {
        player.tryPunch(
          playerWorldPos,
          facingX,
          boss: boss,
          bossWorldCenter: bossWorldPos,
          damage: session.stats.punchDamage,
        );
      } else if (k == LogicalKeyboardKey.digit2 ||
          k == LogicalKeyboardKey.numpad2) {
        player.tryKick(
          playerWorldPos,
          facingX,
          boss: boss,
          bossWorldCenter: bossWorldPos,
          damage: session.stats.kickDamage,
        );
      }
    }

    final base = 200.0;
    final sp = base * session.stats.speedMultiplier;
    velocity = Vector2.zero();
    if (keysPressed.contains(LogicalKeyboardKey.arrowUp)) velocity.y -= sp;
    if (keysPressed.contains(LogicalKeyboardKey.arrowDown)) velocity.y += sp;
    if (keysPressed.contains(LogicalKeyboardKey.arrowLeft)) velocity.x -= sp;
    if (keysPressed.contains(LogicalKeyboardKey.arrowRight)) velocity.x += sp;

    return KeyEventResult.handled;
  }
}
