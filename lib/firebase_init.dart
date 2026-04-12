import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';

bool _initialized = false;
Future<void>? _initFuture;

Future<void> ensureFirebaseInitialized() async {
  if (_initialized || Firebase.apps.isNotEmpty) {
    _initialized = true;
    return;
  }
  _initFuture ??= _performInit();
  try {
    await _initFuture!;
  } catch (_) {
    _initFuture = null;
    rethrow;
  }
}

Future<void> _performInit() async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  _initialized = true;
}

/// Firestore 규칙(`request.auth != null`) 및 `uid` 기반 문서 경로용 — 익명 로그인.
Future<void> ensureAnonymousAuthForApp() async {
  await ensureFirebaseInitialized();
  if (FirebaseAuth.instance.currentUser != null) return;
  await FirebaseAuth.instance.signInAnonymously();
}
