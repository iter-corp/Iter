import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../../l10n/app_strings.dart';
import '../../providers/auth_providers.dart';
import '../../providers/chat_providers.dart';
import '../../services/chat_service.dart';
import '../../theme/app_theme.dart';

/// Per-chat media browser. Three tabs over the chat's `messages` stream:
///   • Images — every photo sent in this chat (grid; tap to view, save, forward)
///   • Links  — every URL extracted from message text (copy or forward)
///   • Voices — every voice note (forward to another chat)
/// Reached from the chat header (info icon next to the translate button).
class ChatMediaScreen extends ConsumerWidget {
  final String chatId;
  final String chatTitle;

  const ChatMediaScreen({
    super.key,
    required this.chatId,
    required this.chatTitle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messagesAsync = ref.watch(messagesProvider(chatId));

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(chatTitle),
          bottom: TabBar(
            tabs: [
              Tab(
                  icon: const Icon(Icons.image_outlined),
                  text: context.t.images),
              Tab(icon: const Icon(Icons.link), text: context.t.links),
              Tab(icon: const Icon(Icons.mic_none), text: context.t.voices),
            ],
          ),
        ),
        body: messagesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(context.t.errorWithMessage(e))),
          data: (msgs) {
            final images =
                msgs.where((m) => (m.imageUrl ?? '').isNotEmpty).toList()
                  ..sort(_sortNewestFirst);
            final voices =
                msgs.where((m) => (m.voiceUrl ?? '').isNotEmpty).toList()
                  ..sort(_sortNewestFirst);
            final links = _extractLinks(msgs);

            return TabBarView(
              children: [
                _ImagesGrid(images: images),
                _LinksList(links: links),
                _VoicesList(voices: voices),
              ],
            );
          },
        ),
      ),
    );
  }

  static int _sortNewestFirst(ChatMessage a, ChatMessage b) {
    final at = a.createdAt;
    final bt = b.createdAt;
    if (at == null) return 1;
    if (bt == null) return -1;
    return bt.compareTo(at);
  }

  static List<_LinkEntry> _extractLinks(List<ChatMessage> msgs) {
    final regex = RegExp(
      r'((?:https?://|www\.)[^\s]+|\b[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)*\.[a-z]{2,24}(?:/[^\s]*)?)',
      caseSensitive: false,
    );
    final out = <_LinkEntry>[];
    for (final m in msgs) {
      if (m.text.isEmpty) continue;
      for (final match in regex.allMatches(m.text)) {
        var url = match.group(0)!;
        final lower = url.toLowerCase();
        if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
          url = 'https://$url';
        }
        out.add(_LinkEntry(url: url, message: m));
      }
    }
    out.sort((a, b) => _sortNewestFirst(a.message, b.message));
    return out;
  }
}

class _LinkEntry {
  final String url;
  final ChatMessage message;
  _LinkEntry({required this.url, required this.message});
}

// ─────────────────────────────────────────────
// Images tab
// ─────────────────────────────────────────────

class _ImagesGrid extends ConsumerWidget {
  final List<ChatMessage> images;
  const _ImagesGrid({required this.images});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (images.isEmpty) {
      return _EmptyState(
        icon: Icons.image_outlined,
        text: context.t.noImagesShared,
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: images.length,
      itemBuilder: (context, i) {
        final url = images[i].imageUrl!;
        return GestureDetector(
          onTap: () => _openImage(context, ref, url),
          onLongPress: () => _showImageActions(context, ref, url),
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(color: Colors.black12),
            errorWidget: (_, __, ___) => Container(
              color: Colors.black12,
              child: const Icon(Icons.broken_image, color: Colors.white54),
            ),
          ),
        );
      },
    );
  }

  void _openImage(BuildContext context, WidgetRef ref, String url) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              IconButton(
                tooltip: context.t.saveToGallery,
                icon: const Icon(Icons.download),
                onPressed: () => _saveImage(context, url),
              ),
              IconButton(
                tooltip: context.t.forwardToAnotherChat,
                icon: const Icon(Icons.forward),
                onPressed: () => _forwardImage(context, ref, url),
              ),
            ],
          ),
          body: Center(
            child: InteractiveViewer(
              child: CachedNetworkImage(imageUrl: url),
            ),
          ),
        ),
      ),
    );
  }

  void _showImageActions(BuildContext context, WidgetRef ref, String url) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.download),
              title: Text(context.t.saveToGallery),
              onTap: () {
                Navigator.pop(context);
                _saveImage(context, url);
              },
            ),
            ListTile(
              leading: const Icon(Icons.forward),
              title: Text(context.t.forwardToAnotherChat),
              onTap: () {
                Navigator.pop(context);
                _forwardImage(context, ref, url);
              },
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _saveImage(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.of(context);
  final strings = context.t;
  messenger.showSnackBar(SnackBar(
    content: Text(strings.saving),
    duration: const Duration(milliseconds: 700),
  ));
  try {
    if (!await Gal.hasAccess()) {
      final granted = await Gal.requestAccess();
      if (!granted) {
        messenger.showSnackBar(
          SnackBar(content: Text(strings.permissionDenied)),
        );
        return;
      }
    }
    final tempDir = await getTemporaryDirectory();
    final filename = url.split('?').first.split('/').last;
    final ext = filename.contains('.') ? filename.split('.').last : 'jpg';
    final tempPath = '${tempDir.path}/iter_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final res = await http.get(Uri.parse(url));
    if (res.statusCode != 200) {
      throw Exception('download failed: ${res.statusCode}');
    }
    final file = File(tempPath);
    await file.writeAsBytes(res.bodyBytes);
    await Gal.putImage(tempPath, album: 'Iter');
    messenger.showSnackBar(
      SnackBar(content: Text(strings.savedToGallery)),
    );
  } catch (e) {
    debugPrint('[chat-media] save failed: $e');
    messenger.showSnackBar(
      SnackBar(content: Text(strings.saveFailed(e))),
    );
  }
}

Future<void> _forwardImage(
    BuildContext context, WidgetRef ref, String url) async {
  final target = await _pickForwardTarget(context, ref);
  if (target == null) return;
  await _sendForward(
    ref: ref,
    target: target,
    imageUrl: url,
  );
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(context.t.forwardedTo(target.title))),
  );
}

