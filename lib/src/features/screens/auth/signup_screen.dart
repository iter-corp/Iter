import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_strings.dart';
import '../../../providers/auth_providers.dart';
import '../../../services/auth_service.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/responsive.dart';
import '../../widgets/app_page_background.dart';
import '../../widgets/primary_action_button.dart';

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
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _error;

  // Per-field "touched" flags — a field becomes touched the first time it
  // loses focus or the user submits the form. Validation errors only render
  // once a field is touched, so users don't see red text while they're still
  // typing their first attempt.
  bool _emailTouched = false;
  bool _passTouched = false;
  bool _confirmTouched = false;

  // RFC-5322-lite email check: local@domain.tld with at least one dot in
  // the domain part. Catches the common "text@" / "text@x" mistakes that a
  // bare `contains('@')` would miss without going so strict that valid
  // addresses fail.
  static final _emailRegex = RegExp(
    r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$',
  );

  /// Password rule: at least 8 characters, with both a letter and a digit.
  /// Stronger than Firebase's default 6-char floor — keeps validation in sync
  /// with what we tell the user via the helper text below the field.
  String? _validatePassword(String? value, AppStrings t) {
    final v = value ?? '';
    if (v.isEmpty) return t.signupEnterPassword;
    if (v.length < 8) return t.signupPasswordMinLength;
    final hasLetter = v.contains(RegExp(r'[A-Za-z]'));
    final hasDigit = v.contains(RegExp(r'\d'));
    if (!hasLetter || !hasDigit) return t.signupPasswordLetterNumber;
    return null;
  }

  String _friendlyError(FirebaseAuthException e,
      {String fallback = 'Signup failed'}) {
    switch (e.code) {
      case 'invalid-email':
        return 'That email address looks invalid.';
      case 'email-already-in-use':
        return 'An account with this email already exists.';
      case 'weak-password':
        return 'Password is too weak. Use at least 8 characters.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      default:
        return fallback;
    }
  }

  @override
  void initState() {
    super.initState();
    // Rebuild as the user edits the password so the red "min 8 chars" pill
    // appears / disappears live once the field has been touched. Without
    // this listener the helper would only re-evaluate on blur.
    _passCtrl.addListener(_onPassChanged);
  }

  void _onPassChanged() {
    if (_passTouched && mounted) setState(() {});
  }

  @override
  void dispose() {
    _passCtrl.removeListener(_onPassChanged);
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // On submit, treat every field as touched so any errors render even
    // for fields the user never focused (e.g. tapping Sign Up with empty
    // form). Validation then runs through the normal autovalidateMode path.
    setState(() {
      _emailTouched = true;
      _passTouched = true;
      _confirmTouched = true;
    });
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ref.read(authServiceProvider).signUp(
            email: _emailCtrl.text,
            password: _passCtrl.text,
          );
      if (!mounted) return;
      final emailParam = Uri.encodeComponent(_emailCtrl.text.trim());
      final sendErr = result?.emailSendError;
      final errParam =
          sendErr == null ? '' : '&sendError=${Uri.encodeComponent(sendErr)}';
      context.go('/otp?email=$emailParam$errParam');
    } on AccountDeletedException catch (e) {
      setState(() => _error = e.toString());
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
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
          .signInWithGoogle(intent: GoogleAuthIntent.signup);
    } on GoogleAuthFlowException catch (e) {
      setState(() => _error = e.toString());
    } on AccountDeletedException catch (e) {
      setState(() => _error = e.toString());
    } on FirebaseAuthException catch (e) {
      setState(
          () => _error = _friendlyError(e, fallback: 'Google sign-in failed.'));
    } catch (e) {
      setState(() => _error = 'Google sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hPad = context.scaleW(16, 24);
    final vPad = context.scaleW(20, 32);
    final logoSize = context.scaleW(72, 84);
    final t = context.t;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppPageBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
            child: Form(
              key: _formKey,
              // No form-level autovalidate: each field opts in via its own
              // `touched` flag so errors only appear after the user leaves the
              // field (or taps Sign Up), not while they're still typing.
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
                    onToggleObscure: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    touched: _passTouched,
                    onBlur: () {
                      if (!_passTouched) setState(() => _passTouched = true);
                      // Surface a mismatch error on the confirm field as soon
                      // as the user finishes typing the password — otherwise
                      // they'd need to re-focus the confirm field to see it.
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
                    onToggleObscure: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                    touched: _confirmTouched,
                    onBlur: () {
                      if (!_confirmTouched) {
                        setState(() => _confirmTouched = true);
                      }
                    },
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return t.signupEnterPassword;
                      }
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
                        color: context.isDark
                            ? const Color(0xFF3D1F1F)
                            : const Color(0xFFFFEEEE),
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
                  SizedBox(height: context.scaleW(20, 30)),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        context.t.alreadyHaveAccount,
                        style:
                            TextStyle(fontSize: 13, color: context.textMuted),
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
        autovalidateMode: touched
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
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
                  prefixIcon:
                      Icon(prefixIcon, size: 20, color: context.textMuted),
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
            if (field.hasError) _authFieldError(field.errorText!),
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

  // ignore: unused_element
  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData prefixIcon,
    required String? Function(String?) validator,
    TextInputType? keyboardType,
    bool isPassword = false,
    String? helperText,
    // `touched` flips to true after the field's first blur (or after a
    // submit attempt). While false the field never shows validation errors;
    // once true we autovalidate so corrections update live as the user fixes
    // the input. `onBlur` is invoked the first time focus is lost so the
    // parent can flip its `touched` flag.
    bool touched = false,
    VoidCallback? onBlur,
    // Password fields each own their own obscure state — pass the current
    // value via `obscured` and a toggle via `onToggleObscure` so the eye
    // icon flips just this field. For non-password fields these are ignored.
    bool? obscured,
    VoidCallback? onToggleObscure,
  }) {
    final isObscured = isPassword ? (obscured ?? true) : false;
    return Focus(
      onFocusChange: (hasFocus) {
        if (!hasFocus) onBlur?.call();
      },
      // `canRequestFocus: false` keeps this wrapper from stealing focus from
      // the inner TextFormField — we only want it for the blur callback.
      canRequestFocus: false,
      child: AppGlassCard(
        radius: 16,
        child: TextFormField(
          controller: controller,
          validator: validator,
          autovalidateMode: touched
              ? AutovalidateMode.onUserInteraction
              : AutovalidateMode.disabled,
          keyboardType: keyboardType,
          obscureText: isObscured,
          // Autofill hints help password managers offer to generate / save a
          // strong password on the signup flow.
          autofillHints: isPassword
              ? const [AutofillHints.newPassword]
              : keyboardType == TextInputType.emailAddress
                  ? const [AutofillHints.email]
                  : null,
          style: TextStyle(fontSize: 14, color: context.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(fontSize: 14, color: context.textMuted),
            // Render the helper as a custom widget so we can give it a red
            // pill background with white text — calls out the password rule
            // more clearly than the default muted-text helper.
            helper: helperText == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE53935),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          helperText,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
            helperMaxLines: 2,
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
