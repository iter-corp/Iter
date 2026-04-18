import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../providers/auth_providers.dart';
import '../../../theme/app_theme.dart';

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

  final bool _isIOS = Platform.isIOS;

  Future<void> _signInWithApple() async {
    setState(() {
      _appleLoading = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).signInWithApple();
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? 'Apple sign-in failed');
    } catch (e) {
      setState(() => _error = 'Apple sign-in failed: $e');
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
      await ref.read(authServiceProvider).signInWithGoogle();
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? 'Google sign-in failed');
    } catch (e) {
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
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? 'Login failed');
    } finally {
      if (mounted) setState(() => _loading = false);
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
                const SizedBox(height: 30),
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: context.purpleSoft,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.send_rounded,
                    color: Color(0xFFCE5DE5),
                    size: 30,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Sign In',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Please enter the code we just sent\nto email',
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
                  hint: 'Username or email',
                  prefixIcon: Icons.person_2_outlined,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Enter your username or email'
                      : null,
                ),
                const SizedBox(height: 14),
                _buildTextField(
                  controller: _passCtrl,
                  hint: 'Password',
                  prefixIcon: Icons.lock_outline,
                  isPassword: true,
                  validator: (v) =>
                      (v == null || v.length < 6) ? 'Min 6 characters' : null,
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: () => context.push('/forgot-password'),
                    child: const Text(
                      'Forget Password?',
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFFCE5DE5),
                      ),
                    ),
                  ),
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
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFCE5DE5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 0,
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            'Sign In',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(child: Divider(color: context.borderColor)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'Or',
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
                      ? 'Signing in...'
                      : 'Sign In with Google',
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
                        ? 'Signing in...'
                        : 'Sign In with Apple',
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
                const SizedBox(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Don't have account? ",
                      style: TextStyle(fontSize: 13, color: context.textMuted),
                    ),
                    GestureDetector(
                      onTap: () => context.push('/signup'),
                      child: const Text(
                        'Sign Up',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFCE5DE5),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
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
    return TextFormField(
      controller: controller,
      validator: validator,
      obscureText: isPassword ? _obscurePassword : false,
      style: TextStyle(fontSize: 14, color: context.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: 14, color: context.textMuted),
        prefixIcon: Icon(prefixIcon, size: 20, color: context.textMuted),
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
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        filled: true,
        fillColor: context.cardBg,
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
      ),
    );
  }

  Widget _buildSocialButton({
    required String label,
    required Widget icon,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
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
          backgroundColor: context.cardBg,
          side: BorderSide(color: context.borderColor),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
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
