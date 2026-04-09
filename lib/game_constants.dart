/// 플레이어·NPC가 같은 `man.png` 스프라이트 시트를 쓸 때 공유하는 값.
/// (600×100, 6프레임 등 — 에셋 바꾸면 여기만 맞추면 됨)
const int kManWalkFrameCount = 6;
const double kManWalkStepTime = 0.12;
const String kManSpriteAsset = 'man.png';

const String kManPunchAsset = 'man_punch.png';
const String kManKickAsset = 'man_kick.png';

/// 펀치·킥 스프라이트 한 프레임당 표시 시간(초). **값이 작을수록 빠름.**
const double kPunchAnimStepTime = 0.05;
const double kKickAnimStepTime = 0.05;

/// 월드 좌표(캐릭터 중심 간 거리) 기준 타격 거리.
const double kPunchHitRange = 100;
const double kKickHitRange = 125;

const int kDefaultMaxHp = 10;

const double kNpcAttackRange = 95;
const double kNpcAttackCooldownSec = 1.15;

const double kShopHoleRadius = 40;
const double kBossDoorTriggerRadius = 72;
const double kBossDoorWidth = 110;
const double kBossDoorHeight = 150;

/// 보스 최대 체력 배수·플레이어에게 입히는 피해량 배수 (기본 1 대비).
const double kBossHpMultiplier = 2;
const double kBossDamageMultiplier = 2;
