/// NPC 전투 성향 — 이동·접근 방식이 달라짐.
enum NpcAggression {
  /// 배회만 (플레이어에게 접근하지 않음).
  passive,
  /// 멈춤 ↔ 천천히 접근 반복.
  normal,
  /// 즉시 플레이어 방향으로 이동.
  aggressive,
}
