import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../navigation/user_profile_nav.dart';
import '../../providers/auth_providers.dart';
import '../../providers/chat_providers.dart';
import '../../services/chat_service.dart';
import '../../services/storage_service.dart';
import '../model/post_model.dart';
import '../widgets/post_card.dart';

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
    super.dispose();
  }

  void _onTextChanged(String text) {
    _typingTimer?.cancel();
    final uid = _currentUid;
    if (uid == null) return;
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
    await ref.read(chatServiceProvider).sendMessage(
          chatId: widget.chatId,
          senderUid: uid,
          receiverUid: widget.otherUid,
          text: text,
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
      await ref.read(chatServiceProvider).sendMessage(
            chatId: widget.chatId,
            senderUid: uid,
            receiverUid: widget.otherUid,
            text: '',
            imageUrl: url,
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

  @override
  Widget build(BuildContext context) {
    final presenceAsync = ref.watch(presenceWatchProvider(widget.otherUid));
    final typingAsync =
        ref.watch(typingWatchProvider('${widget.chatId}|${widget.otherUid}'));
    final messagesAsync = ref.watch(messagesProvider(widget.chatId));

    ref.listen(messagesProvider(widget.chatId), (_, __) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    });

    final isOnline = presenceAsync.whenOrNull(data: (p) => p.online) ?? false;
    final isTyping = typingAsync.whenOrNull(data: (t) => t) ?? false;

    return Scaffold(
      backgroundColor: Colors.white,
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
                    onTap: _openOtherProfile,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundImage: widget.otherAvatar.isNotEmpty
                              ? NetworkImage(widget.otherAvatar)
                              : null,
                          child: widget.otherAvatar.isEmpty
                              ? const Icon(Icons.person)
                              : null,
                        ),
                        if (isOnline)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: Colors.white, width: 1.5),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: _openOtherProfile,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.otherName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 15),
                          ),
                          Text(
                            isTyping
                                ? 'Typing...'
                                : isOnline
                                    ? 'Online'
                                    : 'Offline',
                            style: TextStyle(
                              color: isTyping ? Colors.purple : Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.videocam_outlined, size: 24),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.call_outlined, size: 22),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // MESSAGES
            Expanded(
              child: messagesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (msgs) {
                  final currentUid = _currentUid ?? '';
                  if (msgs.isEmpty) {
                    return const Center(
                      child: Text('Say hello!',
                          style: TextStyle(color: Colors.grey)),
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
                        msg: msg,
                        isMe: msg.senderUid == currentUid,
                        otherUid: widget.otherUid,
                        otherAvatar: widget.otherAvatar,
                      );
                    },
                  );
                },
              ),
            ),

            // INPUT
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
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
                        : const Icon(Icons.camera_alt_outlined,
                            color: Colors.grey),
                  ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F0F0),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _controller,
                        onChanged: _onTextChanged,
                        decoration: const InputDecoration(
                          hintText: 'Message...',
                          hintStyle:
                              TextStyle(color: Colors.grey, fontSize: 14),
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _sendMessage,
                    icon: const Icon(Icons.send, color: Color(0xFFB05ECC)),
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

class _MessageBubble extends StatelessWidget {
  final ChatMessage msg;
  final bool isMe;
  final String otherUid;
  final String otherAvatar;

  const _MessageBubble({
    required this.msg,
    required this.isMe,
    required this.otherUid,
    required this.otherAvatar,
  });

  String _fmt(DateTime? dt) {
    if (dt == null) return '';
    return DateFormat('h:mm a').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            GestureDetector(
              onTap: () => openUserProfile(context, uid: otherUid),
              child: CircleAvatar(
                radius: 16,
                backgroundImage:
                    otherAvatar.isNotEmpty ? NetworkImage(otherAvatar) : null,
                child: otherAvatar.isEmpty
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
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isMe
                        ? const Color(0xFFB05ECC)
                        : const Color(0xFFF0F0F0),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isMe ? 16 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 16),
                    ),
                  ),
                  child: (msg.sharedPostId != null &&
                          msg.sharedPostId!.isNotEmpty)
                      ? _SharedPostPreview(
                          postId: msg.sharedPostId!,
                          isMe: isMe,
                        )
                      : (msg.imageUrl != null && msg.imageUrl!.isNotEmpty)
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
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
                                          isMe ? Colors.white : Colors.black,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ],
                            )
                          : Text(
                              msg.text,
                              style: TextStyle(
                                color: isMe ? Colors.white : Colors.black,
                                fontSize: 14,
                              ),
                            ),
                ),
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
                      color: Colors.grey.shade700,
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
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                  if (isMe && msg.seenBy.length > 1) ...[
                    const SizedBox(width: 4),
                    const Text(
                      'Seen',
                      style: TextStyle(color: Colors.grey, fontSize: 11),
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
              builder: (_) => _SharedPostViewScreen(post: post),
            ),
          ),
          child: Container(
            width: 240,
            decoration: BoxDecoration(
              color: isMe ? Colors.white.withValues(alpha: 0.12) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isMe
                    ? Colors.white.withValues(alpha: 0.35)
                    : Colors.grey.shade300,
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
                          color: isMe ? Colors.white : Colors.black,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        post.caption.isEmpty ? 'Shared post' : post.caption,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: isMe ? Colors.white : Colors.black87,
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

class _SharedPostViewScreen extends StatelessWidget {
  final Post post;

  const _SharedPostViewScreen({required this.post});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Post'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: [
          PostCard(post: post),
        ],
      ),
    );
  }
}
