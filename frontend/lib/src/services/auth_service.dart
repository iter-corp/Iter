import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Legacy exception kept for compatibility with existing UI catches.
class AccountDeletedException implements Exception {
  const AccountDeletedException();
  @override
  String toString() =>
      'This account has been deleted and can no longer sign in.';
}

enum GoogleAuthIntent { login, signup }

class GoogleAuthFlowException implements Exception {
  final String message;
  const GoogleAuthFlowException(this.message);

  @override
  String toString() => message;
}

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Set to true only when the current session started via sign-up so the
  /// router knows to send the user to onboarding. Cleared on login or
  /// sign-out so returning users always land on /home.
  bool justSignedUp = false;

  Map<String, dynamic> _defaultUserDoc(User user, {String? avatarUrl}) {
    return {
      'uid': user.uid,
      'email': user.email,
      'username': null,
      'handle': null,
      'bio': '',
      'avatarUrl': avatarUrl,
      'coverUrl': null,
      'gender': null,
      'role': 'user',
      'suspended': false,
      'isPrivate': false,
      'followersCount': 0,
      'followingCount': 0,
      'postsCount': 0,
      'fcmTokens': <String>[],
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  Future<void> _ensureUserDoc(User user, {String? avatarUrl}) async {
    final ref = _db.collection('users').doc(user.uid);
    final snap = await ref.get();
    if (snap.exists) return;
    await ref.set(_defaultUserDoc(user, avatarUrl: avatarUrl));
  }

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
      justSignedUp = true;
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
        'isPrivate': false,
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
    justSignedUp = false;
    final cred = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = cred.user;
    if (user != null) {
      await _ensureUserDoc(user);
    }
    return user;
  }

  Future<User?> signInWithGoogle({required GoogleAuthIntent intent}) async {
    // Always sign out first to clear any cached account so the account picker
    // is shown every time rather than silently reusing the last session.
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
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

    // Validate intent BEFORE _ensureUserDoc and before the router can react
    // to auth state changes, so there is no visible login flash.
    final isNew = cred.additionalUserInfo?.isNewUser ?? false;
    justSignedUp = isNew;
    if (intent == GoogleAuthIntent.login && isNew) {
      try {
        await user.delete();
      } catch (_) {}
      try {
        await _googleSignIn.signOut();
      } catch (_) {}
      await _auth.signOut();
      throw const GoogleAuthFlowException(
        'No account found for this Google email. Please sign up first.',
      );
    }
    if (intent == GoogleAuthIntent.signup && !isNew) {
      try {
        await _googleSignIn.signOut();
      } catch (_) {}
      await _auth.signOut();
      throw const GoogleAuthFlowException(
        'An account with this Google email already exists. Please log in instead.',
      );
    }

    // Intent validated — safe to persist/update the user doc now.
    await _ensureUserDoc(user, avatarUrl: user.photoURL);

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
        'isPrivate': false,
        'followersCount': 0,
        'followingCount': 0,
        'postsCount': 0,
        'fcmTokens': <String>[],
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    return user;
  }

  Future<User?> signInWithApple() async {
    final rawNonce = _generateNonce();
    final nonce = sha256.convert(utf8.encode(rawNonce)).toString();

    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: nonce,
    );

    final oauthCredential = OAuthProvider('apple.com').credential(
      idToken: appleCredential.identityToken,
      rawNonce: rawNonce,
    );

    final cred = await _auth.signInWithCredential(oauthCredential);
    final user = cred.user;
    if (user == null) return null;

    await _ensureUserDoc(user);

    final isNew = cred.additionalUserInfo?.isNewUser ?? false;
    justSignedUp = isNew;
    if (isNew) {
      final displayName = [
        appleCredential.givenName,
        appleCredential.familyName,
      ].where((s) => s != null && s.isNotEmpty).join(' ');

      if (displayName.isNotEmpty) {
        await user.updateDisplayName(displayName);
      }

      await _db.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'email': user.email ?? appleCredential.email,
        'username': null,
        'handle': null,
        'bio': '',
        'avatarUrl': null,
        'coverUrl': null,
        'gender': null,
        'role': 'user',
        'suspended': false,
        'isPrivate': false,
        'followersCount': 0,
        'followingCount': 0,
        'postsCount': 0,
        'fcmTokens': <String>[],
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    return user;
  }

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)])
        .join();
  }

  Future<void> signOut() async {
    justSignedUp = false;
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    await _auth.signOut();
  }

  Future<void> resetPassword(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());
}
