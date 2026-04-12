import 'package:flame/components.dart';
import 'package:flutter/material.dart';

class BattleStatusHud extends PositionComponent {
  BattleStatusHud({
    required this.faceSprite,
  }) : super(anchor: Anchor.topLeft, priority: 20000);

  final Sprite faceSprite;

  String myName = 'ME';
  String otherName = 'REMOTE';
  int floor = 1;
  int otherFloor = 1;
  int npcAlive = 0;
  int npcTotal = 0;
  Color npcColor = const Color(0xFF7EB6FF);

  static const double _panelH = 88;
  static const double _pad = 10;
  static const double _face = 38;

  @override
  void render(Canvas canvas) {
    final bg = Paint()..color = const Color(0xAA111111);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.x, size.y),
        const Radius.circular(12),
      ),
      bg,
    );

    _drawEntry(
      canvas,
      x: _pad,
      title: myName,
      line2: '${floor}F',
      tint: Colors.white,
    );
    _drawEntry(
      canvas,
      x: size.x / 3 + _pad * 0.5,
      title: otherName.isEmpty ? 'WAITING...' : otherName,
      line2: '${otherFloor}F',
      tint: const Color(0xFFFFD54F),
    );
    _drawEntry(
      canvas,
      x: size.x * 2 / 3 + _pad * 0.5,
      title: 'NPC',
      line2: '$npcAlive/$npcTotal',
      tint: npcColor,
    );
  }

  void _drawEntry(
    Canvas canvas, {
    required double x,
    required String title,
    required String line2,
    required Color tint,
  }) {
    final faceRect = Rect.fromLTWH(x, 12, _face, _face);
    faceSprite.renderRect(
      canvas,
      faceRect,
      overridePaint:
          Paint()..colorFilter = ColorFilter.mode(tint, BlendMode.srcATop),
    );

    final titlePainter = TextPainter(
      text: TextSpan(
        text: title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    )..layout(maxWidth: size.x / 3 - 56);
    titlePainter.paint(canvas, Offset(x + _face + 8, 14));

    final line2Painter = TextPainter(
      text: TextSpan(
        text: line2,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: size.x / 3 - 56);
    line2Painter.paint(canvas, Offset(x + _face + 8, 36));
  }

  void syncLayout(Vector2 gameSize) {
    size.setValues(gameSize.x - 20, _panelH);
    position.setValues(10, 8);
  }
}
