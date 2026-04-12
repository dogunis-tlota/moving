enum GamePhase { waiting, playing, finished }

enum AvatarAction { idle, walk, punch, kick, grab }

AvatarAction actionFromString(String? value) {
  switch (value) {
    case 'walk':
      return AvatarAction.walk;
    case 'punch':
      return AvatarAction.punch;
    case 'kick':
      return AvatarAction.kick;
    case 'grab':
      return AvatarAction.grab;
    default:
      return AvatarAction.idle;
  }
}

String actionToString(AvatarAction action) {
  switch (action) {
    case AvatarAction.idle:
      return 'idle';
    case AvatarAction.walk:
      return 'walk';
    case AvatarAction.punch:
      return 'punch';
    case AvatarAction.kick:
      return 'kick';
    case AvatarAction.grab:
      return 'grab';
  }
}

class PlayerNetState {
  PlayerNetState({
    required this.x,
    required this.y,
    required this.facingX,
    required this.hp,
    required this.action,
    required this.updatedAtMs,
    this.score = 0,
    this.floor = 1,
    this.roomRx = 1,
    this.roomRy = 1,
  });

  final double x;
  final double y;
  final double facingX;
  final int hp;
  final AvatarAction action;
  final int updatedAtMs;
  /// 멀티: 내가 처치한 NPC로 모은 점수.
  final int score;
  /// 멀티: 현재 도전 중인 층.
  final int floor;
  /// 멀티: 격자 방 X (0…2).
  final int roomRx;
  /// 멀티: 격자 방 Y (0…2).
  final int roomRy;

  Map<String, dynamic> toMap() => <String, dynamic>{
    'x': x,
    'y': y,
    'facingX': facingX,
    'hp': hp,
    'action': actionToString(action),
    'updatedAtMs': updatedAtMs,
    'score': score,
    'floor': floor,
    'roomRx': roomRx,
    'roomRy': roomRy,
  };

  static PlayerNetState fromMap(Map<dynamic, dynamic> map) {
    return PlayerNetState(
      x: (map['x'] as num?)?.toDouble() ?? 0,
      y: (map['y'] as num?)?.toDouble() ?? 0,
      facingX: (map['facingX'] as num?)?.toDouble() ?? 1,
      hp: (map['hp'] as num?)?.toInt() ?? 0,
      action: actionFromString(map['action'] as String?),
      updatedAtMs: (map['updatedAtMs'] as num?)?.toInt() ?? 0,
      score: (map['score'] as num?)?.toInt() ?? 0,
      floor: (map['floor'] as num?)?.toInt() ?? 1,
      roomRx: (map['roomRx'] as num?)?.toInt() ?? 1,
      roomRy: (map['roomRy'] as num?)?.toInt() ?? 1,
    );
  }
}

class NpcNetState {
  NpcNetState({
    required this.id,
    required this.x,
    required this.y,
    required this.hp,
    required this.action,
  });

  final String id;
  final double x;
  final double y;
  final int hp;
  final AvatarAction action;

  Map<String, dynamic> toMap() => <String, dynamic>{
    'id': id,
    'x': x,
    'y': y,
    'hp': hp,
    'action': actionToString(action),
  };

  static NpcNetState fromMap(Map<dynamic, dynamic> map) {
    return NpcNetState(
      id: (map['id'] ?? '').toString(),
      x: (map['x'] as num?)?.toDouble() ?? 0,
      y: (map['y'] as num?)?.toDouble() ?? 0,
      hp: (map['hp'] as num?)?.toInt() ?? 0,
      action: actionFromString(map['action'] as String?),
    );
  }
}

class BossNetState {
  BossNetState({
    required this.x,
    required this.y,
    required this.hp,
    required this.alive,
    required this.action,
  });

  final double x;
  final double y;
  final int hp;
  final bool alive;
  final AvatarAction action;

  Map<String, dynamic> toMap() => <String, dynamic>{
    'x': x,
    'y': y,
    'hp': hp,
    'alive': alive,
    'action': actionToString(action),
  };

  static BossNetState fromMap(Map<dynamic, dynamic> map) {
    return BossNetState(
      x: (map['x'] as num?)?.toDouble() ?? 0,
      y: (map['y'] as num?)?.toDouble() ?? 0,
      hp: (map['hp'] as num?)?.toInt() ?? 0,
      alive: map['alive'] == true,
      action: actionFromString(map['action'] as String?),
    );
  }
}

class WorldNetState {
  WorldNetState({
    required this.floor,
    required this.npcs,
    this.boss,
    required this.victory,
    this.hostScore = 0,
    this.guestScore = 0,
    this.winnerTag = '',
  });

  final int floor;
  final List<NpcNetState> npcs;
  final BossNetState? boss;
  final bool victory;
  final int hostScore;
  final int guestScore;
  final String winnerTag;

  Map<String, dynamic> toMap() => <String, dynamic>{
    'floor': floor,
    'npcs': npcs.map((e) => e.toMap()).toList(),
    if (boss != null) 'boss': boss!.toMap(),
    'victory': victory,
    'hostScore': hostScore,
    'guestScore': guestScore,
    'winnerTag': winnerTag,
  };

  static WorldNetState fromMap(Map<dynamic, dynamic> map) {
    final rawNpcs = map['npcs'];
    final npcs = <NpcNetState>[];
    if (rawNpcs is List) {
      for (final item in rawNpcs) {
        if (item is Map) npcs.add(NpcNetState.fromMap(item));
      }
    } else if (rawNpcs is Map) {
      for (final item in rawNpcs.values) {
        if (item is Map) npcs.add(NpcNetState.fromMap(item));
      }
    }
    final rawBoss = map['boss'];
    return WorldNetState(
      floor: (map['floor'] as num?)?.toInt() ?? 1,
      npcs: npcs,
      boss: rawBoss is Map ? BossNetState.fromMap(rawBoss) : null,
      victory: map['victory'] == true,
      hostScore: (map['hostScore'] as num?)?.toInt() ?? 0,
      guestScore: (map['guestScore'] as num?)?.toInt() ?? 0,
      winnerTag: (map['winnerTag'] ?? '').toString(),
    );
  }

  static WorldNetState initial() =>
      WorldNetState(
        floor: 1,
        npcs: const <NpcNetState>[],
        victory: false,
        hostScore: 0,
        guestScore: 0,
        winnerTag: '',
      );
}
