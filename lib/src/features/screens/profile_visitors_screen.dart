import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_strings.dart';
import '../../navigation/user_profile_nav.dart';
import '../../providers/auth_providers.dart';
import '../../providers/profile_visitor_providers.dart';
import '../../services/profile_visitor_service.dart';
import '../../theme/app_theme.dart';
import '../widgets/app_page_background.dart';

/// "Who visited my profile" — a list of users sorted by their most
/// recent visit, with a tap-through to each visitor's profile. Driven
/// by [myProfileVisitorsProvider]; data lands in
/// `users/{ownerUid}/visitors/{visitorUid}` whenever
/// [ProfileVisitorService.recordVisit] is called.
class ProfileVisitorsScreen extends ConsumerWidget {
  const ProfileVisitorsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visitorsAsync = ref.watch(myProfileVisitorsProvider);
    final countAsync = ref.watch(myProfileVisitorCountProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppPageBackground(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              title: Text(context.t.profileVisitors),
              centerTitle: false,
              automaticallyImplyLeading: false,
              leading: const FrostedCircleBackButton(),
              leadingWidth: 56,
              flexibleSpace: const FrostedAppBarBackground(),
              backgroundColor: Colors.transparent,
              foregroundColor: context.textPrimary,
              elevation: 0,
              scrolledUnderElevation: 0,
              pinned: true,
            ),
            // Plain header row sitting directly on the page background — no
            // boxed card, so the top of the screen reads as one continuous
            // scrollable surface rather than a second bar.
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Row(
                  children: [
                    const Icon(Icons.visibility_outlined,
                        color: Color(0xFFB05ECC)),
                    const SizedBox(width: 10),
                    Text(
                      countAsync.when(
                        data: (c) => context.t.profileVisitorsCount(c),
                        loading: () => context.t.profileVisitorsCount('...'),
                        error: (_, __) => context.t.profileVisitorsCount('-'),
                      ),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ...visitorsAsync.when(
              loading: () => const <Widget>[
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
              error: (e, _) => <Widget>[
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: Text(context.t.errorWithMessage(e))),
                ),
              ],
              data: (visitors) {
                if (visitors.isEmpty) {
                  return <Widget>[
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: AppGlassCard(
                          margin: const EdgeInsets.all(24),
                          padding: const EdgeInsets.all(24),
                          radius: 20,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.search_off,
                                  size: 48, color: context.textMuted),
                              const SizedBox(height: 12),
                              Text(
                                context.t.profileNoVisitsYet,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: context.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                context.t.profileNoVisitsSubtitle,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: context.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ];
                }
                return <Widget>[
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      0,
                      16,
                      20 + MediaQuery.paddingOf(context).bottom,
                    ),
                    sliver: SliverList.separated(
                      itemCount: visitors.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final v = visitors[i];
                        return _VisitorTile(
                          entry: v,
                          relative: context.t.timeAgo(v.lastVisitedAt),
                        );
                      },
                    ),
                  ),
                ];
              },
            ),
          ],
        ),
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
    final t = context.t;
    final avatar = (data?['avatarUrl'] as String?) ?? '';

    return AppGlassCard(
      radius: 18,
      child: ListTile(
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
                  ? t.profileVisitedTimes(relative, entry.visitCount)
                  : t.profileVisited(relative))
              : (entry.visitCount > 1
                  ? t.profileVisitorVisits(fullName, entry.visitCount)
                  : fullName),
          style: TextStyle(color: context.textSecondary, fontSize: 12),
        ),
        trailing: Text(
          relative,
          style: TextStyle(color: context.textMuted, fontSize: 11),
        ),
      ),
    );
  }
}
