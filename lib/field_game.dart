import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game_constants.dart';
import 'game_session.dart';
import 'firebase_player_repository.dart';
import 'grass_field_layer.dart';
import 'hp_bar.dart';
import 'multiplayer_guest_character.dart';
import 'multiplayer_guest_local_character.dart';
import 'multiplayer_host_character.dart';
import 'npc_character.dart';
import 'player_identity_service.dart';
import 'player_character.dart';
import 'single_player_character.dart';
import 'multiplayer/network_session.dart';
import 'multiplayer/room_models.dart';
import 'world_walls.dart';

enum _PickupKind { power, speed }

/// 월드 좌표의 파워/스피드 픽업(화면은 카메라에 맞춤).
class _PickupBlob extends PositionComponent {
  _PickupBlob({
    required this.worldCenter,
    required this.kind,
  }) : super(
          size: Vector2(52, 46),
          anchor: Anchor.center,
          priority: 8000,
        );

  Vector2 worldCenter;
  final _PickupKind kind;

  void syncCam(Vector2 camTopLeft) {
    position = worldCenter - camTopLeft;
  }

  @override
  void render(Canvas canvas) {
    const r = 17.0;
    final cx = size.x / 2;
    final cy = 17.0;
    final paint = ui.Paint()
      ..color = kind == _PickupKind.power
          ? const Color(0xFFFF6B6B)
          : const Color(0xFF40E0FF);
    canvas.drawCircle(Offset(cx, cy), r, paint);

    final label = kind == _PickupKind.power ? 'Power' : 'speed';
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 8,
          fontWeight: FontWeight.w600,
          shadows: [
            Shadow(
              color: Color(0xCC000000),
              blurRadius: 3,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy + r + 1));
  }
}

/// Flutter 상단 오버레이용 HUD 스냅샷.
class FieldOverlayHudData {
  const FieldOverlayHudData({
    required this.floor,
    required this.hp,
    required this.hpMax,
    required this.npcAlive,
    required this.npcTotal,
    this.remoteShort = '',
    this.hostScore,
    this.guestScore,
    this.powerBuffSecRemain = 0,
    this.speedBuffSecRemain = 0,
  });

  final int floor;
  final int hp;
  final int hpMax;
  final int npcAlive;
  final int npcTotal;
  final String remoteShort;
  final int? hostScore;
  final int? guestScore;
  final int powerBuffSecRemain;
  final int speedBuffSecRemain;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FieldOverlayHudData &&
          floor == other.floor &&
          hp == other.hp &&
          hpMax == other.hpMax &&
          npcAlive == other.npcAlive &&
          npcTotal == other.npcTotal &&
          remoteShort == other.remoteShort &&
          hostScore == other.hostScore &&
          guestScore == other.guestScore &&
          powerBuffSecRemain == other.powerBuffSecRemain &&
          speedBuffSecRemain == other.speedBuffSecRemain;

  @override
  int get hashCode => Object.hash(
        floor,
        hp,
        hpMax,
        npcAlive,
        npcTotal,
        remoteShort,
        hostScore,
        guestScore,
        powerBuffSecRemain,
        speedBuffSecRemain,
      );
}

/// 메인 잔디 필드 — 층별 NPC·포털·부활.
class FieldGame extends FlameGame with KeyboardEvents {
  FieldGame({
    required this.session,
    required this.onRequestRevive,
    required this.onVictory,
    this.network,
    this.overlayHud,
    this.getRunElapsedSeconds,
    this.onSinglePlayerRunEnded,
  });

  final GameSession session;
  final Future<bool> Function() onRequestRevive;
  final Future<void> Function() onVictory;
  final NetworkSession? network;
  final ValueNotifier<FieldOverlayHudData>? overlayHud;
  /// 싱글: 경과 초 (HUD 타이머와 동일).
  final int Function()? getRunElapsedSeconds;
  /// 싱글: 부활 거절 시 도달 층·시간 기록 후 게임 오버 UI.
  final void Function(int floor, int elapsedSec)? onSinglePlayerRunEnded;

  late PlayerCharacter player;
  NpcCharacter? remotePlayer;
  final List<NpcCharacter> _npcs = [];
  final List<HpBar> _npcHpBars = [];
  final List<_PickupBlob> _pickups = [];

