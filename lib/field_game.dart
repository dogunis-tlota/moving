import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/components.dart' hide Timer;
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
import 'boss_character.dart';
import 'boss_reward_skill.dart';
import 'dungeon_layout.dart';
import 'npc_aggression.dart';
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
    this.roomNumber = 5,
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
  /// 1…9 (3×3 방).
  final int roomNumber;
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
          roomNumber == other.roomNumber &&
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
        roomNumber,
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
    this.bossBanner,
    this.getRunElapsedSeconds,
    this.onSinglePlayerRunEnded,
  });

  final GameSession session;
  final Future<bool> Function() onRequestRevive;
  final Future<void> Function() onVictory;
  final NetworkSession? network;
  final ValueNotifier<FieldOverlayHudData>? overlayHud;
  /// 상단 큰 보스 등장 문구(몇 초 후 자동 해제).
  final ValueNotifier<String?>? bossBanner;
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

  BossCharacter? _boss;
  HpBar? _bossHpBar;
  double _bossNextAttackIn = 0;
  Timer? _bossBannerClearTimer;

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
  bool _attackComboRunning = false;

  final FirebasePlayerRepository _playerRepo = FirebasePlayerRepository();

  bool get _isMulti => network != null;

  BossRewardSkill? get _rewardSkill => session.bossRewardSkill;
  bool get _isHost => network?.isHost ?? true;
  int _prevAliveNpcCount = 0;
  bool _healedAfterRemoteDown = false;
  String _remoteName = '';
  /// 격자 방 (0…2). 시작은 중앙 (1,1).
  int _roomX = 1;
  int _roomY = 1;
  double _roomTransitionCooldown = 0;
  /// 멀티: 내 인스턴스에서 NPC 처치로 얻은 점수.
  int _myScore = 0;
  /// 방마다 1→2→3→4명 웨이브. 5 = 4번째 웨이브까지 스폰 완료 후 전원 처치 시 층 진행.
  int _roomWaveIndex = 1;
  double _roomWaveSpawnDelay = kNpcRoomFirstSpawnDelaySec;
  bool _npcWaveSpawnBusy = false;

  Vector2 get _halfBounds => Vector2(kMapWidth / 2, kMapHeight / 2);

  double get _bossFightMoveFactor =>
      (_boss != null && _boss!.isAlive) ? kBossFightMoveSpeedFactor : 1.0;

  (double hw, double hh) get _playerWallHalf =>
      (player.size.x * 0.38, player.size.y * 0.42);

  (double hw, double hh) _npcWallHalf(NpcCharacter n) =>
      (n.size.x * 0.36, n.size.y * 0.38);

  /// 플레이어 중심(`manWorldPos`)을 화면 중앙에 두려는 카메라를 구한 뒤, 맵 밖이 보이지 않게 클램프.
  /// 클램프 시 배경은 멈추고 `player.position = manWorldPos - cam`으로 캐릭터만 화면 안에서 움직임.
  Vector2 _cameraTopLeft() {
    final halfW = kMapWidth / 2;
    final halfH = kMapHeight / 2;
    final vw = size.x;
    final vh = size.y;
    var cx = manWorldPos.x - vw / 2;
    var cy = manWorldPos.y - vh / 2;

    double clampCam(double ideal, double minC, double maxC) {
      if (maxC < minC) {
        return (minC + maxC) / 2;
      }
      return ideal.clamp(minC, maxC);
    }

    cx = clampCam(cx, -halfW, halfW - vw);
    cy = clampCam(cy, -halfH, halfH - vh);
    return Vector2(cx, cy);
  }

  void _syncGrassRoom() {
    grassField?.syncDoorsForRoom(_roomX, _roomY);
  }

  void _afterRoomChange() {
    _roomTransitionCooldown = 0.45;
    _syncGrassRoom();
    unawaited(_spawnFloorNpcs());
  }

  void _removeBossIfAny() {
    _bossBannerClearTimer?.cancel();
    _bossBannerClearTimer = null;
    if (_boss != null) {
      remove(_boss!);
      _boss = null;
    }
    if (_bossHpBar != null) {
      remove(_bossHpBar!);
      _bossHpBar = null;
    }
    _bossNextAttackIn = 0;
  }

  Vector2 _randomBossSpawnNearDoor() {
    final hw = _halfBounds.x;
    const inset = 82.0;
    double jx() => (_rng.nextDouble() * 2 - 1) * (kDoorGapHalfWorld * 0.78);
    double jy() => (_rng.nextDouble() * 2 - 1) * (kDoorGapHalfWorld * 0.55);
    final candidates = <Vector2>[];
    if (DungeonLayout.hasNorth(_roomX, _roomY)) {
      candidates.add(Vector2(jx(), kPathMinWorldY + inset));
    }
    if (DungeonLayout.hasSouth(_roomX, _roomY)) {
      candidates.add(Vector2(jx(), kPathMaxWorldY - inset));
    }
    if (DungeonLayout.hasEast(_roomX, _roomY)) {
      candidates.add(Vector2(hw - inset, kPathMidWorldY + jy()));
    }
    if (DungeonLayout.hasWest(_roomX, _roomY)) {
      candidates.add(Vector2(-hw + inset, kPathMidWorldY + jy()));
    }
    if (candidates.isEmpty) {
      return Vector2(0, kPathMidWorldY);
    }
    final pick = candidates[_rng.nextInt(candidates.length)];
    return Vector2(pick.x, pick.y);
  }

  Future<void> _spawnFieldBoss() async {
    if (_boss != null || _floorBusy) return;
    _floorBusy = true;
    try {
      _roomWaveIndex = 6;
      final boss = await BossCharacter.loadForField(images, player.size);
      boss.worldHalfBounds = _halfBounds;
      boss.worldPathMinY = kPathMinWorldY;
      boss.worldPathMaxY = kPathMaxWorldY;
      boss.worldCenter.setFrom(_randomBossSpawnNearDoor());
      final bh = (boss.size.x * 0.36, boss.size.y * 0.38);
      for (var t = 0; t < 12; t++) {
        if (!worldWallOverlapsAabb(
          boss.worldCenter.x,
          boss.worldCenter.y,
          bh.$1,
          bh.$2,
        )) {
          break;
        }
        boss.worldCenter.setFrom(_randomBossSpawnNearDoor());
      }
      resolveWorldWallsForCenter(boss.worldCenter, bh.$1, bh.$2);
      add(boss);
      _boss = boss;
      _bossNextAttackIn = 0.4;
      final bar = HpBar(segmentCount: boss.maxHp)..label = 'BOSS';
      bar.setFilled(boss.hp);
      add(bar);
      _bossHpBar = bar;

      bossBanner?.value = '보스가 등장했다!';
      _bossBannerClearTimer?.cancel();
      _bossBannerClearTimer = Timer(const Duration(seconds: 4), () {
        bossBanner?.value = null;
      });
    } finally {
      _floorBusy = false;
    }
  }

  Future<void> _onFieldBossDefeated() async {
    session.bossRewardSkill = BossRewardSkill
        .values[_rng.nextInt(BossRewardSkill.values.length)];
    await _advanceFloor();
  }

  /// 출입구(이웃이 있는 변)에서만 이웃 방으로 전환.
  bool _tryRoomTransition() {
    if (_roomTransitionCooldown > 0) return false;
    if (player.isAttacking) return false;
    const doorDepth = 56.0;
    const inset = 92.0;
    const vMin = 38.0;
    final mult = session.stats.effectiveSpeedScale;
    final vx = velocity.x * mult;
    final vy = velocity.y * mult;
    final hw = _halfBounds.x;
    final doorX = kDoorGapHalfWorld;
    final my = kPathMidWorldY;

    // 동·서: 세로 문은 길 중앙 부근(|y - my| ≤ doorX)에서만.
    if (DungeonLayout.hasEast(_roomX, _roomY) &&
        manWorldPos.x >= hw - doorDepth &&
        vx > vMin &&
        (manWorldPos.y - my).abs() <= doorX) {
      _roomX++;
      manWorldPos.x = -hw + inset;
      _afterRoomChange();
      return true;
    }
    if (DungeonLayout.hasWest(_roomX, _roomY) &&
        manWorldPos.x <= -hw + doorDepth &&
        vx < -vMin &&
        (manWorldPos.y - my).abs() <= doorX) {
      _roomX--;
      manWorldPos.x = hw - inset;
      _afterRoomChange();
      return true;
    }
    // 남·북: 가로 문은 x≈0 중앙(|x| ≤ doorX)에서만.
    if (DungeonLayout.hasSouth(_roomX, _roomY) &&
        manWorldPos.y >= kPathMaxWorldY - doorDepth &&
        vy > vMin &&
        manWorldPos.x.abs() <= doorX) {
      _roomY++;
      manWorldPos.y = kPathMinWorldY + inset;
      _afterRoomChange();
      return true;
    }
    if (DungeonLayout.hasNorth(_roomX, _roomY) &&
        manWorldPos.y <= kPathMinWorldY + doorDepth &&
        vy < -vMin &&
        manWorldPos.x.abs() <= doorX) {
      _roomY--;
      manWorldPos.y = kPathMaxWorldY - inset;
      _afterRoomChange();
      return true;
    }
    return false;
  }

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
    manWorldPos.y = manWorldPos.y.clamp(kPathMinWorldY, kPathMaxWorldY);
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
    _removeBossIfAny();
    _clearNpcs();
    _roomWaveIndex = 1;
    _roomWaveSpawnDelay = kNpcRoomFirstSpawnDelaySec;
    _npcWaveSpawnBusy = false;
    _prevAliveNpcCount = 0;
    _spawnPickups();
  }

  void _randomizeNpcStats(NpcCharacter npc, int floor) {
    npc.aggression = NpcAggression.values[_rng.nextInt(3)];
    npc.wanderSpeed = kPlayerFieldMoveSpeed;
    npc.meleeDamage = 1 + _rng.nextInt(3);
    npc.maxHp = npcMaxHpForFloor(floor);
    npc.health = npc.maxHp;
    npc.tintColor = HSVColor.fromAHSV(
      1,
      _rng.nextDouble() * 360,
      0.65 + _rng.nextDouble() * 0.25,
      0.85 + _rng.nextDouble() * 0.12,
    ).toColor();
    npc.paint.colorFilter = ColorFilter.mode(npc.tintColor, BlendMode.srcATop);
  }

  Future<void> _spawnNpcWaveBatch(int batchSize) async {
    if (batchSize < 1 || batchSize > 4) return;
    _npcWaveSpawnBusy = true;
    try {
      final floor = session.currentFloor;
      for (var i = 0; i < batchSize; i++) {
        final npc = await NpcCharacter.load(images);
        _randomizeNpcStats(npc, floor);
        npc.worldHalfBounds = _halfBounds;
        npc.worldPathMinY = kPathMinWorldY;
        npc.worldPathMaxY = kPathMaxWorldY;
        final base = _rng.nextDouble() * 2 * pi;
        final angle = base + (i / batchSize) * 2 * pi * 0.88;
        final dist = 400 + _rng.nextDouble() * 240;
        npc.worldCenter.setFrom(
          manWorldPos + Vector2(cos(angle) * dist, sin(angle) * dist),
        );
        npc.worldCenter.x =
            npc.worldCenter.x.clamp(-_halfBounds.x, _halfBounds.x);
        npc.worldCenter.y =
            npc.worldCenter.y.clamp(kPathMinWorldY, kPathMaxWorldY);
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
          final d = 380 + _rng.nextDouble() * 260;
          npc.worldCenter.setFrom(
            manWorldPos + Vector2(cos(ang) * d, sin(ang) * d),
          );
          npc.worldCenter.x =
              npc.worldCenter.x.clamp(-_halfBounds.x, _halfBounds.x);
          npc.worldCenter.y =
              npc.worldCenter.y.clamp(kPathMinWorldY, kPathMaxWorldY);
        }
        resolveWorldWallsForCenter(npc.worldCenter, nh.$1, nh.$2);
        npc.nextAttackIn = 0;
        add(npc);
        _npcs.add(npc);

        final bar = HpBar(segmentCount: npc.maxHp);
        bar.setFilled(npc.health);
        add(bar);
        _npcHpBars.add(bar);
      }
      _prevAliveNpcCount = _npcs.where((n) => n.isAlive).length;
    } finally {
      _npcWaveSpawnBusy = false;
    }
  }

  Future<void> _spawnNpcWaveBatchAndIncrement(int batchSize) async {
    await _spawnNpcWaveBatch(batchSize);
    _roomWaveIndex++;
    _roomWaveSpawnDelay = 0;
  }

  void _tryProgressRoomNpcWaves(double dt) {
    if (_floorBusy || _npcWaveSpawnBusy) return;
    if (_roomWaveIndex == 0) return;

    if (_boss != null && !_boss!.isAlive && !_floorBusy) {
      _removeBossIfAny();
      unawaited(_onFieldBossDefeated());
      return;
    }

    final anyAlive = _npcs.any((n) => n.isAlive);

    if (!anyAlive &&
        _npcs.isNotEmpty &&
        _npcs.every((n) => !n.isAlive) &&
        _roomWaveIndex == 5 &&
        _boss == null &&
        !_floorBusy) {
      unawaited(_spawnFieldBoss());
      return;
    }

    if (anyAlive) return;
    if (_roomWaveIndex > 4) return;

    if (_roomWaveSpawnDelay > 0) {
      _roomWaveSpawnDelay -= dt;
      return;
    }

    final size = _roomWaveIndex;
    unawaited(_spawnNpcWaveBatchAndIncrement(size));
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
        wc.y = wc.y.clamp(kPathMinWorldY, kPathMaxWorldY);
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

  void _purgeDeadNpcs() {
    for (var i = _npcs.length - 1; i >= 0; i--) {
      if (_npcs[i].isAlive) continue;
      remove(_npcs[i]);
      remove(_npcHpBars[i]);
      _npcs.removeAt(i);
      _npcHpBars.removeAt(i);
    }
  }

  void _rebuildVelocity() {
    final baseSpeed = kPlayerFieldMoveSpeed;
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
    if (_attackComboRunning) return;
    if (_rewardSkill == BossRewardSkill.triplePunch) {
      unawaited(_runTriplePunchCombo());
      return;
    }
    _singlePunchStrike();
  }

  void _singlePunchStrike() {
    final beforeHp = _npcs.map((n) => n.health).toList(growable: false);
    final beforeBossHp = _boss?.hp;
    player.tryPunch(
      manWorldPos,
      facingX,
      npcs: _npcs,
      boss: _boss,
      bossWorldCenter: _boss?.worldCenter,
      damage: session.stats.punchDamage,
    );
    if (_isMulti) {
      final kills = _countNpcKills(beforeHp);
      if (kills > 0) {
        _myScore += kills * 10;
      }
    }
    _applyPunchStunAfterHit(beforeHp, beforeBossHp);
  }

  Future<void> _runTriplePunchCombo() async {
    if (_attackComboRunning) return;
    _attackComboRunning = true;
    try {
      for (var hit = 0; hit < 3; hit++) {
        if (!isLoaded || player.health <= 0) return;
        _singlePunchStrike();
        if (hit == 2) break;
        while (player.isAttacking && isLoaded) {
          await Future<void>.delayed(const Duration(milliseconds: 16));
        }
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
    } finally {
      _attackComboRunning = false;
    }
  }

  void _applyPunchStunAfterHit(List<int> beforeNpcHp, int? beforeBossHp) {
    if (_rewardSkill != BossRewardSkill.punchStun) return;
    final n = min(beforeNpcHp.length, _npcs.length);
    for (var i = 0; i < n; i++) {
      if (beforeNpcHp[i] > _npcs[i].health && _npcs[i].isAlive) {
        _npcs[i].addStun(0.5);
      }
    }
    if (beforeBossHp != null &&
        _boss != null &&
        _boss!.isAlive &&
        beforeBossHp > _boss!.hp) {
      _boss!.addStun(0.5);
    }
  }

  void triggerKick() {
    if (!isLoaded) return;
    if (_attackComboRunning) return;
    if (_rewardSkill == BossRewardSkill.tripleKickNoKnockback) {
      unawaited(_runTripleKickCombo());
      return;
    }
    final beforeHp = _npcs.map((n) => n.health).toList(growable: false);
    final bossHpBefore = _boss?.hp;
    player.tryKick(
      manWorldPos,
      facingX,
      npcs: _npcs,
      boss: _boss,
      bossWorldCenter: _boss?.worldCenter,
      damage: session.stats.kickDamage,
    );
    for (var i = 0; i < _npcs.length; i++) {
      if (beforeHp[i] > _npcs[i].health) {
        _knockNpcFromPlayer(_npcs[i]);
      }
    }
    if (bossHpBefore != null &&
        _boss != null &&
        _boss!.hp < bossHpBefore) {
      _knockBossFromPlayer();
    }
    if (_isMulti) {
      final kills = _countNpcKills(beforeHp);
      if (kills > 0) {
        _myScore += kills * 10;
      }
    }
  }

  Future<void> _runTripleKickCombo() async {
    if (_attackComboRunning) return;
    _attackComboRunning = true;
    try {
      for (var hit = 0; hit < 3; hit++) {
        if (!isLoaded || player.health <= 0) return;
        final beforeHp = _npcs.map((n) => n.health).toList(growable: false);
        player.tryKick(
          manWorldPos,
          facingX,
          npcs: _npcs,
          boss: _boss,
          bossWorldCenter: _boss?.worldCenter,
          damage: session.stats.kickDamage,
        );
        if (_isMulti) {
          final kills = _countNpcKills(beforeHp);
          if (kills > 0) {
            _myScore += kills * 10;
          }
        }
        if (hit == 2) break;
        while (player.isAttacking && isLoaded) {
          await Future<void>.delayed(const Duration(milliseconds: 16));
        }
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
    } finally {
      _attackComboRunning = false;
    }
  }

  double _kickKnockDistance() {
    var d = kKickKnockbackNpc.toDouble();
    if (_rewardSkill == BossRewardSkill.kickKnockback15) {
      d *= 1.5;
    }
    return d;
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
    if (_rewardSkill == BossRewardSkill.tripleKickNoKnockback) return;
    final dist = _kickKnockDistance();
    var dx = npc.worldCenter.x - manWorldPos.x;
    if (dx.abs() < 0.01) {
      dx = facingX * dist;
    } else {
      dx = dx.sign * dist;
    }
    final nh = _npcWallHalf(npc);
    applyHorizontalKnockback(npc.worldCenter, dx, nh.$1, nh.$2, _halfBounds.x);
  }

  void _knockBossFromPlayer() {
    if (_boss == null || !_boss!.isAlive) return;
    if (_rewardSkill == BossRewardSkill.tripleKickNoKnockback) return;
    final dist = _kickKnockDistance();
    var dx = _boss!.worldCenter.x - manWorldPos.x;
    if (dx.abs() < 0.01) {
      dx = facingX * dist;
    } else {
      dx = dx.sign * dist;
    }
    final bh = (_boss!.size.x * 0.36, _boss!.size.y * 0.38);
    applyHorizontalKnockback(
      _boss!.worldCenter,
      dx,
      bh.$1,
      bh.$2,
      _halfBounds.x,
    );
  }

  Future<void> _advanceFloor() async {
    if (_floorBusy) return;
    _floorBusy = true;
    pauseEngine();
    try {
      _removeBossIfAny();
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
        _healFullOnWin();
        await _spawnFloorNpcs();
      } else {
        session.currentFloor++;
        _healFullOnWin();
        _roomWaveIndex = 0;
        // 같은 방에서는 더 이상 스폰 없음. 다음 방 `_spawnFloorNpcs`에서 1→… 웨이브 재시작.
      }
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
    player.position = manWorldPos - _cameraTopLeft();
    remoteWorldPos.setFrom(manWorldPos + Vector2(80, 0));

    if (_isMulti) {
      remotePlayer = await MultiplayerGuestCharacter.load(images);
      remotePlayer!.opacity = 0;
      remotePlayer!.position = remoteWorldPos - _cameraTopLeft();
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
      remoteHpBar!.setFilled(kDefaultMaxHp);
    }
    _syncGrassRoom();
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
    if (!isLoaded) return;

    final bfm = _bossFightMoveFactor;
    final spdScale = session.stats.effectiveSpeedScale;
    for (final n in _npcs) {
      if (n.isAlive) {
        n.chaseTargetWorld = manWorldPos;
      }
      n.worldSpeedFactor = bfm;
      n.wanderSpeed = kPlayerFieldMoveSpeed * spdScale;
    }
    _tryProgressRoomNpcWaves(dt);

    super.update(dt);

    session.stats.tickBuffs(dt);
    if (_roomTransitionCooldown > 0) {
      _roomTransitionCooldown -= dt;
      if (_roomTransitionCooldown < 0) {
        _roomTransitionCooldown = 0;
      }
    }

    for (final npc in _npcs) {
      npc.finishAttackIfNeeded();
    }
    _boss?.finishAttackIfNeeded();
    player.finishAttackIfNeeded();
    remotePlayer?.finishAttackIfNeeded();

    if (!player.isAttacking) {
      final mult =
          session.stats.effectiveSpeedScale * _bossFightMoveFactor;
      final ph = _playerWallHalf;
      tryMoveWithWorldWalls(
        manWorldPos,
        velocity.x * dt * mult,
        velocity.y * dt * mult,
        ph.$1,
        ph.$2,
      );
      if (!_tryRoomTransition()) {
        manWorldPos.x = manWorldPos.x.clamp(-_halfBounds.x, _halfBounds.x);
        manWorldPos.y =
            manWorldPos.y.clamp(kPathMinWorldY, kPathMaxWorldY);
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
    if (_boss != null) {
      final bsf = _bossFightMoveFactor;
      _boss!.chaseSpeedWorld = kPlayerFieldMoveSpeed * session.stats.effectiveSpeedScale;
      _boss!.stepMovement(dt, manWorldPos, speedFactor: bsf);
      _boss!.syncScreen(cam);
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
          player.takeDamage(npc.meleeDamage.clamp(1, 99));
          if (npc.openingAttackIsKick) {
            _knockPlayerFromNpc(npc.worldCenter);
          }
        }
      }
    }

    if (_boss != null && _boss!.isAlive) {
      _bossNextAttackIn = (_bossNextAttackIn - dt).clamp(0.0, 999.0);
      if (_bossNextAttackIn <= 0 &&
          manWorldPos.distanceTo(_boss!.worldCenter) <
              ((player.size.x + _boss!.size.x) * 0.40)
                  .clamp(24.0, kNpcAttackRange) &&
          !_boss!.isAttacking) {
        if (_boss!.beginAttackToward(manWorldPos)) {
          _bossNextAttackIn = kNpcAttackCooldownSec;
          player.takeDamage(_boss!.attackDamage.clamp(1, 99));
        }
      }
    }

    final aliveNpcCount = _npcs.where((n) => n.isAlive).length;
    if (aliveNpcCount < _prevAliveNpcCount) {
      _healFullOnWin();
    }
    _prevAliveNpcCount = aliveNpcCount;
    _purgeDeadNpcs();

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
    player.position = manWorldPos - cam;

    hpBar.followPlayerFeet(player.position, player.size);
    hpBar.setFilled(player.health);

    final remoteState = network?.remotePlayer.value;
    if (remotePlayer != null && remoteState != null) {
      final sameRoom =
          remoteState.roomRx == _roomX && remoteState.roomRy == _roomY;
      if (sameRoom) {
        remotePlayer!.opacity = 1;
        final t = (dt * 8).clamp(0.0, 1.0);
        remoteWorldPos =
            remoteWorldPos + (Vector2(remoteState.x, remoteState.y) - remoteWorldPos) * t;
        remoteWorldPos.x =
            remoteWorldPos.x.clamp(-_halfBounds.x, _halfBounds.x);
        remoteWorldPos.y =
            remoteWorldPos.y.clamp(kPathMinWorldY, kPathMaxWorldY);
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
        remoteHpBar?.followPlayerFeet(remotePlayer!.position, remotePlayer!.size);
        remoteHpBar?.setFilled(remoteState.hp);

        if (remoteState.hp <= 0) {
          if (!_healedAfterRemoteDown) {
            _healFullOnWin();
            _healedAfterRemoteDown = true;
          }
        } else {
          _healedAfterRemoteDown = false;
        }
      } else {
        remotePlayer!.opacity = 0;
        remoteHpBar?.position.setValues(-9999, -9999);
      }
    } else if (remotePlayer != null) {
      remotePlayer!.opacity = 0;
      remoteHpBar?.position.setValues(-9999, -9999);
    }

    for (var i = 0; i < _npcs.length; i++) {
      final npc = _npcs[i];
      final bar = _npcHpBars[i];
      bar.followPlayerFeet(npc.position, npc.size);
      bar.setFilled(npc.health);
    }
    if (_bossHpBar != null && _boss != null) {
      _bossHpBar!.followPlayerFeet(_boss!.position, _boss!.size);
      _bossHpBar!.setFilled(_boss!.hp);
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
            roomRx: _roomX,
            roomRy: _roomY,
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
      npcAlive: _npcs.where((n) => n.isAlive).length +
          ((_boss?.isAlive ?? false) ? 1 : 0),
      npcTotal: _npcs.length + ((_boss != null) ? 1 : 0),
      roomNumber: DungeonLayout.roomNumber1to9(_roomX, _roomY),
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

  @override
  void onRemove() {
    _bossBannerClearTimer?.cancel();
    super.onRemove();
  }
}
