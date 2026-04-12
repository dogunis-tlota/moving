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
  String? remotePlayerId;
  bool isHost = false;

  final ValueNotifier<PlayerNetState?> remotePlayer = ValueNotifier(null);
  final ValueNotifier<String> remoteTag = ValueNotifier('');
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

  /// 입장 가능한 방 코드 목록 (대기 중·게스트 없음).
  static Future<List<String>> listOpenRoomCodes() async {
    await ensureFirebaseInitialized();
    return RealtimeRoomService().listJoinableRoomCodes();
  }

  /// RTDB `rooms`에 존재하는 방 코드 전체(스냅샷, 최대 [limit]개).
  static Future<List<String>> listRoomCodesFromDatabase({int limit = 80}) async {
    await ensureFirebaseInitialized();
    return RealtimeRoomService().listRoomCodesInDatabase(limit: limit);
  }

  /// 새로고침 후 호스트가 이전에 만든 방 코드 복구 (RTDB `userActiveRooms`만 사용).
  static Future<String?> tryRestoreHostRoomCode() async {
    await ensureFirebaseInitialized();
    final auth = FirebaseAuthService();
    final user = await auth.ensureSignedInAnonymously();
    return RealtimeRoomService().fetchPendingRoomCodeForHost(user.uid);
  }

  /// 이미 존재하는 방에 호스트로 다시 연결 (방 코드 표시·스트림 복구).
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
      roomCode: code,
      guestPlayerId: playerId,
      guestTag: playerTag,
    );
    if (!ok) return false;
    roomCode = code;
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
    _metaSub?.cancel();

    _playersSub = _service.watchPlayers(roomCode).listen((players) {
      String? remoteId;
      for (final id in players.keys) {
        if (id != localPlayerId) {
          remoteId = id;
          break;
        }
      }
      remotePlayerId = remoteId;
      remotePlayer.value = remoteId != null ? players[remoteId] : null;
    });

    _worldSub = _service.watchWorld(roomCode).listen((state) {
      world.value = state;
      victory.value = state.victory;
    });

    _metaSub = _service.watchRoomMeta(roomCode).listen((meta) {
      final phase = (meta['phase'] ?? '').toString();
      if (isHost) {
        remoteTag.value = (meta['guestTag'] ?? '').toString();
      } else {
        remoteTag.value = (meta['hostTag'] ?? '').toString();
      }
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

  /// 10층 클리어 등 매치 종료. 호스트·게스트 모두 호출 가능.
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

  Future<void> damageRemote(int amount) async {
    final remoteId = remotePlayerId;
    if (remoteId == null || roomCode.isEmpty) return;
    await _service.damagePlayer(
      roomCode: roomCode,
      playerId: remoteId,
      amount: amount,
    );
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
    remotePlayerId = null;
    isHost = false;
    remotePlayer.value = null;
    remoteTag.value = '';
    world.value = WorldNetState.initial();
    victory.value = false;
    _lastPublishPlayerMs = 0;
    _lastPublishWorldMs = 0;
  }
}
