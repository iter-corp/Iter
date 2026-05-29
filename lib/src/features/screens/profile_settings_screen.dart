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
import '../widgets/app_page_background.dart';
import 'admin/admin_events_screen.dart';
import 'blocked_users_screen.dart';
import 'change_password_screen.dart';
import 'contact_us_screen.dart';
import 'event_notifications_settings_screen.dart';
import 'profile_visitors_screen.dart';
import 'saved_translations_screen.dart';

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
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(context.t.settings),
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: context.textPrimary,
        elevation: 0,
        flexibleSpace: const AppPageBackground(child: SizedBox.expand()),
      ),
      body: AppPageBackground(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            24 + MediaQuery.of(context).padding.bottom,
          ),
          children: [
            _SectionHeader(title: context.t.account),
            _SettingsTile(
              leading:
                  const Icon(Icons.email_outlined, color: AppColors.purple),
              title: Text(context.t.changeEmail),
              trailing: Icon(Icons.chevron_right, color: context.textSecondary),
              onTap: () => _changeEmail(context),
            ),
            // Only users who actually have a password to change see this row.
            // Pure-Google (or pure-Apple) accounts manage their password
            // through the provider, not in this app — exposing a "Set
            // password" entry here was confusing and the resulting screen
            // had no "current password" to verify against.
            if (_isEmailPasswordUser())
              _SettingsTile(
                leading: const Icon(Icons.lock_reset, color: AppColors.purple),
                title: Text(context.t.changePassword),
                trailing:
                    Icon(Icons.chevron_right, color: context.textSecondary),
                onTap: () => _changePassword(context),
              ),
            _SettingsTile(
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
            _SettingsTile(
              leading: const Icon(Icons.visibility_outlined,
                  color: AppColors.purple),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
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
            _SettingsTile(
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
            _SettingsTile(
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
            _SettingsTile(
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
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const PreferredTranslationLanguageScreen(),
                ),
              ),
            ),
            _SettingsTile(
              leading:
                  const Icon(Icons.bookmarks_outlined, color: AppColors.purple),
              title: Text(context.t.savedTranslations),
              trailing: Icon(Icons.chevron_right, color: context.textSecondary),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SavedTranslationsScreen(),
                ),
              ),
            ),
            _SectionHeader(title: context.t.appearance),
            _SettingsTile(
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
            _SettingsTile(
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
            _SettingsTile(
              leading: const Icon(Icons.support_agent_outlined,
                  color: AppColors.purple),
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
            _SettingsTile(
              leading: const Icon(Icons.block, color: Color(0xFFD27B2B)),
              title: Text(context.t.blockedUsers),
              trailing: Icon(Icons.chevron_right, color: context.textSecondary),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const BlockedUsersScreen()),
              ),
            ),
            // Approved event managers land here with event-posting rights
            // but no other admin tooling. Full admins see the broader
            // "Admin panel" entry below; this tile is for the limited
            // org_admin role granted via Contact us.
            if (isOrgAdmin && !isAdmin) ...[
              _SectionHeader(title: context.t.settingsSectionOrganization),
              _SettingsTile(
                leading:
                    const Icon(Icons.event_outlined, color: AppColors.purple),
                title: Text(context.t.manageEvents,
                    style: const TextStyle(
                        color: AppColors.purple, fontWeight: FontWeight.w600)),
                subtitle: Text(
                  context.t.settingsManageEventsSubtitle,
                  style: TextStyle(fontSize: 12, color: context.textSecondary),
                ),
                trailing:
                    Icon(Icons.chevron_right, color: context.textSecondary),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AdminEventsScreen()),
                ),
              ),
            ],
            if (isAdmin) ...[
              _SectionHeader(title: context.t.admin),
              _SettingsTile(
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
            _SettingsTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: Text(context.t.logout,
                  style: const TextStyle(color: Colors.red)),
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
            _SettingsTile(
              leading:
                  const Icon(Icons.delete_forever, color: Colors.redAccent),
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

  /// Opens the full-page change-password screen. Only reachable when the
  /// settings row is shown, which is gated on the user actually having a
  /// password credential to change — so the social-user "set password"
  /// branch that used to live here is no longer needed.
  Future<void> _changePassword(BuildContext context) async {
    final passwordUpdated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
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
    } on FirebaseAuthException catch (e) {
      // The Auth-email-rename step inside selfDeleteCurrentUser is the
      // most common failure point — it requires a recent login. Try to
      // re-auth and retry once if the user is a password account.
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

    // Sign out locally so the cached credential doesn't linger.
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}

    if (context.mounted) {
      context.go('/login');
    }
  }

  /// Prompts a password user for their current password and re-authenticates
  /// so a subsequent privileged operation (email rename, delete) can proceed.
  /// Returns true on success, false if the user cancelled or re-auth failed.
  /// For non-password accounts (Google / Apple) returns false immediately —
  /// they need a different re-auth flow we don't trigger from here.
  Future<bool> _reauthBeforeDelete(BuildContext context, User user) async {
    final isPasswordUser =
        user.providerData.any((p) => p.providerId == 'password');
    if (!isPasswordUser || user.email == null) return false;

    final passCtrl = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.t.settingsCurrentPassword),
        content: TextField(
          controller: passCtrl,
          obscureText: true,
          autofocus: true,
          decoration: InputDecoration(hintText: ctx.t.settingsCurrentPassword),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ctx.t.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, passCtrl.text),
            child: Text(ctx.t.ok),
          ),
        ],
      ),
    );
    passCtrl.dispose();
    if (password == null || password.isEmpty) return false;

    try {
      final cred = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );
      await user.reauthenticateWithCredential(cred);
      return true;
    } on FirebaseAuthException {
      return false;
    }
  }
}

