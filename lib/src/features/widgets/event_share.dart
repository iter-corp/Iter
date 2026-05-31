import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_strings.dart';
import '../../providers/auth_providers.dart';
import '../../providers/chat_providers.dart';
import '../../providers/story_providers.dart';
import '../../services/admin_service.dart';
import '../../theme/app_theme.dart';
import 'event_detail.dart';

/// Fetches the event doc by [eventId] and pushes [EventDetailScreen]
/// built from its fields. Single entry point for every "open this event"
/// tap that only has an ID — shared-event chat bubbles, story "View
/// event" pills, notification taps.
Future<void> openEventById(BuildContext context, String eventId) async {
  if (eventId.isEmpty) return;
  try {
    final doc = await FirebaseFirestore.instance
        .collection('events')
        .doc(eventId)
        .get();
    if (!context.mounted) return;
    if (!doc.exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t.eventUnavailableBody)),
      );
      return;
    }
    final ev = AdminEvent.fromDoc(doc);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EventDetailScreen(
          eventId: ev.id,
          title: ev.title,
          subtitle: ev.subtitle,
          location: ev.location,
          eventType: ev.eventType,
          funds: ev.funds,
          deadlineAt: ev.deadlineAt,
          imageUrls: ev.imageUrls,
          description: ev.description,
          link: ev.link,
          phone: ev.phone,
          email: ev.email,
          createdByUid: ev.createdByUid,
        ),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.t.errorWithMessage(e.toString()))),
    );
  }
}

/// Opens the "share event" bottom sheet: send the event to a friend (DM)
/// or post it to your story. Mirrors the post-share sheet in post_card.
Future<void> showEventShareSheet(
  BuildContext context, {
  required AdminEvent event,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.cardBg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) {
      return Consumer(
        builder: (ctx, ref, _) {
          final currentUid = ref.read(authStateProvider).value?.uid;
          final inboxAsync = ref.watch(inboxProvider);
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.65,
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      ctx.t.eventShare,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  // Share to story.
                  ListTile(
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [Color(0xFFD044E8), Color(0xFF7E3BE8)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: const Icon(Icons.auto_stories_outlined,
                          color: Colors.white, size: 22),
                    ),
                    title: Text(ctx.t.eventShareToStory),
                    onTap: () async {
                      await _shareEventToStory(ctx, ref, event);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: currentUid == null
                        ? const SizedBox.shrink()
                        : inboxAsync.when(
                            loading: () => const Center(
                                child: CircularProgressIndicator()),
                            error: (e, _) => Center(
                                child: Text(ctx.t.homeErrorPrefix(e))),
                            data: (convs) {
                              if (convs.isEmpty) {
                                return Center(
                                  child: Text(
                                    ctx.t.postCardNoConversations,
                                    textAlign: TextAlign.center,
                                    style:
                                        const TextStyle(color: Colors.grey),
                                  ),
                                );
                              }
                              return ListView.separated(
                                padding:
                                    const EdgeInsets.fromLTRB(14, 10, 14, 16),
                                itemCount: convs.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (_, i) {
                                  final c = convs[i];
                                  return ListTile(
                                    leading: CircleAvatar(
                                      backgroundImage:
                                          c.otherAvatarUrl.isNotEmpty
                                              ? NetworkImage(c.otherAvatarUrl)
                                              : null,
                                      child: c.otherAvatarUrl.isEmpty
                                          ? const Icon(Icons.person)
                                          : null,
                                    ),
                                    title: Text(c.otherUsername),
                                    trailing: FilledButton(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: AppColors.purple,
                                        foregroundColor: Colors.white,
                                      ),
                                      onPressed: () async {
                                        await _sendEventToChat(
                                          ref,
                                          chatId: c.chatId,
                                          senderUid: currentUid,
                                          receiverUid: c.otherUid,
                                          eventId: event.id,
                                        );
                                        if (ctx.mounted) Navigator.pop(ctx);
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(ctx.t
                                                  .eventShareSent(
                                                      c.otherUsername)),
                                            ),
                                          );
                                        }
                                      },
                                      child: Text(ctx.t.postCardSend),
                                    ),
                                  );
                                },
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
    },
  );
}

Future<void> _sendEventToChat(
  WidgetRef ref, {
  required String chatId,
  required String senderUid,
  required String receiverUid,
  required String eventId,
}) async {
  await ref.read(chatServiceProvider).sendMessage(
        chatId: chatId,
        senderUid: senderUid,
        receiverUid: receiverUid,
        text: '',
        sharedEventId: eventId,
      );
}

Future<void> _shareEventToStory(
  BuildContext context,
  WidgetRef ref,
  AdminEvent event,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final strings = context.t;
  try {
    final image = event.imageUrls.isNotEmpty ? event.imageUrls.first : '';
    await ref.read(storyServiceProvider).createStory(
          imageUrl: image,
          sharedEventId: event.id,
          sharedEventTitle: event.title,
        );
    messenger.showSnackBar(
      SnackBar(content: Text(strings.eventSharedToStory)),
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(strings.eventShareStoryFailed(e.toString()))),
    );
  }
}

/// Compact event card rendered inside a chat bubble for a `sharedEventId`
/// message. Tapping opens the event. Watches the event doc live so it
/// reflects edits/deletes.
class SharedEventMessage extends StatelessWidget {
  final String eventId;

  const SharedEventMessage({super.key, required this.eventId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('events')
          .doc(eventId)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 60,
            width: 220,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        if (!snap.hasData || snap.data?.exists != true) {
          return Text(context.t.eventUnavailableBody);
        }
        final ev = AdminEvent.fromDoc(snap.data!);
        final hasImage = ev.imageUrls.isNotEmpty;
        return GestureDetector(
          onTap: () => openEventById(context, eventId),
          child: Container(
            width: 220,
            decoration: BoxDecoration(
              color: context.cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasImage)
                  ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(12)),
                    child: CachedNetworkImage(
                      imageUrl: ev.imageUrls.first,
                      width: 220,
                      height: 120,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) =>
                          Container(height: 120, color: context.borderColor),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.event_outlined,
                              size: 14, color: AppColors.purple),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              ev.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: context.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (ev.location.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            ev.location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: context.textSecondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
