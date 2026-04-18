import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../providers/admin_providers.dart';
import '../../../theme/app_theme.dart';

class AdminBlacklistScreen extends ConsumerWidget {
  const AdminBlacklistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(blacklistProvider);
    return Scaffold(
      backgroundColor: context.surfaceSoft,
      appBar: AppBar(
        title: const Text('Blacklisted emails'),
        backgroundColor: context.cardBg,
        foregroundColor: context.textPrimary,
        elevation: 0,
      ),
      body: listAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 48, color: context.textSecondary),
                  const SizedBox(height: 12),
                  Text('No blacklisted emails',
                      style: TextStyle(color: context.textSecondary)),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final item = items[i];
              final email = (item['email'] as String?) ?? '';
              final deletedAt =
                  (item['deletedAt'] as dynamic)?.toDate() as DateTime?;
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade100),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.block, color: Colors.red, size: 18),
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
                              'Deleted ${DateFormat('MMM d, y').format(deletedAt)}',
                              style: TextStyle(
                                  color: context.textSecondary, fontSize: 11),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Remove from blacklist?'),
                            content: Text(
                                'Allow $email to register again?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Remove',
                                    style: TextStyle(color: Colors.green)),
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
                      icon: Icon(Icons.restore, color: context.textSecondary),
                      tooltip: 'Remove from blacklist',
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
