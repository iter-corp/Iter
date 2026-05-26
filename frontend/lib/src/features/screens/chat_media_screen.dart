import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../l10n/app_strings.dart';
import '../../providers/auth_providers.dart';
import '../../providers/chat_providers.dart';
import '../../services/chat_service.dart';
import '../../theme/app_theme.dart';

/// Per-chat media browser. Four tabs over the chat's `messages` stream:
///   • Images — every photo sent in this chat (grid)
///   • Files  — every document/file attachment
///   • Voices — every voice note
///   • Links  — every URL extracted from message text
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
      length: 4,
      child: Scaffold(
        backgroundColor: context.surfaceSoft,
        appBar: AppBar(
          backgroundColor: context.cardBg,
          foregroundColor: context.textPrimary,
          elevation: 0,
          title: Text(
            chatTitle,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(56),
            child: Container(
              color: context.cardBg,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: _MediaTabBar(
                tabs: [
                  _TabSpec(icon: Icons.photo_library_outlined, label: context.t.images),
                  _TabSpec(icon: Icons.insert_drive_file_outlined, label: context.t.files),
                  _TabSpec(icon: Icons.graphic_eq, label: context.t.voices),
                  _TabSpec(icon: Icons.link, label: context.t.links),
                ],
              ),
            ),
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
            final files =
                msgs.where((m) => (m.fileUrl ?? '').isNotEmpty).toList()
                  ..sort(_sortNewestFirst);
            final links = _extractLinks(msgs);

            return TabBarView(
              children: [
                _ImagesGrid(images: images),
                _FilesList(files: files),
                _VoicesList(voices: voices),
                _LinksList(links: links),
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
// Modern segmented tab bar — pill-shaped, animated, premium feel.
// ─────────────────────────────────────────────

class _TabSpec {
  final IconData icon;
  final String label;
  _TabSpec({required this.icon, required this.label});
}

class _MediaTabBar extends StatelessWidget {
  final List<_TabSpec> tabs;
  const _MediaTabBar({required this.tabs});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: context.inputFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.borderColor),
      ),
      padding: const EdgeInsets.all(4),
      child: TabBar(
        isScrollable: false,
        labelPadding: EdgeInsets.zero,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          color: AppColors.purple,
          borderRadius: BorderRadius.circular(11),
          boxShadow: [
            BoxShadow(
              color: AppColors.purple.withValues(alpha: 0.22),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        labelColor: Colors.white,
        unselectedLabelColor: context.textSecondary,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        unselectedLabelStyle:
            const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        tabs: [
          for (final t in tabs)
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(t.icon, size: 16),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      t.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
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
        icon: Icons.photo_library_outlined,
        text: context.t.noImagesShared,
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: images.length,
      itemBuilder: (context, i) {
        final url = images[i].imageUrl!;
        return GestureDetector(
          onTap: () => _openImage(context, ref, url),
          onLongPress: () => _showImageActions(context, ref, url),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(color: context.inputFill),
              errorWidget: (_, __, ___) => Container(
                color: context.inputFill,
                child: Icon(Icons.broken_image, color: context.textSecondary),
              ),
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
      backgroundColor: context.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
// Files tab
// ─────────────────────────────────────────────

class _FilesList extends ConsumerWidget {
  final List<ChatMessage> files;
  const _FilesList({required this.files});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (files.isEmpty) {
      return _EmptyState(
        icon: Icons.insert_drive_file_outlined,
        text: context.t.noFilesShared,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      itemCount: files.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final m = files[i];
        return _FileTile(message: m);
      },
    );
  }
}

class _FileTile extends ConsumerStatefulWidget {
  final ChatMessage message;
  const _FileTile({required this.message});

  @override
  ConsumerState<_FileTile> createState() => _FileTileState();
}

class _FileTileState extends ConsumerState<_FileTile> {
  bool _opening = false;

  Future<void> _open() async {
    if (_opening) return;
    final m = widget.message;
    final url = m.fileUrl;
    if (url == null || url.isEmpty) return;
    setState(() => _opening = true);
    try {
      final dir = await getTemporaryDirectory();
      final rawName = (m.fileName ?? '').isNotEmpty
          ? m.fileName!
          : url.split('?').first.split('/').last;
      final safeName = rawName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final path = '${dir.path}/$safeName';
      final file = File(path);
      if (!await file.exists()) {
        final res = await http.get(Uri.parse(url));
        if (res.statusCode != 200) {
          throw Exception('HTTP ${res.statusCode}');
        }
        await file.writeAsBytes(res.bodyBytes);
      }
      final result = await OpenFilex.open(path, type: m.fileMimeType);
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t.openFailed(result.message))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t.openFailed(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _forward() async {
    final target = await _pickForwardTarget(context, ref);
    if (target == null) return;
    final m = widget.message;
    await _sendForward(
      ref: ref,
      target: target,
      fileUrl: m.fileUrl,
      fileName: m.fileName,
      fileMimeType: m.fileMimeType,
      fileSizeBytes: m.fileSizeBytes,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.t.forwardedTo(target.title))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final name = (m.fileName ?? '').isNotEmpty
        ? m.fileName!
        : context.t.unknownFile;
    final ext = _extOf(name).toUpperCase();
    final size = _formatSize(m.fileSizeBytes);

    return InkWell(
      onTap: _open,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.borderColor),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: context.purpleSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: _opening
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: AppColors.purple),
                    )
                  : Text(
                      ext.isEmpty ? 'FILE' : ext,
                      style: const TextStyle(
                        color: AppColors.purple,
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                        letterSpacing: 0.5,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: context.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (size.isNotEmpty) size,
                      _formatTime(m.createdAt),
                    ].where((s) => s.isNotEmpty).join(' • '),
                    style: TextStyle(
                      fontSize: 12,
                      color: context.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: context.t.forward,
              icon: const Icon(Icons.forward),
              color: context.textSecondary,
              onPressed: _forward,
            ),
          ],
        ),
      ),
    );
  }

  String _extOf(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot >= name.length - 1) return '';
    return name.substring(dot + 1);
  }

  String _formatSize(int? bytes) {
    if (bytes == null || bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      itemCount: links.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final entry = links[i];
        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: entry.url));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.t.linkCopied)),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.borderColor),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: context.purpleSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.link, color: AppColors.purple),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.url,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.purple,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatTime(entry.message.createdAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, color: context.textSecondary),
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
                        SnackBar(
                            content: Text(context.t.forwardedTo(target.title))),
                      );
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'copy', child: Text(context.t.copy)),
                    PopupMenuItem(
                        value: 'forward', child: Text(context.t.forward)),
                  ],
                ),
              ],
            ),
          ),
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
        icon: Icons.graphic_eq,
        text: context.t.noVoiceMessages,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      itemCount: voices.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final m = voices[i];
        final secs = ((m.voiceDurationMs ?? 0) / 1000).round();
        final title = secs > 0
            ? context.t.secsVoiceMessage(secs)
            : context.t.voiceMessage;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.borderColor),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: context.purpleSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.mic, color: AppColors.purple),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatTime(m.createdAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: context.textSecondary),
                onSelected: (value) async {
                  if (value == 'forward') {
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
                      SnackBar(
                          content: Text(context.t.forwardedTo(target.title))),
                    );
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                      value: 'forward', child: Text(context.t.forward)),
                ],
              ),
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
  String? fileUrl,
  String? fileName,
  String? fileMimeType,
  int? fileSizeBytes,
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
    fileUrl: fileUrl,
    fileName: fileName,
    fileMimeType: fileMimeType,
    fileSizeBytes: fileSizeBytes,
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
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: context.purpleSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 40, color: AppColors.purple),
          ),
          const SizedBox(height: 14),
          Text(
            text,
            style: TextStyle(
              color: context.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatTime(DateTime? dt) {
  if (dt == null) return '';
  return DateFormat('MMM d, h:mm a').format(dt);
}