  late HpBar hpBar;
  HpBar? remoteHpBar;
  GrassFieldLayer? grassField;

  final Random _rng = Random();
  Vector2 velocity = Vector2.zero();
  final Vector2 _keyVelocity = Vector2.zero();
  final Vector2 _touchVelocity = Vector2.zero();
  Vector2 manWorldPos = Vector2.zero();
  Vector2 remoteWorldPos = Vector2.zero();
  double facingX = 1;
  double remoteFacingX = 1;
  AvatarAction _remoteLastAction = AvatarAction.idle;

  bool _deathBusy = false;
  bool _floorBusy = false;

  final FirebasePlayerRepository _playerRepo = FirebasePlayerRepository();

  bool get _isMulti => network != null;
  bool get _isHost => network?.isHost ?? true;
  int _prevAliveNpcCount = 0;
  bool _healedAfterRemoteDown = false;
  String _remoteName = '';
  /// 멀티: 내 인스턴스에서 NPC 처치로 얻은 점수.
  int _myScore = 0;
  Vector2 get _halfBounds => Vector2(kMapWidth / 2, kMapHeight / 2);

  (double hw, double hh) get _playerWallHalf =>
      (player.size.x * 0.38, player.size.y * 0.42);

  (double hw, double hh) _npcWallHalf(NpcCharacter n) =>
      (n.size.x * 0.36, n.size.y * 0.38);

  Vector2 _cameraTopLeft() =>
      manWorldPos - size / 2 + player.size / 2;

  void _clearPickups() {
    for (final p in _pickups) {
      remove(p);
    }
    _pickups.clear();
  }

  void _clearNpcs() {
    _clearPickups();
    for (final b in _npcHpBars) {
      remove(b);
    }
    for (final n in _npcs) {
      remove(n);
    }
    _npcHpBars.clear();
    _npcs.clear();
  }

  void _randomSpawnInField() {
    const spread = 1800.0;
    manWorldPos.setValues(
      session.spawnRng.nextDouble() * spread - spread / 2,
      session.spawnRng.nextDouble() * spread - spread / 2,
    );
    manWorldPos.x = manWorldPos.x.clamp(-_halfBounds.x, _halfBounds.x);
    manWorldPos.y = manWorldPos.y.clamp(-_halfBounds.y, _halfBounds.y);
    if (isLoaded) {
      final ph = _playerWallHalf;
      if (worldWallOverlapsAabb(
        manWorldPos.x,
        manWorldPos.y,
        ph.$1,
        ph.$2,
      )) {
        resolveWorldWallsForCenter(manWorldPos, ph.$1, ph.$2);
      }
    }
  }

  Future<void> _spawnFloorNpcs() async {
    _clearNpcs();

    final count = session.currentFloor;
    for (var i = 0; i < count; i++) {
      final npc = await NpcCharacter.load(images);
      npc.tintColor = HSVColor.fromAHSV(
        1,
        _rng.nextDouble() * 360,
        0.65 + _rng.nextDouble() * 0.25,
        0.85 + _rng.nextDouble() * 0.12,
      ).toColor();
      npc.paint.colorFilter = ColorFilter.mode(npc.tintColor, BlendMode.srcATop);
      npc.worldHalfBounds = _halfBounds;
      final floor = session.currentFloor;
      npc.maxHp = npcMaxHpForFloor(floor);
      npc.health = npc.maxHp;
      npc.wanderSpeed = npcWanderSpeedForFloor(floor);
      final angle = _rng.nextDouble() * 2 * pi;
      final dist = 160 + _rng.nextDouble() * 140;
      npc.worldCenter.setFrom(
        manWorldPos + Vector2(cos(angle) * dist, sin(angle) * dist),
      );
      npc.worldCenter.x = npc.worldCenter.x.clamp(-_halfBounds.x, _halfBounds.x);
      npc.worldCenter.y = npc.worldCenter.y.clamp(-_halfBounds.y, _halfBounds.y);
      final nh = _npcWallHalf(npc);
      for (var t = 0; t < 16; t++) {
        if (!worldWallOverlapsAabb(
          npc.worldCenter.x,
          npc.worldCenter.y,
          nh.$1,
          nh.$2,
        )) {
          break;
        }
        final ang = _rng.nextDouble() * 2 * pi;
        final d = 120 + _rng.nextDouble() * 200;
        npc.worldCenter.setFrom(
          manWorldPos + Vector2(cos(ang) * d, sin(ang) * d),
        );
        npc.worldCenter.x =
            npc.worldCenter.x.clamp(-_halfBounds.x, _halfBounds.x);
        npc.worldCenter.y =
            npc.worldCenter.y.clamp(-_halfBounds.y, _halfBounds.y);
      }
      resolveWorldWallsForCenter(npc.worldCenter, nh.$1, nh.$2);
      npc.nextAttackIn = 0;
      add(npc);
      _npcs.add(npc);

      final bar = HpBar(segmentCount: npc.maxHp);
      bar.label = 'NPC ${i + 1}';
      bar.setFilled(npc.health);
      add(bar);
      _npcHpBars.add(bar);
    }
    _prevAliveNpcCount = _npcs.where((n) => n.isAlive).length;
    _spawnPickups();
  }

