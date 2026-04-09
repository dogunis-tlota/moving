import 'dart:math';
import 'dart:ui';

import 'package:flame/cache.dart';
import 'package:flame/components.dart';

import 'game_constants.dart';

/// 운동장에서 상·하·좌·우 중 랜덤 방향으로 걷는 NPC.
/// 월드 기준 위치는 스프라이트 **중심** (플레이어 `manWorldPos`와 동일한 기준).
class NpcCharacter extends SpriteAnimationComponent {
  NpcCharacter._({
    required super.animation,
    required super.size,
  }) : super(anchor: Anchor.center);

  /// 걷는 속도 (월드 픽셀/초).
  static const double wanderSpeed = 90;

  static const double _minDirectionSeconds = 0.7;
  static const double _maxDirectionSeconds = 2.2;

  final Random _rng = Random();
  Vector2 worldCenter = Vector2(150, -80);
  final Vector2 _dir = Vector2(1, 0);
  double _directionTimeLeft = 0;

  int health = kDefaultMaxHp;

  bool get isAlive => health > 0;

  /// [images]로 `kManSpriteAsset`을 읽어 걷기 애니메이션을 만든다.
  static Future<NpcCharacter> load(Images images) async {
    final image = await images.load(kManSpriteAsset);
    assert(
      image.width % kManWalkFrameCount == 0,
      '$kManSpriteAsset width must divide by $kManWalkFrameCount.',
    );
    final frameW = image.width / kManWalkFrameCount;
    final frameH = image.height.toDouble();
    final data = SpriteAnimationData.sequenced(
      amount: kManWalkFrameCount,
      stepTime: kManWalkStepTime,
      textureSize: Vector2(frameW.toDouble(), frameH),
      amountPerRow: kManWalkFrameCount,
    );

    final npc = NpcCharacter._(
      animation: SpriteAnimation.fromFrameData(image, data),
      size: Vector2(frameW.toDouble(), frameH),
    );
    npc.paint.colorFilter = const ColorFilter.mode(
      Color(0xFF7EB6FF),
      BlendMode.srcATop,
    );
    return npc;
  }

  void takeDamage(int amount) {
    if (!isAlive || amount <= 0) return;
    health = (health - amount).clamp(0, kDefaultMaxHp);
    if (!isAlive) {
      playing = false;
      opacity = 0.45;
    }
  }

  void _pickNewDirection() {
    switch (_rng.nextInt(4)) {
      case 0:
        _dir.setValues(0, -1);
        break;
      case 1:
        _dir.setValues(0, 1);
        break;
      case 2:
        _dir.setValues(-1, 0);
        break;
      default:
        _dir.setValues(1, 0);
    }
    _directionTimeLeft =
        _minDirectionSeconds +
        _rng.nextDouble() * (_maxDirectionSeconds - _minDirectionSeconds);
  }

  @override
  void onMount() {
    super.onMount();
    _pickNewDirection();
  }

  @override
  void update(double dt) {
    if (!isAlive) return;

    _directionTimeLeft -= dt;
    if (_directionTimeLeft <= 0) {
      _pickNewDirection();
    }

    worldCenter += _dir * wanderSpeed * dt;

    if (_dir.x.abs() > 0.1) {
      scale.x = _dir.x > 0 ? 1.0 : -1.0;
    }
    scale.y = 1.0;
    playing = true;

    super.update(dt);
  }

  void syncScreenPosition(Vector2 cameraTopLeft) {
    position = worldCenter - cameraTopLeft;
  }
}
