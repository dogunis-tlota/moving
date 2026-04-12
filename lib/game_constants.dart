/// 플레이어·NPC가 같은 `man.png` 스프라이트 시트를 쓸 때 공유하는 값.
/// (600×100, 6프레임 등 — 에셋 바꾸면 여기만 맞추면 됨)
const int kManWalkFrameCount = 6;
const double kManWalkStepTime = 0.12;
const String kManSpriteAsset = 'man.png';
const double kCharacterScale = 0.56;

const String kManPunchAsset = 'man_punch.png';
const String kManKickAsset = 'man_kick.png';

/// 펀치·킥 스프라이트 한 프레임당 표시 시간(초). **값이 작을수록 빠름.**
const double kPunchAnimStepTime = 0.05;
const double kKickAnimStepTime = 0.05;

/// 타격 판정: (플레이어·상대 스프라이트 반폭 합) + `size.x` × 아래 배수.
/// 즉 추가 판정 거리는 **캐릭터 스프라이트 가로 크기**를 단위로 씀.
const double kPunchReachSpriteWidths = 1.0;
const double kKickReachSpriteWidths = 1.15;

const int kDefaultMaxHp = 10;

/// RTDB 멀티 방 유지 시간(밀리초). 이후 입장 불가·목록에서 정리.
const int kRoomLifetimeMs = 5 * 60 * 1000;

/// 필드 파워업·스피드업 지속 시간(초).
const double kPickupBuffDurationSec = 30;

/// 픽업 획득 판정 반경(월드 좌표).
const double kPickupPickupRadius = 40;

/// 층이 오를수록 NPC 최대 체력 증가량(기본 [kDefaultMaxHp]에 가산).
const int kNpcBonusHpPerFloor = 2;

/// 필드 이동 최대 속도(월드 픽셀/초). 키보드·터치 정규화 후 이 값을 곱함. NPC·보스도 동일 기준에 [PlayerStats.effectiveSpeedScale]을 곱해 맞춤.
const double kPlayerFieldMoveSpeed = 200.0;

int npcMaxHpForFloor(int floor) {
  final f = floor.clamp(1, kMaxFloor);
  return kDefaultMaxHp + (f - 1) * kNpcBonusHpPerFloor;
}

/// 킥 피격 시 밀려나는 거리(월드 좌표, 벽에서 멈춤).
const double kKickKnockbackPlayer = 26;
const double kKickKnockbackNpc = 22;

/// 메인 필드 층 수 (1F ~ 10F). 10층 클리어 시 승리.
const int kMaxFloor = 10;

/// 모바일에서 화면 비율 고정용 (레터박스).
const double kTargetAspectRatio = 16 / 9;

/// 필드 맵 크기(월드 좌표). 무한 필드 방지용 경계(9방 공통, 이전보다 축소).
const double kMapWidth = 1500;
/// 세로 길이.
const double kMapHeight = 500;

/// 상단 비율 — 하늘·지평선(걸을 수 없음). 배경·[kPathMinWorldY]와 동일 기준.
const double kFieldHorizonFraction = 0.25;

/// 길(이동 가능)의 북쪽 끝 월드 Y. 그 위(더 작은 Y)는 배경만.
double get kPathMinWorldY =>
    -kMapHeight * 0.5 + kMapHeight * kFieldHorizonFraction;

/// 길의 남쪽 끝 월드 Y(맵 하단).
double get kPathMaxWorldY => kMapHeight * 0.5;

/// 길 세로 중앙(동·서 문 세로 구간 중심).
double get kPathMidWorldY => (kPathMinWorldY + kPathMaxWorldY) / 2;

/// 출입구 갭의 절반 폭(월드). `GrassFieldLayer` 테두리와 방 전환 판정이 같아야 함.
const double kDoorGapHalfWorld = 64;

/// 방 입장 후 첫 NPC 웨이브까지 대기(초).
const double kNpcRoomFirstSpawnDelaySec = 3.0;

/// 적이 플레이어에게 피해를 주는 거리(가까이 붙어야 맞도록 축소).
const double kNpcAttackRange = 62;
const double kNpcAttackCooldownSec = 1.15;

/// 보스 최대 체력 배수·플레이어에게 입히는 피해량 배수 (기본 1 대비).
const double kBossHpMultiplier = 2;
const double kBossDamageMultiplier = 2;
/// 필드 보스 근접 피해에 추가 배율(요청: 파워 1.5배).
const double kBossFieldPowerMultiplier = 1.5;

/// 필드 보스 스프라이트 = 플레이어 표시 크기 × 이 값.
const double kBossFieldSizeVsPlayer = 1.5;
/// 보스전 중 플레이어·NPC·보스 이동 속도 배율.
const double kBossFightMoveSpeedFactor = 0.5;
