// Firebase 옵션 — `flutterfire configure`로 재생성하면 웹 등이 콘솔과 자동 일치합니다.
// ignore_for_file: lines_longer_than_80_chars, avoid_classes_with_only_static_members

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// [Firebase.initializeApp]에 넘길 기본 옵션 (플랫폼별).
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  /// 웹 앱은 Firebase 콘솔 → 프로젝트 설정에서 복사한 값이 정확합니다.
  /// `appId`가 잘못되면 웹 초기화가 실패할 수 있으니 `flutterfire configure`로 갱신하세요.
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCKRqkTCuwVkbOAxhX3Ujm7WXhFUqyHy7c',
    appId: '1:312031209328:web:maru-moving-game',
    messagingSenderId: '312031209328',
    projectId: 'maru-moving-game',
    authDomain: 'maru-moving-game.firebaseapp.com',
    databaseURL: 'https://maru-moving-game-default-rtdb.firebaseio.com',
    storageBucket: 'maru-moving-game.firebasestorage.app',
  );

  /// `android/app/google-services.json`과 동일.
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCKRqkTCuwVkbOAxhX3Ujm7WXhFUqyHy7c',
    appId: '1:312031209328:android:c89aae0ccdc12f649e51b5',
    messagingSenderId: '312031209328',
    projectId: 'maru-moving-game',
    databaseURL: 'https://maru-moving-game-default-rtdb.firebaseio.com',
    storageBucket: 'maru-moving-game.firebasestorage.app',
  );

  /// `ios/Runner/GoogleService-Info.plist`와 동일.
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDz4vk4hFKcQTuX9sGSaBkaTSbg8ne3igM',
    appId: '1:312031209328:ios:381e61d829b345e09e51b5',
    messagingSenderId: '312031209328',
    projectId: 'maru-moving-game',
    databaseURL: 'https://maru-moving-game-default-rtdb.firebaseio.com',
    storageBucket: 'maru-moving-game.firebasestorage.app',
    iosBundleId: 'com.marucompany.floorup',
  );

  /// macOS 전용 plist가 없을 때 iOS 앱과 동일 프로젝트로 연결.
  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyDz4vk4hFKcQTuX9sGSaBkaTSbg8ne3igM',
    appId: '1:312031209328:ios:381e61d829b345e09e51b5',
    messagingSenderId: '312031209328',
    projectId: 'maru-moving-game',
    databaseURL: 'https://maru-moving-game-default-rtdb.firebaseio.com',
    storageBucket: 'maru-moving-game.firebasestorage.app',
    iosBundleId: 'com.marucompany.floorup',
  );
}
