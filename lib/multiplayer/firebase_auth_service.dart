import 'package:firebase_auth/firebase_auth.dart';

class FirebaseAuthService {
  FirebaseAuthService({FirebaseAuth? auth}) : _auth = auth;

  FirebaseAuth? _auth;
  FirebaseAuth get _firebaseAuth => _auth ??= FirebaseAuth.instance;

  Future<User> ensureSignedInAnonymously() async {
    final current = _firebaseAuth.currentUser;
    if (current != null) return current;
    final cred = await _firebaseAuth.signInAnonymously();
    final user = cred.user;
    if (user == null) {
      throw StateError('Anonymous auth failed');
    }
    return user;
  }
}
