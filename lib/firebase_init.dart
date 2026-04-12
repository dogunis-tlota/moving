import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

bool _initialized = false;

Future<void> ensureFirebaseInitialized() async {
  if (_initialized || Firebase.apps.isNotEmpty) {
    _initialized = true;
    return;
  }

  if (kIsWeb) {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'AIzaSyCKRqkTCuwVkbOAxhX3Ujm7WXhFUqyHy7c',
        appId: '1:312031209328:web:maru-moving-game',
        messagingSenderId: '312031209328',
        projectId: 'maru-moving-game',
        authDomain: 'maru-moving-game.firebaseapp.com',
        storageBucket: 'maru-moving-game.firebasestorage.app',
        databaseURL: 'https://maru-moving-game-default-rtdb.firebaseio.com',
      ),
    );
  } else {
    await Firebase.initializeApp();
  }
  _initialized = true;
}
