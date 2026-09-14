import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_strings.dart';
import '../../../providers/auth_providers.dart';
import '../../../services/auth_service.dart';
import '../../widgets/app_page_background.dart';
import '../../widgets/primary_action_button.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/responsive.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _googleLoading = false;
  bool _appleLoading = false;
  bool _obscurePassword = true;
  String? _error;

  final bool _isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Maps a [FirebaseAuthException] code to a short human-readable message.
  /// Firebase's default messages leak technical detail ("There is no user
  /// record corresponding to this identifier..."). This collapses every
  /// "wrong credentials" variant into one clear line so the user knows
  /// exactly what to fix.
  String _friendlyError(FirebaseAuthException e,
      {String fallback = 'Login failed'}) {
    switch (e.code) {
      case 'invalid-email':
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
      case 'invalid-login-credentials':
        return 'Incorrect email or password.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again in a few minutes.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      case 'unauthorized-domain':
        return 'Domain is not authorized for Google Sign-In in Firebase Console.';
      default:
        return fallback;
    }
  }

  Future<void> _signInWithApple() async {
    setState(() {
      _appleLoading = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).signInWithApple();
    } on AccountDeletedException catch (e) {
      setState(() => _error = e.toString());
    } on FirebaseAuthException catch (e) {
      setState(
          () => _error = _friendlyError(e, fallback: 'Apple sign-in failed.'));
    } catch (_) {
      setState(() => _error = 'Apple sign-in failed.');
    } finally {
      if (mounted) setState(() => _appleLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _googleLoading = true;
      _error = null;
    });
    try {
      await ref
          .read(authServiceProvider)
          .signInWithGoogle(intent: GoogleAuthIntent.login);
    } on GoogleAuthFlowException catch (e) {
      setState(() => _error = e.toString());
    } on AccountDeletedException catch (e) {
      setState(() => _error = e.toString());
    } on FirebaseAuthException catch (e) {
      if (e.code == 'popup-closed-by-user') {
        return;
      }
      setState(
          () => _error = _friendlyError(e, fallback: 'Google sign-in failed.'));
    } catch (e) {
      debugPrint('[google-signin] error: $e');
      final errStr = e.toString();
      if (errStr.contains('popup_closed') || errStr.contains('popup_blocked')) {
        return;
      }
      if (errStr.contains(': 10') || errStr.contains('common.api.j: 10')) {
        setState(() => _error =
            'Google Sign-In configuration error (Code 10). Missing SHA-1 fingerprint in Firebase Console.');
        return;
      }
      setState(() => _error = 'Google sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).signIn(
            email: _usernameCtrl.text,
            password: _passCtrl.text,
          );
    } on AccountDeletedException catch (e) {
      setState(() => _error = e.toString());
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _friendlyError(e));
    } catch (_) {
      setState(() => _error = 'Login failed. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hPad = context.scaleW(16, 24);
    final vPad = context.scaleW(20, 32);
    final logoSize = context.scaleW(72, 84);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppPageBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
                child: Form(
                  key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(height: context.scaleW(16, 30)),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset(
                      'assets/img/app_icon.png',
                      width: logoSize,
                      height: logoSize,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    context.t.login,
                    style: TextStyle(
                      fontSize: context.scaleW(20, 24),
                      fontWeight: FontWeight.bold,
                      color: context.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.t.loginSubtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: context.textMuted,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 30),
                  _buildTextField(
                    controller: _usernameCtrl,
                    hint: context.t.loginUsernameOrEmail,
                    prefixIcon: Icons.person_2_outlined,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? context.t.loginEnterUsernameOrEmail
                        : null,
                  ),
                  const SizedBox(height: 14),
                  _buildTextField(
                    controller: _passCtrl,
                    hint: context.t.password,
                    prefixIcon: Icons.lock_outline,
                    isPassword: true,
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return context.t.signupEnterPassword;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: GestureDetector(
                      onTap: () => context.push('/forgot-password'),
                      child: Text(
                        context.t.forgotPassword,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFFCE5DE5),
                        ),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    AppGlassCard(
                      width: double.infinity,
                      radius: 14,
                      surfaceAlpha: context.isDark ? 0.62 : 0.54,
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  PrimaryActionButton(
                    label: context.t.login,
                    onPressed: _loading ? null : _submit,
                    loading: _loading,
                    size: PrimaryActionSize.large,
                    fullWidth: true,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(child: Divider(color: context.borderColor)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          context.t.loginOr,
                          style:
                              TextStyle(fontSize: 13, color: context.textMuted),
                        ),
                      ),
                      Expanded(child: Divider(color: context.borderColor)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildSocialButton(
                    label: _googleLoading
                        ? context.t.loginSigningIn
                        : context.t.continueWithGoogle,
                    icon: _googleLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : _buildSocialBadge('G', const Color(0xFF4285F4)),
                    onTap: _googleLoading ? () {} : _signInWithGoogle,
                  ),
                  if (_isIOS) ...[
                    const SizedBox(height: 12),
                    _buildSocialButton(
                      label: _appleLoading
                          ? context.t.loginSigningIn
                          : context.t.continueWithApple,
                      icon: _appleLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(Icons.apple,
                              size: 24, color: context.textPrimary),
                      onTap: _appleLoading ? () {} : _signInWithApple,
                    ),
                  ],
                  const SizedBox(height: 30),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        context.t.dontHaveAccount,
                        style:
                            TextStyle(fontSize: 13, color: context.textMuted),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => context.push('/signup'),
                        child: Text(
                          context.t.signUp,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFCE5DE5),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: context.bottomSafeInset),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);
}

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData prefixIcon,
    required String? Function(String?) validator,
    bool isPassword = false,
  }) {
    return FormField<String>(
      initialValue: controller.text,
      validator: validator,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      builder: (field) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppGlassCard(
            radius: 16,
            borderAlpha: field.hasError ? 0.7 : null,
            child: TextField(
              controller: controller,
              obscureText: isPassword ? _obscurePassword : false,
              onChanged: field.didChange,
              style: TextStyle(fontSize: 14, color: context.textPrimary),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(fontSize: 14, color: context.textMuted),
                prefixIcon:
                    Icon(prefixIcon, size: 20, color: context.textMuted),
                suffixIcon: isPassword
                    ? IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 20,
                          color: context.textMuted,
                        ),
                        onPressed: () {
                          setState(() => _obscurePassword = !_obscurePassword);
                        },
                      )
                    : null,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                filled: true,
                fillColor: Colors.transparent,
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          if (field.hasError && field.errorText != null)
            _authFieldError(field.errorText!),
        ],
      ),
    );
  }

  Widget _authFieldError(String text) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 16, top: 6),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.redAccent,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildSocialButton({
    required String label,
    required Widget icon,
    required VoidCallback onTap,
  }) {
    return AppGlassCard(
      width: double.infinity,
      height: 52,
      radius: 16,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: icon,
        label: Text(
          label,
          style: TextStyle(
            color: context.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.transparent,
          side: BorderSide.none,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Widget _buildSocialBadge(String label, Color color) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
