import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../game_constants.dart';
import 'room_models.dart';

bool _isRoomExpiredMap(Map<String, dynamic> map) {
  final now = DateTime.now().millisecondsSinceEpoch;
  final ex = (map['expiresAtMs'] as num?)?.toInt();
  if (ex != null) return now > ex;
  final cr = (map['createdAtMs'] as num?)?.toInt();
  if (cr != null) return now > cr + kRoomLifetimeMs;
  return false;
}

int _playerCountFromRoomMap(Map<String, dynamic> map) {
  final p = map['players'];
  if (p is! Map) return 0;
  return p.length;
}

class RealtimeRoomService {
  RealtimeRoomService({FirebaseDatabase? database}) : _db = database;

  FirebaseDatabase? _db;
  FirebaseDatabase get _database {
    final existing = _db;
    if (existing != null) return existing;
    final app = Firebase.app();
    final url =
        app.options.databaseURL?.trim().isNotEmpty == true
            ? app.options.databaseURL!.trim()
            : 'https://maru-moving-game-default-rtdb.firebaseio.com';
    _db = FirebaseDatabase.instanceFor(app: app, databaseURL: url);
    return _db!;
  }

  DatabaseReference roomRef(String roomCode) => _database.ref('rooms/$roomCode');

  DatabaseReference _userActiveRoomRef(String uid) =>
      _database.ref('userActiveRooms/$uid');

