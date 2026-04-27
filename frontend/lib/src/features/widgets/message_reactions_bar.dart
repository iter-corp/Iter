import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/reaction_providers.dart';
import '../../services/reaction_service.dart';
import '../../theme/app_theme.dart';

/// Bottom-sheet picker of popular reaction emojis. Tapping one toggles it
/// on the message referenced by [parentPath] + [messageId].
void showReactionsSheet(
  BuildContext context, {
  required WidgetRef ref,
  required String parentPath,
  required String messageId,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: context.cardBg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 20),
        child: Consumer(
          builder: (context, sheetRef, _) {
            final myAsync = sheetRef.watch(myReactionProvider(
              '$parentPath::$messageId',
            ));
            final mine = myAsync.value;
            // The reaction picker can have many emojis; on narrow screens
            // a fixed Row overflows. Use a horizontal ListView so the user
            // can scroll to find any emoji and the layout never overflows.
            return SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: kReactionEmojis.length,
                separatorBuilder: (_, __) => const SizedBox(width: 4),
                itemBuilder: (_, i) {
                  final e = kReactionEmojis[i];
                  final selected = mine == e;
                  return GestureDetector(
                    onTap: () async {
                      await sheetRef.read(reactionServiceProvider).toggle(
                            parentPath: parentPath,
                            messageId: messageId,
                            emoji: e,
                          );
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: selected
                            ? context.purpleSoft
                            : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: Text(e, style: const TextStyle(fontSize: 28)),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    ),
  );
}

/// Compact row below a message showing current reaction counts per emoji.
/// Tapping a pill toggles the current user's reaction to that emoji.
class MessageReactionsRow extends ConsumerWidget {
  final String parentPath;
  final String messageId;

  const MessageReactionsRow({
    super.key,
    required this.parentPath,
    required this.messageId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = '$parentPath::$messageId';
    final countsAsync = ref.watch(reactionCountsProvider(key));
    final mine = ref.watch(myReactionProvider(key)).value;
    final counts = countsAsync.value ?? const <String, int>{};
    if (counts.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: counts.entries.map((entry) {
          final isMine = mine == entry.key;
          return GestureDetector(
            onTap: () {
              ref.read(reactionServiceProvider).toggle(
                    parentPath: parentPath,
                    messageId: messageId,
                    emoji: entry.key,
                  );
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isMine
                    ? context.purpleSoft
                    : context.inputFill,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isMine
                      ? const Color(0xFFB05ECC)
                      : Colors.transparent,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(entry.key, style: const TextStyle(fontSize: 13)),
                  const SizedBox(width: 4),
                  Text(
                    '${entry.value}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isMine
                          ? const Color(0xFFB05ECC)
                          : Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
