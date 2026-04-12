import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import 'game_constants.dart';

/// 플레이어 발밑 화면 좌표에 맞추는 체력바. 가로 길이는 스프라이트 너비와 동일, [segmentCount]칸.
/// [앵커 topCenter] — `playerCenter`와 가로 정렬, 세로는 스프라이트 하단 아래 [feetGap].
class HpBar extends PositionComponent {
  HpBar({int? segmentCount})
      : segmentCount = segmentCount ?? kDefaultMaxHp,
        filled = segmentCount ?? kDefaultMaxHp,
        super(anchor: Anchor.topCenter, priority: 10000);

  int segmentCount;
  int filled;
  String? label;

  static const double feetGap = 10;

  double _gapPx = 2;

  final Paint _border = Paint()
    ..color = const Color(0xFF1A3D1F)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;
  final Paint _fill = Paint()
    ..color = const Color.fromARGB(255, 4, 244, 16); //밝은초록색으로로
  final Paint _empty = Paint()..color = const Color(0xFF2A3D2E);

  void setFilled(int value) {
    filled = value.clamp(0, segmentCount);
  }

  /// 플레이어 `Anchor.center` 기준 화면 위치·크기.
  void followPlayerFeet(Vector2 playerCenter, Vector2 playerSize) {
    final barW = playerSize.x;
    final barH = (barW * 0.12).clamp(10.0, 20.0);
    size.setValues(barW, barH);
    position.setValues(
      playerCenter.x,
      playerCenter.y + playerSize.y / 2 + feetGap,
    );
    _gapPx = (barW * 0.018).clamp(1.0, 4.0);
  }

  @override
  void render(Canvas canvas) {
    if (label != null && label!.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset((size.x - tp.width) / 2, -tp.height - 4));
    }

    final n = segmentCount;
    final totalGaps = (n - 1) * _gapPx;
    final segW = (size.x - totalGaps) / n;
    final h = size.y;

    for (var i = 0; i < n; i++) {
      final left = i * (segW + _gapPx);
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, 0, segW, h),
        Radius.circular((h * 0.2).clamp(2.0, 4.0)),
      );
      canvas.drawRRect(r, i < filled ? _fill : _empty);
      canvas.drawRRect(r, _border);
    }
  }
}
