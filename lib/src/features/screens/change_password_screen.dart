import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_strings.dart';
import '../../theme/app_theme.dart';
import '../widgets/app_page_background.dart';

/// Full-page change-password screen. Replaces the old `AlertDialog`
/// version so the keyboard has room to open without overflowing, and so
/// the user gets standard back-button + Save action affordances instead
/// of dialog-style "Cancel / Save" footer buttons.
///
/// Pushed from the settings screen for email/password users; social
/// users (Google / Apple) without a linked password still see the
/// "set password" dialog because the flow is meaningfully different
/// (link new credential rather than re-auth + update).
///
/// Pops with `true` on a successful update so the caller can show a
/// success snackbar; pops with `false` (or null on back-button) when
/// cancelled.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _FieldError extends StatelessWidget {
  final String text;
  const _FieldError(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 14, top: 6),
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
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _currentPassCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  String? _error;
  // Whether the user has interacted with the confirm field at least once.
  // We delay the "don't match" error until then so the field doesn't show
  // red the moment focus moves into it — only after they've typed.
  bool _confirmTouched = false;

  @override
  void initState() {
    super.initState();
    // Live mismatch check: trigger a rebuild whenever either field
    // changes so the confirm field's errorText updates as the user types.
    // Without this, the error only appeared after tapping Save.
    _newPassCtrl.addListener(_rebuild);
    _confirmPassCtrl.addListener(_onConfirmChanged);
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _onConfirmChanged() {
    if (!mounted) return;
    setState(() {
      // The first keystroke in the confirm field flips it from "untouched"
      // to "touched" so the mismatch error becomes visible from then on.
      if (!_confirmTouched && _confirmPassCtrl.text.isNotEmpty) {
        _confirmTouched = true;
      }
    });
  }

  /// Returns the localized mismatch message when the confirm field has
  /// been touched and disagrees with the new-password field. Returns null
  /// in every other case (untouched / matches / confirm empty) so the
  /// field renders without a red error label.
  String? get _confirmError {
    if (!_confirmTouched) return null;
    if (_confirmPassCtrl.text.isEmpty) return null;
    if (_confirmPassCtrl.text == _newPassCtrl.text) return null;
    return context.t.settingsPasswordsDoNotMatch;
  }

  @override
  void dispose() {
    _newPassCtrl.removeListener(_rebuild);
    _confirmPassCtrl.removeListener(_onConfirmChanged);
    _currentPassCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  /// Password rule shared with signup and the "set password" dialog:
  /// at least 8 characters, with both a letter and a digit. Returns
  /// the localized error message, or null when valid.
  String? _validatePassword(String value) {
    final t = context.t;
    if (value.length < 8) return t.signupPasswordMinLength;
    final hasLetter = value.contains(RegExp(r'[A-Za-z]'));
    final hasDigit = value.contains(RegExp(r'\d'));
    if (!hasLetter || !hasDigit) return t.signupPasswordLetterNumber;
    return null;
  }

  Future<void> _save() async {
    final current = _currentPassCtrl.text;
    final newPass = _newPassCtrl.text;
    final confirm = _confirmPassCtrl.text;
    // Required-field check. Current password is intentionally first and
    // mandatory — the Firebase re-auth call below would fail anyway, but
    // surfacing the requirement up-front is clearer for the user.
    if (current.isEmpty || newPass.isEmpty || confirm.isEmpty) {
      setState(() => _error = context.t.settingsAllFieldsRequired);
      return;
    }
    final passError = _validatePassword(newPass);
    if (passError != null) {
      setState(() => _error = passError);
      return;
    }
    if (newPass != confirm) {
      // The confirm field already shows a live errorText so this is just a
      // belt-and-suspenders block before we hit Firebase.
      setState(() {
        _confirmTouched = true;
        _error = context.t.settingsPasswordsDoNotMatch;
      });
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) {
      setState(() => _error = context.t.settingsNoEmailAccount);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final cred = EmailAuthProvider.credential(
        email: user.email!,
        password: current,
      );
      await user.reauthenticateWithCredential(cred);
      await user.updatePassword(newPass);

      if (mounted) Navigator.of(context).pop(true);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = switch (e.code) {
          'wrong-password' ||
          'invalid-credential' =>
            context.t.settingsIncorrectCurrentPassword,
          'requires-recent-login' => context.t.settingsSecurityReloginShort,
          'weak-password' => context.t.settingsNewPasswordTooWeak,
          'too-many-requests' => context.t.settingsTooManyRequests,
          'network-request-failed' => context.t.settingsNetworkError,
          _ => e.message ?? context.t.settingsSomethingWentWrong,
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.t.settingsSomethingWentWrongRetry;
      });
    }
  }

  /// Same look as the old `_settingsInputDecoration` helper in
  /// profile_settings_screen.dart. Inlined here so this file stays
  /// self-contained instead of reaching into another file's privates.
  InputDecoration _fieldDecoration({
    required String label,
    required Widget suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: context.textSecondary),
      filled: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: InputBorder.none,
      border: InputBorder.none,
      focusedBorder: InputBorder.none,
      suffixIcon: suffixIcon,
      suffixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Only the Save action drives the busy state now that the inline
    // reset-email flow is gone (the forgot-password link just pushes a
    // route; it can't block this screen).
    final busy = _loading;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(context.t.changePassword),
        backgroundColor: Colors.transparent,
        foregroundColor: context.textPrimary,
        elevation: 0,
        flexibleSpace: const AppPageBackground(child: SizedBox.expand()),
        actions: [
          TextButton(
            onPressed: busy ? null : _save,
            child: _loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    context.t.save,
                    style: const TextStyle(color: AppColors.purple),
                  ),
          ),
        ],
      ),
      body: AppPageBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              24 + MediaQuery.of(context).padding.bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppGlassCard(
                  radius: 16,
                  padding: EdgeInsets.zero,
                  child: TextField(
                    controller: _currentPassCtrl,
                    obscureText: _obscureCurrent,
                    autofillHints: const [AutofillHints.password],
                    decoration: _fieldDecoration(
                      label: context.t.settingsCurrentPassword,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureCurrent
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () =>
                            setState(() => _obscureCurrent = !_obscureCurrent),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                AppGlassCard(
                  radius: 16,
                  padding: EdgeInsets.zero,
                  child: TextField(
                    controller: _newPassCtrl,
                    obscureText: _obscureNew,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: _fieldDecoration(
                      label: context.t.settingsNewPassword,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureNew ? Icons.visibility_off : Icons.visibility,
                        ),
                        onPressed: () =>
                            setState(() => _obscureNew = !_obscureNew),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                AppGlassCard(
                  radius: 16,
                  padding: EdgeInsets.zero,
                  child: TextField(
                    controller: _confirmPassCtrl,
                    obscureText: _obscureConfirm,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: _fieldDecoration(
                      label: context.t.settingsConfirmNewPassword,
                      // Live mismatch error — `_confirmError` is null until the
                      // user has typed something AND the value differs from the
                      // new-password field, so it doesn't yell at them while
                      // they're still in the middle of typing the same value.
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirm
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () =>
                            setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                    ),
                  ),
                ),
                if (_confirmError != null) _FieldError(_confirmError!),
                const SizedBox(height: 8),
                // "Forgot current password?" — navigates to the same
                // forgot-password screen used from the login page rather
                // than firing a reset email inline. Keeping it as a single
                // flow means the user gets the full email-entry +
                // confirmation UX they're already familiar with.
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    onPressed: _loading
                        ? null
                        : () => context.push('/forgot-password'),
                    child: Text(context.t.forgotPassword),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.purple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: busy ? null : _save,
                    child: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            context.t.save,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
