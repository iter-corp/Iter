import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_strings.dart';
import '../../providers/admin_providers.dart';
import '../../providers/admin_report_notifications_provider.dart';
import '../../providers/auth_providers.dart';
import '../../providers/contact_request_providers.dart';
import '../../providers/locale_provider.dart';
import '../../providers/preferred_language_provider.dart';
import '../../providers/profile_visitor_providers.dart';
import '../../providers/theme_provider.dart';
import '../../services/admin_service.dart';
import '../../services/translate_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/share_app.dart';
import 'admin/admin_events_screen.dart';
import 'contact_us_screen.dart';
import 'event_notifications_settings_screen.dart';
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
    final isOrgAdmin = ref.watch(isOrgAdminProvider);
    final hasNewReports = ref.watch(hasAnyNewReportsProvider);
    final hasUnreadContact = ref.watch(hasUnreadContactRequestsProvider);
    final hasUnreadReply = ref.watch(hasUnreadAdminReplyProvider);
    final userDoc = ref.watch(currentUserDocProvider).valueOrNull;
    final isPrivate = (userDoc?['isPrivate'] as bool?) ?? false;
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final preferredLang = ref.watch(preferredLanguageProvider);
    final uiLanguage = ref.watch(localeProvider);
    final visitorCount =
        ref.watch(myProfileVisitorCountProvider).valueOrNull ?? 0;

    return Scaffold(
      backgroundColor: context.cardBg,
      appBar: AppBar(
        title: Text(context.t.settings),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _SectionHeader(title: context.t.account),
          ListTile(
            leading: const Icon(Icons.email_outlined, color: AppColors.purple),
            title: Text(context.t.changeEmail),
            trailing: Icon(Icons.chevron_right, color: context.textSecondary),
            onTap: () => _changeEmail(context),
          ),
          ListTile(
            leading: const Icon(Icons.lock_reset, color: AppColors.purple),
            title: Text(_isEmailPasswordUser()
                ? context.t.changePassword
                : context.t.setPassword),
            subtitle: _isEmailPasswordUser()
                ? null
                : Text(context.t.settingsSetPasswordSubtitle,
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
            title: Text(context.t.privateAccount),
            subtitle: Text(
              isPrivate
                  ? context.t.profileOnlyFollowersCanSee
                  : context.t.profileAnyoneCanSee,
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
            title: Text(context.t.profileVisitors),
            subtitle: Text(
              visitorCount == 0
                  ? context.t.settingsVisitorsSeeWho
                  : (visitorCount == 1
                      ? context.t.settingsVisitorsViewedOne
                      : context.t.settingsVisitorsViewedMany(visitorCount)),
              style: TextStyle(fontSize: 12, color: context.textSecondary),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (visitorCount > 0)
                  Container(
                    margin: const EdgeInsetsDirectional.only(end: 6),
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
          _SectionHeader(title: context.t.settingsSectionNotifications),
          ListTile(
            leading: const Icon(Icons.event_available_outlined,
                color: AppColors.purple),
            title: Text(context.t.eventNotifTitle),
            subtitle: Text(
              context.t.settingsEventNotifSubtitle,
              style: TextStyle(fontSize: 12, color: context.textSecondary),
            ),
            trailing: Icon(Icons.chevron_right, color: context.textSecondary),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const EventNotificationsSettingsScreen(),
              ),
            ),
          ),
          _SectionHeader(title: context.t.languageLabel),
          ListTile(
            leading: const Icon(Icons.language, color: AppColors.purple),
            title: Text(context.t.appLanguage),
            subtitle: Text(
              context.t.settingsAppLanguageSubtitle,
              style: TextStyle(fontSize: 12, color: context.textSecondary),
            ),
            trailing: Text(
              uiLanguage.nativeName,
              textDirection: uiLanguage.direction,
              style: const TextStyle(
                color: AppColors.purple,
                fontWeight: FontWeight.w600,
              ),
            ),
            onTap: () => context.push('/language'),
          ),
          ListTile(
            leading: const Icon(Icons.translate, color: AppColors.purple),
            title: Text(context.t.translationLanguage),
            subtitle: Text(
              context.t.settingsTranslationLanguageSubtitle,
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
          _SectionHeader(title: context.t.appearance),
          ListTile(
            leading: Icon(
              isDark ? Icons.dark_mode : Icons.light_mode,
              color: isDark ? Colors.amber : Colors.grey,
            ),
            title: Text(context.t.darkMode),
            trailing: Switch.adaptive(
              value: isDark,
              activeTrackColor: AppColors.purple,
              onChanged: (_) => ref.read(themeModeProvider.notifier).toggle(),
            ),
            onTap: () => ref.read(themeModeProvider.notifier).toggle(),
          ),
          _SectionHeader(title: context.t.settingsSectionInvite),
          ListTile(
            leading: const Icon(Icons.ios_share, color: AppColors.purple),
            title: Text(context.t.settingsInviteFriends),
            subtitle: Text(
              context.t.settingsInviteFriendsSubtitle,
              style: TextStyle(fontSize: 12, color: context.textSecondary),
            ),
            trailing: Icon(Icons.chevron_right, color: context.textSecondary),
            onTap: () {
              final cfg = ref.read(adminConfigProvider).valueOrNull ??
                  const AdminConfig();
              shareInviteLink(context, cfg);
            },
          ),
          _SectionHeader(title: context.t.settingsSectionSupport),
          ListTile(
            leading:
                const Icon(Icons.support_agent_outlined, color: AppColors.purple),
            title: Text(context.t.contactUs),
            subtitle: Text(
              context.t.settingsContactUsSubtitle,
              style: TextStyle(fontSize: 12, color: context.textSecondary),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasUnreadReply)
                  Container(
                    width: 9,
                    height: 9,
                    margin: const EdgeInsetsDirectional.only(end: 8),
                    decoration: BoxDecoration(
                      color: AppColors.purple,
                      shape: BoxShape.circle,
                      border: Border.all(color: context.cardBg, width: 1),
                    ),
                  ),
                Icon(Icons.chevron_right, color: context.textSecondary),
              ],
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ContactUsScreen()),
            ),
          ),
          _SectionHeader(title: context.t.safety),
          ListTile(
            leading: const Icon(Icons.block, color: Color(0xFFD27B2B)),
            title: Text(context.t.blockedUsers),
            trailing: Icon(Icons.chevron_right, color: context.textSecondary),
            onTap: () => _showBlockedUsers(context),
          ),
          // Approved event managers land here with event-posting rights
          // but no other admin tooling. Full admins see the broader
          // "Admin panel" entry below; this tile is for the limited
          // org_admin role granted via Contact us.
          if (isOrgAdmin && !isAdmin) ...[
            _SectionHeader(title: context.t.settingsSectionOrganization),
            ListTile(
              leading: const Icon(Icons.event_outlined,
                  color: AppColors.purple),
              title: Text(context.t.manageEvents,
                  style: const TextStyle(
                      color: AppColors.purple,
                      fontWeight: FontWeight.w600)),
              subtitle: Text(
                context.t.settingsManageEventsSubtitle,
                style: TextStyle(fontSize: 12, color: context.textSecondary),
              ),
              trailing: Icon(Icons.chevron_right, color: context.textSecondary),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AdminEventsScreen()),
              ),
            ),
          ],
          if (isAdmin) ...[
            _SectionHeader(title: context.t.admin),
            ListTile(
              leading:
                  const Icon(Icons.shield_outlined, color: Color(0xFF7E3BE8)),
              title: Text(
                context.t.profileAdminPanel,
                style: const TextStyle(
                  color: Color(0xFF7E3BE8),
                  fontWeight: FontWeight.w600,
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasNewReports || hasUnreadContact)
                    Container(
                      width: 9,
                      height: 9,
                      margin: const EdgeInsetsDirectional.only(end: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE04E5C),
                        shape: BoxShape.circle,
                        border: Border.all(color: context.cardBg, width: 1),
                      ),
                    ),
                  Icon(Icons.chevron_right, color: context.textSecondary),
                ],
              ),
              onTap: () => context.push('/admin'),
            ),
          ],
          _SectionHeader(title: context.t.dangerZone),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title:
                Text(context.t.logout, style: const TextStyle(color: Colors.red)),
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
            title: Text(
              context.t.deleteAccount,
              style: const TextStyle(color: Colors.redAccent),
            ),
            subtitle: Text(
              context.t.profileDeleteAccountSubtitle,
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
          title: Text(ctx.t.settingsCannotChangeEmailTitle),
          content: Text(
            ctx.t.settingsCannotChangeEmailBody,
          ),
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

    final verificationSent = await showDialog<bool>(
      context: context,
      builder: (_) => const _ChangeEmailDialog(),
    );
    if (verificationSent == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.t.settingsVerificationEmailSent,
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
          backgroundColor: context.cardBg,
          surfaceTintColor: Colors.transparent,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(ctx.t.setPassword),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ctx.t.settingsSetPasswordDialogBody,
                style: TextStyle(fontSize: 13, color: context.textSecondary),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: newPassCtrl,
                obscureText: obscureNew,
                decoration: _settingsInputDecoration(
                  context,
                  label: ctx.t.settingsNewPassword,
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
                decoration: _settingsInputDecoration(
                  context,
                  label: ctx.t.settingsConfirmPassword,
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
              child: Text(ctx.t.cancel),
            ),
            TextButton(
              onPressed: loading
                  ? null
                  : () async {
                      final newPass = newPassCtrl.text;
                      final confirm = confirmPassCtrl.text;
                      if (newPass.isEmpty || confirm.isEmpty) {
                        setState(() =>
                            error = ctx.t.settingsAllFieldsRequired);
                        return;
                      }
                      if (newPass.length < 6) {
                        setState(() =>
                            error = ctx.t.settingsPasswordMin6);
                        return;
                      }
                      if (newPass != confirm) {
                        setState(() =>
                            error = ctx.t.settingsPasswordsDoNotMatch);
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
                            SnackBar(
                              content: Text(
                                  context.t.settingsPasswordSetSuccess),
                            ),
                          );
                        }
                      } on FirebaseAuthException catch (e) {
                        setState(() {
                          loading = false;
                          error = switch (e.code) {
                            'weak-password' => ctx.t.settingsPasswordTooWeak,
                            'provider-already-linked' =>
                              ctx.t.settingsPasswordAlreadyLinked,
                            _ => e.message ??
                                ctx.t.settingsSomethingWentWrong,
                          };
                        });
                      } catch (_) {
                        setState(() {
                          loading = false;
                          error = ctx.t.settingsSomethingWentWrongRetry;
                        });
                      }
                    },
              child: loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(ctx.t.settingsSetPasswordButton,
                      style: const TextStyle(color: AppColors.purple)),
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
        SnackBar(content: Text(context.t.settingsPasswordUpdated)),
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
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      sheet.t.settingsPreferredLanguage,
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
        title: Text(context.t.profileDeleteAccountTitle),
        content: Text(
          context.t.profileDeleteAccountBody,
        ),
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
      await authUser.delete();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.t.settingsSecurityRelogin,
              ),
            ),
          );
        }
        return;
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(context.t.settingsDeleteFailed(e.message ?? e.code))),
        );
      }
      return;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t.settingsDeleteFailed(e))),
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

