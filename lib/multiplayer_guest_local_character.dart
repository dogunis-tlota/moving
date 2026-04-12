import 'package:flame/cache.dart';

import 'player_character.dart';

class MultiplayerGuestLocalCharacter {
  const MultiplayerGuestLocalCharacter._();

  static Future<PlayerCharacter> load(Images images) {
    return PlayerCharacter.load(images);
  }
}
