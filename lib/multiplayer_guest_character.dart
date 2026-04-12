import 'dart:ui';

import 'package:flame/cache.dart';

import 'npc_character.dart';

class MultiplayerGuestCharacter {
  const MultiplayerGuestCharacter._();

  static Future<NpcCharacter> load(Images images) async {
    final c = await NpcCharacter.load(images);
    c.isNetworkDriven = true;
    c.tintColor = const Color(0xFFFFE082);
    c.paint.colorFilter = ColorFilter.mode(c.tintColor, BlendMode.srcATop);
    return c;
  }
}
