import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_strings.dart';
import '../../providers/admin_providers.dart';
import '../../providers/auth_providers.dart';
import '../../theme/app_theme.dart';
import '../widgets/app_page_background.dart';
import 'change_email_screen.dart';
import 'change_password_screen.dart';

/// Groups all account-identity & lifecycle controls in one place:
/// change email, change password, private-account toggle, and delete account.
/// These previously lived scattered across the main Settings screen; the
/// "Account Center" tile there now opens this page instead.
class AccountCenterScreen extends ConsumerWidget {
  const AccountCenterScreen({super.key});

  bool _isEmailPasswordUser() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    return user.providerData.any((p) => p.providerId == 'password');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userDoc = ref.watch(currentUserDocProvider).value;
    final isPrivate = (userDoc?['isPrivate'] as bool?) ?? false;
    final isEmailPasswordUser = _isEmailPasswordUser();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(context.t.accountCenter),
        backgroundColor: Colors.transparent,
        foregroundColor: context.textPrimary,
        elevation: 0,
        flexibleSpace: const AppPageBackground(child: SizedBox.expand()),
      ),
      body: AppPageBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            const SizedBox(height: 4),

            // ── Email ────────────────────────────────────────────────
            _Tile(
              leading:
                  const Icon(Icons.email_outlined, color: AppColors.purple),
              title: context.t.changeEmail,
              trailing:
                  Icon(Icons.chevron_right, color: context.textSecondary),
              onTap: () => _changeEmail(context),
            ),

            // ── Password (email/password accounts only) ──────────────
            if (isEmailPasswordUser)
              _Tile(
                leading:
                    const Icon(Icons.lock_outline, color: AppColors.purple),
                title: context.t.changePassword,
                trailing:
                    Icon(Icons.chevron_right, color: context.textSecondary),
                onTap: () async {
                  final updated = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                        builder: (_) => const ChangePasswordScreen()),
                  );
                  if (updated == true && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(context.t.settingsPasswordUpdated)),
                    );
                  }
                },
              ),

            // ── Private account toggle ───────────────────────────────
            _Tile(
              leading: Icon(
                isPrivate ? Icons.lock_outline : Icons.lock_open,
                color: AppColors.purple,
              ),
              title: context.t.privateAccount,
              subtitle: isPrivate
                  ? context.t.profileOnlyFollowersCanSee
                  : context.t.profileAnyoneCanSee,
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

            const SizedBox(height: 16),

            // ── Delete account (destructive) ─────────────────────────
            _Tile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: context.t.deleteAccount,
              titleColor: Colors.red,
              subtitle: context.t.profileDeleteAccountSubtitle,
              subtitleColor: Colors.red,
              onTap: () => _confirmDeleteAccount(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _changeEmail(BuildContext context) async {
    if (!_isEmailPasswordUser()) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.t.settingsCannotChangeEmailTitle),
          content: Text(ctx.t.settingsCannotChangeEmailBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(ctx.t.ok),
            ),
          ],
        ),
      );
      return;
    }

    final verificationSent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ChangeEmailScreen()),
    );
    if (verificationSent == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t.settingsVerificationEmailSent)),
      );
    }
  }

  Future<void> _confirmDeleteAccount(
      BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(context.t.profileDeleteAccountTitle),
        content: Text(context.t.profileDeleteAccountBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.t.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              context.t.profileDeleteEverything,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.t.profileDeletingAccount)),
    );

    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) return;
    final uid = authUser.uid;

    try {
      await ref.read(adminServiceProvider).selfDeleteCurrentUser(uid);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        if (!context.mounted) return;
        final reAuthed = await _reauthBeforeDelete(context, authUser);
        if (!reAuthed) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.t.settingsSecurityRelogin)),
            );
          }
          return;
        }
        try {
          await ref.read(adminServiceProvider).selfDeleteCurrentUser(uid);
        } catch (e2) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.t.settingsDeleteFailed(e2))),
            );
          }
          return;
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text(context.t.settingsDeleteFailed(e.message ?? e.code))),
          );
        }
        return;
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t.settingsDeleteFailed(e))),
        );
      }
      return;
    }

    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}

    if (context.mounted) {
      context.go('/login');
    }
  }

  Future<bool> _reauthBeforeDelete(BuildContext context, User user) async {
    final isPasswordUser =
        user.providerData.any((p) => p.providerId == 'password');
    if (!isPasswordUser || user.email == null) return false;

    final passCtrl = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(dctx.t.settingsCurrentPassword),
        content: TextField(
          controller: passCtrl,
          obscureText: true,
          autofocus: true,
          decoration: InputDecoration(
            labelText: dctx.t.settingsCurrentPassword,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx),
            child: Text(dctx.t.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dctx, passCtrl.text),
            child: Text(dctx.t.ok),
          ),
        ],
      ),
    );
    if (password == null || password.isEmpty) return false;
    try {
      final cred =
          EmailAuthProvider.credential(email: user.email!, password: password);
      await user.reauthenticateWithCredential(cred);
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// Local glass list tile mirroring the main settings page styling.
class _Tile extends StatelessWidget {
  final Widget? leading;
  final String title;
  final Color? titleColor;
  final String? subtitle;
  final Color? subtitleColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _Tile({
    this.leading,
    required this.title,
    this.titleColor,
    this.subtitle,
    this.subtitleColor,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppGlassCard(
      margin: const EdgeInsets.symmetric(vertical: 4),
      radius: 16,
      surfaceAlpha: context.isDark ? 0.42 : 0.36,
      borderAlpha: context.isDark ? 0.14 : 0.50,
      child: ListTile(
        leading: leading,
        title: Text(title, style: TextStyle(color: titleColor)),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                style: TextStyle(
                  fontSize: 12,
                  color: subtitleColor ?? context.textSecondary,
                ),
              ),
        trailing: trailing,
        onTap: onTap,
        iconColor: AppColors.purple,
        textColor: context.textPrimary,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
