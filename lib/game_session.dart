import 'dart:math';

import 'player_stats.dart';
import 'revive_manager.dart';

/// 필드 / 상점 / 보스에서 공유하는 세션.
class GameSession {
  final PlayerStats stats = PlayerStats();
  final ReviveManager revive = ReviveManager();
  final Random spawnRng = Random();

  /// 상점에서 체력회복 선택 시 필드에서 HP 채움.
  bool pendingFullHeal = false;
}