InputDecoration _settingsInputDecoration(
  BuildContext context, {
  required String label,
  Widget? suffixIcon,
}) {
  final baseBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: context.borderColor),
  );

  return InputDecoration(
    labelText: label,
    labelStyle: TextStyle(color: context.textSecondary),
    filled: false,
    fillColor: Colors.transparent,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    enabledBorder: baseBorder,
    border: baseBorder,
    focusedBorder: baseBorder.copyWith(
      borderSide: const BorderSide(color: AppColors.purple, width: 1.5),
    ),
    suffixIcon: suffixIcon,
    suffixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
  );
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
      setState(() => _error = context.t.settingsAllFieldsRequired);
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) {
      setState(() => _error = context.t.settingsNoEmailAccount);
      return;
    }

    if (newEmail.toLowerCase() == user.email!.toLowerCase()) {
      setState(
        () => _error = context.t.settingsEmailMustDiffer,
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
    return AlertDialog(
      backgroundColor: context.cardBg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(context.t.changeEmail),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: _settingsInputDecoration(context,
                label: context.t.settingsNewEmail),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passCtrl,
            obscureText: _obscure,
            decoration: _settingsInputDecoration(
              context,
              label: context.t.settingsCurrentPassword,
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
          child: Text(context.t.cancel),
        ),
        TextButton(
          onPressed: _loading ? null : _save,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(context.t.save,
                  style: const TextStyle(color: AppColors.purple)),
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
      setState(() => _error = context.t.settingsAllFieldsRequired);
      return;
    }
    if (newPass.length < 6) {
      setState(() => _error = context.t.settingsPasswordMin6);
      return;
    }
    if (newPass != confirm) {
      setState(() => _error = context.t.settingsPasswordsDoNotMatch);
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

  Future<void> _sendResetEmail() async {
    final userEmail = FirebaseAuth.instance.currentUser?.email;
    if (userEmail == null || userEmail.isEmpty) {
      setState(() {
        _noticeIsError = true;
        _notice = context.t.settingsNoEmailAccount;
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
        _notice = context.t.settingsResetEmailSent(userEmail);
      });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _sendingReset = false;
        _noticeIsError = true;
        _notice = switch (e.code) {
          'too-many-requests' => context.t.settingsTooManyRequests,
          'network-request-failed' => context.t.settingsNetworkError,
          'invalid-email' => context.t.settingsEmailInvalidYours,
          _ => e.message ?? context.t.settingsCouldNotSendReset,
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sendingReset = false;
        _noticeIsError = true;
        _notice = context.t.settingsCouldNotSendReset;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.cardBg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(context.t.changePassword),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _currentPassCtrl,
            obscureText: _obscureCurrent,
            decoration: _settingsInputDecoration(
              context,
              label: context.t.settingsCurrentPassword,
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
            decoration: _settingsInputDecoration(
              context,
              label: context.t.settingsNewPassword,
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
            decoration: _settingsInputDecoration(
              context,
              label: context.t.settingsConfirmNewPassword,
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
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: (_loading || _sendingReset) ? null : _sendResetEmail,
              child: _sendingReset
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(context.t.forgotPassword),
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
          child: Text(context.t.cancel),
        ),
        TextButton(
          onPressed: (_loading || _sendingReset) ? null : _save,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(context.t.save,
                  style: const TextStyle(color: AppColors.purple)),
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
                context.t.settingsBlockedUsersTitle,
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
          context.t.settingsBlockedUsersHint,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.textSecondary),
        ),
      ),
    );
  }
}
