import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Thrown when sign-in succeeded against Firebase Auth but the email has
/// been blacklisted (the account was previously deleted by an admin or by
/// the user themselves). Caught by the login UI to show a friendly message.
class AccountDeletedException implements Exception {
  const AccountDeletedException();
  @override
  String toString() => 'This account has been deleted and can no longer sign in.';
}

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Returns true when [email] has a tombstone in `blacklist/{email}`.
  /// Empty emails are treated as not blacklisted so anonymous-style accounts
  /// don't get permanently locked out.
  Future<bool> isEmailBlacklisted(String email) async {
    if (email.isEmpty) return false;
    try {
      final snap = await _db.collection('blacklist').doc(email).get();
      return snap.exists;
    } catch (_) {
      // If the read fails (e.g. transient network issue) we let the user
      // through — a stale blacklist hit will be caught on the next call.
      return false;
    }
  }

  /// If the just-signed-in [user] has a blacklisted email, immediately sign
  /// them back out and throw [AccountDeletedException] so the UI can react.
  Future<void> _enforceBlacklist(User user) async {
    final email = user.email ?? '';
    if (await isEmailBlacklisted(email)) {
      await _auth.signOut();
      try {
        await _googleSignIn.signOut();
      } catch (_) {}
      throw const AccountDeletedException();
    }
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
    if (user != null) await _enforceBlacklist(user);
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
    await _enforceBlacklist(user);

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
    await _enforceBlacklist(user);

    final isNew = cred.additionalUserInfo?.isNewUser ?? false;
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
    // Disable Firestore network BEFORE revoking the auth token. This stops all
    // active stream subscriptions cleanly instead of letting them receive
    // permission-denied errors when the token is invalidated.
    await FirebaseFirestore.instance.disableNetwork();
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  Future<void> resetPassword(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());
}
