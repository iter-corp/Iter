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
import 'account_center_screen.dart';
import 'admin/admin_events_screen.dart';
import 'blocked_users_screen.dart';
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
            // Email, password, private-account and delete-account all live
            // behind one Account Center page now, instead of being scattered
            // across this list.
            _SettingsTile(
              leading: const Icon(Icons.manage_accounts_outlined,
                  color: AppColors.purple),
              title: Text(context.t.accountCenter),
              trailing: Icon(Icons.chevron_right, color: context.textSecondary),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const AccountCenterScreen()),
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
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(ctx.t.logout),
                    content: Text(ctx.t.logoutConfirmBody),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(ctx.t.cancel),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: TextButton.styleFrom(
                            foregroundColor: Colors.red),
                        child: Text(ctx.t.logout),
                      ),
                    ],
                  ),
                );
                if (confirmed != true || !context.mounted) return;
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
            // Delete account moved into Account Center (ACCOUNT section above).
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  String _languageLabel(String code) {
    final seen = <String>{};
    for (final lang in kTranslateLanguages) {
      if (!seen.add(lang.code)) continue;
      if (lang.code == code) return lang.label;
    }
    return code.toUpperCase();
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
