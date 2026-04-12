import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import 'player_identity.dart';

/// Firebase Firestore에 플레이어 데이터를 등록.
class FirebasePlayerRepository {
  Future<void> registerPlayer(PlayerIdentity identity) async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      final db = FirebaseFirestore.instance;
      await db.collection('players').add(identity.toMap());
    } catch (_) {
      // Firebase 미설정/네트워크 오류 시 게임 진행은 유지
    }
  }
}
