import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_strings.dart';
import '../../providers/auth_providers.dart';
import '../../providers/block_providers.dart';
import '../../theme/app_theme.dart';
import '../widgets/app_page_background.dart';

class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(context.t.blockedUsers),
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: context.textPrimary,
        elevation: 0,
        flexibleSpace: const AppPageBackground(child: SizedBox.expand()),
      ),
      body: const AppPageBackground(
        child: SafeArea(
          top: false,
          child: _BlockedUsersList(),
        ),
      ),
    );
  }
}

class _BlockedUsersList extends ConsumerWidget {
  const _BlockedUsersList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blockedAsync = ref.watch(blockedUsersProvider);
    return blockedAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            context.t.errorWithMessage(e),
            textAlign: TextAlign.center,
            style: TextStyle(color: context.textSecondary),
          ),
        ),
      ),
      data: (uids) {
        if (uids.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.block, size: 48, color: context.textMuted),
                  const SizedBox(height: 12),
                  Text(
                    context.t.profileNoBlockedUsers,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: context.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.t.profileBlockedUsersHint,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final bottomPadding = MediaQuery.viewPaddingOf(context).bottom + 24;
        return ListView.separated(
          padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPadding),
          itemCount: uids.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _BlockedUserCard(uid: uids[i]),
        );
      },
    );
  }
}

class _BlockedUserCard extends ConsumerWidget {
  final String uid;
  const _BlockedUserCard({required this.uid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(userByUidProvider(uid)).valueOrNull;
    final username = (data?['username'] as String?) ?? uid;
    final avatar = (data?['avatarUrl'] as String?) ?? '';

    return AppGlassCard(
      radius: 16,
      padding: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: CircleAvatar(
          radius: 21,
          backgroundColor: context.inputFill,
          backgroundImage:
              avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null,
          child: avatar.isEmpty
              ? Icon(Icons.person, color: context.textSecondary)
              : null,
        ),
        title: Text(
          username,
          style: TextStyle(
            color: context.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: SizedBox(
          height: 34,
          child: OutlinedButton(
            onPressed: () async {
              final me = ref.read(authServiceProvider).currentUser;
              if (me == null) return;
              await ref.read(blockServiceProvider).unblockUser(
                    currentUid: me.uid,
                    targetUid: uid,
                  );
            },
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.red, width: 1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(17),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            child: Text(
              context.t.unblock,
              style: const TextStyle(
                color: Colors.red,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
