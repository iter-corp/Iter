import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../providers/auth_providers.dart';
import '../../../theme/app_theme.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
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
      await ref.read(authServiceProvider).signUp(
            email: _emailCtrl.text,
            password: _passCtrl.text,
          );
      if (!mounted) return;
      context.push('/otp?email=${Uri.encodeComponent(_emailCtrl.text.trim())}');
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? 'Signup failed');
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
                  'Sign Up',
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
                  hint: 'Username',
                  prefixIcon: Icons.person_2_outlined,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter a username'
                      : null,
                ),
                const SizedBox(height: 14),
                _buildTextField(
                  controller: _emailCtrl,
                  hint: 'Email',
                  prefixIcon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) => value == null || !value.contains('@')
                      ? 'Enter a valid email'
                      : null,
                ),
                const SizedBox(height: 14),
                _buildTextField(
                  controller: _passCtrl,
                  hint: 'Password',
                  prefixIcon: Icons.lock_outline,
                  isPassword: true,
                  validator: (value) => value == null || value.length < 6
                      ? 'Min 6 characters'
                      : null,
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
                            'Sign Up',
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
                  label: 'Sign In with Google',
                  icon: _buildSocialBadge('G', const Color(0xFF4285F4)),
                  onTap: () {},
                ),
                const SizedBox(height: 12),
                _buildSocialButton(
                  label: 'Sign In with Facebook',
                  icon: _buildSocialBadge('f', const Color(0xFF1877F2)),
                  onTap: () {},
                ),
                const SizedBox(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Already have an account? ',
                      style: TextStyle(fontSize: 13, color: context.textMuted),
                    ),
                    GestureDetector(
                      onTap: () => context.go('/login'),
                      child: const Text(
                        'Sign In',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFFCE5DE5),
                          fontWeight: FontWeight.w600,
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
    TextInputType? keyboardType,
    bool isPassword = false,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
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
