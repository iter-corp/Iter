import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_strings.dart';
import '../../../providers/auth_providers.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/primary_action_button.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).resetPassword(_emailCtrl.text);
      if (mounted) setState(() => _sent = true);
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _friendlyError(e));
    } catch (_) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendlyError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'That email address looks invalid.';
      case 'user-not-found':
        return 'No account found with this email.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Check your connection.';
      default:
        return e.message ?? 'Something went wrong.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 12),
                // Back button
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: context.inputFill,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.arrow_back,
                          size: 20, color: context.textPrimary),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                // Lock icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: context.purpleSoft,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock_reset_rounded,
                    size: 40,
                    color: Color(0xFFCE5DE5),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  context.t.forgotPassword,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  context.t.forgotPasswordSubtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: context.textMuted,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),

                if (_sent) ...[
                  // Success state
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: context.isDark
                          ? const Color(0xFF1A2E1A)
                          : const Color(0xFFEEFAEE),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.check_circle_rounded,
                            color: Color(0xFF3BD671), size: 48),
                        const SizedBox(height: 12),
                        Text(
                          context.t.forgotPasswordEmailSent,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: context.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          context.t.forgotPasswordCheckInbox,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: context.textSecondary,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: context.borderColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: Text(
                        context.t.forgotPasswordBackToLogin,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: context.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  // Email input
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return context.t.forgotPasswordEnterEmail;
                      }
                      if (!v.contains('@')) {
                        return context.t.forgotPasswordEnterValidEmail;
                      }
                      return null;
                    },
                    style: TextStyle(fontSize: 14, color: context.textPrimary),
                    decoration: InputDecoration(
                      hintText: context.t.forgotPasswordEmailAddress,
                      hintStyle:
                          TextStyle(fontSize: 14, color: context.textMuted),
                      prefixIcon: Icon(Icons.email_outlined,
                          size: 20, color: context.textMuted),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: context.cardBg,
                      contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    ),
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
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              color: Colors.red, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                  color: Colors.red, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),
                  PrimaryActionButton(
                    label: context.t.forgotPasswordSendResetLink,
                    onPressed: _loading ? null : _submit,
                    loading: _loading,
                    size: PrimaryActionSize.large,
                    fullWidth: true,
                  ),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.arrow_back,
                            size: 16, color: context.textMuted),
                        const SizedBox(width: 4),
                        Text(
                          context.t.forgotPasswordBackToLogin,
                          style: TextStyle(
                            fontSize: 13,
                            color: context.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
