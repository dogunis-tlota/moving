import 'dart:math';

import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flutter/material.dart' show KeyEventResult;
import 'package:flutter/services.dart';

import 'game_constants.dart';
import 'game_session.dart';
import 'grass_field_layer.dart';
import 'hp_bar.dart';
import 'npc_character.dart';
import 'player_character.dart';
import 'world_portals.dart';

/// 메인 잔디 필드 — NPC·포털·부활.
class FieldGame extends FlameGame with KeyboardEvents {
  FieldGame({
    required this.session,
    required this.onOpenShop,
    required this.onOpenBoss,
    required this.onRequestRevive,
  });

  final GameSession session;
  final Future<void> Function() onOpenShop;
  final Future<void> Function() onOpenBoss;
  final Future<bool> Function() onRequestRevive;

  late PlayerCharacter player;
  late NpcCharacter npc;
  late HpBar hpBar;
  late HpBar npcHpBar;
  GrassFieldLayer? grassField;
  late WorldPortals portals;

  final Random _rng = Random();
  Vector2 velocity = Vector2.zero();
  Vector2 manWorldPos = Vector2.zero();
  double facingX = 1;

  double npcAttackTimer = 0;
  double portalLock = 0;
  bool _deathBusy = false;
  bool _routeBusy = false;

  Vector2 _cameraTopLeft() =>
      manWorldPos - size / 2 + player.size / 2;

  void _randomSpawnInField() {
    const spread = 2200.0;
    manWorldPos.setValues(
      session.spawnRng.nextDouble() * spread - spread / 2,
      session.spawnRng.nextDouble() * spread - spread / 2,
    );
  }

  Future<void> _runShopEntry() async {
    if (_routeBusy) return;
    _routeBusy = true;
    portalLock = 100;
    await onOpenShop();
    if (session.pendingFullHeal) {
      player.healFull();
      session.pendingFullHeal = false;
    }
    portalLock = 2.5;
    _routeBusy = false;
  }

  Future<void> _runBossEntry() async {
    if (_routeBusy) return;
    _routeBusy = true;
    portalLock = 100;
    await onOpenBoss();
    portalLock = 2.5;
    _routeBusy = false;
  }

  void _runDeathFlow() {
    if (_deathBusy || player.health > 0) return;
    _deathBusy = true;
    pauseEngine();
    onRequestRevive().then((yes) {
      if (yes) {
        session.revive.consumeFreeRevive();
      }
      player.healFull();
      _randomSpawnInField();
    }).whenComplete(() {
      _deathBusy = false;
      resumeEngine();
    });
  }

  @override
  Future<void> onLoad() async {
    portals = WorldPortals(_rng);
    final field = GrassFieldLayer()
      ..size = Vector2(size.x, size.y)
      ..portals = portals;
    grassField = field;
    add(field);

    player = await PlayerCharacter.load(images);
    npc = await NpcCharacter.load(images);
    npc.worldCenter = manWorldPos + Vector2(260, 40);
    add(npc);
    add(player);
    player.position = size / 2;

    hpBar = HpBar();
    add(hpBar);
    npcHpBar = HpBar();
    add(npcHpBar);

    hpBar.followPlayerFeet(player.position, player.size);
    hpBar.setFilled(player.health);
    npcHpBar.followPlayerFeet(npc.position, npc.size);
    npcHpBar.setFilled(npc.health);
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    grassField?.size.setFrom(size);
    if (isLoaded) {
      hpBar.followPlayerFeet(player.position, player.size);
      npcHpBar.followPlayerFeet(npc.position, npc.size);
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!isLoaded) return;

    portalLock = (portalLock - dt).clamp(0, 999.0);

    player.finishAttackIfNeeded();

    if (!player.isAttacking) {
      final mult = session.stats.speedMultiplier;
      manWorldPos.add(velocity * dt * mult);
    }

    final cam = _cameraTopLeft();
    grassField!.cameraTopLeft = cam;
    npc.syncScreenPosition(cam);

    npcAttackTimer += dt;
    if (npc.isAlive &&
        npcAttackTimer >= kNpcAttackCooldownSec &&
        manWorldPos.distanceTo(npc.worldCenter) < kNpcAttackRange) {
      npcAttackTimer = 0;
      player.takeDamage(1);
    }

    if (portalLock <= 0 && !_routeBusy) {
      if (portals.collidesShop(manWorldPos)) {
        _runShopEntry();
      } else if (portals.collidesBossDoor(manWorldPos)) {
        _runBossEntry();
      }
    }

    if (player.health <= 0) {
      _runDeathFlow();
    }

    if (!player.isAttacking) {
      final moving = velocity.length2 > 1;
      if (moving) {
        player.playing = true;
      } else {
        player.playing = false;
        player.animationTicker?.currentIndex = 0;
      }

      if (velocity.x.abs() > 0.5) {
        facingX = velocity.x > 0 ? 1.0 : -1.0;
      }
    }

    player.scale = Vector2(facingX, 1);
    player.position = size / 2;

    hpBar.followPlayerFeet(player.position, player.size);
    hpBar.setFilled(player.health);
    npcHpBar.followPlayerFeet(npc.position, npc.size);
    npcHpBar.setFilled(npc.health);
  }

  @override
  KeyEventResult onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    if (isLoaded && event is KeyDownEvent) {
      final k = event.logicalKey;
      if (k == LogicalKeyboardKey.digit1 ||
          k == LogicalKeyboardKey.numpad1) {
        player.tryPunch(
          manWorldPos,
          facingX,
          npc: npc,
          damage: session.stats.punchDamage,
        );
      } else if (k == LogicalKeyboardKey.digit2 ||
          k == LogicalKeyboardKey.numpad2) {
        player.tryKick(
          manWorldPos,
          facingX,
          npc: npc,
          damage: session.stats.kickDamage,
        );
      }
    }

    const baseSpeed = 200.0;
    velocity = Vector2.zero();
    if (keysPressed.contains(LogicalKeyboardKey.arrowUp)) {
      velocity.y -= baseSpeed;
    }
    if (keysPressed.contains(LogicalKeyboardKey.arrowDown)) {
      velocity.y += baseSpeed;
    }
    if (keysPressed.contains(LogicalKeyboardKey.arrowLeft)) {
      velocity.x -= baseSpeed;
    }
    if (keysPressed.contains(LogicalKeyboardKey.arrowRight)) {
      velocity.x += baseSpeed;
    }

    return KeyEventResult.handled;
  }
}
