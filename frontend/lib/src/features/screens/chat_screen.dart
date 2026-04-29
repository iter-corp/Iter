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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../navigation/user_profile_nav.dart';
import '../../theme/app_theme.dart';
import '../../providers/auth_providers.dart';
import '../../providers/block_providers.dart';
import '../../providers/chat_providers.dart';
import '../../providers/event_chat_providers.dart';
import '../../providers/reaction_providers.dart';
import '../../services/chat_service.dart';
import '../../services/reaction_service.dart';
import '../../services/storage_service.dart';
import '../../services/translate_service.dart';
import '../model/post_model.dart';
import '../widgets/message_reactions_bar.dart';
import '../widgets/poll_widgets.dart';
import 'chat_media_screen.dart';
import 'group_settings_screen.dart';
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

  // Dictation (speech-to-text) state. Lets the user speak a message and
  // have it transcribed into the text field — they can edit before sending.
  // The platform's SpeechRecognizer uses the device default locale, which
  // is the closest thing to language auto-detection it supports natively.
  final stt.SpeechToText _stt = stt.SpeechToText();
  bool _sttInitialized = false;
  bool _isDictating = false;
  // The text that was already in the field when dictation started, so we
  // append onto it instead of overwriting whatever the user had typed.
  String _dictationBaseText = '';
  // User-selected dictation locale. null = device default. Long-press the
  // dictation button to change.
  String? _dictationLocaleId;

  // Auto-translate incoming messages. Persisted per-chat in SharedPreferences
  // so each chat can have its own preference. _autoTranslateTarget is the
  // language code (e.g., 'en', 'ckb') the partner's messages get translated
  // INTO. The settings sheet is opened from the translate icon in the header.
  bool _autoTranslate = false;
  String _autoTranslateTarget = 'en';

  String? get _currentUid => ref.read(authStateProvider).value?.uid;

  String get _prefsAutoKey => 'chat_autotranslate_${widget.chatId}';
  String get _prefsLangKey => 'chat_autotranslate_lang_${widget.chatId}';

  Future<void> _loadAutoTranslatePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _autoTranslate = prefs.getBool(_prefsAutoKey) ?? false;
      _autoTranslateTarget = prefs.getString(_prefsLangKey) ?? 'en';
    });
  }

  Future<void> _saveAutoTranslatePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsAutoKey, _autoTranslate);
    await prefs.setString(_prefsLangKey, _autoTranslateTarget);
  }

  @override
  void initState() {
    super.initState();
    _loadAutoTranslatePrefs();
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
    if (_isDictating) {
      _stt.stop();
    }
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
    
    try {
      // Check group permissions if this is a group chat
      final chatDoc = ref.read(chatDocProvider(widget.chatId)).value;
      if (chatDoc != null && (chatDoc['kind'] as String?) == 'group') {
        // Check if messaging is restricted
        final restrictMessaging = chatDoc['restrictMessaging'] as bool? ?? false;
        final adminOnly = chatDoc['adminOnly'] as bool? ?? false;
        final admins = (chatDoc['admins'] as List<dynamic>?) ?? [];
        final isAdmin = admins.contains(uid);
        
        if (restrictMessaging && !isAdmin) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Messaging is restricted in this group')),
            );
          }
          return;
        }
        
        if (adminOnly && !isAdmin) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Only admins can message in this group')),
            );
          }
          return;
        }
      }
      
      await ref.read(chatServiceProvider).sendMessage(
            chatId: widget.chatId,
            senderUid: uid,
            receiverUid: widget.otherUid,
            text: text,
            replyToId: reply?.id,
            replyToText: reply == null ? null : _previewOf(reply),
            replyToSenderUid: reply?.senderUid,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send message: $e')),
        );
      }
    }
  }

  Future<void> _pickAndSendImage() async {
    if (_sendingImage) return;
    final uid = _currentUid;
    if (uid == null) return;

    // Check group permissions first
    try {
      final chatDoc = ref.read(chatDocProvider(widget.chatId)).value;
      if (chatDoc != null && (chatDoc['kind'] as String?) == 'group') {
        final mediaShare = chatDoc['mediaShare'] as bool? ?? true;
        final restrictMessaging = chatDoc['restrictMessaging'] as bool? ?? false;
        final adminOnly = chatDoc['adminOnly'] as bool? ?? false;
        final admins = (chatDoc['admins'] as List<dynamic>?) ?? [];
        final isAdmin = admins.contains(uid);
        
        if (!mediaShare) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Media sharing is disabled in this group')),
            );
          }
          return;
        }
        
        if ((restrictMessaging || adminOnly) && !isAdmin) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('You cannot send media in this group')),
            );
          }
          return;
        }
      }
    } catch (e) {
      debugPrint('Error checking group permissions: $e');
    }

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

  Future<void> _startVoiceRecording() async {
    if (_uploadingVoice || _isRecording) return;
    final uid = _currentUid;
    if (uid == null) return;

    // Check group permissions first
    try {
      final chatDoc = ref.read(chatDocProvider(widget.chatId)).value;
      if (chatDoc != null && (chatDoc['kind'] as String?) == 'group') {
        final mediaShare = chatDoc['mediaShare'] as bool? ?? true;
        final restrictMessaging = chatDoc['restrictMessaging'] as bool? ?? false;
        final adminOnly = chatDoc['adminOnly'] as bool? ?? false;
        final admins = (chatDoc['admins'] as List<dynamic>?) ?? [];
        final isAdmin = admins.contains(uid);

        if (!mediaShare) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Media sharing is disabled in this group')),
            );
          }
          return;
        }
        
        if ((restrictMessaging || adminOnly) && !isAdmin) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('You cannot send voice messages in this group')),
            );
          }
          return;
        }
      }
    } catch (e) {
      debugPrint('Error checking group permissions: $e');
    }

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

  Future<void> _stopAndSendVoiceRecording() async {
    debugPrint('[chat-voice] stopAndSend invoked '
        '(isRecording=$_isRecording uploading=$_uploadingVoice)');

    if (!_isRecording || _uploadingVoice) {
      debugPrint('[chat-voice] aborting: not recording or already uploading');
      return;
    }
    final uid = _currentUid;
    if (uid == null) {
      debugPrint('[chat-voice] aborting: no uid');
      return;
    }

    // Stop recording.
    final path = await _recorder.stop();
    final startedAt = _recordStartedAt;
    setState(() {
      _isRecording = false;
      _recordStartedAt = null;
    });
    debugPrint('[chat-voice] recorder.stop() returned path=$path');
    if (path == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to record voice message')),
        );
      }
      return;
    }

    final file = File(path);
    // Validate file exists and has content
    if (!await file.exists()) {
      debugPrint('[chat-voice] file does not exist: $path');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recording file not found')),
        );
      }
      return;
    }

    final fileSize = await file.length();
    debugPrint('[chat-voice] file size = $fileSize bytes');
    if (fileSize == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Voice recording is empty')),
        );
      }
      try {
        await file.delete();
      } catch (_) {}
      return;
    }

    setState(() => _uploadingVoice = true);
    try {
      final durationMs = startedAt == null
          ? null
          : DateTime.now().difference(startedAt).inMilliseconds;
      debugPrint('[chat-voice] computed durationMs=$durationMs');

      // Validate duration - minimum 300ms
      if (durationMs != null && durationMs < 300) {
        debugPrint('[chat-voice] too short, aborting');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Voice message too short (min 300ms)')),
          );
        }
        try {
          await file.delete();
        } catch (_) {}
        return;
      }

      debugPrint('[chat-voice] starting upload to storage…');
      final url = await StorageService()
          .uploadChatAudio(file, widget.chatId);
      debugPrint('[chat-voice] upload returned url=$url');

      if (url.isEmpty) {
        debugPrint('[chat-voice] upload returned EMPTY url');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to upload voice message - empty URL')),
          );
        }
        return;
      }

      final reply = _replyTarget;
      setState(() => _replyTarget = null);
      debugPrint('[chat-voice] writing chat message…');
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
      debugPrint('[chat-voice] sendMessage OK');
    } catch (e, st) {
      debugPrint('[chat-voice] FAILED: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Voice upload failed: $e')),
        );
      }
    } finally {
      // Best-effort cleanup of the temp file.
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
      if (mounted) setState(() => _uploadingVoice = false);
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

  /// Tap-to-dictate: speech-to-text into the message field. The user can
  /// then edit and send. Tap again to stop. Distinct from the hold-to-send
  /// voice-message button (which uploads an audio recording).
  Future<void> _toggleDictation() async {
    if (_isDictating) {
      await _stt.stop();
      if (mounted) setState(() => _isDictating = false);
      return;
    }

    if (!_sttInitialized) {
      _sttInitialized = await _stt.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted) setState(() => _isDictating = false);
          }
        },
        onError: (err) {
          debugPrint('[chat-stt] error: ${err.errorMsg}');
          if (!mounted) return;
          setState(() => _isDictating = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Dictation error: ${err.errorMsg}')),
          );
        },
      );
      if (!_sttInitialized) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Microphone unavailable. Check permission.'),
            ),
          );
        }
        return;
      }
    }

    // Use the user-picked locale (long-press the mic to change). When the
    // user hasn't chosen one we pass null so the engine falls back to its
    // own default — calling _stt.systemLocale() hangs silently on some
    // Android builds and prevents listen() from ever starting.
    final String? localeId = _dictationLocaleId;

    _dictationBaseText = _controller.text;
    setState(() => _isDictating = true);

    await _stt.listen(
      localeId: localeId,
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        cancelOnError: false,
        listenMode: stt.ListenMode.dictation,
      ),
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 4),
      onResult: (result) {
        if (!mounted) return;
        final spoken = result.recognizedWords;
        final separator =
            _dictationBaseText.isEmpty || _dictationBaseText.endsWith(' ')
                ? ''
                : ' ';
        final next = '$_dictationBaseText$separator$spoken';
        _controller.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
        // Keep the typing-indicator behavior in sync with the new text.
        _onTextChanged(next);
      },
    );
  }

  /// Long-press handler on the dictation mic — lets the user pick which
  /// language to dictate in for this chat. Includes an "Auto (device default)"
  /// option that resets back to the system locale.
  Future<void> _pickDictationLocale() async {
    if (!_sttInitialized) {
      _sttInitialized = await _stt.initialize();
      if (!_sttInitialized) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Microphone unavailable. Check permission.'),
            ),
          );
        }
        return;
      }
    }

    final installed = await _stt.locales();
    if (!mounted) return;

    final selected = await showModalBottomSheet<_DictationLocaleChoice>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.auto_awesome),
                title: const Text('Auto (device default)'),
                trailing: _dictationLocaleId == null
                    ? const Icon(Icons.check, color: Color(0xFFB05ECC))
                    : null,
                onTap: () => Navigator.pop(
                  sheetContext,
                  const _DictationLocaleChoice(id: null, label: 'Auto'),
                ),
              ),
              const Divider(height: 1),
              ...installed.map((loc) => ListTile(
                    title: Text(loc.name),
                    subtitle: Text(loc.localeId),
                    trailing: _dictationLocaleId == loc.localeId
                        ? const Icon(Icons.check, color: Color(0xFFB05ECC))
                        : null,
                    onTap: () => Navigator.pop(
                      sheetContext,
                      _DictationLocaleChoice(
                        id: loc.localeId,
                        label: loc.name,
                      ),
                    ),
                  )),
            ],
          ),
        );
      },
    );

    if (selected == null || !mounted) return;
    setState(() {
      _dictationLocaleId = selected.id;
    });
  }

  /// Bottom-sheet shown from the translate icon in the chat header. Lets
  /// the user toggle auto-translate of incoming messages and pick which
  /// language to translate them into. Settings are persisted per-chat.
  Future<void> _openTranslationSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Translation',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Automatically translate the other person\'s messages '
                      'into your preferred language. You can still tap any '
                      'message to see the original.',
                      style: TextStyle(
                          color: Theme.of(sheetContext)
                              .textTheme
                              .bodySmall
                              ?.color,
                          fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Auto-translate incoming messages'),
                      value: _autoTranslate,
                      onChanged: (v) {
                        setSheetState(() {});
                        setState(() => _autoTranslate = v);
                        _saveAutoTranslatePrefs();
                      },
                    ),
                    const SizedBox(height: 8),
                    Builder(
                      builder: (context) {
                        // De-duplicate by language code so the dropdown's
                        // "exactly one item per value" assertion holds.
                        // kTranslateLanguages lists English twice (USA / UK)
                        // for dictation locale variety; the translate
                        // target only cares about the BCP-47 code.
                        final seen = <String>{};
                        final items = <DropdownMenuItem<String>>[];
                        for (final lang in kTranslateLanguages) {
                          if (!seen.add(lang.code)) continue;
                          items.add(DropdownMenuItem(
                            value: lang.code,
                            child: Text(lang.label),
                          ));
                        }
                        return DropdownButtonFormField<String>(
                          initialValue: _autoTranslateTarget,
                          decoration: const InputDecoration(
                            labelText: 'Translate into',
                            border: OutlineInputBorder(),
                          ),
                          items: items,
                          onChanged: (v) {
                            if (v == null) return;
                            setSheetState(() {});
                            setState(() => _autoTranslateTarget = v);
                            _saveAutoTranslatePrefs();
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Whether we've successfully landed at the bottom for the first batch of
  // messages. Until this is true, "scroll to bottom" jumps (no animation)
  // and retries on subsequent frames so layout settling can't leave us
  // parked above the latest message.
  bool _initialScrollDone = false;

  void _scrollToBottom({bool animated = true}) {
    if (!_scrollController.hasClients) {
      // ListView hasn't been built yet. Try again next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToBottom(animated: animated);
      });
      return;
    }
    final target = _scrollController.position.maxScrollExtent;
    if (animated && _initialScrollDone) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(target);
    }

    // The first time messages arrive, image/voice bubbles can still be
    // sizing themselves on the next frame, which grows maxScrollExtent
    // after our first jump. Retry a couple of frames so we end up truly
    // at the latest message even when the bubble heights settle late.
    if (!_initialScrollDone) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final newTarget = _scrollController.position.maxScrollExtent;
        if ((newTarget - _scrollController.offset).abs() > 1) {
          _scrollController.jumpTo(newTarget);
        }
        _initialScrollDone = true;
      });
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
    // Block state. Hide the message composer when either side has
    // blocked the other so the rules-blocked write isn't attempted (and
    // the user understands *why* they can't type).
    final iBlockedThem = !isGroup &&
        widget.otherUid.isNotEmpty &&
        (ref.watch(isBlockedProvider(widget.otherUid)).value ?? false);
    final theyBlockedMe = !isGroup &&
        widget.otherUid.isNotEmpty &&
        (ref.watch(isBlockedByProvider(widget.otherUid)).value ?? false);
    final blockBannerLabel = iBlockedThem
        ? 'You\'ve blocked this user. Unblock from their profile to send messages.'
        : (theyBlockedMe
            ? 'You can\'t reply to this conversation.'
            : null);

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
                  IconButton(
                    tooltip: _autoTranslate
                        ? 'Auto-translate ON ($_autoTranslateTarget)'
                        : 'Translation settings',
                    onPressed: _openTranslationSettings,
                    icon: Icon(
                      _autoTranslate ? Icons.translate : Icons.translate_outlined,
                      color: _autoTranslate
                          ? const Color(0xFFB05ECC)
                          : context.textSecondary,
                    ),
                  ),
                  if (isGroup)
                    IconButton(
                      tooltip: 'Group settings',
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => GroupSettingsScreen(
                              chatId: widget.chatId,
                              groupName: groupName,
                            ),
                          ),
                        );
                      },
                      icon: Icon(
                        Icons.group_outlined,
                        color: context.textSecondary,
                      ),
                    ),
                  IconButton(
                    tooltip: 'Shared media',
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ChatMediaScreen(
                            chatId: widget.chatId,
                            chatTitle: isGroup ? groupName : widget.otherName,
                          ),
                        ),
                      );
                    },
                    icon: Icon(
                      Icons.info_outline,
                      color: context.textSecondary,
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
                        autoTranslate: _autoTranslate,
                        autoTranslateTarget: _autoTranslateTarget,
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

            // INPUT (or block banner)
            if (blockBannerLabel != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: context.inputFill,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: context.borderColor),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.block,
                          size: 18, color: context.textSecondary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          blockBannerLabel,
                          style: TextStyle(
                              color: context.textSecondary, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Padding(
              padding: const EdgeInsets.all(12),
              child: _isRecording
                  ? _RecordingBar(
                      startedAt: _recordStartedAt,
                      onCancel: _cancelRecording,
                      onStop: _stopAndSendVoiceRecording,
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
                            padding: const EdgeInsets.only(left: 16, right: 4),
                            decoration: BoxDecoration(
                              color: context.inputFill,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _controller,
                                    onChanged: _onTextChanged,
                                    decoration: InputDecoration(
                                      hintText: 'Message...',
                                      hintStyle: TextStyle(
                                          color: context.textMuted,
                                          fontSize: 14),
                                      border: InputBorder.none,
                                    ),
                                    onSubmitted: (_) => _sendMessage(),
                                  ),
                                ),
                                // Tap-to-dictate sits INSIDE the input pill so
                                // it reads as a text-input affordance. We use
                                // a plain GestureDetector with opaque hit-test
                                // because IconButton/InkWell inside a
                                // BoxDecoration container was swallowing taps
                                // (gesture arena conflict with Tooltip's
                                // long-press recognizer).
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: _toggleDictation,
                                  onLongPress: _pickDictationLocale,
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Icon(
                                      _isDictating
                                          ? Icons.keyboard_voice
                                          : Icons.keyboard_voice_outlined,
                                      color: _isDictating
                                          ? const Color(0xFFB05ECC)
                                          : context.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        if (_controller.text.trim().isEmpty && !_uploadingVoice)
                          // Tap-to-record voice message. First tap starts
                          // recording (the input row swaps to _RecordingBar
                          // which has its own stop / cancel buttons).
                          GestureDetector(
                            onTap: _startVoiceRecording,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: const Icon(
                                Icons.mic_none,
                                color: Color(0xFFB05ECC),
                                size: 24,
                              ),
                            ),
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
                    style: TextStyle(color: context.textPrimary, fontSize: 13)),
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

class _MessageBubble extends ConsumerStatefulWidget {
  final String chatId;
  final ChatMessage msg;
  final bool isMe;
  final String otherUid;
  final String otherAvatar;
  final bool isGroup;
  final VoidCallback onReply;
  final bool autoTranslate;
  final String autoTranslateTarget;

  const _MessageBubble({
    required this.chatId,
    required this.msg,
    required this.isMe,
    required this.otherUid,
    required this.otherAvatar,
    required this.onReply,
    this.isGroup = false,
    this.autoTranslate = false,
    this.autoTranslateTarget = 'en',
  });

  @override
  ConsumerState<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends ConsumerState<_MessageBubble> {
  // Translated body for this message, computed lazily once auto-translate
  // is on. Null until the request completes (or fails).
  String? _translated;
  // Cache key the translation was generated for: "<targetLang>|<originalText>".
  // Lets us re-translate when the user changes target language without
  // re-translating on every parent rebuild.
  String? _translatedFor;
  bool _translating = false;
  // Per-bubble toggle: when true, show the original even if auto-translate
  // is on. Tap "Show original" / "Show translation" to flip.
  bool _showOriginal = false;
  // Last error from the translation service, surfaced inline so the user
  // knows it failed for this message rather than getting silent fallback.
  String? _translateError;

  // Convenience accessors so the build method reads cleanly.
  ChatMessage get msg => widget.msg;
  bool get isMe => widget.isMe;
  String get otherUid => widget.otherUid;
  String get otherAvatar => widget.otherAvatar;
  bool get isGroup => widget.isGroup;
  VoidCallback get onReply => widget.onReply;

  /// True when the message should be displayed translated. Self-messages and
  /// empty-text messages are never translated, only the partner's prose.
  bool get _shouldTranslate =>
      widget.autoTranslate &&
      !isMe &&
      msg.text.trim().isNotEmpty &&
      !_showOriginal;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeTranslate();
  }

  @override
  void didUpdateWidget(covariant _MessageBubble old) {
    super.didUpdateWidget(old);
    if (old.autoTranslate != widget.autoTranslate ||
        old.autoTranslateTarget != widget.autoTranslateTarget ||
        old.msg.text != widget.msg.text) {
      _maybeTranslate();
    }
  }

  Future<void> _maybeTranslate() async {
    if (!_shouldTranslate) return;
    final cacheKey = '${widget.autoTranslateTarget}|${msg.text}';
    if (_translatedFor == cacheKey) return; // already done
    if (_translating) return;
    setState(() {
      _translating = true;
      _translateError = null;
    });
    try {
      final out = await const TranslateService().translateText(
        text: msg.text,
        sourceLang: 'auto',
        targetLang: widget.autoTranslateTarget,
      );
      if (!mounted) return;
      setState(() {
        _translated = out;
        _translatedFor = cacheKey;
        _translating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _translating = false;
        _translateError = e.toString();
      });
    }
  }

  String _fmt(DateTime? dt) {
    if (dt == null) return '';
    return DateFormat('h:mm a').format(dt);
  }

  /// Builds the text to render for the message body, plus an optional
  /// trailing "Show original" / "Show translation" / loading indicator.
  Widget _buildBody({required Color textColor}) {
    final originalStyle = TextStyle(color: textColor, fontSize: 14);
    if (!widget.autoTranslate || isMe || msg.text.trim().isEmpty) {
      return Text(msg.text, style: originalStyle);
    }

    final body = _showOriginal
        ? msg.text
        : (_translated ?? msg.text); // until translation arrives, show original

    final hintColor = isMe
        ? Colors.white.withValues(alpha: 0.85)
        : const Color(0xFFB05ECC);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(body, style: originalStyle),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_translating)
              SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 1.4,
                  valueColor: AlwaysStoppedAnimation<Color>(hintColor),
                ),
              )
            else
              Icon(Icons.translate, size: 12, color: hintColor),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () {
                if (_translating) return;
                if (_translateError != null) {
                  // Allow a retry by clearing cache marker.
                  setState(() {
                    _translateError = null;
                    _translatedFor = null;
                  });
                  _maybeTranslate();
                  return;
                }
                if (_translated == null) {
                  _maybeTranslate();
                  return;
                }
                setState(() => _showOriginal = !_showOriginal);
              },
              child: Text(
                _translateError != null
                    ? 'Translation failed — tap to retry'
                    : _translating
                        ? 'Translating…'
                        : _showOriginal
                            ? 'Show translation'
                            : 'Show original',
                style: TextStyle(
                  color: hintColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
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
                  secondaryBackground: _replySwipeBg(context, alignLeft: false),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (hasReply)
                            _RepliedQuote(
                              isMe: isMe,
                              senderUid: msg.replyToSenderUid ?? '',
                              text: msg.replyToText ?? '',
                            ),
                          if (msg.storyId != null && msg.storyId!.isNotEmpty)
                            _StoryReplyBanner(
                              isMe: isMe,
                              storyImageUrl: msg.storyImageUrl,
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
                              _buildBody(
                                textColor: isMe
                                    ? Colors.white
                                    : context.textPrimary,
                              ),
                            ],
                          ] else
                            _buildBody(
                              textColor:
                                  isMe ? Colors.white : context.textPrimary,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              MessageReactionsRow(
                parentPath: 'chats/${widget.chatId}/messages',
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
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _fmt(msg.createdAt),
                    style: TextStyle(color: context.textMuted, fontSize: 11),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    _MessageStatusIcon(
                      pending: msg.createdAt == null,
                      seen: msg.seenBy.length > 1,
                      mutedColor: context.textMuted,
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
    final parentPath = 'chats/${widget.chatId}/messages';
    showModalBottomSheet(
      context: context,
      backgroundColor: context.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            // Reactions strip — surfaced at the top so a tap on a
            // message goes straight to picking an emoji, no extra tap
            // through an "Add reaction" item.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Consumer(
                builder: (context, sheetRef, _) {
                  final myAsync = sheetRef.watch(myReactionProvider(
                    '$parentPath::${msg.id}',
                  ));
                  final mine = myAsync.value;
                  return SizedBox(
                    height: 56,
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
                            await sheetRef
                                .read(reactionServiceProvider)
                                .toggle(
                                  parentPath: parentPath,
                                  messageId: msg.id,
                                  emoji: e,
                                );
                            if (sheet.mounted) Navigator.pop(sheet);
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
                            child:
                                Text(e, style: const TextStyle(fontSize: 28)),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Reply'),
              onTap: () {
                Navigator.pop(sheet);
                onReply();
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
              color: isMe
                  ? Colors.white.withValues(alpha: 0.85)
                  : context.textSecondary,
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

  Future<void> _seekTo(double progress) async {
    final total = _duration;
    if (total == null || total.inMilliseconds == 0) return;
    final target = Duration(
      milliseconds: (total.inMilliseconds * progress.clamp(0.0, 1.0)).round(),
    );
    await _player.seek(target);
    if (mounted) setState(() => _position = target);
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
      width: 240,
      child: Row(
        children: [
          GestureDetector(
            onTap: _toggle,
            child: Icon(
              _playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
              color: fg,
              size: 32,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _WaveformScrubber(
                  url: widget.url,
                  progress: progress,
                  fg: fg,
                  trackBg: trackBg,
                  onSeek: _seekTo,
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

/// WhatsApp-style waveform scrubber for voice messages. We don't decode the
/// audio file (would need a heavy native dependency), so bar heights are a
/// deterministic pseudo-random pattern derived from the URL — same URL
/// always gets the same waveform, so it doesn't reshuffle on rebuild.
/// Tapping or horizontal-dragging seeks playback.
class _WaveformScrubber extends StatelessWidget {
  final String url;
  final double progress;
  final Color fg;
  final Color trackBg;
  final ValueChanged<double> onSeek;

  const _WaveformScrubber({
    required this.url,
    required this.progress,
    required this.fg,
    required this.trackBg,
    required this.onSeek,
  });

  static List<double> _heightsFor(String url) {
    const barCount = 38;
    var seed = url.hashCode & 0x7fffffff;
    final out = <double>[];
    for (var i = 0; i < barCount; i++) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      final v = (seed % 1000) / 1000.0;
      out.add(0.25 + v * 0.75);
    }
    return out;
  }

  void _handleSeek(BuildContext context, Offset localPosition) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final width = box.size.width;
    if (width <= 0) return;
    onSeek((localPosition.dx / width).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (innerContext) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _handleSeek(innerContext, d.localPosition),
        onHorizontalDragUpdate: (d) =>
            _handleSeek(innerContext, d.localPosition),
        child: SizedBox(
          height: 28,
          child: CustomPaint(
            painter: _WaveformPainter(
              heights: _heightsFor(url),
              progress: progress,
              fg: fg,
              trackBg: trackBg,
            ),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> heights;
  final double progress;
  final Color fg;
  final Color trackBg;

  _WaveformPainter({
    required this.heights,
    required this.progress,
    required this.fg,
    required this.trackBg,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (heights.isEmpty) return;
    const barWidth = 2.5;
    final gap =
        (size.width - barWidth * heights.length) / (heights.length - 1);
    final centerY = size.height / 2;
    final progressX = size.width * progress;

    final activePaint = Paint()
      ..color = fg
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barWidth;
    final inactivePaint = Paint()
      ..color = trackBg
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barWidth;

    for (var i = 0; i < heights.length; i++) {
      final x = i * (barWidth + gap) + barWidth / 2;
      final h = heights[i] * (size.height - 4);
      final paint = x <= progressX ? activePaint : inactivePaint;
      canvas.drawLine(
        Offset(x, centerY - h / 2),
        Offset(x, centerY + h / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      old.progress != progress ||
      old.fg != fg ||
      old.trackBg != trackBg ||
      old.heights != heights;
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

/// Carries the user's dictation-language pick out of the bottom sheet.
/// `id` is null for "Auto (device default)".
class _DictationLocaleChoice {
  final String? id;
  final String label;
  const _DictationLocaleChoice({required this.id, required this.label});
}

/// Small WhatsApp-style status icon for own messages:
///   • clock      — pending write (no server timestamp yet)
///   • single ✓   — sent / delivered (written to Firestore)
///   • double ✓✓  — seen (recipient has the message in their seenBy list)
/// The seen state shows in the brand purple to draw the eye.
class _MessageStatusIcon extends StatelessWidget {
  final bool pending;
  final bool seen;
  final Color mutedColor;
  const _MessageStatusIcon({
    required this.pending,
    required this.seen,
    required this.mutedColor,
  });

  @override
  Widget build(BuildContext context) {
    if (pending) {
      return Icon(Icons.access_time, size: 12, color: mutedColor);
    }
    if (seen) {
      return const Icon(Icons.done_all, size: 14, color: Color(0xFFB05ECC));
    }
    return Icon(Icons.done_all, size: 14, color: mutedColor);
  }
}

/// Header rendered at the top of a message bubble when the message was sent
/// in response to a story. Shows a thin "Replied to story" line and, when
/// the original story image URL is available, a tiny rounded thumbnail so
/// the recipient knows exactly which story prompted the reply/reaction.
class _StoryReplyBanner extends StatelessWidget {
  final bool isMe;
  final String? storyImageUrl;
  const _StoryReplyBanner({
    required this.isMe,
    this.storyImageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final fg = isMe
        ? Colors.white.withValues(alpha: 0.85)
        : const Color(0xFFB05ECC);
    final bg = isMe
        ? Colors.white.withValues(alpha: 0.15)
        : Colors.black.withValues(alpha: 0.05);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(color: fg, width: 3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (storyImageUrl != null && storyImageUrl!.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedNetworkImage(
                imageUrl: storyImageUrl!,
                width: 28,
                height: 36,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  width: 28,
                  height: 36,
                  color: Colors.black12,
                ),
                errorWidget: (_, __, ___) => Container(
                  width: 28,
                  height: 36,
                  color: Colors.black26,
                  child:
                      Icon(Icons.broken_image, size: 14, color: fg),
                ),
              ),
            )
          else
            Icon(Icons.auto_stories, size: 14, color: fg),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'Replied to story',
              style: TextStyle(
                color: fg,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