class PreferredTranslationLanguageScreen extends ConsumerStatefulWidget {
  const PreferredTranslationLanguageScreen({super.key});

  @override
  ConsumerState<PreferredTranslationLanguageScreen> createState() =>
      _PreferredTranslationLanguageScreenState();
}

class _PreferredTranslationLanguageScreenState
    extends ConsumerState<PreferredTranslationLanguageScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<TranslateLanguage> _entries() {
    final seen = <String>{};
    final entries = <TranslateLanguage>[];
    for (final lang in kTranslateLanguages) {
      if (seen.add(lang.code)) entries.add(lang);
    }
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(preferredLanguageProvider);
    final allEntries = _entries();
    final q = _query.trim().toLowerCase();
    final entries = q.isEmpty
        ? allEntries
        : allEntries
            .where((lang) =>
                lang.label.toLowerCase().contains(q) ||
                lang.code.toLowerCase().contains(q))
            .toList(growable: false);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(context.t.settingsPreferredLanguage),
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: context.textPrimary,
        elevation: 0,
        flexibleSpace: const AppPageBackground(child: SizedBox.expand()),
      ),
      body: AppPageBackground(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: AppGlassCard(
                radius: 16,
                padding: EdgeInsets.zero,
                surfaceAlpha: context.isDark ? 0.42 : 0.36,
                borderAlpha: context.isDark ? 0.14 : 0.50,
                child: TextField(
                  controller: _searchCtrl,
                  textInputAction: TextInputAction.search,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: context.t.translateSearchLanguages,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                            },
                          ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Text(
                        context.t.translateNoLanguagesMatch,
                        style: TextStyle(color: context.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        0,
                        16,
                        24 + MediaQuery.of(context).padding.bottom,
                      ),
                      itemCount: entries.length,
                      itemBuilder: (_, i) {
                        final lang = entries[i];
                        final selected = lang.code == current;
                        return AppGlassCard(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 0, vertical: 4),
                          radius: 16,
                          surfaceAlpha: context.isDark ? 0.42 : 0.36,
                          borderAlpha: context.isDark ? 0.14 : 0.50,
                          child: ListTile(
                            title: Text(lang.label),
                            subtitle: Text(
                              lang.code.toUpperCase(),
                              style: TextStyle(
                                fontSize: 12,
                                color: context.textSecondary,
                              ),
                            ),
                            trailing: selected
                                ? const Icon(Icons.check,
                                    color: AppColors.purple)
                                : null,
                            onTap: () async {
                              await ref
                                  .read(preferredLanguageProvider.notifier)
                                  .set(
                                    lang.code,
                                  );
                              if (context.mounted) Navigator.of(context).pop();
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppGlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      radius: 16,
      surfaceAlpha: context.isDark ? 0.42 : 0.36,
      borderAlpha: context.isDark ? 0.14 : 0.50,
      child: ListTile(
        leading: leading,
        title: title,
        subtitle: subtitle,
        trailing: trailing,
        onTap: onTap,
        iconColor: AppColors.purple,
        textColor: context.textPrimary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
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
  return InputDecoration(
    labelText: label,
    labelStyle: TextStyle(color: context.textSecondary),
    filled: false,
    fillColor: Colors.transparent,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    enabledBorder: InputBorder.none,
    border: InputBorder.none,
    focusedBorder: InputBorder.none,
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
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: AppGlassCard(
        radius: 20,
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.t.changeEmail,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            AppGlassCard(
              radius: 16,
              padding: EdgeInsets.zero,
              child: TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: _settingsInputDecoration(context,
                    label: context.t.settingsNewEmail),
              ),
            ),
            const SizedBox(height: 12),
            AppGlassCard(
              radius: 16,
              padding: EdgeInsets.zero,
              child: TextField(
                controller: _passCtrl,
                obscureText: _obscure,
                decoration: _settingsInputDecoration(
                  context,
                  label: context.t.settingsCurrentPassword,
                  suffixIcon: IconButton(
                    icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
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
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed:
                      _loading ? null : () => Navigator.of(context).pop(false),
                  child: Text(context.t.cancel),
                ),
                const SizedBox(width: 8),
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
            ),
          ],
        ),
      ),
    );
  }
}