  void _spawnPickups() {
    const minN = 2;
    const maxN = 4;
    final n = minN + _rng.nextInt(maxN - minN + 1);
    final cam = _cameraTopLeft();
    for (var i = 0; i < n; i++) {
      final kind = _rng.nextBool() ? _PickupKind.power : _PickupKind.speed;
      var wc = Vector2.zero();
      for (var t = 0; t < 18; t++) {
        final angle = _rng.nextDouble() * 2 * pi;
        final dist = 180 + _rng.nextDouble() * 520;
        wc.setFrom(
          manWorldPos + Vector2(cos(angle) * dist, sin(angle) * dist),
        );
        wc.x = wc.x.clamp(-_halfBounds.x, _halfBounds.x);
        wc.y = wc.y.clamp(-_halfBounds.y, _halfBounds.y);
        if (!worldWallOverlapsAabb(wc.x, wc.y, 22, 22)) {
          break;
        }
      }
      resolveWorldWallsForCenter(wc, 22, 22);
      final blob = _PickupBlob(worldCenter: wc.clone(), kind: kind);
      blob.syncCam(cam);
      add(blob);
      _pickups.add(blob);
    }
  }

  void _healFullOnWin() {
    player.healFull();
  }

  int _countNpcKills(List<int> beforeHp) {
    var kills = 0;
    final count = min(beforeHp.length, _npcs.length);
    for (var i = 0; i < count; i++) {
      if (beforeHp[i] > 0 && _npcs[i].health <= 0) {
        kills++;
      }
    }
    return kills;
  }

  void _rebuildVelocity() {
    const baseSpeed = 200.0;
    final x = (_keyVelocity.x + _touchVelocity.x).clamp(-1.0, 1.0);
    final y = (_keyVelocity.y + _touchVelocity.y).clamp(-1.0, 1.0);
    velocity.setValues(x * baseSpeed, y * baseSpeed);
  }

  void setTouchMove({
    bool up = false,
    bool down = false,
    bool left = false,
    bool right = false,
  }) {
    _touchVelocity.setValues(
      (right ? 1.0 : 0.0) + (left ? -1.0 : 0.0),
      (down ? 1.0 : 0.0) + (up ? -1.0 : 0.0),
    );
    _rebuildVelocity();
  }

  /// 터치 패드/조이스틱용: [-1,1] 범위.
  void setTouchMoveAnalog(double nx, double ny) {
    _touchVelocity.setValues(
      nx.clamp(-1.0, 1.0),
      ny.clamp(-1.0, 1.0),
    );
    _rebuildVelocity();
  }

  void clearTouchMove() {
    _touchVelocity.setZero();
    _rebuildVelocity();
  }

  void triggerPunch() {
    if (!isLoaded) return;
    final beforeHp =
        _isMulti ? _npcs.map((n) => n.health).toList(growable: false) : const <int>[];
    player.tryPunch(
      manWorldPos,
      facingX,
      npcs: _npcs,
      damage: session.stats.punchDamage,
    );
    if (_isMulti) {
      final kills = _countNpcKills(beforeHp);
      if (kills > 0) {
        _myScore += kills * 10;
      }
    }
  }

