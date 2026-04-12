import 'dart:math';

import 'player_stats.dart';
import 'revive_manager.dart';

/// 필드 / 보스에서 공유하는 세션.
class GameSession {
  final PlayerStats stats = PlayerStats();
  final ReviveManager revive = ReviveManager();
  final Random spawnRng = Random();

  /// IP 체크 기반 플레이어 태그 (예: KR_4821).
  String playerTag = 'KR_0000';

  /// 메인 필드 현재 층 (1 ~ 10).
  int currentFloor = 1;

  /// 시작 화면에서 선택된 캐릭터 슬롯 (현재 0만 사용).
  int selectedCharacterIndex = 0;
}
