import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../theme/app_theme.dart';
import '../widgets/app_page_background.dart';
import '../widgets/primary_action_button.dart';

/// Full-page "Change email" flow (previously a popup dialog).
///
/// Re-authenticates the user with their current password, then sends a
/// verification link to the new address via [User.verifyBeforeUpdateEmail].
/// The email only actually changes after the user clicks that link, so we pop
/// with `true` to let the caller show a "verification sent" message.
///
/// Only email/password accounts can change their email here; Google/Apple
/// accounts manage their email with the identity provider.
class ChangeEmailScreen extends StatefulWidget {
  const ChangeEmailScreen({super.key});

  @override
  State<ChangeEmailScreen> createState() => _ChangeEmailScreenState();
}

class _ChangeEmailScreenState extends State<ChangeEmailScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final newEmail = _emailCtrl.text.trim();
    final password = _passCtrl.text;
    if (newEmail.isEmpty || password.isEmpty) {
      setState(() => _error = context.t.settingsAllFieldsRequired);
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) {
      setState(() => _error = context.t.settingsNoEmailAccount);
      return;
    }
    if (newEmail.toLowerCase() == user.email!.toLowerCase()) {
      setState(() => _error = context.t.settingsEmailMustDiffer);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cred = EmailAuthProvider.credential(
          email: user.email!, password: password);
      await user.reauthenticateWithCredential(cred);
      try {
        await user.verifyBeforeUpdateEmail(newEmail);
      } on FirebaseAuthException catch (e) {
        // Fallback for projects where verify-before-update isn't enabled.
        if (e.code == 'operation-not-allowed' || e.code == 'internal-error') {
          // ignore: deprecated_member_use
          await user.updateEmail(newEmail);
          await user.sendEmailVerification();
        } else {
          rethrow;
        }
      }
      if (mounted) Navigator.of(context).pop(true);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = switch (e.code) {
          'wrong-password' ||
          'invalid-credential' =>
            context.t.settingsIncorrectPassword,
          'requires-recent-login' => context.t.settingsSecurityReloginShort,
          'email-already-in-use' => context.t.settingsEmailAlreadyInUse,
          'invalid-email' => context.t.settingsEmailInvalid,
          'too-many-requests' => context.t.settingsTooManyRequests,
          'network-request-failed' => context.t.settingsNetworkError,
          'operation-not-allowed' => context.t.settingsEmailChangeNotEnabled,
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

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(context.t.changeEmail),
        backgroundColor: Colors.transparent,
        foregroundColor: context.textPrimary,
        elevation: 0,
        flexibleSpace: const AppPageBackground(child: SizedBox.expand()),
      ),
      body: AppPageBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEEEE),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: context.t.settingsNewEmail,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _passCtrl,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: context.t.settingsCurrentPassword,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                PrimaryActionButton(
                  label: context.t.save,
                  onPressed: _loading ? null : _save,
                  loading: _loading,
                  size: PrimaryActionSize.large,
                  fullWidth: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
