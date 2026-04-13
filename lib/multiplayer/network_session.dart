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

  StreamSubscription<Map<String, PlayerNetState>>? _playersSub;
  StreamSubscription<WorldNetState>? _worldSub;
  StreamSubscription<Map<String, dynamic>>? _metaSub;

  int _lastPublishPlayerMs = 0;
  int _lastPublishWorldMs = 0;

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

  void _applyPlayerTagsFromMeta(Map<String, dynamic> meta) {
    final raw = meta['playerTags'];
    final out = <String, String>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        out[k.toString()] = v.toString();
      });
    }
    playerTags.value = out;
  }

  void _bindStreams() {
    _playersSub?.cancel();
    _worldSub?.cancel();
    _metaSub?.cancel();

    _playersSub = _service.watchPlayers(roomCode).listen((players) {
      allPlayers.value = players;
      final remotes = <String, PlayerNetState>{};
      for (final e in players.entries) {
        if (e.key != localPlayerId) {
          remotes[e.key] = e.value;
        }
      }
      remotePlayers.value = remotes;
    });

    _worldSub = _service.watchWorld(roomCode).listen((state) {
      world.value = state;
      victory.value = state.victory;
    });

    _metaSub = _service.watchRoomMeta(roomCode).listen((meta) {
      _applyPlayerTagsFromMeta(meta);
      final phase = (meta['phase'] ?? '').toString();
      if (phase == 'finished') {
        victory.value = true;
      }
    });
  }

  Future<void> publishPlayer(PlayerNetState state) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastPublishPlayerMs < 40) return;
    _lastPublishPlayerMs = now;
    if (roomCode.isEmpty || localPlayerId.isEmpty) return;
    await _service.updatePlayerState(
      roomCode: roomCode,
      playerId: localPlayerId,
      state: state,
    );
  }

  Future<void> publishWorld(WorldNetState state) async {
    if (!isHost) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastPublishWorldMs < 70) return;
    _lastPublishWorldMs = now;
    if (roomCode.isEmpty) return;
    await _service.updateWorldState(roomCode: roomCode, state: state);
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
    await _metaSub?.cancel();
    _playersSub = null;
    _worldSub = null;
    _metaSub = null;
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
  }
}
