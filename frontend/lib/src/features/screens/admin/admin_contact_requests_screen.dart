import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_strings.dart';
import '../../../providers/admin_providers.dart';
import '../../../providers/contact_request_providers.dart';
import '../../../services/contact_request_service.dart';
import '../../../theme/app_theme.dart';
import '../contact_us_screen.dart';

/// Admin-side list of every contact-us thread. Filterable by type +
/// status. Tapping a row opens [ContactThreadScreen], which the
/// admin uses to reply and (for organization requests) approve the
/// user as an event-posting org_admin.
class AdminContactRequestsScreen extends ConsumerStatefulWidget {
  const AdminContactRequestsScreen({super.key});

  @override
  ConsumerState<AdminContactRequestsScreen> createState() =>
      _AdminContactRequestsScreenState();
}

class _AdminContactRequestsScreenState
    extends ConsumerState<AdminContactRequestsScreen> {
  /// `null` = all, otherwise filter to a specific type.
  ContactRequestType? _typeFilter;

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
      backgroundColor: context.surfaceSoft,
      appBar: AppBar(
        title: Text(context.t.contactRequests),
        backgroundColor: context.cardBg,
        foregroundColor: context.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            _FilterBar(
              typeFilter: _typeFilter,
              onTypeChanged: (v) => setState(() => _typeFilter = v),
              onlyUnread: _onlyUnread,
              onUnreadChanged: (v) => setState(() => _onlyUnread = v),
            ),
            Expanded(
              child: async.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) =>
                    Center(child: Text(context.t.adminCouldNotLoad(e))),
                data: (all) {
                  final filtered = all.where((r) {
                    if (_typeFilter != null && r.type != _typeFilter) {
                      return false;
                    }
                    if (_onlyUnread && !r.unreadByAdmin) return false;
                    return true;
                  }).toList();
                  if (filtered.isEmpty) {
                    return Center(
                      child: Text(context.t.adminNoRequests,
                          style: TextStyle(color: context.textSecondary)),
                    );
                  }
                  return ListView.separated(
                    padding:
                        const EdgeInsets.fromLTRB(12, 8, 12, 24),
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

class _FilterBar extends StatelessWidget {
  final ContactRequestType? typeFilter;
  final ValueChanged<ContactRequestType?> onTypeChanged;
  final bool onlyUnread;
  final ValueChanged<bool> onUnreadChanged;

  const _FilterBar({
    required this.typeFilter,
    required this.onTypeChanged,
    required this.onlyUnread,
    required this.onUnreadChanged,
  });

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, bool selected, VoidCallback onTap) {
      return GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.purple.withValues(alpha: 0.12)
                : context.cardBg,
            border: Border.all(
              color: selected ? AppColors.purple : context.borderColor,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
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
          chip(context.t.adminFilterAll, typeFilter == null && !onlyUnread, () {
            onTypeChanged(null);
            onUnreadChanged(false);
          }),
          const SizedBox(width: 6),
          chip(
            context.t.adminFilterMessages,
            typeFilter == ContactRequestType.message,
            () => onTypeChanged(typeFilter == ContactRequestType.message
                ? null
                : ContactRequestType.message),
          ),
          const SizedBox(width: 6),
          chip(
            context.t.adminFilterOrganization,
            typeFilter == ContactRequestType.organization,
            () => onTypeChanged(
                typeFilter == ContactRequestType.organization
                    ? null
                    : ContactRequestType.organization),
          ),
          const SizedBox(width: 16),
          chip(context.t.adminFilterAwaitingReply, onlyUnread,
              () => onUnreadChanged(!onlyUnread)),
        ],
      ),
    );
  }
}

class _AdminRequestTile extends StatelessWidget {
  final ContactRequest request;
  final VoidCallback onTap;

  const _AdminRequestTile({required this.request, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isOrg = request.type == ContactRequestType.organization;
    final unread = request.unreadByAdmin;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: unread
                  ? AppColors.purple.withValues(alpha: 0.5)
                  : context.borderColor,
              width: unread ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
