import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../navigation/user_profile_nav.dart';
import '../../providers/auth_providers.dart';
import '../../providers/profile_visitor_providers.dart';
import '../../services/profile_visitor_service.dart';
import '../../theme/app_theme.dart';

/// "Who visited my profile" — a list of users sorted by their most
/// recent visit, with a tap-through to each visitor's profile. Driven
/// by [myProfileVisitorsProvider]; data lands in
/// `users/{ownerUid}/visitors/{visitorUid}` whenever
/// [ProfileVisitorService.recordVisit] is called.
class ProfileVisitorsScreen extends ConsumerWidget {
  const ProfileVisitorsScreen({super.key});

  String _ago(DateTime? dt) {
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visitorsAsync = ref.watch(myProfileVisitorsProvider);
    final countAsync = ref.watch(myProfileVisitorCountProvider);

    return Scaffold(
      backgroundColor: context.cardBg,
      appBar: AppBar(
        title: const Text('Profile visitors'),
        centerTitle: false,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Row(
              children: [
                const Icon(Icons.visibility_outlined,
                    color: Color(0xFFB05ECC)),
                const SizedBox(width: 10),
                Text(
                  countAsync.when(
                    data: (c) => '$c ${c == 1 ? 'visitor' : 'visitors'}',
                    loading: () => '… visitors',
                    error: (_, __) => '— visitors',
                  ),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: visitorsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (visitors) {
                if (visitors.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off,
                              size: 48, color: context.textMuted),
                          const SizedBox(height: 12),
                          Text(
                            'No profile visits yet',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: context.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'When other users open your profile, they\'ll '
                            'show up here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: context.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: visitors.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final v = visitors[i];
                    return _VisitorTile(
                      entry: v,
                      relative: _ago(v.lastVisitedAt),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _VisitorTile extends ConsumerWidget {
  final ProfileVisitorEntry entry;
  final String relative;

  const _VisitorTile({required this.entry, required this.relative});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userByUidProvider(entry.uid));
    final data = userAsync.value;
    final username = (data?['username'] as String?) ?? '…';
    final fullName = (data?['fullName'] as String?) ?? '';
    final avatar = (data?['avatarUrl'] as String?) ?? '';

    return ListTile(
      onTap: () => openUserProfile(context, uid: entry.uid),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: context.inputFill,
        backgroundImage:
            avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null,
        child: avatar.isEmpty
            ? Icon(Icons.person, color: context.textSecondary)
            : null,
      ),
      title: Text(
        username,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        fullName.isEmpty
            ? (entry.visitCount > 1
                ? 'Visited $relative · ${entry.visitCount}× total'
                : 'Visited $relative')
            : (entry.visitCount > 1
                ? '$fullName · ${entry.visitCount}× visits'
                : fullName),
        style: TextStyle(color: context.textSecondary, fontSize: 12),
      ),
      trailing: Text(
        relative,
        style: TextStyle(color: context.textMuted, fontSize: 11),
      ),
    );
  }
}
