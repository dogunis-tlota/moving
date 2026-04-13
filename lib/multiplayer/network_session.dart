import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../firebase_init.dart';
import 'firebase_auth_service.dart';
import 'realtime_room_service.dart';
import 'room_models.dart';

class NetworkSession {
  NetworkSession({
    RealtimeRoomService? service,
    FirebaseAuthService? authService,
  }) : _service = service ?? RealtimeRoomService(),
       _authService = authService ?? FirebaseAuthService();

  final RealtimeRoomService _service;
  final FirebaseAuthService _authService;

  String roomCode = '';
  String localPlayerId = '';
  String localTag = '';
  bool isHost = false;

  /// 방에 있는 모든 플레이어(로컬 포함).
  final ValueNotifier<Map<String, PlayerNetState>> allPlayers =
      ValueNotifier<Map<String, PlayerNetState>>({});

  /// 로컬을 제외한 상대 목록.
  final ValueNotifier<Map<String, PlayerNetState>> remotePlayers =
      ValueNotifier<Map<String, PlayerNetState>>({});

  /// `playerId` → 표시 태그.
  final ValueNotifier<Map<String, String>> playerTags =
      ValueNotifier<Map<String, String>>({});

  final ValueNotifier<WorldNetState> world = ValueNotifier(WorldNetState.initial());
  final ValueNotifier<bool> victory = ValueNotifier(false);
  final ValueNotifier<String?> error = ValueNotifier(null);
  /// 디버그 빌드용: 최근 1초 네트워크 TX 요약.
  final ValueNotifier<String> debugTxSummary = ValueNotifier<String>('');

  StreamSubscription<Map<String, PlayerNetState>>? _playersSub;
  StreamSubscription<WorldNetState>? _worldSub;
  StreamSubscription<String>? _phaseSub;
  StreamSubscription<Map<String, String>>? _playerTagsSub;

  int _lastPublishPlayerMs = 0;
  int _lastPublishWorldMs = 0;
  PlayerNetState? _lastPublishedPlayer;
  WorldNetState? _lastPublishedWorld;
  int _dbgPlayerWrites = 0;
  int _dbgWorldWrites = 0;
  int _dbgPlayerSuppressed = 0;
  int _dbgWorldSuppressed = 0;
  int _dbgPlayersRx = 0;
  int _dbgWorldRx = 0;
  int _dbgPhaseRx = 0;
  int _dbgTagsRx = 0;
  int _dbgLastReportMs = 0;

  static const int _playerMinPublishMs = 40;
  static const int _playerHeartbeatMs = 350;
  static const int _worldMinPublishMs = 70;
  static const int _worldHeartbeatMs = 500;
  static const double _positionEpsilon = 2.0;
  static const double _facingEpsilon = 0.05;

