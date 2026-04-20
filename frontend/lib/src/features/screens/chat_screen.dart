import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../navigation/user_profile_nav.dart';
import '../../theme/app_theme.dart';
import '../../providers/auth_providers.dart';
import '../../providers/chat_providers.dart';
import '../../providers/event_chat_providers.dart';
import '../../services/chat_service.dart';
import '../../services/storage_service.dart';
import '../model/post_model.dart';
import '../widgets/message_reactions_bar.dart';
import '../widgets/poll_widgets.dart';
import 'post_detail_screen.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String chatId;
  final String otherUid;
  final String otherName;
  final String otherAvatar;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.otherUid,
    required this.otherName,
    required this.otherAvatar,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _typingTimer;
  bool _sendingImage = false;

  // Reply state — the message currently being replied to (null when none).
  ChatMessage? _replyTarget;

  // Voice recording state.
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  DateTime? _recordStartedAt;
  bool _uploadingVoice = false;

  String? get _currentUid => ref.read(authStateProvider).value?.uid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final uid = _currentUid;
      if (uid == null) return;
      ref.read(presenceServiceProvider).setOnline(uid);
      ref.read(chatServiceProvider).markSeen(chatId: widget.chatId, uid: uid);
    });
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    _recorder.dispose();
    super.dispose();
  }

  void _onTextChanged(String text) {
    _typingTimer?.cancel();
    final uid = _currentUid;
    if (uid == null) return;
    // Typing indicator is only meaningful in 1:1 chats where otherUid is set.
    if (widget.otherUid.isEmpty) return;
    if (text.isNotEmpty) {
      ref.read(typingServiceProvider).setTyping(widget.chatId, uid, true);
      _typingTimer = Timer(const Duration(seconds: 2), () {
        ref.read(typingServiceProvider).setTyping(widget.chatId, uid, false);
      });
    } else {
      ref.read(typingServiceProvider).setTyping(widget.chatId, uid, false);
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    final uid = _currentUid;
    if (text.isEmpty || uid == null) return;
    _typingTimer?.cancel();
    ref.read(typingServiceProvider).setTyping(widget.chatId, uid, false);
    _controller.clear();
    final reply = _replyTarget;
    setState(() => _replyTarget = null);
    await ref.read(chatServiceProvider).sendMessage(
          chatId: widget.chatId,
          senderUid: uid,
          receiverUid: widget.otherUid,
          text: text,
          replyToId: reply?.id,
          replyToText: reply == null ? null : _previewOf(reply),
          replyToSenderUid: reply?.senderUid,
        );
  }

  Future<void> _pickAndSendImage() async {
    if (_sendingImage) return;
    final uid = _currentUid;
    if (uid == null) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (picked == null) return;

    setState(() => _sendingImage = true);
    try {
      final url = await StorageService()
          .uploadChatImage(File(picked.path), widget.chatId);
      final reply = _replyTarget;
      setState(() => _replyTarget = null);
      await ref.read(chatServiceProvider).sendMessage(
            chatId: widget.chatId,
            senderUid: uid,
            receiverUid: widget.otherUid,
            text: '',
            imageUrl: url,
            replyToId: reply?.id,
            replyToText: reply == null ? null : _previewOf(reply),
            replyToSenderUid: reply?.senderUid,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Image upload failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingImage = false);
    }
  }

  Future<void> _toggleVoiceRecording() async {
    if (_uploadingVoice) return;
    final uid = _currentUid;
    if (uid == null) return;

    if (_isRecording) {
      // Stop + upload + send.
      final path = await _recorder.stop();
      final startedAt = _recordStartedAt;
      setState(() {
        _isRecording = false;
        _recordStartedAt = null;
      });
      if (path == null) return;

      setState(() => _uploadingVoice = true);
      try {
        final file = File(path);
        final durationMs = startedAt == null
            ? null
            : DateTime.now().difference(startedAt).inMilliseconds;
        final url = await StorageService()
            .uploadChatAudio(file, widget.chatId);
        final reply = _replyTarget;
        setState(() => _replyTarget = null);
        await ref.read(chatServiceProvider).sendMessage(
              chatId: widget.chatId,
              senderUid: uid,
              receiverUid: widget.otherUid,
              text: '',
              voiceUrl: url,
              voiceDurationMs: durationMs,
              replyToId: reply?.id,
              replyToText: reply == null ? null : _previewOf(reply),
              replyToSenderUid: reply?.senderUid,
            );
        // Best-effort cleanup of the temp file.
        try {
          await file.delete();
        } catch (_) {}
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Voice upload failed: $e')),
          );
        }
      } finally {
        if (mounted) setState(() => _uploadingVoice = false);
      }
    } else {
      if (!await _recorder.hasPermission()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission denied')),
          );
        }
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      setState(() {
        _isRecording = true;
        _recordStartedAt = DateTime.now();
      });
    }
  }

  Future<void> _cancelRecording() async {
    if (!_isRecording) return;
    final path = await _recorder.stop();
    setState(() {
      _isRecording = false;
      _recordStartedAt = null;
    });
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _openOtherProfile() {
    openUserProfile(context, uid: widget.otherUid);
  }

  void _startReply(ChatMessage msg) {
    setState(() => _replyTarget = msg);
  }

  String _previewOf(ChatMessage m) {
    if (m.voiceUrl != null && m.voiceUrl!.isNotEmpty) return 'Voice message';
    if (m.imageUrl != null && m.imageUrl!.isNotEmpty) return 'Photo';
    if (m.sharedPostId != null && m.sharedPostId!.isNotEmpty) {
      return 'Shared post';
    }
    return m.text;
  }

  @override
  Widget build(BuildContext context) {
    final chatDocAsync = ref.watch(chatDocProvider(widget.chatId));
    final chatDoc = chatDocAsync.value ?? const <String, dynamic>{};
    final isGroup = (chatDoc['kind'] as String?) == 'group';
    final groupName = (chatDoc['groupName'] as String?) ?? widget.otherName;
    final participantCount = ((chatDoc['participants'] as List?)?.length ?? 0);

    final presenceAsync =
        isGroup ? null : ref.watch(presenceWatchProvider(widget.otherUid));
    final typingAsync = isGroup
        ? null
        : ref.watch(typingWatchProvider('${widget.chatId}|${widget.otherUid}'));
    final messagesAsync = ref.watch(messagesProvider(widget.chatId));

    ref.listen(messagesProvider(widget.chatId), (_, __) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    });

    final isOnline = presenceAsync?.whenOrNull(data: (p) => p.online) ?? false;
    final isTyping = typingAsync?.whenOrNull(data: (t) => t) ?? false;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // HEADER
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, size: 22),
                  ),
                  GestureDetector(
                    onTap: isGroup ? null : _openOtherProfile,
                    child: Stack(
                      children: [
                        isGroup
                            ? const CircleAvatar(
                                radius: 18,
                                backgroundColor: Color(0xFF7E3BE8),
                                child: Icon(Icons.groups,
                                    color: Colors.white, size: 20),
                              )
                            : CircleAvatar(
                                radius: 18,
                                backgroundImage: widget.otherAvatar.isNotEmpty
                                    ? NetworkImage(widget.otherAvatar)
                                    : null,
                                child: widget.otherAvatar.isEmpty
                                    ? const Icon(Icons.person)
                                    : null,
                              ),
                        if (!isGroup && isOnline)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: Theme.of(context)
                                        .scaffoldBackgroundColor,
                                    width: 1.5),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: isGroup ? null : _openOtherProfile,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isGroup ? groupName : widget.otherName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 15),
                          ),
                          Text(
                            isGroup
                                ? '$participantCount members'
                                : (isTyping
                                    ? 'Typing...'
                                    : isOnline
                                        ? 'Online'
                                        : 'Offline'),
                            style: TextStyle(
                              color: isTyping
                                  ? Colors.purple
                                  : context.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          if (!isGroup && _currentUid != null)
                            _SharedEventLabel(
                              meUid: _currentUid!,
                              otherUid: widget.otherUid,
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Divider(height: 1, color: Theme.of(context).dividerColor),

            // MESSAGES
            Expanded(
              child: messagesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (msgs) {
                  final currentUid = _currentUid ?? '';
                  if (msgs.isEmpty) {
                    return Center(
                      child: Text('Say hello!',
                          style: TextStyle(color: context.textSecondary)),
                    );
                  }
                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    itemCount: msgs.length,
                    itemBuilder: (context, i) {
                      final msg = msgs[i];
                      return _MessageBubble(
                        chatId: widget.chatId,
                        msg: msg,
                        isMe: msg.senderUid == currentUid,
                        otherUid: widget.otherUid,
                        otherAvatar: widget.otherAvatar,
                        isGroup: isGroup,
                        onReply: () => _startReply(msg),
                      );
                    },
                  );
                },
              ),
            ),

            if (isGroup)
              PollsSection(
                parentPath: 'chats/${widget.chatId}',
                canCreate: true,
              ),

            // REPLY PREVIEW (above input)
            if (_replyTarget != null)
              _ReplyComposingBar(
                target: _replyTarget!,
                previewText: _previewOf(_replyTarget!),
                onCancel: () => setState(() => _replyTarget = null),
              ),

            // INPUT
            Padding(
              padding: const EdgeInsets.all(12),
              child: _isRecording
                  ? _RecordingBar(
                      startedAt: _recordStartedAt,
                      onCancel: _cancelRecording,
                      onStop: _toggleVoiceRecording,
                    )
                  : Row(
                      children: [
                        IconButton(
                          onPressed: _sendingImage ? null : _pickAndSendImage,
                          icon: _sendingImage
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Color(0xFFB05ECC)),
                                )
                              : Icon(Icons.camera_alt_outlined,
                                  color: context.textSecondary),
                        ),
                        Expanded(
                          child: Container(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: context.inputFill,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: TextField(
                              controller: _controller,
                              onChanged: _onTextChanged,
                              decoration: InputDecoration(
                                hintText: 'Message...',
                                hintStyle: TextStyle(
                                    color: context.textMuted, fontSize: 14),
                                border: InputBorder.none,
                              ),
                              onSubmitted: (_) => _sendMessage(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        if (_controller.text.trim().isEmpty && !_uploadingVoice)
                          IconButton(
                            onPressed: _toggleVoiceRecording,
                            icon: const Icon(Icons.mic_none,
                                color: Color(0xFFB05ECC)),
                          )
                        else if (_uploadingVoice)
                          const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Color(0xFFB05ECC)),
                            ),
                          )
                        else
                          IconButton(
                            onPressed: _sendMessage,
                            icon: const Icon(Icons.send,
                                color: Color(0xFFB05ECC)),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Reply preview bar — shown above the input while composing a reply.
// ─────────────────────────────────────────────

class _ReplyComposingBar extends StatelessWidget {
  final ChatMessage target;
  final String previewText;
  final VoidCallback onCancel;

  const _ReplyComposingBar({
    required this.target,
    required this.previewText,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: context.purpleSoft,
        border: Border(
          left: BorderSide(
            color: const Color(0xFFB05ECC).withValues(alpha: 0.8),
            width: 3,
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.reply, size: 16, color: Color(0xFFB05ECC)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              previewText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.textPrimary, fontSize: 13),
            ),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: onCancel,
            icon: Icon(Icons.close, size: 18, color: context.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Recording bar — replaces the input row while the user is recording.
// ─────────────────────────────────────────────

class _RecordingBar extends StatefulWidget {
  final DateTime? startedAt;
  final VoidCallback onCancel;
  final VoidCallback onStop;

  const _RecordingBar({
    required this.startedAt,
    required this.onCancel,
    required this.onStop,
  });

  @override
  State<_RecordingBar> createState() => _RecordingBarState();
}

class _RecordingBarState extends State<_RecordingBar> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _elapsed() {
    if (widget.startedAt == null) return '0:00';
    final d = DateTime.now().difference(widget.startedAt!);
    final mm = d.inMinutes.toString().padLeft(1, '0');
    final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: widget.onCancel,
          icon: const Icon(Icons.delete_outline, color: Colors.red),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: context.inputFill,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                const Icon(Icons.fiber_manual_record,
                    color: Colors.red, size: 14),
                const SizedBox(width: 8),
                Text('Recording… ${_elapsed()}',
                    style:
                        TextStyle(color: context.textPrimary, fontSize: 13)),
              ],
            ),
          ),
        ),
        IconButton(
          onPressed: widget.onStop,
          icon: const Icon(Icons.send, color: Color(0xFFB05ECC)),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Message bubble
// ─────────────────────────────────────────────

class _MessageBubble extends ConsumerWidget {
  final String chatId;
  final ChatMessage msg;
  final bool isMe;
  final String otherUid;
  final String otherAvatar;
  final bool isGroup;
  final VoidCallback onReply;

  const _MessageBubble({
    required this.chatId,
    required this.msg,
    required this.isMe,
    required this.otherUid,
    required this.otherAvatar,
    required this.onReply,
    this.isGroup = false,
  });

  String _fmt(DateTime? dt) {
    if (dt == null) return '';
    return DateFormat('h:mm a').format(dt);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // In groups we look up each sender's live profile dynamically. In 1:1
    // chats we reuse the cached otherAvatar passed into the screen.
    final senderLive =
        isGroup ? ref.watch(userByUidProvider(msg.senderUid)).value : null;
    final senderAvatar =
        isGroup ? ((senderLive?['avatarUrl'] as String?) ?? '') : otherAvatar;
    final senderName =
        isGroup ? ((senderLive?['username'] as String?) ?? 'Member') : '';
    final senderUidForTap = isGroup ? msg.senderUid : otherUid;

    final hasReply = msg.replyToId != null && msg.replyToId!.isNotEmpty;
    final hasVoice = msg.voiceUrl != null && msg.voiceUrl!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            GestureDetector(
              onTap: () => openUserProfile(context, uid: senderUidForTap),
              child: CircleAvatar(
                radius: 16,
                backgroundImage:
                    senderAvatar.isNotEmpty ? NetworkImage(senderAvatar) : null,
                child: senderAvatar.isEmpty
                    ? const Icon(Icons.person, size: 16)
                    : null,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Column(
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (isGroup && !isMe)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2, left: 4),
                  child: Text(
                    senderName,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: context.textSecondary,
                    ),
                  ),
                ),
              GestureDetector(
                onLongPress: () => _showBubbleMenu(context, ref),
                child: Dismissible(
                  key: ValueKey('dismiss-${msg.id}'),
                  direction: isMe
                      ? DismissDirection.endToStart
                      : DismissDirection.startToEnd,
                  confirmDismiss: (_) async {
                    onReply();
                    return false; // never actually dismiss — just trigger reply
                  },
                  background: _replySwipeBg(context, alignLeft: true),
                  secondaryBackground:
                      _replySwipeBg(context, alignLeft: false),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isMe ? const Color(0xFFB05ECC) : context.inputFill,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(16),
                          topRight: const Radius.circular(16),
                          bottomLeft: Radius.circular(isMe ? 16 : 4),
                          bottomRight: Radius.circular(isMe ? 4 : 16),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (hasReply)
                            _RepliedQuote(
                              isMe: isMe,
                              senderUid: msg.replyToSenderUid ?? '',
                              text: msg.replyToText ?? '',
                            ),
                          if (hasVoice)
                            _VoiceMessageBubble(
                              url: msg.voiceUrl!,
                              durationMs: msg.voiceDurationMs,
                              isMe: isMe,
                            )
                          else if (msg.sharedPostId != null &&
                              msg.sharedPostId!.isNotEmpty)
                            _SharedPostPreview(
                              postId: msg.sharedPostId!,
                              isMe: isMe,
                            )
                          else if (msg.imageUrl != null &&
                              msg.imageUrl!.isNotEmpty) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: CachedNetworkImage(
                                imageUrl: msg.imageUrl!,
                                width: 240,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => const SizedBox(
                                  height: 180,
                                  child: Center(
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                ),
                              ),
                            ),
                            if (msg.text.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                msg.text,
                                style: TextStyle(
                                  color:
                                      isMe ? Colors.white : context.textPrimary,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ] else
                            Text(
                              msg.text,
                              style: TextStyle(
                                color:
                                    isMe ? Colors.white : context.textPrimary,
                                fontSize: 14,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              MessageReactionsRow(
                parentPath: 'chats/$chatId/messages',
                messageId: msg.id,
              ),
              if (msg.sharedPostId != null &&
                  msg.sharedPostId!.isNotEmpty &&
                  msg.text.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: Text(
                    msg.text,
                    style: TextStyle(
                      color: context.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    _fmt(msg.createdAt),
                    style: TextStyle(color: context.textMuted, fontSize: 11),
                  ),
                  if (isMe && msg.seenBy.length > 1) ...[
                    const SizedBox(width: 4),
                    Text(
                      'Seen',
                      style: TextStyle(color: context.textMuted, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _replySwipeBg(BuildContext context, {required bool alignLeft}) {
    return Align(
      alignment: alignLeft ? Alignment.centerLeft : Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Icon(Icons.reply, color: context.textSecondary, size: 20),
      ),
    );
  }

  void _showBubbleMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Reply'),
              onTap: () {
                Navigator.pop(sheet);
                onReply();
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_reaction_outlined),
              title: const Text('Add reaction'),
              onTap: () {
                Navigator.pop(sheet);
                showReactionsSheet(
                  context,
                  ref: ref,
                  parentPath: 'chats/$chatId/messages',
                  messageId: msg.id,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Replied-to quote — thin colored bar + preview text shown atop a bubble
// whose sender is replying to another message.
// ─────────────────────────────────────────────

class _RepliedQuote extends ConsumerWidget {
  final bool isMe;
  final String senderUid;
  final String text;

  const _RepliedQuote({
    required this.isMe,
    required this.senderUid,
    required this.text,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final who = ref.watch(userByUidProvider(senderUid)).value;
    final name = (who?['username'] as String?) ?? 'Someone';
    final bg = isMe
        ? Colors.white.withValues(alpha: 0.18)
        : Colors.black.withValues(alpha: 0.05);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: isMe ? Colors.white : const Color(0xFFB05ECC),
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isMe ? Colors.white : const Color(0xFFB05ECC),
            ),
          ),
          Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color:
                  isMe ? Colors.white.withValues(alpha: 0.85) : context.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Voice message bubble — play/pause + duration.
// ─────────────────────────────────────────────

class _VoiceMessageBubble extends StatefulWidget {
  final String url;
  final int? durationMs;
  final bool isMe;

  const _VoiceMessageBubble({
    required this.url,
    required this.durationMs,
    required this.isMe,
  });

  @override
  State<_VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<_VoiceMessageBubble> {
  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration? _duration;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<void>? _completeSub;
  StreamSubscription<Duration>? _durSub;

  @override
  void initState() {
    super.initState();
    _duration = widget.durationMs == null
        ? null
        : Duration(milliseconds: widget.durationMs!);
    _posSub = _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playing = false;
          _position = Duration.zero;
        });
      }
    });
    _durSub = _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _completeSub?.cancel();
    _durSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      setState(() => _playing = false);
    } else {
      await _player.play(UrlSource(widget.url));
      setState(() => _playing = true);
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString();
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final total = _duration ?? Duration.zero;
    final progress = total.inMilliseconds == 0
        ? 0.0
        : (_position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    final fg = widget.isMe ? Colors.white : const Color(0xFFB05ECC);
    final trackBg = widget.isMe
        ? Colors.white.withValues(alpha: 0.35)
        : const Color(0xFFB05ECC).withValues(alpha: 0.25);
    return SizedBox(
      width: 220,
      child: Row(
        children: [
          GestureDetector(
            onTap: _toggle,
            child: Icon(
              _playing
                  ? Icons.pause_circle_filled
                  : Icons.play_circle_fill,
              color: fg,
              size: 32,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: trackBg,
                    valueColor: AlwaysStoppedAnimation(fg),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _playing
                      ? _fmt(_position)
                      : (_duration == null ? '0:00' : _fmt(_duration!)),
                  style: TextStyle(color: fg, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SharedPostPreview extends StatelessWidget {
  final String postId;
  final bool isMe;

  const _SharedPostPreview({
    required this.postId,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final stream =
        FirebaseFirestore.instance.collection('posts').doc(postId).snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        final doc = snapshot.data;
        if (doc == null) {
          return const SizedBox(
            height: 80,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }

        if (!doc.exists) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Original post unavailable'),
          );
        }

        final post = Post.fromDoc(doc);
        final hasImage = post.imageUrls.isNotEmpty;

        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PostDetailScreen(postId: postId),
            ),
          ),
          child: Container(
            width: 240,
            decoration: BoxDecoration(
              color:
                  isMe ? Colors.white.withValues(alpha: 0.12) : context.cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isMe
                    ? Colors.white.withValues(alpha: 0.35)
                    : context.borderColor,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasImage)
                  ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(12)),
                    child: CachedNetworkImage(
                      imageUrl: post.imageUrls.first,
                      height: 140,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.authorUsername,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: isMe ? Colors.white : context.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        post.caption.isEmpty ? 'Shared post' : post.caption,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: isMe ? Colors.white : context.textSecondary,
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

/// Shows "Member of <EventTitle>" under the username when the two users
/// share at least one event group chat. Hidden otherwise.
class _SharedEventLabel extends ConsumerWidget {
  final String meUid;
  final String otherUid;

  const _SharedEventLabel({required this.meUid, required this.otherUid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = '$meUid|$otherUid';
    final async = ref.watch(sharedEventProvider(key));
    // Silently hide on error (e.g. permission-denied from collectionGroup).
    if (async.hasError || !async.hasValue) return const SizedBox.shrink();
    final shared = async.value;
    if (shared == null) return const SizedBox.shrink();
    final title = shared['eventTitle'] ?? '';
    if (title.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: context.purpleSoft,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.groups, size: 11, color: Color(0xFFB05ECC)),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                'Member of $title',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFB05ECC),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
