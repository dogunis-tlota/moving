import 'package:flame/cache.dart';

import 'npc_character.dart';

class MultiplayerGuestCharacter {
  const MultiplayerGuestCharacter._();

  static Future<NpcCharacter> load(Images images) async {
    final c = await NpcCharacter.load(images);
    c.isNetworkDriven = true;
    return c;
  }
}