  void triggerKick() {
    if (!isLoaded) return;
    final beforeHp = _npcs.map((n) => n.health).toList(growable: false);
    player.tryKick(
      manWorldPos,
      facingX,
      npcs: _npcs,
      damage: session.stats.kickDamage,
    );
    for (var i = 0; i < _npcs.length; i++) {
      if (beforeHp[i] > _npcs[i].health) {
        _knockNpcFromPlayer(_npcs[i]);
      }
    }
    if (_isMulti) {
      final kills = _countNpcKills(beforeHp);
      if (kills > 0) {
        _myScore += kills * 10;
      }
    }
  }

  void _knockPlayerFromNpc(Vector2 attackerCenter) {
    var dx = manWorldPos.x - attackerCenter.x;
    if (dx.abs() < 0.01) {
      dx = -facingX * kKickKnockbackPlayer;
    } else {
      dx = dx.sign * kKickKnockbackPlayer;
    }
    final ph = _playerWallHalf;
    applyHorizontalKnockback(manWorldPos, dx, ph.$1, ph.$2, _halfBounds.x);
  }

  void _knockNpcFromPlayer(NpcCharacter npc) {
    var dx = npc.worldCenter.x - manWorldPos.x;
    if (dx.abs() < 0.01) {
      dx = facingX * kKickKnockbackNpc;
    } else {
      dx = dx.sign * kKickKnockbackNpc;
    }
    final nh = _npcWallHalf(npc);
    applyHorizontalKnockback(npc.worldCenter, dx, nh.$1, nh.$2, _halfBounds.x);
  }

  Future<void> _advanceFloor() async {
    if (_floorBusy) return;
    _floorBusy = true;
    pauseEngine();
    try {
      if (session.currentFloor >= kMaxFloor) {
        if (_isMulti) {
          final remote = network!.remotePlayer.value;
          final myFloor = session.currentFloor;
          final myScore = _myScore;
          final theirFloor = remote?.floor ?? 1;
          final theirScore = remote?.score ?? 0;
          final String winner;
          if (myFloor > theirFloor) {
            winner = session.playerTag;
          } else if (theirFloor > myFloor) {
            winner = _remoteName.isEmpty
                ? (network!.isHost ? 'GUEST' : 'HOST')
                : _remoteName;
          } else if (myScore > theirScore) {
            winner = session.playerTag;
          } else if (theirScore > myScore) {
            winner = _remoteName.isEmpty
                ? (network!.isHost ? 'GUEST' : 'HOST')
                : _remoteName;
          } else {
            winner = 'DRAW';
          }
          final hostPts = network!.isHost ? myScore : theirScore;
          final guestPts = network!.isHost ? theirScore : myScore;
          await network!.finishMatch(
            hostScore: hostPts,
            guestScore: guestPts,
            winnerTag: winner,
          );
        }
        await onVictory();
        session.currentFloor = 1;
        _myScore = 0;
      } else {
        session.currentFloor++;
      }
      _healFullOnWin();
      await _spawnFloorNpcs();
    } finally {
      resumeEngine();
      _floorBusy = false;
    }
  }

  void _runDeathFlow() {
    if (_deathBusy || player.health > 0) return;
    _deathBusy = true;
    pauseEngine();
    unawaited(_runDeathFlowAsync());
  }

  Future<void> _runDeathFlowAsync() async {
    final yes = await onRequestRevive();
    if (!isLoaded) return;
    if (yes) {
      session.revive.consumeFreeRevive();
      player.healFull();
      _randomSpawnInField();
    } else if (_isMulti) {
      player.healFull();
      _randomSpawnInField();
    } else {
      final floor = session.currentFloor;
      final elapsed = getRunElapsedSeconds?.call() ?? 0;
      onSinglePlayerRunEnded?.call(floor, elapsed);
      return;
    }
    _deathBusy = false;
    resumeEngine();
  }

