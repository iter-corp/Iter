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
import 'widgets/auth_desktop_wrapper.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  bool _googleLoading = false;
  bool _appleLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _error;

  bool _emailTouched = false;
  bool _passTouched = false;
  bool _confirmTouched = false;

  final bool _isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static final _emailRegex =
      RegExp(r'^[a-zA-Z0-9.!#$%&’*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)+$');

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  String _friendlyError(FirebaseAuthException e, {String fallback = 'Sign-up failed'}) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'An account already exists with this email. Try logging in instead.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return 'Password is too weak. Try adding numbers or symbols.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      default:
        return fallback;
    }
  }

  String? _validatePassword(String? value, AppStrings t) {
    final v = value ?? '';
    if (v.isEmpty) return t.enterPassword;
    if (v.length < 6) return t.passwordTooShort;
    return null;
  }

  Future<void> _submit() async {
    setState(() {
      _emailTouched = true;
      _passTouched = true;
      _confirmTouched = true;
    });

    if (!_formKey.currentState!.validate()) return;

    if (_passCtrl.text != _confirmCtrl.text) {
      setState(() => _error = context.t.passwordsDontMatch);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final email = _emailCtrl.text.trim();
      final result = await ref.read(authServiceProvider).signUp(
            email: email,
            password: _passCtrl.text,
          );
      if (result == null) {
        if (mounted) setState(() => _error = 'Sign-up failed. Please try again.');
        return;
      }
    } on AccountDeletedException catch (e) {
      setState(() => _error = e.toString());
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _friendlyError(e));
    } catch (_) {
      setState(() => _error = 'Sign-up failed. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
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
      setState(() => _error = _friendlyError(e, fallback: 'Apple sign-in failed.'));
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
      await ref.read(authServiceProvider).signInWithGoogle(intent: GoogleAuthIntent.signup);
    } on GoogleAuthFlowException catch (e) {
      setState(() => _error = e.toString());
    } on AccountDeletedException catch (e) {
      setState(() => _error = e.toString());
    } on FirebaseAuthException catch (e) {
      if (e.code == 'popup-closed-by-user') return;
      setState(() => _error = _friendlyError(e, fallback: 'Google sign-in failed.'));
    } catch (e) {
      final errStr = e.toString();
      if (errStr.contains('popup_closed') || errStr.contains('popup_blocked')) return;
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
  Widget build(BuildContext context) {
    return AuthDesktopWrapper(
      mobileContent: _buildMobileLayout(context),
      cardContent: _buildDesktopCardForm(context),
      underCardWidget: _buildDesktopUnderCard(context),
    );
  }

  /// Desktop Card Form: Facebook-style Sign Up card
  Widget _buildDesktopCardForm(BuildContext context) {
    final t = context.t;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            t.signUp,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            t.signupSubtitle,
            style: TextStyle(
              fontSize: 13,
              color: context.textMuted,
            ),
          ),
          const SizedBox(height: 18),
          Divider(color: context.borderColor),
          const SizedBox(height: 18),
          _buildAuthTextField(
            controller: _emailCtrl,
            hint: t.email,
            prefixIcon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            touched: _emailTouched,
            onBlur: () {
              if (!_emailTouched) setState(() => _emailTouched = true);
            },
            validator: (value) {
              final v = value?.trim() ?? '';
              if (v.isEmpty || !_emailRegex.hasMatch(v)) {
                return t.signupEnterValidEmail;
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          _buildAuthTextField(
            controller: _passCtrl,
            hint: t.password,
            prefixIcon: Icons.lock_outline,
            isPassword: true,
            obscured: _obscurePassword,
            onToggleObscure: () => setState(() => _obscurePassword = !_obscurePassword),
            touched: _passTouched,
            onBlur: () {
              if (!_passTouched) setState(() => _passTouched = true);
              if (_confirmTouched) setState(() {});
            },
            validator: (value) => _validatePassword(value, t),
          ),
          const SizedBox(height: 14),
          _buildAuthTextField(
            controller: _confirmCtrl,
            hint: t.confirmPassword,
            prefixIcon: Icons.lock_outline,
            isPassword: true,
            obscured: _obscureConfirm,
            onToggleObscure: () => setState(() => _obscureConfirm = !_obscureConfirm),
            touched: _confirmTouched,
            onBlur: () {
              if (!_confirmTouched) setState(() => _confirmTouched = true);
            },
            validator: (value) {
              if (value == null || value.isEmpty) return t.signupEnterPassword;
              if (value != _passCtrl.text) return t.passwordsDontMatch;
              return null;
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.isDark ? const Color(0xFF3D1F1F) : const Color(0xFFFFEEEE),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            ),
          ],
          const SizedBox(height: 20),
          PrimaryActionButton(
            label: context.t.signUp,
            onPressed: _loading ? null : _submit,
            loading: _loading,
            size: PrimaryActionSize.large,
            fullWidth: true,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: Divider(color: context.borderColor)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  context.t.loginOr,
                  style: TextStyle(fontSize: 12, color: context.textMuted),
                ),
              ),
              Expanded(child: Divider(color: context.borderColor)),
            ],
          ),
          const SizedBox(height: 14),
          _buildSocialButton(
            label: _googleLoading ? context.t.loginSigningIn : context.t.continueWithGoogle,
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
            const SizedBox(height: 10),
            _buildSocialButton(
              label: _appleLoading ? context.t.loginSigningIn : context.t.continueWithApple,
              icon: _appleLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.apple, size: 24, color: context.textPrimary),
              onTap: _appleLoading ? () {} : _signInWithApple,
            ),
          ],
          const SizedBox(height: 20),
          Divider(color: context.borderColor),
          const SizedBox(height: 16),
          // Prominent "Already have an account? Log In"
          Center(
            child: SizedBox(
              height: 44,
              child: OutlinedButton(
                onPressed: () => context.go('/login'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFCE5DE5),
                  side: const BorderSide(color: Color(0xFFCE5DE5), width: 1.2),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  context.t.signIn,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopUnderCard(BuildContext context) {
    return Center(
      child: Text.rich(
        TextSpan(
          text: '${context.t.alreadyHaveAccount} ',
          style: TextStyle(fontSize: 13, color: context.textMuted),
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: GestureDetector(
                onTap: () => context.go('/login'),
                child: Text(
                  context.t.signIn,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFCE5DE5),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Mobile single-column layout
  Widget _buildMobileLayout(BuildContext context) {
    final hPad = context.scaleW(16, 24);
    final vPad = context.scaleW(20, 32);
    final logoSize = context.scaleW(72, 84);
    final t = context.t;

    return Center(
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
                  t.signUp,
                  style: TextStyle(
                    fontSize: context.scaleW(20, 24),
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  t.signupSubtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: context.textMuted,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 30),
                _buildAuthTextField(
                  controller: _emailCtrl,
                  hint: t.email,
                  prefixIcon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  touched: _emailTouched,
                  onBlur: () {
                    if (!_emailTouched) setState(() => _emailTouched = true);
                  },
                  validator: (value) {
                    final v = value?.trim() ?? '';
                    if (v.isEmpty || !_emailRegex.hasMatch(v)) {
                      return t.signupEnterValidEmail;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                _buildAuthTextField(
                  controller: _passCtrl,
                  hint: t.password,
                  prefixIcon: Icons.lock_outline,
                  isPassword: true,
                  obscured: _obscurePassword,
                  onToggleObscure: () => setState(() => _obscurePassword = !_obscurePassword),
                  touched: _passTouched,
                  onBlur: () {
                    if (!_passTouched) setState(() => _passTouched = true);
                    if (_confirmTouched) setState(() {});
                  },
                  validator: (value) => _validatePassword(value, t),
                ),
                const SizedBox(height: 14),
                _buildAuthTextField(
                  controller: _confirmCtrl,
                  hint: t.confirmPassword,
                  prefixIcon: Icons.lock_outline,
                  isPassword: true,
                  obscured: _obscureConfirm,
                  onToggleObscure: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  touched: _confirmTouched,
                  onBlur: () {
                    if (!_confirmTouched) setState(() => _confirmTouched = true);
                  },
                  validator: (value) {
                    if (value == null || value.isEmpty) return t.signupEnterPassword;
                    if (value != _passCtrl.text) return t.passwordsDontMatch;
                    return null;
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.isDark ? const Color(0xFF3D1F1F) : const Color(0xFFFFEEEE),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                PrimaryActionButton(
                  label: context.t.signUp,
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
                        style: TextStyle(fontSize: 13, color: context.textMuted),
                      ),
                    ),
                    Expanded(child: Divider(color: context.borderColor)),
                  ],
                ),
                const SizedBox(height: 16),
                _buildSocialButton(
                  label: _googleLoading ? context.t.loginSigningIn : context.t.continueWithGoogle,
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
                    label: _appleLoading ? context.t.loginSigningIn : context.t.continueWithApple,
                    icon: _appleLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(Icons.apple, size: 24, color: context.textPrimary),
                    onTap: _appleLoading ? () {} : _signInWithApple,
                  ),
                ],
                SizedBox(height: context.scaleW(20, 30)),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      context.t.alreadyHaveAccount,
                      style: TextStyle(fontSize: 13, color: context.textMuted),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => context.go('/login'),
                      child: Text(
                        context.t.signIn,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFFCE5DE5),
                          fontWeight: FontWeight.w600,
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
    );
  }

  Widget _buildAuthTextField({
    required TextEditingController controller,
    required String hint,
    required IconData prefixIcon,
    required String? Function(String?) validator,
    TextInputType? keyboardType,
    bool isPassword = false,
    bool touched = false,
    VoidCallback? onBlur,
    bool? obscured,
    VoidCallback? onToggleObscure,
  }) {
    final isObscured = isPassword ? (obscured ?? true) : false;
    return Focus(
      onFocusChange: (hasFocus) {
        if (!hasFocus) onBlur?.call();
      },
      canRequestFocus: false,
      child: FormField<String>(
        initialValue: controller.text,
        validator: validator,
        autovalidateMode:
            touched ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
        builder: (field) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppGlassCard(
              radius: 16,
              borderAlpha: field.hasError ? 0.7 : null,
              child: TextField(
                controller: controller,
                keyboardType: keyboardType,
                obscureText: isObscured,
                onChanged: field.didChange,
                autofillHints: isPassword
                    ? const [AutofillHints.newPassword]
                    : keyboardType == TextInputType.emailAddress
                        ? const [AutofillHints.email]
                        : null,
                style: TextStyle(fontSize: 14, color: context.textPrimary),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: TextStyle(fontSize: 14, color: context.textMuted),
                  prefixIcon: Icon(prefixIcon, size: 20, color: context.textMuted),
                  suffixIcon: isPassword
                      ? IconButton(
                          icon: Icon(
                            isObscured
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 20,
                            color: context.textMuted,
                          ),
                          onPressed: onToggleObscure,
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
            if (field.hasError && field.errorText != null) _authFieldError(field.errorText!),
          ],
        ),
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
