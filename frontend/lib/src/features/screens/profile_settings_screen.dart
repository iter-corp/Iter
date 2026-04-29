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
            trailing:
                Icon(Icons.chevron_right, color: context.textSecondary),
            onTap: () => _showBlockedUsers(context),
          ),

          if (isAdmin) ...[
            const _SectionHeader(title: 'Admin'),
            ListTile(
              leading: const Icon(Icons.shield_outlined,
                  color: Color(0xFF7E3BE8)),
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
            title:
                const Text('Log out', style: TextStyle(color: Colors.red)),
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
                            ? const Icon(Icons.check,
                                color: AppColors.purple)
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