  Future<void> _saveHostPendingRoomCode(String hostPlayerId, String roomCode) async {
    await _userActiveRoomRef(hostPlayerId).set(<String, dynamic>{
      'roomCode': roomCode,
      'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> clearHostPendingRoomCode(String hostPlayerId) async {
    await _userActiveRoomRef(hostPlayerId).remove();
  }

  Future<void> putHostPendingRoomCode(String hostPlayerId, String roomCode) async {
    await _saveHostPendingRoomCode(hostPlayerId, roomCode);
  }

  Future<String?> fetchPendingRoomCodeForHost(String hostPlayerId) async {
    final snap = await _userActiveRoomRef(hostPlayerId).get();
    final raw = snap.value;
    if (raw is! Map) return null;
    final code = (raw['roomCode'] ?? '').toString();
    if (code.isEmpty) return null;
    final roomSnap = await roomRef(code).get();
    final rv = roomSnap.value;
    if (rv is! Map) {
      await clearHostPendingRoomCode(hostPlayerId);
      return null;
    }
    final map = rv.map((k, v) => MapEntry(k.toString(), v));
    if ((map['hostPlayerId'] ?? '').toString() != hostPlayerId) {
      await clearHostPendingRoomCode(hostPlayerId);
      return null;
    }
    final phase = (map['phase'] ?? '').toString();
    if (phase == 'finished') {
      await clearHostPendingRoomCode(hostPlayerId);
      return null;
    }
    if (_isRoomExpiredMap(map)) {
      await clearHostPendingRoomCode(hostPlayerId);
      unawaited(roomRef(code).remove());
      return null;
    }
    return code;
  }

  DatabaseReference playerRef(String roomCode, String playerId) =>
      roomRef(roomCode).child('players/$playerId');

  DatabaseReference worldRef(String roomCode) => roomRef(roomCode).child('world');

  Future<void> createRoom({
    required String roomCode,
    required String hostPlayerId,
    required String hostTag,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await roomRef(roomCode).set(<String, dynamic>{
      'createdAtMs': now,
      'expiresAtMs': now + kRoomLifetimeMs,
      'phase': 'playing',
      'hostPlayerId': hostPlayerId,
      'players': <String, dynamic>{
        hostPlayerId: PlayerNetState(
          x: 0,
          y: 0,
          facingX: 1,
          hp: kDefaultMaxHp,
          action: AvatarAction.idle,
          updatedAtMs: now,
          score: 0,
          floor: 1,
          roomRx: 1,
          roomRy: 1,
        ).toMap(),
      },
      'playerTags': <String, dynamic>{
        hostPlayerId: hostTag,
      },
      'world': WorldNetState.initial().toMap(),
    });
    await _saveHostPendingRoomCode(hostPlayerId, roomCode);
    await playerRef(roomCode, hostPlayerId).onDisconnect().remove();
    await roomRef(roomCode).child('playerTags/$hostPlayerId').onDisconnect().remove();
  }

  Future<bool> joinRoom({
    required String roomCode,
    required String playerId,
    required String playerTag,
  }) async {
    final room = roomRef(roomCode);
    final snapshot = await room.get();
    final raw = snapshot.value;
    if (raw is! Map) return false;
    final map = raw.map((k, v) => MapEntry(k.toString(), v));
    if (_isRoomExpiredMap(map)) {
      unawaited(room.remove());
      return false;
    }
    final phase = (map['phase'] ?? '').toString();
    if (phase == 'finished') return false;

    final n = _playerCountFromRoomMap(map);
    if (n >= kPvpMaxRoomPlayers) return false;

    final players = map['players'];
    if (players is Map && players.containsKey(playerId)) {
      return false;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    await playerRef(roomCode, playerId).set(
      PlayerNetState(
        x: 0,
        y: 0,
        facingX: 1,
        hp: kDefaultMaxHp,
        action: AvatarAction.idle,
        updatedAtMs: now,
        score: 0,
        floor: 1,
        roomRx: 1,
        roomRy: 1,
      ).toMap(),
    );
    await room.child('playerTags/$playerId').set(playerTag);
    await room.update(<String, dynamic>{
      'phase': 'playing',
    });

    await playerRef(roomCode, playerId).onDisconnect().remove();
    await room.child('playerTags/$playerId').onDisconnect().remove();
    return true;
  }

  Future<void> leaveRoom({
    required String roomCode,
    required String playerId,
    required bool isHost,
  }) async {
    if (isHost) {
      await clearHostPendingRoomCode(playerId);
      await roomRef(roomCode).remove();
      return;
    }
    await playerRef(roomCode, playerId).remove();
    await roomRef(roomCode).child('playerTags/$playerId').remove();
  }

  /// 위치·액션만 갱신. [hp]는 [damagePlayer]로만 변경(클라가 set으로 덮어쓰지 않음).
  Future<void> updatePlayerState({
    required String roomCode,
    required String playerId,
    required PlayerNetState state,
  }) async {
    await playerRef(roomCode, playerId).update(<String, dynamic>{
      'x': state.x,
      'y': state.y,
      'facingX': state.facingX,
      'action': actionToString(state.action),
      'updatedAtMs': state.updatedAtMs,
      'score': state.score,
      'floor': state.floor,
      'roomRx': state.roomRx,
      'roomRy': state.roomRy,
    });
  }

  Future<void> updateWorldState({
    required String roomCode,
    required WorldNetState state,
  }) async {
    await worldRef(roomCode).set(state.toMap());
  }

  Future<String?> findJoinableRoomCode() async {
    final snap =
        await _database
            .ref('rooms')
            .orderByChild('phase')
            .equalTo('playing')
            .limitToFirst(24)
            .get();
    final raw = snap.value;
    if (raw is! Map) return null;
    for (final key in raw.keys) {
      final code = key.toString();
      final roomSnap = await roomRef(code).get();
      final rv = roomSnap.value;
      if (rv is! Map) continue;
      final rm = rv.map((k, v) => MapEntry(k.toString(), v));
      if (_isRoomExpiredMap(rm)) {
        unawaited(roomRef(code).remove());
        continue;
      }
      if (_playerCountFromRoomMap(rm) < kPvpMaxRoomPlayers) {
        return code;
      }
    }
    return null;
  }

  Future<List<String>> listRoomCodesInDatabase({int limit = 80}) async {
    try {
      final snap =
          await _database.ref('rooms').orderByKey().limitToFirst(limit).get();
      final raw = snap.value;
      if (raw is! Map) return [];
      final out = <String>[];
      raw.forEach((key, value) {
        final code = key.toString();
        if (value is Map) {
          final m = value.map((k, v) => MapEntry(k.toString(), v));
          if (_isRoomExpiredMap(m)) {
            unawaited(roomRef(code).remove());
            return;
          }
        }
        out.add(code);
      });
      out.sort();
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<List<String>> listJoinableRoomCodes({int limit = 48}) async {
    try {
      final snap = await _database
          .ref('rooms')
          .orderByChild('phase')
          .equalTo('playing')
          .limitToFirst(limit)
          .get();
      final raw = snap.value;
      if (raw is! Map) return [];
      final out = <String>[];
      raw.forEach((key, value) {
        if (value is Map) {
          final code = key.toString();
          final m = value.map((k, v) => MapEntry(k.toString(), v));
          if (_isRoomExpiredMap(m)) {
            unawaited(roomRef(code).remove());
            return;
          }
          if (_playerCountFromRoomMap(m) < kPvpMaxRoomPlayers) {
            out.add(code);
          }
        }
      });
      out.sort();
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<void> damagePlayer({
    required String roomCode,
    required String playerId,
    required int amount,
  }) async {
    if (amount <= 0) return;
    final node = playerRef(roomCode, playerId);
    final snap = await node.get();
    final raw = snap.value;
    if (raw is! Map) return;
    final map = raw.map((k, v) => MapEntry(k.toString(), v));
    final hp = (map['hp'] as num?)?.toInt() ?? 0;
    final next = (hp - amount).clamp(0, 999);
    await node.update(<String, dynamic>{
      'hp': next,
      'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> setPlayerHp({
    required String roomCode,
    required String playerId,
    required int hp,
  }) async {
    await playerRef(roomCode, playerId).update(<String, dynamic>{
      'hp': hp.clamp(0, 999),
      'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> damageBoss({
    required String roomCode,
    required int amount,
  }) async {
    if (amount <= 0) return;
    final node = worldRef(roomCode);
    final snap = await node.get();
    final raw = snap.value;
    if (raw is! Map) return;
    final map = raw.map((k, v) => MapEntry(k.toString(), v));
    final bossRaw = map['boss'];
    if (bossRaw is! Map) return;
    final boss = bossRaw.map((k, v) => MapEntry(k.toString(), v));
    final alive = boss['alive'] == true;
    if (!alive) return;
    final hp = (boss['hp'] as num?)?.toInt() ?? 0;
    final next = (hp - amount).clamp(0, 999);
    final nextAlive = next > 0;
    await node.update(<String, dynamic>{
      'boss/hp': next,
      'boss/alive': nextAlive,
      if (!nextAlive) 'boss/action': actionToString(AvatarAction.idle),
    });
  }

  Stream<Map<String, PlayerNetState>> watchPlayers(String roomCode) {
    return roomRef(roomCode).child('players').onValue.map((event) {
      final raw = event.snapshot.value;
      final out = <String, PlayerNetState>{};
      if (raw is! Map) return out;
      raw.forEach((key, value) {
        if (value is Map) {
          out[key.toString()] = PlayerNetState.fromMap(value);
        }
      });
      return out;
    });
  }

  Stream<WorldNetState> watchWorld(String roomCode) {
    return worldRef(roomCode).onValue.map((event) {
      final raw = event.snapshot.value;
      if (raw is Map) return WorldNetState.fromMap(raw);
      return WorldNetState.initial();
    });
  }

  Stream<String> watchRoomPhase(String roomCode) {
    return roomRef(roomCode).child('phase').onValue.map((event) {
      final v = event.snapshot.value;
      return (v ?? '').toString();
    });
  }

  Stream<Map<String, String>> watchPlayerTags(String roomCode) {
    return roomRef(roomCode).child('playerTags').onValue.map((event) {
      final raw = event.snapshot.value;
      final out = <String, String>{};
      if (raw is Map) {
        raw.forEach((k, v) {
          out[k.toString()] = v.toString();
        });
      }
      return out;
    });
  }
}
