import 'game_constants.dart';

/// 플레이어 강화 (파워업 / 이동속도) + 필드 픽업(30초 2배).
class PlayerStats {
  double powerMultiplier = 1;
  double speedMultiplier = 1;

  double _powerBuffSec = 0;
  double _speedBuffSec = 0;

  void tickBuffs(double dt) {
    if (_powerBuffSec > 0) {
      _powerBuffSec -= dt;
      if (_powerBuffSec < 0) _powerBuffSec = 0;
    }
    if (_speedBuffSec > 0) {
      _speedBuffSec -= dt;
      if (_speedBuffSec < 0) _speedBuffSec = 0;
    }
  }

  /// 남은 초(올림, HUD용).
  int get powerBuffRemainingSecCeil =>
      _powerBuffSec > 0 ? _powerBuffSec.ceil() : 0;
  int get speedBuffRemainingSecCeil =>
      _speedBuffSec > 0 ? _speedBuffSec.ceil() : 0;

  void activatePowerBuff([double sec = kPickupBuffDurationSec]) {
    _powerBuffSec = sec;
  }

  void activateSpeedBuff([double sec = kPickupBuffDurationSec]) {
    _speedBuffSec = sec;
  }

  bool get _powerBoostActive => _powerBuffSec > 0;
  bool get _speedBoostActive => _speedBuffSec > 0;

  double get _powerScale =>
      powerMultiplier * (_powerBoostActive ? 2.0 : 1.0);
  double get effectiveSpeedScale =>
      speedMultiplier * (_speedBoostActive ? 2.0 : 1.0);

  int get punchDamage =>
      (1 * _powerScale).ceil().clamp(1, 99);
  int get kickDamage =>
      (1 * _powerScale).ceil().clamp(1, 99);
}
