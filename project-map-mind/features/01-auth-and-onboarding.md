# Auth and Onboarding

## What this feature does
Covers the cold-start brand surface (`SplashScreen`), the 5-slide marketing intro (`AppIntroScreen`), the three Firebase Auth flows (email/password, Google, Apple), the email-verification waiting screen (`OtpScreen` — there is no SMS OTP here, the name is legacy), the password-reset flow (`ForgotPasswordScreen`), and a single multi-section onboarding form (`OnboardingScreen`) that collects display name, username, bio, gender, GPS + city, plus optional "About you" personalization (profession, field, academic level, goals). Auth state and the user's Firestore doc are exposed application-wide through `authProviders`. Sign-up creates a Firestore `users/{uid}` doc immediately so personalization can be merged in later from the same screen.

## Key screens / widgets
- [splash_screen.dart](../../lib/src/features/screens/auth/splash_screen.dart) — logo + wordmark + spinner; renders while `authStateProvider` is loading.
- [app_intro_screen.dart](../../lib/src/features/screens/auth/app_intro_screen.dart) — 5-slide PageView marketing intro (Posts, Discuss, Travel, Events, Translate). On finish writes `appIntroSeen: true` to the user doc and `context.go('/home')`.
- [login_screen.dart](../../lib/src/features/screens/auth/login_screen.dart) — email + password, Google button always, Apple button only on iOS (`Platform.isIOS`). Maps `FirebaseAuthException` codes to friendly strings in `_friendlyError`.
- [signup_screen.dart](../../lib/src/features/screens/auth/signup_screen.dart) — email + password + confirm, password rule "8+ chars with letter and digit", per-field "touched" gating so errors only show after blur or submit. Routes to `/otp?email=…`.
- [otp_screen.dart](../../lib/src/features/screens/auth/otp_screen.dart) — actually an **email-verification waiting screen** (it does NOT collect a 6-digit code). The user opens the link in their inbox then taps "Verify", which calls `reloadAndCheckEmailVerified` and routes to `/onboarding`. Back arrow calls `discardPendingSignup` to delete the half-created account.
- [forgot_password_screen.dart](../../lib/src/features/screens/auth/forgot_password_screen.dart) — single email field, sends Firebase password-reset email.
- [onboarding_screen.dart](../../lib/src/features/screens/auth/onboarding_screen.dart) — final required step. Name, username (`^[a-z0-9._]{3,24}$`, lowercased, uniqueness check via `UserService.isUsernameTaken`), bio, gender dropdown, GPS button (`Geolocator` + `geocoding` reverse to city), `CityPickerField`, plus the optional `AboutYouEditor` (`personalization_fields.dart`).

## Auth providers used
- Email / password (`signUp`, `signIn`).
- Google sign-in (`google_sign_in`) — `signInWithGoogle({intent: login|signup})`. On `login` intent + new user, immediately deletes the new auth user and throws `GoogleAuthFlowException("No account found … sign up first.")`. `signup` intent for an existing user silently logs in.
- Apple sign-in (`sign_in_with_apple`) — iOS only; uses SHA-256 nonce + `OAuthProvider('apple.com')`. Pulls given/family name into `displayName` on the first run.
- Password reset (`sendPasswordResetEmail`).

## Firestore collections touched
- `users/{uid}` — created at sign-up and at Google/Apple first sign-in with a default doc (`uid`, `email`, `username:null`, `handle:null`, `bio:''`, `avatarUrl`, `coverUrl:null`, `gender:null`, `role:'user'`, `suspended:false`, `isPrivate:false`, `appIntroSeen:false`, counters, `fcmTokens:[]`, `createdAt`). Onboarding merges in `name`, `username`, `usernameLower`, `handle`, `bio`, `gender`, `city`, `location:{lat,lng}`, `profession`, `field`, `academicLevel` (only when `academicLevelAppliesTo(profession)` is true), `goals`. App-intro completion sets `appIntroSeen:true`.

## Services used
- [auth_service.dart](../../lib/src/services/auth_service.dart) — wraps `FirebaseAuth`, holds `justSignedUp` flag so the router knows to push to onboarding after sign-up. Exposes `discardPendingSignup` which deletes the user doc + auth user (timeouts: doc 6 s, auth 8 s).
- [user_service.dart](../../lib/src/services/user_service.dart) — `streamUser`, `updateUser`, `isUsernameTaken`.
- [admin_service.dart](../../lib/src/services/admin_service.dart) — `adminConfigProvider` supplies the dropdown options for profession, field, academic level, goals in the onboarding personalization block.
- [city_service.dart](../../lib/src/services/city_service.dart) — backs `CityPickerField`.
- `geolocator`, `geocoding` — GPS and reverse geocode used by the "Use my location" button.

## Non-obvious business rules
- The `authStateProvider` does `user.getIdToken()` + a 50 ms yield after sign-in. This is a deliberate fix for a transient permission-denied that fired when Firestore opened a snapshot before its internal auth listener saw the new token.
- `currentUserDocProvider` uses `_retryStream` (up to 3 retries with 600 ms × n back-off) for the same race.
- "Continue with Google" on the signup page is a unified entry: an existing user is silently logged in (no flash to `/home` → `/login` bounce). The same button on the login page rejects new users.
- `_ensureUserDoc` is **idempotent backfill only**: it never overwrites a populated email or avatar — it only fills missing ones. This was added because some legacy docs had `email:null`.
- `discardPendingSignup` refuses to delete an already-verified account (throws `email-already-verified`).
- Username constraint is enforced both client-side (regex) and via `isUsernameTaken` lookup before write.
- Academic level is only persisted when `academicLevelAppliesTo(_profession)` returns true — students keep it, professionals don't.
- The `OtpScreen` "destination" defaults to a placeholder phone number `(400)650-1111` if no email arg is passed — defensive only; the signup flow always passes the email.
- Password rule diverges from Firebase's 6-char floor (client requires 8+ with letter + digit). Helper text appears as a red pill, not muted text.
- Per-field "touched" pattern in signup avoids showing red text while the user is still typing the first attempt; `_passCtrl.addListener` rebuilds live once touched.

## Localization
~76 `context.t.*` calls across the 7 auth screens (login 15, intro 12, onboarding 26, others ≤10 each).

## Related files
- `lib/src/features/screens/auth/splash_screen.dart`
- `lib/src/features/screens/auth/app_intro_screen.dart`
- `lib/src/features/screens/auth/login_screen.dart`
- `lib/src/features/screens/auth/signup_screen.dart`
- `lib/src/features/screens/auth/otp_screen.dart`
- `lib/src/features/screens/auth/forgot_password_screen.dart`
- `lib/src/features/screens/auth/onboarding_screen.dart`
- `lib/src/services/auth_service.dart`
- `lib/src/services/user_service.dart`
- `lib/src/services/city_service.dart`
- `lib/src/providers/auth_providers.dart`
- `lib/src/features/widgets/personalization_fields.dart`
- `lib/src/features/widgets/primary_action_button.dart`
- `lib/src/features/widgets/app_page_background.dart`
