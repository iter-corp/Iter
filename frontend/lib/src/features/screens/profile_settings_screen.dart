import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/admin_providers.dart';
import '../../providers/auth_providers.dart';
import '../../providers/preferred_language_provider.dart';
import '../../providers/profile_visitor_providers.dart';
import '../../providers/theme_provider.dart';
import '../../services/translate_service.dart';
import '../../theme/app_theme.dart';
import 'profile_visitors_screen.dart';

/// Full-screen profile settings page. Replaces the older bottom-sheet
/// settings menu with a dedicated route so we can group preferences
/// (account / appearance / language / safety / danger zone) and add
/// new settings (e.g. preferred translation language) without making
/// the sheet unwieldy.
class ProfileSettingsScreen extends ConsumerWidget {
  const ProfileSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider);
    final userDoc = ref.watch(currentUserDocProvider).valueOrNull;
    final isPrivate = (userDoc?['isPrivate'] as bool?) ?? false;
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final preferredLang = ref.watch(preferredLanguageProvider);
    final visitorCount =
        ref.watch(myProfileVisitorCountProvider).valueOrNull ?? 0;

    return Scaffold(
      backgroundColor: context.cardBg,
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const _SectionHeader(title: 'Account'),
          ListTile(
            leading: const Icon(Icons.email_outlined, color: AppColors.purple),
            title: const Text('Change email'),
            trailing: Icon(Icons.chevron_right, color: context.textSecondary),
            onTap: () => _changeEmail(context),
          ),
          ListTile(
            leading: const Icon(Icons.lock_reset, color: AppColors.purple),
            title: Text(
                _isEmailPasswordUser() ? 'Change password' : 'Set a password'),
            subtitle: _isEmailPasswordUser()
                ? null
                : Text('Add a password so you can also sign in with email',
                    style:
                        TextStyle(fontSize: 12, color: context.textSecondary)),
            trailing: Icon(Icons.chevron_right, color: context.textSecondary),
            onTap: () => _changePassword(context),
          ),
          ListTile(
            leading: Icon(
              isPrivate ? Icons.lock_outline : Icons.lock_open,
              color: AppColors.purple,
            ),
            title: const Text('Private account'),
            subtitle: Text(
              isPrivate
                  ? 'Only followers can see your posts'
                  : 'Anyone can see your posts',
              style: TextStyle(fontSize: 12, color: context.textSecondary),
            ),
            trailing: Switch.adaptive(
              value: isPrivate,
              activeTrackColor: AppColors.purple,
              onChanged: (val) async {
                final uid = ref.read(authServiceProvider).currentUser?.uid;
                if (uid == null) return;
                await ref
                    .read(userServiceProvider)
                    .updateUser(uid, {'isPrivate': val});
              },
            ),
          ),
          ListTile(
            leading:
                const Icon(Icons.visibility_outlined, color: AppColors.purple),
            title: const Text('Profile visitors'),
            subtitle: Text(
              visitorCount == 0
                  ? 'See who has opened your profile'
                  : '$visitorCount ${visitorCount == 1 ? 'person has' : 'people have'} viewed your profile',
              style: TextStyle(fontSize: 12, color: context.textSecondary),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (visitorCount > 0)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: context.purpleSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$visitorCount',
                      style: const TextStyle(
                        color: Color(0xFFB05ECC),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                Icon(Icons.chevron_right, color: context.textSecondary),
              ],
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ProfileVisitorsScreen(),
              ),
            ),
          ),
          const _SectionHeader(title: 'Language'),
          ListTile(
            leading: const Icon(Icons.translate, color: AppColors.purple),
            title: const Text('Preferred language'),
            subtitle: Text(
              'Used when translating posts, messages, and voice notes',
              style: TextStyle(fontSize: 12, color: context.textSecondary),
            ),
            trailing: Text(
              _languageLabel(preferredLang),
              style: TextStyle(
                color: context.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            onTap: () => _pickLanguage(context, ref, current: preferredLang),
          ),
          const _SectionHeader(title: 'Appearance'),
          ListTile(
            leading: Icon(
              isDark ? Icons.dark_mode : Icons.light_mode,
              color: isDark ? Colors.amber : Colors.grey,
            ),
            title: const Text('Dark mode'),
            trailing: Switch.adaptive(
              value: isDark,
              activeTrackColor: AppColors.purple,
              onChanged: (_) => ref.read(themeModeProvider.notifier).toggle(),
            ),
            onTap: () => ref.read(themeModeProvider.notifier).toggle(),
          ),
          const _SectionHeader(title: 'Safety'),
          ListTile(
            leading: const Icon(Icons.block, color: Color(0xFFD27B2B)),
            title: const Text('Blocked users'),
            trailing: Icon(Icons.chevron_right, color: context.textSecondary),
            onTap: () => _showBlockedUsers(context),
          ),
          if (isAdmin) ...[
            const _SectionHeader(title: 'Admin'),
            ListTile(
              leading:
                  const Icon(Icons.shield_outlined, color: Color(0xFF7E3BE8)),
              title: const Text(
                'Admin panel',
                style: TextStyle(
                  color: Color(0xFF7E3BE8),
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () => context.push('/admin'),
            ),
          ],
          const _SectionHeader(title: 'Danger zone'),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Log out', style: TextStyle(color: Colors.red)),
            onTap: () async {
              await ref.read(authServiceProvider).signOut();
              ref.invalidate(adminConfigProvider);
              ref.invalidate(adminPostsProvider);
              ref.invalidate(adminEventsProvider);
              ref.invalidate(blacklistProvider);
              if (context.mounted) {
                context.go('/login');
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
            title: const Text(
              'Delete account',
              style: TextStyle(color: Colors.redAccent),
            ),
            subtitle: const Text(
              'Permanently remove your account and all your data.',
            ),
            onTap: () => _confirmDeleteAccount(context, ref),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// Returns true if the current user signed up with email+password.
  bool _isEmailPasswordUser() {
    final user = FirebaseAuth.instance.currentUser;
    return user?.providerData.any((p) => p.providerId == 'password') ?? false;
  }

  Future<void> _changeEmail(BuildContext context) async {
    if (!_isEmailPasswordUser()) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cannot change email'),
          content: const Text(
            'Your email address is your Google account email. '
            'It can only be changed from your Google account settings at myaccount.google.com.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final verificationSent = await showDialog<bool>(
      context: context,
      builder: (_) => const _ChangeEmailDialog(),
    );
    if (verificationSent == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Verification email sent. Check your inbox to confirm the new address.',
          ),
        ),
      );
    }
  }

  Future<void> _changePassword(BuildContext context) async {
    final hasPassword = _isEmailPasswordUser();
    // Google users who haven't set a password yet link a new credential.
    // Google users who already linked a password, or plain email users,
    // go through the normal current-password verification flow.
    if (!hasPassword) {
      await _setPasswordForSocialUser(context);
    } else {
      await _changePasswordForEmailUser(context);
    }
  }

  /// Google (or other social) users who have no password yet.
  /// Links an EmailAuthProvider credential so they can also sign in
  /// with email + password going forward.
  Future<void> _setPasswordForSocialUser(BuildContext context) async {
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();
    bool obscureNew = true;
    bool obscureConfirm = true;
    String? error;
    bool loading = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Set a password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add a password to your account so you can also sign in with your email.',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: newPassCtrl,
                obscureText: obscureNew,
                decoration: InputDecoration(
                  labelText: 'New password',
                  suffixIcon: IconButton(
                    icon: Icon(
                        obscureNew ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => obscureNew = !obscureNew),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmPassCtrl,
                obscureText: obscureConfirm,
                decoration: InputDecoration(
                  labelText: 'Confirm password',
                  suffixIcon: IconButton(
                    icon: Icon(obscureConfirm
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () =>
                        setState(() => obscureConfirm = !obscureConfirm),
                  ),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(error!,
                    style: const TextStyle(color: Colors.red, fontSize: 13)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: loading ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: loading
                  ? null
                  : () async {
                      final newPass = newPassCtrl.text;
                      final confirm = confirmPassCtrl.text;
                      if (newPass.isEmpty || confirm.isEmpty) {
                        setState(() => error = 'All fields are required.');
                        return;
                      }
                      if (newPass.length < 6) {
                        setState(() =>
                            error = 'Password must be at least 6 characters.');
                        return;
                      }
                      if (newPass != confirm) {
                        setState(() => error = 'Passwords do not match.');
                        return;
                      }
                      setState(() {
                        loading = true;
                        error = null;
                      });
                      try {
                        final user = FirebaseAuth.instance.currentUser!;
                        final cred = EmailAuthProvider.credential(
                          email: user.email!,
                          password: newPass,
                        );
                        await user.linkWithCredential(cred);
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'Password set. You can now sign in with your email and this password.'),
                            ),
                          );
                        }
                      } on FirebaseAuthException catch (e) {
                        setState(() {
                          loading = false;
                          error = switch (e.code) {
                            'weak-password' => 'Password is too weak.',
                            'provider-already-linked' =>
                              'A password is already linked to this account.',
                            _ => e.message ?? 'Something went wrong.',
                          };
                        });
                      } catch (_) {
                        setState(() {
                          loading = false;
                          error = 'Something went wrong. Please try again.';
                        });
                      }
                    },
              child: loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Set password',
                      style: TextStyle(color: AppColors.purple)),
            ),
          ],
        ),
      ),
    );

    newPassCtrl.dispose();
    confirmPassCtrl.dispose();
  }

  /// Email+password users, or social users who already linked a password.
  Future<void> _changePasswordForEmailUser(BuildContext context) async {
    final passwordUpdated = await showDialog<bool>(
      context: context,
      builder: (_) => const _ChangePasswordDialog(),
    );
    if (passwordUpdated == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated successfully.')),
      );
    }
  }

  String _languageLabel(String code) {
    final seen = <String>{};
    for (final lang in kTranslateLanguages) {
      if (!seen.add(lang.code)) continue;
      if (lang.code == code) return lang.label;
    }
    return code.toUpperCase();
  }

  Future<void> _pickLanguage(
    BuildContext context,
    WidgetRef ref, {
    required String current,
  }) async {
    final seen = <String>{};
    final entries = <TranslateLanguage>[];
    for (final lang in kTranslateLanguages) {
      if (seen.add(lang.code)) entries.add(lang);
    }

    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (sheet) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheet).size.height * 0.6,
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.borderColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Preferred language',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (_, i) {
                      final lang = entries[i];
                      final selected = lang.code == current;
                      return ListTile(
                        title: Text(lang.label),
                        subtitle: Text(
                          lang.code.toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            color: context.textSecondary,
                          ),
                        ),
                        trailing: selected
                            ? const Icon(Icons.check, color: AppColors.purple)
                            : null,
                        onTap: () => Navigator.pop(sheet, lang.code),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selected != null) {
      await ref.read(preferredLanguageProvider.notifier).set(selected);
    }
  }

  void _showBlockedUsers(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _BlockedUsersSheet(),
    );
  }

  Future<void> _confirmDeleteAccount(
      BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
          'This permanently deletes your profile, posts, comments, stories, '
          'followers, and notifications. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete everything',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Deleting your account...')),
    );

    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) return;
    final uid = authUser.uid;

    try {
      await ref.read(adminServiceProvider).selfDeleteCurrentUser(uid);
      await authUser.delete();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'For security, please log out and log back in, then try again.',
              ),
            ),
          );
        }
        return;
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: ${e.message ?? e.code}')),
        );
      }
      return;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
      return;
    }

    if (context.mounted) {
      context.go('/login');
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: context.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _ChangeEmailDialog extends StatefulWidget {
  const _ChangeEmailDialog();

  @override
  State<_ChangeEmailDialog> createState() => _ChangeEmailDialogState();
}

class _ChangeEmailDialogState extends State<_ChangeEmailDialog> {
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
      setState(() => _error = 'All fields are required.');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) {
      setState(() => _error = 'No signed-in email account found.');
      return;
    }

    if (newEmail.toLowerCase() == user.email!.toLowerCase()) {
      setState(
        () => _error = 'Please enter an email different from your current one.',
      );
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final cred = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );
      await user.reauthenticateWithCredential(cred);

      try {
        await user.verifyBeforeUpdateEmail(newEmail);
      } on FirebaseAuthException catch (e) {
        // Fallback for projects where verify-before-update is not enabled.
        if (e.code == 'operation-not-allowed' || e.code == 'internal-error') {
          await user.updateEmail(newEmail);
          await user.sendEmailVerification();
        } else {
          rethrow;
        }
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = switch (e.code) {
          'wrong-password' || 'invalid-credential' => 'Incorrect password.',
          'requires-recent-login' =>
            'For security, please sign in again and retry.',
          'email-already-in-use' => 'That email is already in use.',
          'invalid-email' => 'That email address looks invalid.',
          'too-many-requests' =>
            'Too many attempts. Please wait and try again.',
          'network-request-failed' =>
            'Network error. Check your connection and try again.',
          'operation-not-allowed' =>
            'Email change is not enabled in Authentication settings.',
          _ => e.message ?? 'Something went wrong.',
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Something went wrong. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change email'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'New email'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passCtrl,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'Current password',
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _loading ? null : _save,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save', style: TextStyle(color: AppColors.purple)),
        ),
      ],
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _currentPassCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  bool _sendingReset = false;
  String? _error;
  String? _notice;
  bool _noticeIsError = false;

  @override
  void dispose() {
    _currentPassCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final current = _currentPassCtrl.text;
    final newPass = _newPassCtrl.text;
    final confirm = _confirmPassCtrl.text;
    if (current.isEmpty || newPass.isEmpty || confirm.isEmpty) {
      setState(() => _error = 'All fields are required.');
      return;
    }
    if (newPass.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }
    if (newPass != confirm) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) {
      setState(() => _error = 'No signed-in email account found.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });

    try {
      final cred = EmailAuthProvider.credential(
        email: user.email!,
        password: current,
      );
      await user.reauthenticateWithCredential(cred);
      await user.updatePassword(newPass);

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = switch (e.code) {
          'wrong-password' ||
          'invalid-credential' =>
            'Incorrect current password.',
          'requires-recent-login' =>
            'For security, please sign in again and retry.',
          'weak-password' => 'New password is too weak.',
          'too-many-requests' =>
            'Too many attempts. Please wait and try again.',
          'network-request-failed' =>
            'Network error. Check your connection and try again.',
          _ => e.message ?? 'Something went wrong.',
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Something went wrong. Please try again.';
      });
    }
  }

  Future<void> _sendResetEmail() async {
    final userEmail = FirebaseAuth.instance.currentUser?.email;
    if (userEmail == null || userEmail.isEmpty) {
      setState(() {
        _noticeIsError = true;
        _notice = 'No signed-in email account found.';
      });
      return;
    }

    setState(() {
      _sendingReset = true;
      _error = null;
      _notice = null;
    });

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: userEmail);
      if (!mounted) return;
      setState(() {
        _sendingReset = false;
        _noticeIsError = false;
        _notice = 'Password reset email sent to $userEmail';
      });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _sendingReset = false;
        _noticeIsError = true;
        _notice = switch (e.code) {
          'too-many-requests' =>
            'Too many attempts. Please wait and try again.',
          'network-request-failed' =>
            'Network error. Check your connection and try again.',
          'invalid-email' => 'Your email address looks invalid.',
          _ => e.message ?? 'Could not send reset email. Please try again.',
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sendingReset = false;
        _noticeIsError = true;
        _notice = 'Could not send reset email. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _currentPassCtrl,
            obscureText: _obscureCurrent,
            decoration: InputDecoration(
              labelText: 'Current password',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureCurrent ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () =>
                    setState(() => _obscureCurrent = !_obscureCurrent),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _newPassCtrl,
            obscureText: _obscureNew,
            decoration: InputDecoration(
              labelText: 'New password',
              suffixIcon: IconButton(
                icon:
                    Icon(_obscureNew ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscureNew = !_obscureNew),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmPassCtrl,
            obscureText: _obscureConfirm,
            decoration: InputDecoration(
              labelText: 'Confirm new password',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: (_loading || _sendingReset) ? null : _sendResetEmail,
              child: _sendingReset
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Forgot password?'),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ],
          if (_notice != null) ...[
            const SizedBox(height: 10),
            Text(
              _notice!,
              style: TextStyle(
                color: _noticeIsError ? Colors.red : Colors.green,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: (_loading || _sendingReset)
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: (_loading || _sendingReset) ? null : _save,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save', style: TextStyle(color: AppColors.purple)),
        ),
      ],
    );
  }
}

class _BlockedUsersSheet extends ConsumerWidget {
  const _BlockedUsersSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.65,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.borderColor,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Blocked Users',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: context.textPrimary,
                ),
              ),
            ),
            // The full _BlockedUserTile lives in profile_screen.dart;
            // we show a lightweight inline list here so the settings
            // page can stand alone. Tapping unblock removes the user.
            const Expanded(child: _BlockedUsersList()),
          ],
        ),
      ),
    );
  }
}

class _BlockedUsersList extends ConsumerWidget {
  const _BlockedUsersList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Open a user profile to block or unblock from there.',
          textAlign: TextAlign.center,
          style: TextStyle(color: context.textSecondary),
        ),
      ),
    );
  }
}
