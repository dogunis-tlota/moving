import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_init.dart';

/// Firestore `leaderboard` — 기록 단위: 도달 층·걸린 시간(초).
class LeaderboardEntry {
  LeaderboardEntry({
    required this.playerTag,
    required this.maxFloor,
    required this.elapsedSeconds,
    required this.recordedAt,
  });

  final String playerTag;
  final int maxFloor;
  final int elapsedSeconds;
  final DateTime? recordedAt;

  static LeaderboardEntry fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data();
    return LeaderboardEntry(
      playerTag: (m['playerTag'] ?? '').toString(),
      maxFloor: (m['maxFloor'] as num?)?.toInt() ?? 0,
      elapsedSeconds: (m['elapsedSeconds'] as num?)?.toInt() ?? 0,
      recordedAt: (m['recordedAt'] as Timestamp?)?.toDate(),
    );
  }
}

class LeaderboardService {
  Future<void> submitRun({
    required String playerTag,
    required int maxFloor,
    required int elapsedSeconds,
  }) async {
    try {
      await ensureAnonymousAuthForApp();
      if (Firebase.apps.isEmpty) return;
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) return;
      await FirebaseFirestore.instance.collection('leaderboard').doc(uid).set(
        <String, dynamic>{
          'uid': uid,
          'playerTag': playerTag,
          'maxFloor': maxFloor,
          'elapsedSeconds': elapsedSeconds,
          'recordedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  /// 층수 우선, 같은 층이면 짧은 시간 순.
  Future<List<LeaderboardEntry>> fetchTop({int limit = 30}) async {
    try {
      await ensureAnonymousAuthForApp();
      if (Firebase.apps.isEmpty) return [];
      final snap = await FirebaseFirestore.instance
          .collection('leaderboard')
          .orderBy('maxFloor', descending: true)
          .limit(100)
          .get();
      final list = snap.docs.map(LeaderboardEntry.fromDoc).toList();
      list.sort((a, b) {
        final c = b.maxFloor.compareTo(a.maxFloor);
        if (c != 0) return c;
        return a.elapsedSeconds.compareTo(b.elapsedSeconds);
      });
      if (list.length <= limit) return list;
      return list.sublist(0, limit);
    } catch (_) {
      return [];
    }
  }
}
