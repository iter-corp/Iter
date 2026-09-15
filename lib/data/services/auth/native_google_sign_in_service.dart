import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:webview_flutter/webview_flutter.dart';

class NativeGoogleSignInService {
  static final NativeGoogleSignInService instance = NativeGoogleSignInService._();
  NativeGoogleSignInService._();

  static const String serverClientId =
      '751233585713-cl111fujhkk21jcm3lbddodlb4hlldkq.apps.googleusercontent.com';
  static const String iosClientId =
      '751233585713-tgffet0qbu9em9mlhsbh84jiqrh24a8o.apps.googleusercontent.com';

  late final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: serverClientId,
    clientId: defaultTargetPlatform == TargetPlatform.iOS ? iosClientId : null,
  );

  bool _isSigningIn = false;

  Future<UserCredential?> signInWithDeviceAccount() async {
    if (_isSigningIn) return null;
    _isSigningIn = true;
    try {
      try {
        await _googleSignIn.signOut();
      } catch (_) {}

      debugPrint('[NativeGoogleAuth] Showing native device account picker...');
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        debugPrint('[NativeGoogleAuth] User dismissed account picker');
        return null;
      }

      debugPrint('[NativeGoogleAuth] Selected: ${googleUser.email}');
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      debugPrint('[NativeGoogleAuth] Native Firebase sign-in success: ${userCredential.user?.uid}');
      return userCredential;
    } catch (e, stack) {
      debugPrint('[NativeGoogleAuth] Error during native Google sign-in: $e\n$stack');
      return null;
    } finally {
      _isSigningIn = false;
    }
  }

  Future<void> bridgeSessionToWebView(WebViewController controller, User user) async {
    try {
      final idToken = await user.getIdToken();
      final refreshToken = user.refreshToken ?? '';
      final uid = user.uid;
      final email = user.email ?? '';
      final displayName = user.displayName ?? '';
      final photoURL = user.photoURL ?? '';

      final escapedUid = jsonEncode(uid);
      final escapedEmail = jsonEncode(email);
      final escapedDisplayName = jsonEncode(displayName);
      final escapedPhotoUrl = jsonEncode(photoURL);
      final escapedIdToken = jsonEncode(idToken ?? '');
      final escapedRefreshToken = jsonEncode(refreshToken);

      final jsCode = '''
        (function() {
          try {
            console.log('[NativeBridge] Writing auth session to IndexedDB...');
            const dbReq = indexedDB.open('firebaseLocalStorageDb');
            dbReq.onerror = function() {
              console.error('[NativeBridge] Could not open IndexedDB, falling back to reload');
              window.location.href = 'https://iterglobal.icu/#/home';
              window.location.reload();
            };
            dbReq.onsuccess = function(e) {
              const db = e.target.result;
              if (!db.objectStoreNames.contains('firebaseLocalStorage')) {
                console.warn('[NativeBridge] Store firebaseLocalStorage not found');
                window.location.href = 'https://iterglobal.icu/#/home';
                window.location.reload();
                return;
              }
              const tx = db.transaction('firebaseLocalStorage', 'readwrite');
              const store = tx.objectStore('firebaseLocalStorage');
              const userObj = {
                fbase_key: 'firebase:authUser:AIzaSyANV9AQMtCxoi-vOPLxddlw_Fd4JPT6LyY:[DEFAULT]',
                value: {
                  uid: $escapedUid,
                  email: $escapedEmail,
                  emailVerified: true,
                  displayName: $escapedDisplayName,
                  isAnonymous: false,
                  photoURL: $escapedPhotoUrl,
                  providerData: [{
                    providerId: 'google.com',
                    uid: $escapedUid,
                    displayName: $escapedDisplayName,
                    email: $escapedEmail,
                    photoURL: $escapedPhotoUrl
                  }],
                  stsTokenManager: {
                    refreshToken: $escapedRefreshToken,
                    accessToken: $escapedIdToken,
                    expirationTime: ${DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch}
                  },
                  createdAt: '${DateTime.now().millisecondsSinceEpoch}',
                  lastLoginAt: '${DateTime.now().millisecondsSinceEpoch}',
                  apiKey: 'AIzaSyANV9AQMtCxoi-vOPLxddlw_Fd4JPT6LyY',
                  appName: '[DEFAULT]'
                }
              };
              store.put(userObj);
              tx.oncomplete = function() {
                console.log('[NativeBridge] Auth saved to IndexedDB. Navigating to home...');
                window.location.href = 'https://iterglobal.icu/#/home';
                setTimeout(function() { window.location.reload(); }, 250);
              };
            };
          } catch(err) {
            console.error('[NativeBridge] Error during auth injection: ' + err);
            window.location.href = 'https://iterglobal.icu/#/home';
            window.location.reload();
          }
        })();
      ''';
      await controller.runJavaScript(jsCode);
    } catch (e) {
      debugPrint('[NativeGoogleAuth] Error bridging session: $e');
    }
  }
}
