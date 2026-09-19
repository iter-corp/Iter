import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_strings.dart';
import '../../../providers/admin_providers.dart';
import '../../../providers/contact_request_providers.dart';
import '../../../services/contact_request_service.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/app_feedback.dart';
import '../../widgets/app_page_background.dart';
import '../../widgets/skeleton_loader.dart';
import '../contact_us_screen.dart';

/// Admin-side list of every contact-us thread. Tapping a row opens [ContactThreadScreen], which the
/// admin uses to reply and approve the user as an event manager when needed.
class AdminContactRequestsScreen extends ConsumerStatefulWidget {
  const AdminContactRequestsScreen({super.key});

  @override
  ConsumerState<AdminContactRequestsScreen> createState() =>
      _AdminContactRequestsScreenState();
}

class _AdminContactRequestsScreenState
    extends ConsumerState<AdminContactRequestsScreen> {
  /// Show only threads still awaiting an admin reply.
  bool _onlyUnread = false;

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isAdminProvider);
    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: Text(context.t.contactRequests)),
        body: Center(
          child: Text(context.t.adminNoAccess,
              style: TextStyle(color: context.textSecondary)),
        ),
      );
    }
    final async = ref.watch(allContactRequestsProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppPageBackground(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              title: Text(context.t.contactRequests),
              backgroundColor: Colors.transparent,
              foregroundColor: context.textPrimary,
              elevation: 0,
              scrolledUnderElevation: 0,
              floating: true,
              snap: true,
            ),
            SliverToBoxAdapter(
              child: _FilterBar(
                onlyUnread: _onlyUnread,
                onUnreadChanged: (v) => setState(() => _onlyUnread = v),
              ),
            ),
            async.when<Widget>(
              loading: () => SkeletonListTile.sliver(count: 6),
              error: (e, _) => SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text(context.t.adminCouldNotLoad(e))),
              ),
              data: (all) {
                final filtered = all.where((r) {
                  if (_onlyUnread && !r.unreadByAdmin) return false;
                  return true;
                }).toList();
                if (filtered.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(context.t.adminNoRequests,
                          style: TextStyle(color: context.textSecondary)),
                    ),
                  );
                }
                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  sliver: SliverList.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _AdminRequestTile(
                      request: filtered[i],
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              ContactThreadScreen(request: filtered[i]),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final bool onlyUnread;
  final ValueChanged<bool> onUnreadChanged;

  const _FilterBar({
    required this.onlyUnread,
    required this.onUnreadChanged,
  });

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, bool selected, VoidCallback onTap) {
      return GestureDetector(
        onTap: onTap,
        child: AppGlassCard(
          radius: 20,
          emphasize: selected,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.purple : context.textPrimary,
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        children: [
          chip(context.t.adminFilterAll, !onlyUnread,
              () => onUnreadChanged(false)),
          const SizedBox(width: 8),
          chip(context.t.adminFilterAwaitingReply, onlyUnread,
              () => onUnreadChanged(!onlyUnread)),
        ],
      ),
    );
  }
}

class _AdminRequestTile extends ConsumerWidget {
  final ContactRequest request;
  final VoidCallback onTap;

  const _AdminRequestTile({required this.request, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOrg = request.type == ContactRequestType.organization;
    final unread = request.unreadByAdmin;
    return AppGlassCard(
      radius: 16,
      emphasize: unread,
      borderAlpha: unread ? 0.65 : null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 4, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isOrg
                                  ? AppColors.purple.withValues(alpha: 0.12)
                                  : context.surfaceSoft,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isOrg
                                  ? context.t.adminBadgeOrganization
                                  : context.t.adminBadgeMessage,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                                color: isOrg
                                    ? AppColors.purple
                                    : context.textSecondary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _StatusPill(status: request.status),
                          const Spacer(),
                          Text(
                            context.t.timeAgo(
                                request.lastMessageAt ?? request.createdAt),
                            style: TextStyle(
                              fontSize: 11,
                              color: context.textSecondary,
                            ),
                          ),
                          if (unread) ...[
                            const SizedBox(width: 8),
                            Container(
                              width: 9,
                              height: 9,
                              decoration: const BoxDecoration(
                                color: AppColors.purple,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        request.userName.isNotEmpty
                            ? request.userName
                            : request.userEmail,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimary,
                        ),
                      ),
                      if (request.userName.isNotEmpty &&
                          request.userEmail.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          request.userEmail,
                          style: TextStyle(
                            fontSize: 11,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        request.lastMessagePreview.isNotEmpty
                            ? request.lastMessagePreview
                            : request.subject,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: context.textPrimary,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: context.t.adminDeleteConversationTooltip,
                  icon: const Icon(Icons.delete_outline,
                      size: 18, color: Colors.red),
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(context.t.adminDeleteConversationTitle),
                        content: Text(context.t.adminDeleteConversationBody),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text(context.t.cancel),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: Text(context.t.delete),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true) return;
                    try {
                      await ref
                          .read(contactRequestServiceProvider)
                          .deleteRequest(request.id);
                      if (!context.mounted) return;
                      AppFeedback.showSuccess(
                          context, context.t.adminConversationDeleted);
                    } catch (e) {
                      if (!context.mounted) return;
                      AppFeedback.showError(
                          context, context.t.failedWithError(e));
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final ContactRequestStatus status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      ContactRequestStatus.open => (context.t.adminStatusOpen, Colors.orange),
      ContactRequestStatus.answered => (
          context.t.adminStatusAnswered,
          Colors.green
        ),
      ContactRequestStatus.promoted => (
          context.t.adminStatusApproved,
          AppColors.purple
        ),
      ContactRequestStatus.revoked => (
          context.t.adminStatusRevoked,
          Colors.red
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: color,
        ),
      ),
    );
  }
}
