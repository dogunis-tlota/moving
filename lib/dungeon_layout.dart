/// 3×3 격자 던전. 좌표는 각각 0…2 (시작은 중앙 (1,1) → 표시 방 번호 5).
class DungeonLayout {
  DungeonLayout._();

  static const int size = 3;

  static bool hasEast(int rx, int ry) => rx < size - 1;

  static bool hasWest(int rx, int ry) => rx > 0;

  static bool hasNorth(int rx, int ry) => ry > 0;

  static bool hasSouth(int rx, int ry) => ry < size - 1;

  /// 1…9 (행 우선: 왼쪽 위가 1, 중앙이 5).
  static int roomNumber1to9(int rx, int ry) => ry * size + rx + 1;
}
