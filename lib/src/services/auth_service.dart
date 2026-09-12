import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'api_client.dart';
import 'realtime_client.dart';

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

/// Result of a sign-up attempt. The auth user is created either way; the
/// verification-email send is best-effort and may fail independently (rate
/// limits, template misconfiguration, transient network). The OTP screen
/// uses [emailSendError] to surface "we couldn't send — tap Resend" rather
/// than leaving the user staring at an inbox that will never get the mail.
class SignupResult {
  final User user;
  final String? emailSendError;
  const SignupResult({required this.user, this.emailSendError});
}

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  late final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: kIsWeb
        ? '751233585713-cl111fujhkk21jcm3lbddodlb4hlldkq.apps.googleusercontent.com'
        : null,
  );

  AuthService() {
    _auth.authStateChanges().listen((user) {
      if (user != null) {
        if (!ApiClient.instance.isAuthenticated) {
          _syncHonoAuth(user);
        }
      } else {
        ApiClient.instance.clearTokens();
        RealtimeClient.instance.disconnect();
      }
    });
  }

  Future<void> _syncHonoAuth(User user, {String? avatarUrl, String? password}) async {
    try {
      if (password != null && password.isNotEmpty) {
        try {
          final res = await ApiClient.instance.post('/auth/login', body: {
            'email': user.email ?? '',
            'password': password,
          });
          if (res is Map<String, dynamic> && res['tokens'] != null) {
            final tokens = res['tokens'] as Map<String, dynamic>;
            await ApiClient.instance.setTokens(
              accessToken: tokens['accessToken'] as String,
              refreshToken: tokens['refreshToken'] as String,
              userId: user.uid,
              userEmail: user.email,
            );
            RealtimeClient.instance.connect();
            return;
          }
        } catch (_) {}
      }

      final syncRes = await ApiClient.instance.post('/auth/firebase-sync', body: {
        'uid': user.uid,
        'email': user.email ?? '',
        'displayName': user.displayName,
        'avatarUrl': avatarUrl ?? user.photoURL,
      });
      if (syncRes is Map<String, dynamic> && syncRes['tokens'] != null) {
        final tokens = syncRes['tokens'] as Map<String, dynamic>;
        final userObj = syncRes['user'] as Map<String, dynamic>?;
        final dbUserId = userObj?['uid'] as String? ?? userObj?['id'] as String? ?? user.uid;
        await ApiClient.instance.setTokens(
          accessToken: tokens['accessToken'] as String,
          refreshToken: tokens['refreshToken'] as String,
          userId: dbUserId,
          userEmail: user.email,
        );
        RealtimeClient.instance.connect();
      }
    } catch (e) {
      debugPrint('[AuthService] _syncHonoAuth error: $e');
    }
  }

  Future<void> syncCurrentSession() async {
    final user = _auth.currentUser;
    if (user != null) {
      await _syncHonoAuth(user);
    }
  }

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Set to true only when the current session started via sign-up so the
  /// router knows to send the user to onboarding. Cleared on login or
  /// sign-out so returning users always land on /home.
  bool justSignedUp = false;

  bool get requiresEmailVerification {
    final user = _auth.currentUser;
    return user != null &&
        (user.email ?? '').trim().isNotEmpty &&
        !user.emailVerified;
  }

  Future<void> sendEmailVerification() async {
    await _auth.currentUser?.reload();
    final user = _auth.currentUser;
    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
    }
  }

  /// Maps a verification-send failure to a user-readable string. Returns null
  /// on success. Kept out of the OTP screen so resend and signup share the
  /// exact same error messaging.
  String _verificationSendError(Object e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'too-many-requests':
          return 'Too many attempts. Wait a few minutes and tap Resend.';
        case 'network-request-failed':
          return 'Network error sending the verification email. Tap Resend.';
        case 'user-not-found':
        case 'no-current-user':
          return 'Account not found. Please sign up again.';
        case 'invalid-recipient-email':
        case 'invalid-email':
          return 'That email address was rejected by the mail server.';
        default:
          return 'Could not send verification email (${e.code}). Tap Resend.';
      }
    }
    return 'Could not send verification email. Tap Resend.';
  }

  Future<bool> reloadAndCheckEmailVerified() async {
    await _auth.currentUser?.reload();
    return _auth.currentUser?.emailVerified ?? false;
  }

  Future<void> discardPendingSignup() async {
    var user = _auth.currentUser;
    if (user == null) return;

    try {
      await user.reload().timeout(const Duration(seconds: 4));
      user = _auth.currentUser;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'no-current-user' || e.code == 'user-not-found') {
        justSignedUp = false;
        return;
      }
      rethrow;
    }

    if (user == null) {
      justSignedUp = false;
      return;
    }

    if (user.emailVerified) {
      throw FirebaseAuthException(
        code: 'email-already-verified',
        message: 'This email is already verified.',
      );
    }

    try {
      await _db
          .collection('users')
          .doc(user.uid)
          .delete()
          .timeout(const Duration(seconds: 6));
    } catch (_) {
      // Best-effort cleanup. Deleting the Auth user is the important part for
      // freeing the email so the user can restart signup on the Spark plan.
    }
    try {
      await ApiClient.instance.delete('/auth/account');
    } catch (_) {}
    await ApiClient.instance.clearTokens();
    RealtimeClient.instance.disconnect();
    justSignedUp = false;
  }

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
      'appIntroSeen': false,
      'welcomeMessageSeen': false,
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
    if (!snap.exists) {
      await ref.set(_defaultUserDoc(user, avatarUrl: avatarUrl));
      return;
    }
    // Doc exists — backfill any identity fields the doc is missing.
    //
    // Background: older docs (and one race-prone code path that's since
    // been fixed) sometimes ended up with `email: null` even though
    // Firebase Auth had the address. The admin users list reads the doc,
    // not the Auth user, so those users showed "No email on file" despite
    // logging in fine. We can't `set(merge: true)` the email blindly —
    // that would also overwrite a perfectly-good email with null if the
    // Auth user's email happened to be null for any reason. So we only
    // patch fields that are missing *and* have a non-empty Auth-side
    // value to fill them with.
    final data = snap.data() ?? {};
    final patch = <String, dynamic>{};

    final docEmail = (data['email'] as String?)?.trim() ?? '';
    final authEmail = (user.email ?? '').trim();
    if (docEmail.isEmpty && authEmail.isNotEmpty) {
      patch['email'] = authEmail;
    }

    // Avatar follows the same idempotent rule — if the caller passed one
    // (Google/Apple flows do) and the doc doesn't already have one, fill
    // it. We never overwrite an avatar the user has customized.
    final docAvatar = (data['avatarUrl'] as String?)?.trim() ?? '';
    if (docAvatar.isEmpty && (avatarUrl ?? '').trim().isNotEmpty) {
      patch['avatarUrl'] = avatarUrl;
    }

    if (patch.isNotEmpty) {
      await ref.set(patch, SetOptions(merge: true));
    }
  }

  Future<SignupResult?> signUp({
    required String email,
    required String password,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = cred.user;
    if (user == null) return null;

    justSignedUp = true;
    try {
      final res = await ApiClient.instance.post('/auth/signup', body: {
        'email': user.email ?? email.trim(),
        'password': password,
        'uid': user.uid,
      });
      if (res is Map<String, dynamic> && res['tokens'] != null) {
        final tokens = res['tokens'] as Map<String, dynamic>;
        await ApiClient.instance.setTokens(
          accessToken: tokens['accessToken'] as String,
          refreshToken: tokens['refreshToken'] as String,
          userId: user.uid,
          userEmail: user.email,
        );
        RealtimeClient.instance.connect();
      }
    } catch (e) {
      debugPrint('[AuthService] Hono signup fallback: $e');
      await _syncHonoAuth(user, password: password);
    }

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
      'appIntroSeen': false,
      'welcomeMessageSeen': false,
      'followersCount': 0,
      'followingCount': 0,
      'postsCount': 0,
      'fcmTokens': <String>[],
      'createdAt': FieldValue.serverTimestamp(),
    });

    String? sendError;
    try {
      await user.sendEmailVerification();
    } catch (e, st) {
      // Don't tear down the account on a send failure — the OTP screen
      // exposes a Resend action — but DO surface the failure so the user
      // isn't left staring at an inbox the mail will never reach. Log the
      // underlying error too so failures (quota, template, network) are
      // diagnosable instead of silently swallowed.
      debugPrint('sendEmailVerification failed during signUp: $e\n$st');
      sendError = _verificationSendError(e);
    }
    return SignupResult(user: user, emailSendError: sendError);
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
      await _syncHonoAuth(user, password: password);
      await _ensureUserDoc(user);
    }
    return user;
  }

  Future<User?> signInWithGoogle({required GoogleAuthIntent intent}) async {
    final UserCredential cred;
    if (kIsWeb) {
      final googleProvider = GoogleAuthProvider();
      googleProvider.setCustomParameters({'prompt': 'select_account'});
      cred = await _auth.signInWithPopup(googleProvider);
    } else {
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

      cred = await _auth.signInWithCredential(credential);
    }

    final user = cred.user;
    if (user == null) return null;

    // Validate intent BEFORE _ensureUserDoc and before the router can react
    // to auth state changes, so there is no visible login flash.
    final isNew = cred.additionalUserInfo?.isNewUser ?? false;
    // Treat "Continue with Google" on signup as a unified entry point: if the
    // Google account already exists we silently log them in instead of
    // erroring out. Otherwise tapping the signup-page Google button for a
    // returning user would briefly land on /home then bounce to /login.
    justSignedUp = isNew;
    if (intent == GoogleAuthIntent.login && isNew) {
      try {
        await user.delete();
      } catch (_) {}
      if (!kIsWeb) {
        try {
          await _googleSignIn.signOut();
        } catch (_) {}
      }
      await _auth.signOut();
      throw const GoogleAuthFlowException(
        'No account found for this Google email. Please sign up first.',
      );
    }

    // Intent validated — safe to persist/update the user doc now.
    await _syncHonoAuth(user, avatarUrl: user.photoURL);
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
        'appIntroSeen': false,
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

    await _syncHonoAuth(user);
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
        'appIntroSeen': false,
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
      await ApiClient.instance.post('/auth/logout');
    } catch (_) {}
    await ApiClient.instance.clearTokens();
    RealtimeClient.instance.disconnect();
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    await _auth.signOut();
  }

  Future<void> resetPassword(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());
}
