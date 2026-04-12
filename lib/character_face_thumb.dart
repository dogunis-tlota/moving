import 'package:flutter/material.dart';

import 'game_constants.dart';

/// `man.png` 스프라이트 시트 첫 프레임의 위쪽(얼굴)만 잘라 표시.
class CharacterFaceThumbnail extends StatelessWidget {
  const CharacterFaceThumbnail({
    super.key,
    this.size = 64,
    this.borderColor = Colors.white24,
    this.selected = false,
  });

  final double size;
  final Color borderColor;
  final bool selected;

  static const double _sheetW = 600;
  static const double _sheetH = 100;

  @override
  Widget build(BuildContext context) {
    final frameW = _sheetW / kManWalkFrameCount;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? Colors.amber : borderColor,
          width: selected ? 2.5 : 1.2,
        ),
        color: const Color(0xFF263238),
      ),
      clipBehavior: Clip.antiAlias,
      child: Transform.scale(
        scale: 2,
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: frameW,
            height: _sheetH * 0.42,
            child: ClipRect(
              child: Align(
                alignment: Alignment.topLeft,
                widthFactor: 1 / kManWalkFrameCount,
                heightFactor: 0.42,
                child: Image.asset(
                  'assets/images/$kManSpriteAsset',
                  width: _sheetW,
                  height: _sheetH,
                  fit: BoxFit.fill,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    Icons.face,
                    color: Colors.white.withValues(alpha: 0.85),
                    size: size * 0.45,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
