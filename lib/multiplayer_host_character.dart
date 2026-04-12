import 'package:flame/cache.dart';

import 'player_character.dart';

class MultiplayerHostCharacter {
  const MultiplayerHostCharacter._();

  static Future<PlayerCharacter> load(Images images) {
    return PlayerCharacter.load(images);
  }
}
