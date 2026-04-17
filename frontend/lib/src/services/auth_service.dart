import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  Future<void> _ensureNotSuspended(User user) async {
    final userSnap = await _db.collection('users').doc(user.uid).get();
    final data = userSnap.data();

    // Only check if document exists; if missing, likely a new user being synced
    if (!userSnap.exists) {
      return;
    }

    final suspended = (data?['suspended'] as bool?) ?? false;
    final deleted = (data?['deleted'] as bool?) ?? false;
    if (suspended || deleted) {
      await _auth.signOut();
      await _googleSignIn.signOut();
      throw FirebaseAuthException(
        code: 'user-disabled',
        message: deleted
            ? 'This account has been deleted by an administrator.'
            : 'This account has been suspended by an administrator.',
      );
    }
  }

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<User?> signUp({
    required String email,
    required String password,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = cred.user;
    if (user != null) {
      await _db.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'email': user.email,
        'username': null,
        'handle': null,
        'bio': '',
        'avatarUrl': null,
        'coverUrl': null,
        'gender': null,
        'role': 'user',
        'suspended': false,
        'followersCount': 0,
        'followingCount': 0,
        'postsCount': 0,
        'fcmTokens': <String>[],
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    return user;
  }

  Future<User?> signIn({
    required String email,
    required String password,
  }) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = cred.user;
    if (user != null) {
      await _ensureNotSuspended(user);
    }
    return user;
  }

  Future<User?> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null;

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final cred = await _auth.signInWithCredential(credential);
    final user = cred.user;
    if (user == null) return null;

    final isNew = cred.additionalUserInfo?.isNewUser ?? false;
    if (isNew) {
      await _db.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'email': user.email,
        'username': null,
        'handle': null,
        'bio': '',
        'avatarUrl': user.photoURL,
        'coverUrl': null,
        'gender': null,
        'role': 'user',
        'suspended': false,
        'followersCount': 0,
        'followingCount': 0,
        'postsCount': 0,
        'fcmTokens': <String>[],
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    await _ensureNotSuspended(user);
    return user;
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  Future<void> resetPassword(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());
}
