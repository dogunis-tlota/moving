/// 상점 아이템 (한 번에 하나만 선택).
enum ShopItem { powerUp, speedUp, heal }

/// 플레이어 강화 (파워업 / 이동속도).
class PlayerStats {
  double powerMultiplier = 1;
  double speedMultiplier = 1;

  int get punchDamage => (1 * powerMultiplier).ceil().clamp(1, 99);
  int get kickDamage => (1 * powerMultiplier).ceil().clamp(1, 99);

  void applyShopItem(ShopItem item) {
    switch (item) {
      case ShopItem.powerUp:
        powerMultiplier += 0.35;
      case ShopItem.speedUp:
        speedMultiplier += 0.25;
      case ShopItem.heal:
        break; // HP 회복은 PlayerCharacter에서 처리
    }
  }
}