  @override
  Future<void> onLoad() async {
    final field = GrassFieldLayer()
      ..size = Vector2(size.x, size.y);
    grassField = field;
    add(field);

    if (_isMulti) {
      if (_isHost) {
        player = await MultiplayerHostCharacter.load(images);
      } else {
        player = await MultiplayerGuestLocalCharacter.load(images);
      }
    } else {
      player = await SinglePlayerCharacter.load(images);
    }
    add(player);
    player.position = size / 2;
    remoteWorldPos.setFrom(manWorldPos + Vector2(80, 0));

    if (_isMulti) {
      remotePlayer = await MultiplayerGuestCharacter.load(images);
      remotePlayer!.opacity = 0;
      remotePlayer!.position = size / 2;
      add(remotePlayer!);
      remoteHpBar = HpBar()..label = 'REMOTE';
      remoteHpBar!.position.setValues(-9999, -9999);
      add(remoteHpBar!);
    }

    hpBar = HpBar();
    add(hpBar);

    await _spawnFloorNpcs();

    final identity = await PlayerIdentityService.resolve();
    session.playerTag = identity.displayName;
    hpBar.label = identity.displayName;
    await _playerRepo.registerPlayer(identity);

    hpBar.followPlayerFeet(player.position, player.size);
    hpBar.setFilled(player.health);
    if (remotePlayer != null && remoteHpBar != null) {
      remoteHpBar!.followPlayerFeet(remotePlayer!.position, remotePlayer!.size);
      remoteHpBar!.setFilled(player.health);
    }
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    grassField?.size.setFrom(size);
    if (isLoaded) {
      hpBar.followPlayerFeet(player.position, player.size);
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!isLoaded) return;

    session.stats.tickBuffs(dt);

    for (final npc in _npcs) {
      npc.finishAttackIfNeeded();
    }
    player.finishAttackIfNeeded();
    remotePlayer?.finishAttackIfNeeded();

    if (!player.isAttacking) {
      final mult = session.stats.effectiveSpeedScale;
      final ph = _playerWallHalf;
      tryMoveWithWorldWalls(
        manWorldPos,
        velocity.x * dt * mult,
        velocity.y * dt * mult,
        ph.$1,
        ph.$2,
      );
      manWorldPos.x = manWorldPos.x.clamp(-_halfBounds.x, _halfBounds.x);
      manWorldPos.y = manWorldPos.y.clamp(-_halfBounds.y, _halfBounds.y);
      if (worldWallOverlapsAabb(
        manWorldPos.x,
        manWorldPos.y,
        ph.$1,
        ph.$2,
      )) {
        resolveWorldWallsForCenter(manWorldPos, ph.$1, ph.$2);
      }
    }

    for (var i = _pickups.length - 1; i >= 0; i--) {
      final blob = _pickups[i];
      if (manWorldPos.distanceTo(blob.worldCenter) < kPickupPickupRadius) {
        if (blob.kind == _PickupKind.power) {
          session.stats.activatePowerBuff();
        } else {
          session.stats.activateSpeedBuff();
        }
        remove(blob);
        _pickups.removeAt(i);
      }
    }

    final cam = _cameraTopLeft();
    grassField!.cameraTopLeft = cam;
    for (final blob in _pickups) {
      blob.syncCam(cam);
    }
    for (final npc in _npcs) {
      npc.syncScreenPosition(cam);
    }

    for (final npc in _npcs) {
      if (!npc.isAlive) continue;
      npc.nextAttackIn = (npc.nextAttackIn - dt).clamp(0.0, 999.0);
      if (npc.nextAttackIn <= 0 &&
          manWorldPos.distanceTo(npc.worldCenter) <
              ((player.size.x + npc.size.x) * 0.40).clamp(24.0, kNpcAttackRange) &&
          !npc.isAttacking) {
        if (npc.beginAttackToward(manWorldPos)) {
          npc.nextAttackIn = kNpcAttackCooldownSec;
          player.takeDamage(1);
          if (npc.openingAttackIsKick) {
            _knockPlayerFromNpc(npc.worldCenter);
          }
        }
      }
    }

    final aliveNpcCount = _npcs.where((n) => n.isAlive).length;
    if (aliveNpcCount < _prevAliveNpcCount) {
      _healFullOnWin();
    }
    _prevAliveNpcCount = aliveNpcCount;

    if (player.health <= 0) {
      _runDeathFlow();
    }

    if (_npcs.isNotEmpty &&
        _npcs.every((n) => !n.isAlive) &&
        !_floorBusy) {
      _advanceFloor();
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

    final remoteState = network?.remotePlayer.value;
    if (remotePlayer != null) {
      remotePlayer!.opacity = 0;
      remoteHpBar?.position.setValues(-9999, -9999);
    }
    if (remotePlayer != null && remoteState != null) {
      final t = (dt * 8).clamp(0.0, 1.0);
      remoteWorldPos = remoteWorldPos + (Vector2(remoteState.x, remoteState.y) - remoteWorldPos) * t;
      remoteFacingX = remoteState.facingX;
      if (_remoteLastAction != remoteState.action ||
          remoteState.action == AvatarAction.idle ||
          remoteState.action == AvatarAction.walk) {
        remotePlayer!.playRemoteAction(
          remoteState.action,
          facingX: remoteFacingX,
          targetWorld: manWorldPos,
        );
        _remoteLastAction = remoteState.action;
      }
      remotePlayer!.position = remoteWorldPos - cam;

      if (remoteState.hp <= 0) {
        if (!_healedAfterRemoteDown) {
          _healFullOnWin();
          _healedAfterRemoteDown = true;
        }
      } else {
        _healedAfterRemoteDown = false;
      }
    }

    for (var i = 0; i < _npcs.length; i++) {
      final npc = _npcs[i];
      final bar = _npcHpBars[i];
      bar.followPlayerFeet(npc.position, npc.size);
      bar.setFilled(npc.health);
    }

    if (_isMulti) {
      _remoteName = network!.remoteTag.value;
      final moving = velocity.length2 > 1;
      final action = player.isAttacking
          ? player.action
          : (moving ? AvatarAction.walk : AvatarAction.idle);
      unawaited(
        network!.publishPlayer(
          PlayerNetState(
            x: manWorldPos.x,
            y: manWorldPos.y,
            facingX: facingX,
            hp: player.health,
            action: action,
            updatedAtMs: DateTime.now().millisecondsSinceEpoch,
            score: _myScore,
            floor: session.currentFloor,
          ),
        ),
      );
      if (_isHost) {
        final rem = network!.remotePlayer.value?.score ?? 0;
        unawaited(
          network!.publishWorld(
            WorldNetState(
              floor: session.currentFloor,
              npcs: const <NpcNetState>[],
              victory: false,
              hostScore: _myScore,
              guestScore: rem,
              winnerTag: '',
            ),
          ),
        );
      }
    }

    final oppScore = network?.remotePlayer.value?.score;
    final hudSnap = FieldOverlayHudData(
      floor: session.currentFloor,
      hp: player.health,
      hpMax: kDefaultMaxHp,
      npcAlive: _npcs.where((n) => n.isAlive).length,
      npcTotal: _npcs.length,
      remoteShort: _isMulti ? _remoteName : '',
      hostScore: _isMulti
          ? (_isHost ? _myScore : (oppScore ?? 0))
          : null,
      guestScore: _isMulti
          ? (_isHost ? (oppScore ?? 0) : _myScore)
          : null,
      powerBuffSecRemain: session.stats.powerBuffRemainingSecCeil,
      speedBuffSecRemain: session.stats.speedBuffRemainingSecCeil,
    );
    if (overlayHud != null && overlayHud!.value != hudSnap) {
      overlayHud!.value = hudSnap;
    }
  }

  @override
  KeyEventResult onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    if (isLoaded && event is KeyDownEvent) {
      final k = event.logicalKey;
      if (k == LogicalKeyboardKey.digit1 ||
          k == LogicalKeyboardKey.numpad1) {
        triggerPunch();
      } else if (k == LogicalKeyboardKey.digit2 ||
          k == LogicalKeyboardKey.numpad2) {
        triggerKick();
      }
    }

    _keyVelocity.setZero();
    if (keysPressed.contains(LogicalKeyboardKey.arrowUp)) {
      _keyVelocity.y -= 1;
    }
    if (keysPressed.contains(LogicalKeyboardKey.arrowDown)) {
      _keyVelocity.y += 1;
    }
    if (keysPressed.contains(LogicalKeyboardKey.arrowLeft)) {
      _keyVelocity.x -= 1;
    }
    if (keysPressed.contains(LogicalKeyboardKey.arrowRight)) {
      _keyVelocity.x += 1;
    }
    _rebuildVelocity();

    return KeyEventResult.handled;
  }
}
