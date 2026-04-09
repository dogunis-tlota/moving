/// 무료 부활 남은 횟수 (최대 3회).
class ReviveManager {
  int freeRevivesLeft = 3;

  bool get canReviveFree => freeRevivesLeft > 0;

  /// 무료 부활 1회 소모. 성공 시 true.
  bool consumeFreeRevive() {
    if (freeRevivesLeft <= 0) return false;
    freeRevivesLeft--;
    return true;
  }
}
