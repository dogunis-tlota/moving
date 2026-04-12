/// 보스 처치 후 선택하는 보상 기술(한 번에 하나만 유지).
enum BossRewardSkill {
  /// 펀치 입력 시 3회 빠르게 연속.
  triplePunch,

  /// 발차기 넉백 거리 1.5배.
  kickKnockback15,

  /// 발차기 넉백 없음 + 발차기 3연속.
  tripleKickNoKnockback,

  /// 펀치 피격 시 0.5초 기절.
  punchStun,
}
