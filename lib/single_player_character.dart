import 'package:flame/cache.dart';

import 'player_character.dart';

class SinglePlayerCharacter {
  const SinglePlayerCharacter._();

  static Future<PlayerCharacter> load(Images images) {
    return PlayerCharacter.load(images);
  }
}