// ─────────────────────────────────────────────
// Links tab
// ─────────────────────────────────────────────

class _LinksList extends ConsumerWidget {
  final List<_LinkEntry> links;
  const _LinksList({required this.links});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (links.isEmpty) {
      return _EmptyState(icon: Icons.link, text: context.t.noLinksShared);
    }
    return ListView.separated(
      itemCount: links.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final entry = links[i];
        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.link)),
          title: Text(
            entry.url,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFB05ECC),
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: Text(_formatTime(entry.message.createdAt)),
          trailing: PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'copy') {
                await Clipboard.setData(ClipboardData(text: entry.url));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.t.linkCopied)),
                );
              } else if (value == 'forward') {
                final target = await _pickForwardTarget(context, ref);
                if (target == null) return;
                await _sendForward(
                  ref: ref,
                  target: target,
                  text: entry.url,
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.t.forwardedTo(target.title))),
                );
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'copy', child: Text(context.t.copy)),
              PopupMenuItem(value: 'forward', child: Text(context.t.forward)),
            ],
          ),
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: entry.url));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.t.linkCopied)),
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// Voices tab
// ─────────────────────────────────────────────

class _VoicesList extends ConsumerWidget {
  final List<ChatMessage> voices;
  const _VoicesList({required this.voices});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (voices.isEmpty) {
      return _EmptyState(
        icon: Icons.mic_none,
        text: context.t.noVoiceMessages,
      );
    }
    return ListView.separated(
      itemCount: voices.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final m = voices[i];
        final secs = ((m.voiceDurationMs ?? 0) / 1000).round();
        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.mic)),
          title: Text(secs > 0
              ? context.t.secsVoiceMessage(secs)
              : context.t.voiceMessage),
          subtitle: Text(_formatTime(m.createdAt)),
          trailing: PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'open') {
                Navigator.pop(context);
              } else if (value == 'forward') {
                final target = await _pickForwardTarget(context, ref);
                if (target == null) return;
                await _sendForward(
                  ref: ref,
                  target: target,
                  voiceUrl: m.voiceUrl,
                  voiceDurationMs: m.voiceDurationMs,
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.t.forwardedTo(target.title))),
                );
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: 'open', child: Text(context.t.goToMessage)),
              PopupMenuItem(
                  value: 'forward', child: Text(context.t.forward)),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// Forwarding: pick target chat + send
// ─────────────────────────────────────────────

class _ForwardTarget {
  final String chatId;
  final String otherUid;
  final String title;
  final bool isGroup;
  _ForwardTarget({
    required this.chatId,
    required this.otherUid,
    required this.title,
    required this.isGroup,
  });
}

Future<_ForwardTarget?> _pickForwardTarget(
    BuildContext context, WidgetRef ref) async {
  return showModalBottomSheet<_ForwardTarget>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _ForwardChatPicker(),
  );
}

class _ForwardChatPicker extends ConsumerWidget {
  const _ForwardChatPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(acceptedInboxProvider);
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: context.cardBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.borderColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                context.t.forwardTo,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: inbox.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) =>
                    Center(child: Text(context.t.errorWithMessage(e))),
                data: (chats) {
                  if (chats.isEmpty) {
                    return Center(child: Text(context.t.noChatsYet));
                  }
                  return ListView.separated(
                    controller: scrollController,
                    itemCount: chats.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final c = chats[i];
                      final title = c.isGroup ? c.groupName : c.otherUsername;
                      final avatar =
                          c.isGroup ? c.groupAvatarUrl : c.otherAvatarUrl;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: context.surfaceSoft,
                          backgroundImage: avatar.isNotEmpty
                              ? CachedNetworkImageProvider(avatar)
                              : null,
                          child: avatar.isEmpty
                              ? Icon(
                                  c.isGroup ? Icons.group : Icons.person,
                                  color: context.textMuted,
                                )
                              : null,
                        ),
                        title: Text(title),
                        onTap: () => Navigator.pop(
                          context,
                          _ForwardTarget(
                            chatId: c.chatId,
                            otherUid: c.otherUid,
                            title: title,
                            isGroup: c.isGroup,
                          ),
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
  }
}

Future<void> _sendForward({
  required WidgetRef ref,
  required _ForwardTarget target,
  String? text,
  String? imageUrl,
  String? voiceUrl,
  int? voiceDurationMs,
}) async {
  final me = ref.read(authStateProvider).value?.uid;
  if (me == null) return;
  final chatService = ref.read(chatServiceProvider);
  await chatService.sendMessage(
    chatId: target.chatId,
    senderUid: me,
    receiverUid: target.otherUid,
    text: text ?? '',
    imageUrl: imageUrl,
    voiceUrl: voiceUrl,
    voiceDurationMs: voiceDurationMs,
  );
}

// ─────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyState({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: context.textSecondary),
          const SizedBox(height: 12),
          Text(text, style: TextStyle(color: context.textSecondary)),
        ],
      ),
    );
  }
}

String _formatTime(DateTime? dt) {
  if (dt == null) return '';
  return DateFormat('MMM d, h:mm a').format(dt);
}