  static String generateRoomCode() {
    final rng = Random();
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  static Future<List<String>> listOpenRoomCodes() async {
    await ensureFirebaseInitialized();
    return RealtimeRoomService().listJoinableRoomCodes();
  }

  static Future<List<String>> listRoomCodesFromDatabase({int limit = 80}) async {
    await ensureFirebaseInitialized();
    return RealtimeRoomService().listRoomCodesInDatabase(limit: limit);
  }

  static Future<String?> tryRestoreHostRoomCode() async {
    await ensureFirebaseInitialized();
    final auth = FirebaseAuthService();
    final user = await auth.ensureSignedInAnonymously();
    return RealtimeRoomService().fetchPendingRoomCodeForHost(user.uid);
  }

  Future<bool> attachAsHost({
    required String roomCode,
    required String playerTag,
  }) async {
    await _ensureFirebaseReady();
    final user = await _authService.ensureSignedInAnonymously();
    final snap = await _service.roomRef(roomCode).get();
    final raw = snap.value;
    if (raw is! Map) return false;
    final map = raw.map((k, v) => MapEntry(k.toString(), v));
    if ((map['hostPlayerId'] ?? '').toString() != user.uid) return false;
    final phase = (map['phase'] ?? '').toString();
    if (phase == 'finished') return false;
    this.roomCode = roomCode;
    localPlayerId = user.uid;
    localTag = playerTag;
    isHost = true;
    _bindStreams();
    await _service.putHostPendingRoomCode(user.uid, roomCode);
    return true;
  }

  Future<void> _ensureFirebaseReady() async {
    try {
      await ensureFirebaseInitialized();
    } catch (e) {
      error.value =
          'Firebase 초기화 실패: $e\n'
          '웹(Chrome) Firebase 옵션을 확인하세요.';
      rethrow;
    }
  }

  Future<void> createRoom({required String playerTag}) async {
    await _ensureFirebaseReady();
    final code = generateRoomCode();
    final user = await _authService.ensureSignedInAnonymously();
    final playerId = user.uid;
    await _service.createRoom(
      roomCode: code,
      hostPlayerId: playerId,
      hostTag: playerTag,
    );
    roomCode = code;
    localPlayerId = playerId;
    localTag = playerTag;
    isHost = true;
    _bindStreams();
  }

  Future<void> autoJoinOrCreate({required String playerTag}) async {
    await _ensureFirebaseReady();
    final joinable = await _service.findJoinableRoomCode();
    if (joinable != null && joinable.isNotEmpty) {
      final ok = await joinRoom(code: joinable, playerTag: playerTag);
      if (ok) return;
    }
    await createRoom(playerTag: playerTag);
  }

  Future<bool> joinRoom({
    required String code,
    required String playerTag,
  }) async {
    await _ensureFirebaseReady();
    final user = await _authService.ensureSignedInAnonymously();
    final playerId = user.uid;
    final ok = await _service.joinRoom(
      roomCode: code.toUpperCase().trim(),
      playerId: playerId,
      playerTag: playerTag,
    );
    if (!ok) return false;
    roomCode = code.toUpperCase().trim();
    localPlayerId = playerId;
    localTag = playerTag;
    isHost = false;
    _bindStreams();
    return true;
  }

  Future<void> leave() async {
    if (roomCode.isEmpty || localPlayerId.isEmpty) {
      await dispose();
      return;
    }
    try {
      await _service.leaveRoom(
        roomCode: roomCode,
        playerId: localPlayerId,
        isHost: isHost,
      );
    } catch (_) {
      // 네트워크 실패해도 로컬 세션은 정리
    } finally {
      await dispose();
    }
  }

  void _bindStreams() {
    _playersSub?.cancel();
    _worldSub?.cancel();
    _phaseSub?.cancel();
    _playerTagsSub?.cancel();

    _playersSub = _service.watchPlayers(roomCode).listen((players) {
      allPlayers.value = players;
      final remotes = <String, PlayerNetState>{};
      for (final e in players.entries) {
        if (e.key != localPlayerId) {
          remotes[e.key] = e.value;
        }
      }
      remotePlayers.value = remotes;
      _dbgPlayersRx++;
      _debugReportNetTraffic(DateTime.now().millisecondsSinceEpoch);
    });

    _worldSub = _service.watchWorld(roomCode).listen((state) {
      world.value = state;
      victory.value = state.victory;
      _dbgWorldRx++;
      _debugReportNetTraffic(DateTime.now().millisecondsSinceEpoch);
    });

    _phaseSub = _service.watchRoomPhase(roomCode).listen((phase) {
      if (phase == 'finished') {
        victory.value = true;
      }
      _dbgPhaseRx++;
      _debugReportNetTraffic(DateTime.now().millisecondsSinceEpoch);
    });

    _playerTagsSub = _service.watchPlayerTags(roomCode).listen((tags) {
      playerTags.value = tags;
      _dbgTagsRx++;
      _debugReportNetTraffic(DateTime.now().millisecondsSinceEpoch);
    });
  }

  Future<void> publishPlayer(PlayerNetState state) async {
    if (roomCode.isEmpty || localPlayerId.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final prev = _lastPublishedPlayer;
    final changed = _playerStateChanged(prev, state);
    final minGap = changed ? _playerMinPublishMs : _playerHeartbeatMs;
    if (now - _lastPublishPlayerMs < minGap) {
      _dbgPlayerSuppressed++;
      _debugReportNetTraffic(now);
      return;
    }
    _lastPublishPlayerMs = now;
    _lastPublishedPlayer = state;
    _dbgPlayerWrites++;
    _debugReportNetTraffic(now);
    await _service.updatePlayerState(
      roomCode: roomCode,
      playerId: localPlayerId,
      state: state,
    );
  }

  Future<void> publishWorld(WorldNetState state) async {
    if (!isHost) return;
    if (roomCode.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final prev = _lastPublishedWorld;
    final changed = _worldStateChanged(prev, state);
    final minGap = changed ? _worldMinPublishMs : _worldHeartbeatMs;
    if (now - _lastPublishWorldMs < minGap) {
      _dbgWorldSuppressed++;
      _debugReportNetTraffic(now);
      return;
    }
    _lastPublishWorldMs = now;
    _lastPublishedWorld = state;
    _dbgWorldWrites++;
    _debugReportNetTraffic(now);
    await _service.updateWorldState(roomCode: roomCode, state: state);
  }

  void _debugReportNetTraffic(int nowMs) {
    if (!kDebugMode) return;
    if (_dbgLastReportMs == 0) {
      _dbgLastReportMs = nowMs;
      return;
    }
    final elapsed = nowMs - _dbgLastReportMs;
    if (elapsed < 1000) return;
    final summary =
        'NET TX P($_dbgPlayerWrites/$_dbgPlayerSuppressed) '
        'W($_dbgWorldWrites/$_dbgWorldSuppressed) '
        'RX Pl$_dbgPlayersRx Wr$_dbgWorldRx Ph$_dbgPhaseRx Tg$_dbgTagsRx';
    debugTxSummary.value = summary;
    debugPrint('[NET TX] $summary');
    _dbgPlayerWrites = 0;
    _dbgWorldWrites = 0;
    _dbgPlayerSuppressed = 0;
    _dbgWorldSuppressed = 0;
    _dbgPlayersRx = 0;
    _dbgWorldRx = 0;
    _dbgPhaseRx = 0;
    _dbgTagsRx = 0;
    _dbgLastReportMs = nowMs;
  }

  bool _playerStateChanged(PlayerNetState? prev, PlayerNetState next) {
    if (prev == null) return true;
    if ((next.x - prev.x).abs() > _positionEpsilon) return true;
    if ((next.y - prev.y).abs() > _positionEpsilon) return true;
    if ((next.facingX - prev.facingX).abs() > _facingEpsilon) return true;
    if (next.hp != prev.hp) return true;
    if (next.action != prev.action) return true;
    if (next.score != prev.score) return true;
    if (next.floor != prev.floor) return true;
    if (next.roomRx != prev.roomRx || next.roomRy != prev.roomRy) return true;
    return false;
  }

  bool _worldStateChanged(WorldNetState? prev, WorldNetState next) {
    if (prev == null) return true;
    if (next.floor != prev.floor) return true;
    if (next.victory != prev.victory) return true;
    if (next.hostScore != prev.hostScore || next.guestScore != prev.guestScore) {
      return true;
    }
    if (next.winnerTag != prev.winnerTag) return true;
    return _bossStateChanged(prev.boss, next.boss);
  }

  bool _bossStateChanged(BossNetState? prev, BossNetState? next) {
    if (prev == null || next == null) return prev != next;
    if ((next.x - prev.x).abs() > _positionEpsilon) return true;
    if ((next.y - prev.y).abs() > _positionEpsilon) return true;
    if (next.hp != prev.hp) return true;
    if (next.alive != prev.alive) return true;
    if (next.action != prev.action) return true;
    return false;
  }

  Future<void> finishMatch({
    required int hostScore,
    required int guestScore,
    required String winnerTag,
  }) async {
    if (roomCode.isEmpty) return;
    await _service.roomRef(roomCode).child('phase').set('finished');
    await _service.updateWorldState(
      roomCode: roomCode,
      state: WorldNetState(
        floor: world.value.floor,
        npcs: const <NpcNetState>[],
        boss: world.value.boss,
        victory: true,
        hostScore: hostScore,
        guestScore: guestScore,
        winnerTag: winnerTag,
      ),
    );
  }

  Future<void> damagePlayer(String targetPlayerId, int amount) async {
    if (roomCode.isEmpty || amount <= 0) return;
    await _service.damagePlayer(
      roomCode: roomCode,
      playerId: targetPlayerId,
      amount: amount,
    );
  }

  Future<void> setLocalPlayerHp(int hp) async {
    if (roomCode.isEmpty || localPlayerId.isEmpty) return;
    await _service.setPlayerHp(
      roomCode: roomCode,
      playerId: localPlayerId,
      hp: hp,
    );
  }

  Future<void> damageBoss(int amount) async {
    if (roomCode.isEmpty || amount <= 0) return;
    await _service.damageBoss(roomCode: roomCode, amount: amount);
  }

  Future<void> dispose() async {
    await _playersSub?.cancel();
    await _worldSub?.cancel();
    await _phaseSub?.cancel();
    await _playerTagsSub?.cancel();
    _playersSub = null;
    _worldSub = null;
    _phaseSub = null;
    _playerTagsSub = null;
    _clearLocalSession();
  }

  void _clearLocalSession() {
    roomCode = '';
    localPlayerId = '';
    localTag = '';
    isHost = false;
    allPlayers.value = {};
    remotePlayers.value = {};
    playerTags.value = {};
    world.value = WorldNetState.initial();
    victory.value = false;
    _lastPublishPlayerMs = 0;
    _lastPublishWorldMs = 0;
    _lastPublishedPlayer = null;
    _lastPublishedWorld = null;
    _dbgPlayerWrites = 0;
    _dbgWorldWrites = 0;
    _dbgPlayerSuppressed = 0;
    _dbgWorldSuppressed = 0;
    _dbgPlayersRx = 0;
    _dbgWorldRx = 0;
    _dbgPhaseRx = 0;
    _dbgTagsRx = 0;
    _dbgLastReportMs = 0;
    debugTxSummary.value = '';
  }
}
