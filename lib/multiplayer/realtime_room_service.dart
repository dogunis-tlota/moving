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

  /// 로컬 복구 후 RTDB `userActiveRooms`를 다시 맞춤.
  Future<void> putHostPendingRoomCode(String hostPlayerId, String roomCode) async {
    await _saveHostPendingRoomCode(hostPlayerId, roomCode);
  }

  /// 호스트가 만든 방 코드(새로고침 복구용). 방이 없거나 종료되었으면 null.
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
      'phase': 'waiting',
      'hostPlayerId': hostPlayerId,
      'guestPlayerId': '',
      'hostTag': hostTag,
      'guestTag': '',
      'players': <String, dynamic>{
        hostPlayerId: PlayerNetState(
          x: 0,
          y: 0,
          facingX: 1,
          hp: 10,
          action: AvatarAction.idle,
          updatedAtMs: now,
          score: 0,
          floor: 1,
        ).toMap(),
      },
      'world': WorldNetState.initial().toMap(),
    });
    await _saveHostPendingRoomCode(hostPlayerId, roomCode);
    await playerRef(roomCode, hostPlayerId).onDisconnect().remove();
    await roomRef(roomCode).child('guestPlayerId').onDisconnect().remove();
  }

  Future<bool> joinRoom({
    required String roomCode,
    required String guestPlayerId,
    required String guestTag,
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
    final guest = (map['guestPlayerId'] ?? '').toString();
    if (guest.isNotEmpty) return false;

    await room.update(<String, dynamic>{
      'guestPlayerId': guestPlayerId,
      'guestTag': guestTag,
      'phase': 'playing',
    });

    final now = DateTime.now().millisecondsSinceEpoch;
    await playerRef(roomCode, guestPlayerId).set(
      PlayerNetState(
        x: 0,
        y: 0,
        facingX: 1,
        hp: 10,
        action: AvatarAction.idle,
        updatedAtMs: now,
        score: 0,
        floor: 1,
      ).toMap(),
    );
    await playerRef(roomCode, guestPlayerId).onDisconnect().remove();
    await roomRef(roomCode).child('guestPlayerId').onDisconnect().remove();
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
    // 게스트: 방 전체 삭제 시도(호스트와 동일하게 세션 종료). 규칙상 실패 시 대기 상태로만 복구.
    try {
      await roomRef(roomCode).remove();
    } catch (_) {
      await playerRef(roomCode, playerId).remove();
      await roomRef(roomCode).child('guestPlayerId').set('');
      await roomRef(roomCode).child('guestTag').set('');
      await roomRef(roomCode).child('phase').set('waiting');
    }
  }

  Future<void> updatePlayerState({
    required String roomCode,
    required String playerId,
    required PlayerNetState state,
  }) async {
    await playerRef(roomCode, playerId).set(state.toMap());
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
            .equalTo('waiting')
            .limitToFirst(1)
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
      return code;
    }
    return null;
  }

  /// DB `rooms` 아래 방 키 목록(정렬, 최대 [limit]개).
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

  /// `phase == waiting` 이고 게스트가 비어 있는 방 코드 목록.
  Future<List<String>> listJoinableRoomCodes({int limit = 48}) async {
    try {
      final snap = await _database
          .ref('rooms')
          .orderByChild('phase')
          .equalTo('waiting')
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
          final g = (m['guestPlayerId'] ?? '').toString();
          if (g.isEmpty) out.add(code);
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

  Stream<Map<String, dynamic>> watchRoomMeta(String roomCode) {
    return roomRef(roomCode).onValue.map((event) {
      final raw = event.snapshot.value;
      if (raw is Map) {
        return raw.map((k, v) => MapEntry(k.toString(), v));
      }
      return <String, dynamic>{};
    });
  }
}
