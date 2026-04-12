import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_init.dart';
import 'player_identity.dart';

/// Firebase Firestore에 플레이어 데이터를 등록.
class FirebasePlayerRepository {
  Future<void> registerPlayer(PlayerIdentity identity) async {
    try {
      await ensureAnonymousAuthForApp();
      if (Firebase.apps.isEmpty) return;
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) return;
      await FirebaseFirestore.instance
          .collection('players')
          .doc(uid)
          .set(identity.toMap(), SetOptions(merge: true));
    } catch (_) {
      // Firebase 미설정/네트워크 오류 시 게임 진행은 유지
    }
  }
}
