import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_strings.dart';
import '../../../providers/admin_providers.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/app_page_background.dart';

class AdminBlacklistScreen extends ConsumerWidget {
  const AdminBlacklistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(blacklistProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppPageBackground(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              title: Text(context.t.adminBlacklistedEmails),
              backgroundColor: Colors.transparent,
              foregroundColor: context.textPrimary,
              elevation: 0,
              scrolledUnderElevation: 0,
              floating: true,
              snap: true,
            ),
            listAsync.when<Widget>(
              loading: () => const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text(context.t.errorWithMessage(e))),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_outline,
                              size: 48, color: context.textSecondary),
                          const SizedBox(height: 12),
                          Text(context.t.adminNoBlacklistedEmails,
                              style: TextStyle(color: context.textSecondary)),
                        ],
                      ),
                    ),
                  );
                }
                return SliverPadding(
                  padding: const EdgeInsets.all(12),
                  sliver: SliverList.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final item = items[i];
                      final email = (item['email'] as String?) ?? '';
                      final deletedAt =
                          (item['deletedAt'] as dynamic)?.toDate() as DateTime?;
                      return AppGlassCard(
                        padding: const EdgeInsets.all(14),
                        radius: 16,
                        borderAlpha: 0.60,
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.block,
                                  color: Colors.red, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    email,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  if (deletedAt != null)
                                    Text(
                                      context.t.adminDeletedOn(
                                          DateFormat('MMM d, y')
                                              .format(deletedAt)),
                                      style: TextStyle(
                                          color: context.textSecondary,
                                          fontSize: 11),
                                    ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    title: Text(context
                                        .t.adminRemoveFromBlacklistTitle),
                                    content: Text(context.t
                                        .adminAllowToRegisterAgain(email)),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: Text(context.t.cancel),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: Text(context.t.remove,
                                            style: const TextStyle(
                                                color: Colors.green)),
                                      ),
                                    ],
                                  ),
                                );
                                if (ok == true) {
                                  await ref
                                      .read(adminServiceProvider)
                                      .removeFromBlacklist(email);
                                }
                              },
                              icon: Icon(Icons.restore,
                                  color: context.textSecondary),
                              tooltip:
                                  context.t.adminRemoveFromBlacklistTooltip,
                            ),
                          ],
                        ),
                      );
                    },
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
