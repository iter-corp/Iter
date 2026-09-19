import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_strings.dart';
import '../../navigation/user_profile_nav.dart';
import '../../theme/app_theme.dart';
import '../../providers/auth_providers.dart';
import '../../providers/event_chat_providers.dart';
import '../../providers/preferred_language_provider.dart';
import '../../services/event_chat_service.dart';
import '../../services/translate_service.dart';
import '../widgets/mention_text.dart';
import '../widgets/message_reactions_bar.dart';
import '../widgets/poll_widgets.dart';
import '../widgets/skeleton_loader.dart';
import 'event_group_settings_screen.dart';

class EventChatScreen extends ConsumerStatefulWidget {
  final String eventId;
  final String eventTitle;
  final String adminUid;

  const EventChatScreen({
    super.key,
    required this.eventId,
    required this.eventTitle,
    required this.adminUid,
  });

  @override
  ConsumerState<EventChatScreen> createState() => _EventChatScreenState();
}

class _EventChatScreenState extends ConsumerState<EventChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String? get _currentUid => ref.read(authStateProvider).value?.uid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(eventChatServiceProvider).markSeen(widget.eventId);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    await ref.read(eventChatServiceProvider).sendMessage(
          eventId: widget.eventId,
          text: text,
        );
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

  void _openAdminProfile() {
    openUserProfile(context, uid: widget.adminUid);
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EventGroupSettingsScreen(
          eventId: widget.eventId,
          eventTitle: widget.eventTitle,
          adminUid: widget.adminUid,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = _currentUid;
    final isAdmin = currentUid != null && currentUid == widget.adminUid;
    final msgsAsync = ref.watch(eventChatMessagesProvider(widget.eventId));
    final adminLive = ref.watch(userByUidProvider(widget.adminUid)).valueOrNull;
    final adminAvatar = (adminLive?['avatarUrl'] as String?) ?? '';
    final adminName =
        (adminLive?['username'] as String?) ?? context.t.adminLabel;

    ref.listen(eventChatMessagesProvider(widget.eventId), (_, __) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    });

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
                    onTap: _openSettings,
                    child: const CircleAvatar(
                      radius: 18,
                      backgroundColor: Color(0xFFB05ECC),
                      child: Icon(Icons.groups, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: _openSettings,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.eventTitle,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          GestureDetector(
                            onTap: _openAdminProfile,
                            child: Row(
                              children: [
                                if (adminAvatar.isNotEmpty)
                                  CircleAvatar(
                                    radius: 7,
                                    backgroundImage:
                                        CachedNetworkImageProvider(adminAvatar),
                                  ),
                                if (adminAvatar.isNotEmpty)
                                  const SizedBox(width: 4),
                                Text(
                                  context.t.adminPrefix(adminName),
                                  style: const TextStyle(
                                    color: Color(0xFFB05ECC),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _openSettings,
                    icon: const Icon(Icons.more_vert, size: 22),
                  ),
                ],
              ),
            ),

            Divider(height: 1, color: Theme.of(context).dividerColor),

            // Event group chats are NOT end-to-end encrypted in v1.
            // Show a small notice so users don't assume the lock-icon
            // banner from 1:1 chats also covers this surface.
            const _EventChatNotEncryptedNotice(),

            // MESSAGES
            Expanded(
              child: msgsAsync.when(
                loading: () => const SkeletonChatMessages(),
                error: (e, _) =>
                    Center(child: Text(context.t.errorWithMessage(e))),
                data: (msgs) {
                  if (msgs.isEmpty) {
                    return Center(
                      child: Text(
                        context.t.noMessages,
                        style: TextStyle(color: context.textSecondary),
                      ),
                    );
                  }
                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    itemCount: msgs.length,
                    itemBuilder: (context, i) {
                      final msg = msgs[i];
                      return _EventMessageBubble(
                        eventId: widget.eventId,
                        msg: msg,
                        isMe: msg.senderUid == currentUid,
                        isFromAdmin: msg.senderUid == widget.adminUid,
                      );
                    },
                  );
                },
              ),
            ),

            PollsSection(
              parentPath: 'eventChats/${widget.eventId}',
              canCreate: isAdmin,
            ),

            // INPUT / read-only notice
            if (isAdmin)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: context.inputFill,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: TextField(
                          controller: _controller,
                          decoration: InputDecoration(
                            hintText: context.t.broadcastAMessage,
                            hintStyle: TextStyle(
                                color: context.textMuted, fontSize: 14),
                            filled: false,
                            fillColor: Colors.transparent,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
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
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                color: context.purpleSoft,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.lock_outline,
                        size: 14, color: Color(0xFF8A3FB8)),
                    const SizedBox(width: 6),
                    Text(
                      context.t.onlyAdminCanSend,
                      style: const TextStyle(
                        color: Color(0xFF8A3FB8),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
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

class _EventMessageBubble extends ConsumerWidget {
  final String eventId;
  final EventChatMessage msg;
  final bool isMe;
  final bool isFromAdmin;

  const _EventMessageBubble({
    required this.eventId,
    required this.msg,
    required this.isMe,
    required this.isFromAdmin,
  });

  ui.TextDirection _detectTextDirection(String text) {
    for (final r in text.runes) {
      if ((r >= 0x0590 && r <= 0x05FF) || // Hebrew
          (r >= 0x0600 && r <= 0x06FF) || // Arabic
          (r >= 0x0700 && r <= 0x074F) || // Syriac
          (r >= 0x0750 && r <= 0x077F) || // Arabic Supplement
          (r >= 0x0780 && r <= 0x07BF) || // Thaana
          (r >= 0x07C0 && r <= 0x07FF) || // NKo
          (r >= 0x08A0 && r <= 0x08FF) || // Arabic Extended-A
          (r >= 0xFB50 && r <= 0xFDFF) || // Arabic Presentation Forms-A
          (r >= 0xFE70 && r <= 0xFEFF)) { // Arabic Presentation Forms-B
        return ui.TextDirection.rtl;
      }
      if ((r >= 0x0041 && r <= 0x005A) || (r >= 0x0061 && r <= 0x007A)) {
        return ui.TextDirection.ltr;
      }
    }
    return ui.TextDirection.ltr;
  }

  String _fmt(DateTime? dt) {
    if (dt == null) return '';
    return DateFormat('h:mm a').format(dt);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final senderLive = ref.watch(userByUidProvider(msg.senderUid)).valueOrNull;
    final senderName = (senderLive?['username'] as String?) ??
        (isFromAdmin ? context.t.adminLabel : context.t.user);
    final senderAvatar = (senderLive?['avatarUrl'] as String?) ?? '';
    final preferredLang = ref.watch(preferredLanguageProvider);

    Future<void> translateMessage() async {
      final text = msg.text.trim();
      if (text.isEmpty) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _EventChatTranslateSheet(
          text: text,
          target: preferredLang,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMe) ...[
            GestureDetector(
              onTap: () => openUserProfile(context, uid: msg.senderUid),
              child: CircleAvatar(
                radius: 16,
                backgroundImage: senderAvatar.isNotEmpty
                    ? CachedNetworkImageProvider(senderAvatar)
                    : null,
                child: senderAvatar.isEmpty
                    ? const Icon(Icons.person, size: 16)
                    : null,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  Padding(
                    padding:
                        const EdgeInsetsDirectional.only(bottom: 2, start: 4),
                    child: Text(
                      isFromAdmin
                          ? context.t.senderAdmin(senderName)
                          : senderName,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isFromAdmin
                            ? const Color(0xFFB05ECC)
                            : context.textSecondary,
                      ),
                    ),
                  ),
                GestureDetector(
                  onLongPress: () => showReactionsSheet(
                    context,
                    ref: ref,
                    parentPath: 'eventChats/$eventId/messages',
                    messageId: msg.id,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color:
                            isMe ? const Color(0xFFB05ECC) : context.inputFill,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(16),
                          topRight: const Radius.circular(16),
                          bottomLeft: Radius.circular(isMe ? 16 : 4),
                          bottomRight: Radius.circular(isMe ? 4 : 16),
                        ),
                      ),
                      child: (msg.imageUrl != null && msg.imageUrl!.isNotEmpty)
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: CachedNetworkImage(
                                    imageUrl: msg.imageUrl!,
                                    width: 240,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                if (msg.text.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  MentionText(
                                    textDirection: _detectTextDirection(msg.text),
                                    text: msg.text,
                                    style: TextStyle(
                                      color: isMe
                                          ? Colors.white
                                          : context.textPrimary,
                                      fontSize: 14,
                                    ),
                                    mentionStyle: TextStyle(
                                      color: isMe ? Colors.white : const Color(0xFFB05ECC),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ],
                            )
                          : MentionText(
                              textDirection: _detectTextDirection(msg.text),
                              text: msg.text,
                              style: TextStyle(
                                color:
                                    isMe ? Colors.white : context.textPrimary,
                                fontSize: 14,
                              ),
                              mentionStyle: TextStyle(
                                color: isMe ? Colors.white : const Color(0xFFB05ECC),
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                    ),
                  ),
                ),
                MessageReactionsRow(
                  parentPath: 'eventChats/$eventId/messages',
                  messageId: msg.id,
                ),
                if (msg.text.trim().isNotEmpty)
                  TextButton.icon(
                    onPressed: translateMessage,
                    icon: const Icon(Icons.translate, size: 14),
                    label: Text(context.t.translate),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: const Size(0, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                const SizedBox(height: 2),
                Text(
                  _fmt(msg.createdAt),
                  style: TextStyle(color: context.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EventChatTranslateSheet extends StatefulWidget {
  final String text;
  final String target;

  const _EventChatTranslateSheet({
    required this.text,
    required this.target,
  });

  @override
  State<_EventChatTranslateSheet> createState() =>
      _EventChatTranslateSheetState();
}

class _EventChatTranslateSheetState extends State<_EventChatTranslateSheet> {
  late String _target;
  String? _translated;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _target = widget.target;
    _translate();
  }

  Future<void> _translate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final out = await const TranslateService().translateText(
        text: widget.text,
        sourceLang: 'auto',
        targetLang: _target,
      );
      if (!mounted) return;
      setState(() {
        _translated = out;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = TranslateService.userFriendlyErrorMessage(e);
        _loading = false;
      });
    }
  }

  void _selectLang(String code) {
    if (code == _target) return;
    setState(() => _target = code);
    _translate();
  }

  String _labelOf(String code) => kTranslateLanguages
      .firstWhere((l) => l.code == code,
          orElse: () => const TranslateLanguage('?', '?'))
      .label;

  @override
  Widget build(BuildContext context) {
    final seen = <String>{};
    final chipLangs = <TranslateLanguage>[];
    for (final lang in kTranslateLanguages) {
      if (seen.add(lang.code)) chipLangs.add(lang);
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.translate, size: 18),
                const SizedBox(width: 8),
                Text(
                  context.t.commentTranslateTo(_labelOf(_target)),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: chipLangs.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final lang = chipLangs[i];
                  final selected = lang.code == _target;
                  final label = lang.code == 'en' ? 'English' : lang.label;
                  return GestureDetector(
                    onTap: () => _selectLang(lang.code),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFFB05ECC)
                            : Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: selected ? Colors.white : null,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red))
            else
              SelectableText(
                _translated ?? '',
                style: const TextStyle(fontSize: 14, height: 1.4),
              ),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.t.close),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Honest disclosure shown at the top of every event group chat: tells
/// the user this surface is NOT end-to-end encrypted, unlike 1:1 and
/// manually-created group chats. Avoids the false-security trap of
/// users assuming the lock-icon banner from the other chat type also
/// applies here.
class _EventChatNotEncryptedNotice extends StatelessWidget {
  const _EventChatNotEncryptedNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.orange.withValues(alpha: 0.10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.info_outline, size: 14, color: Colors.orange),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              context.t.eventMessagesNotEncrypted,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: context.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
