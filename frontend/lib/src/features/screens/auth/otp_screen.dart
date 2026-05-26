import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_strings.dart';
import '../../../providers/auth_providers.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/primary_action_button.dart';

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key, this.email});

  final String? email;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  bool _verifying = false;
  bool _resending = false;
  bool _canceling = false;
  String? _error;

  Future<void> _verify() async {
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      final verified =
          await ref.read(authServiceProvider).reloadAndCheckEmailVerified();
      if (!mounted) return;
      if (verified) {
        context.go('/onboarding');
      } else {
        setState(() {
          _error =
              'Please open the verification link in your email, then tap Verify.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).sendEmailVerification();
      if (mounted) {
        setState(() {
          _error = 'Verification email sent. Check your inbox.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  Future<void> _cancelSignup() async {
    setState(() {
      _canceling = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).discardPendingSignup();
      if (mounted) {
        setState(() => _canceling = false);
        context.go('/signup');
      }
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _error = 'Cancel took too long. Check your connection and try again.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _canceling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final destination = widget.email?.trim().isNotEmpty == true
        ? widget.email!.trim()
        : '(400)650-1111';

    return Scaffold(
      backgroundColor: context.surfaceSoft,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                onPressed: _canceling ? null : _cancelSignup,
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                style: IconButton.styleFrom(
                  backgroundColor: context.cardBg,
                  foregroundColor: context.textPrimary,
                  disabledForegroundColor:
                      context.textMuted.withValues(alpha: 0.55),
                ),
                icon: _canceling
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: context.textMuted,
                        ),
                      )
                    : const Icon(Icons.chevron_left_rounded),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (index) {
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 28,
                    height: 4,
                    decoration: BoxDecoration(
                      color: index == 1
                          ? const Color(0xFFCE5DE5)
                          : context.borderColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 40),
              Center(
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: const BoxDecoration(
                    color: Color.fromARGB(255, 244, 198, 255),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.mark_email_read_rounded,
                    color: Color(0xFFCE5DE5),
                    size: 40,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Center(
                child: Text(
                  context.t.otpEnterCode,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: context.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: Text(
                  context.t.otpCodeSentTo(destination),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: context.textMuted,
                    height: 1.6,
                  ),
                ),
              ),
              const SizedBox(height: 36),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.borderColor),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.mail_outline_rounded,
                      color: Color(0xFFCE5DE5),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        context.t.otpOpenEmailInstruction,
                        style: TextStyle(
                          fontSize: 13,
                          color: context.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 36),
              if (_error != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.cardBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.borderColor),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(fontSize: 13, color: context.textPrimary),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              PrimaryActionButton(
                label: context.t.verify,
                onPressed: _verifying ? null : _verify,
                loading: _verifying,
                size: PrimaryActionSize.large,
                fullWidth: true,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Text(
                    context.t.otpDidntGet,
                    style: TextStyle(fontSize: 13, color: context.textMuted),
                  ),
                  GestureDetector(
                    onTap: _resending ? null : _resend,
                    child: Text(
                      _resending ? context.t.loading : context.t.otpResend,
                      style: TextStyle(
                        fontSize: 13,
                        color: context.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
