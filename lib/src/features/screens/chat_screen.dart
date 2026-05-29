import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:open_filex/open_filex.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:video_player/video_player.dart';

import '../../l10n/app_strings.dart';
import '../../navigation/user_profile_nav.dart';
import '../../theme/app_theme.dart';
import '../../providers/auth_providers.dart';
import '../../providers/block_providers.dart';
import '../../providers/chat_providers.dart';
import '../../providers/event_chat_providers.dart';
import '../../providers/preferred_language_provider.dart';
import '../../providers/reaction_providers.dart';
import '../../services/chat_service.dart';
import '../../services/reaction_service.dart';
import '../../services/storage_service.dart';
import '../../services/story_service.dart';
import '../../services/translate_service.dart';
import '../../utils/app_feedback.dart';
import '../../utils/maps_links.dart';
import '../model/post_model.dart';
import '../widgets/location_map.dart';
import '../widgets/message_reactions_bar.dart';
import '../widgets/poll_widgets.dart';
import 'chat_media_screen.dart';
import 'group_settings_screen.dart';
import 'post_detail_screen.dart';
import 'story_viewer_screen.dart';
import '../widgets/sticker_picker_sheet.dart';

// Pick a text direction from the first strong-directional codepoint in
// [text]. Falls back to LTR for empty / neutral-only strings so the
// caret sits on the left while the user is choosing what to type.
// Covers the standard RTL Unicode blocks: Hebrew, Arabic (incl. Supplement
// and Extended-A), Syriac, Thaana, NKo, and the Arabic Presentation Forms.
ui.TextDirection _detectTextDirection(String text) {
  for (final r in text.runes) {
    if ((r >= 0x0590 && r <= 0x05FF) || // Hebrew
        (r >= 0x0600 && r <= 0x06FF) || // Arabic
        (r >= 0x0700 && r <= 0x074F) || // Syriac
        (r >= 0x0750 && r <= 0x077F) || // Arabic Supplement
        (r >= 0x0780 && r <= 0x07BF) || // Thaana
        (r >= 0x07C0 && r <= 0x07FF) || // NKo
        (r >= 0x08A0 && r <= 0x08FF) || // Arabic Extended-A
        (r >= 0xFB1D && r <= 0xFDFF) || // Hebrew + Arabic Presentation Forms-A
        (r >= 0xFE70 && r <= 0xFEFF)) {
      // Arabic Presentation Forms-B
      return ui.TextDirection.rtl;
    }
  }
  return ui.TextDirection.ltr;
}

/// Choices surfaced by [_MessageBubbleState._showAttachMenu]. Kept at
/// top-level so it can be returned from the modal sheet.
enum _AttachKind { image, video, file }

/// What `_showAttachMenu` resolved to. Location is split out from
/// [_AttachKind] because it has no file-upload / pending-bubble path.
enum _AttachChoice { image, video, file, location }

enum _PendingStatus { uploading, sending, failed }

/// In-flight attachment being sent. Rendered as an outgoing bubble while
/// the upload + Firestore write run, so the user sees their send instantly
/// and watches its status update. Once the real message arrives over the
/// Firestore stream, the matching pending entry is removed.
class _PendingAttachment {
  final String localId;
  final _AttachKind kind;
  final File file;
  final String fileName;
  final int sizeBytes;
  _PendingStatus status = _PendingStatus.uploading;
  String? errorMessage;

  _PendingAttachment({
    required this.localId,
    required this.kind,
    required this.file,
    required this.fileName,
    required this.sizeBytes,
  });
}

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
  // Hard cap for any chat attachment (file or video). 1 GB.
  static const int _kMaxAttachmentBytes = 1024 * 1024 * 1024;

  final TextEditingController _controller = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  Timer? _typingTimer;
  bool _isInputFocused = false;

  /// Number of messages we last rendered for the current chat. Whenever
  /// the live Firestore list returns a longer list than this — typical
  /// when the cached snapshot was shorter than the server's truth, or
  /// when a new message arrives — we re-snap to the bottom so the
  /// newest message stays in view instead of being pushed off-screen
  /// by the prepended history.
  int _lastRenderedCount = 0;

  /// Distance from the bottom of the rendered content at the moment of
  /// the *previous* messages-list emission. The standard
  /// `maxScrollExtent - offset` check fails when the list grows
  /// between frames (you were at the bottom of a 20-message list,
  /// then the list becomes 50 messages — your offset is the same but
  /// you're suddenly 2000px from the new bottom). Tracking distance
  /// across emissions instead lets us correctly say "user was at the
  /// bottom" and re-snap.
  double _lastDistanceFromBottom = double.infinity;

  /// Per-message GlobalKeys so [_scrollToMessage] can jump back to the
  /// original of a reply. Stale entries are cleared on rebuild because
  /// we only insert keys for messages currently rendered.
  final Map<String, GlobalKey> _messageKeys = {};

  /// Latest ordered message ids (oldest -> newest) from the stream,
  /// used to seek a replied-to message even when its widget is off-screen.
  final List<String> _messageOrder = [];

  /// id of the message currently flashing as the result of a reply
  /// quote tap. The bubble paints a brief highlight tween while this
  /// is set so the user can see *which* message we landed on.
  String? _flashedMessageId;

  // Reply state — the message currently being replied to (null when none).
  ChatMessage? _replyTarget;

  // Outgoing attachments currently uploading or being sent. Rendered as
  // bubbles below the real message stream so the user sees their send
  // instantly with a live status indicator.
  final List<_PendingAttachment> _pending = [];
  bool _markingSeen = false;
  bool _showStickerPicker = false;
  DateTime? _lastMarkSeenAt;

  // In-flight guard for text/sticker/location sends. The UI for media
  // sends already gates on the pending-attachment list, so this flag is
  // only consulted by paths that don't add a [_PendingAttachment].
  bool _sendInFlight = false;

  void _addPending(_PendingAttachment p) {
    setState(() => _pending.add(p));
  }

  void _updatePending(String localId, {_PendingStatus? status, String? error}) {
    final i = _pending.indexWhere((p) => p.localId == localId);
    if (i < 0) return;
    setState(() {
      if (status != null) _pending[i].status = status;
      if (error != null) _pending[i].errorMessage = error;
    });
  }

  void _removePending(String localId) {
    setState(() => _pending.removeWhere((p) => p.localId == localId));
  }

  /// Re-run the upload+send pipeline for a pending entry that previously
  /// failed. The reply target is intentionally not re-applied — by the
  /// time the user retries, the original reply context may be stale.
  void _retryPending(_PendingAttachment pending) {
    final uid = _currentUid;
    if (uid == null) return;
    _updatePending(pending.localId,
        status: _PendingStatus.uploading, error: '');
    switch (pending.kind) {
      case _AttachKind.image:
        unawaited(_runImageUpload(uid: uid, pending: pending, reply: null));
        break;
      case _AttachKind.video:
        unawaited(_runVideoUpload(uid: uid, pending: pending, reply: null));
        break;
      case _AttachKind.file:
        unawaited(_runFileUpload(uid: uid, pending: pending, reply: null));
        break;
    }
  }

  // Voice recording state.
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  DateTime? _recordStartedAt;
  bool _uploadingVoice = false;
  // Live transcript captured by the on-device speech recognizer while
  // the voice message is being recorded. Saved alongside the audio
  // URL so the receiver can read or translate the message without
  // waiting for a server-side transcription job.
  final stt.SpeechToText _voiceStt = stt.SpeechToText();
  bool _voiceSttInitialized = false;
  String _voiceTranscript = '';

  // Dictation (speech-to-text) state. Lets the user speak a message and
  // have it transcribed into the text field — they can edit before sending.
  // The platform's SpeechRecognizer uses the device default locale, which
  // is the closest thing to language auto-detection it supports natively.
  final stt.SpeechToText _stt = stt.SpeechToText();
  // bool _sttInitialized = false;  // TODO: Re-enable when _toggleDictation is uncommented
  bool _isDictating = false;
  // The text that was already in the field when dictation started, so we
  // append onto it instead of overwriting whatever the user had typed.
  // String _dictationBaseText = '';  // TODO: Re-enable when _toggleDictation is uncommented
  // User-selected dictation locale. null = device default. Long-press the
  // dictation button to change.
  // String? _dictationLocaleId;  // TODO: Re-enable when _pickDictationLocale is uncommented

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

  Future<void> _markSeenNow() async {
    final uid = _currentUid;
    if (uid == null || _markingSeen) return;
    final now = DateTime.now();
    if (_lastMarkSeenAt != null &&
        now.difference(_lastMarkSeenAt!) < const Duration(milliseconds: 700)) {
      return;
    }

    _markingSeen = true;
    _lastMarkSeenAt = now;
    try {
      await ref
          .read(chatServiceProvider)
          .markSeen(chatId: widget.chatId, uid: uid);
    } catch (_) {
      // Best-effort read receipt update; ignore transient failures.
    } finally {
      _markingSeen = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _messageFocusNode.addListener(() {
      if (!mounted) return;
      setState(() => _isInputFocused = _messageFocusNode.hasFocus);
    });
    // Track the user's scroll position so the next data emission can
    // distinguish "user was at the bottom, snap to new bottom" from
    // "user scrolled up to read history, don't disturb them."
    _scrollController.addListener(_captureDistanceFromBottom);
    _loadAutoTranslatePrefs();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final uid = _currentUid;
      if (uid == null) return;
      // Presence is owned by the app-lifecycle observer in main.dart, which
      // now keeps a heartbeat running while the user is foregrounded. We no
      // longer call setOnline() here — doing so would spin up a second,
      // never-stopped heartbeat on a different PresenceService instance.
      unawaited(_markSeenNow());
    });
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _controller.dispose();
    _messageFocusNode.dispose();
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
        // Guard against the user navigating away during the 2s window —
        // ref.read on a torn-down widget throws.
        if (!mounted) return;
        ref.read(typingServiceProvider).setTyping(widget.chatId, uid, false);
      });
    } else {
      ref.read(typingServiceProvider).setTyping(widget.chatId, uid, false);
    }
  }

  Future<void> _sendMessage() async {
    if (_sendInFlight) return;
    final text = _controller.text.trim();
    final uid = _currentUid;
    if (text.isEmpty || uid == null) return;

    // Permission check happens BEFORE we touch the input so a blocked
    // user doesn't lose what they typed.
    final chatDoc = ref.read(chatDocProvider(widget.chatId)).value;
    if (chatDoc != null && (chatDoc['kind'] as String?) == 'group') {
      final restrictMessaging = chatDoc['restrictMessaging'] as bool? ?? false;
      final adminOnly = chatDoc['adminOnly'] as bool? ?? false;
      final admins = (chatDoc['admins'] as List<dynamic>?) ?? [];
      final isAdmin = admins.contains(uid);

      if (restrictMessaging && !isAdmin) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(context.t.messagingRestrictedGroup)),
          );
        }
        return;
      }
      if (adminOnly && !isAdmin) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(context.t.onlyAdminsCanMessage)),
          );
        }
        return;
      }
    }

    _typingTimer?.cancel();
    ref.read(typingServiceProvider).setTyping(widget.chatId, uid, false);
    _controller.clear();
    final reply = _replyTarget;
    setState(() {
      _replyTarget = null;
      _sendInFlight = true;
    });

    try {
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
      // Restore what the user typed + their reply context so they can
      // retry without re-typing or re-quoting.
      if (mounted) {
        _controller.text = text;
        _controller.selection =
            TextSelection.collapsed(offset: _controller.text.length);
        setState(() => _replyTarget = reply);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t.failedToSendMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _sendInFlight = false);
    }
  }

  /// Returns true if the current user can send media in this chat.
  /// Centralizes the group restrictMessaging / adminOnly / mediaShare
  /// checks so image / video / file flows all share the same gate.
  bool _checkCanSendMedia() {
    final uid = _currentUid;
    if (uid == null) return false;
    try {
      final chatDoc = ref.read(chatDocProvider(widget.chatId)).value;
      if (chatDoc != null && (chatDoc['kind'] as String?) == 'group') {
        final mediaShare = chatDoc['mediaShare'] as bool? ?? true;
        final restrictMessaging =
            chatDoc['restrictMessaging'] as bool? ?? false;
        final adminOnly = chatDoc['adminOnly'] as bool? ?? false;
        final admins = (chatDoc['admins'] as List<dynamic>?) ?? [];
        final isAdmin = admins.contains(uid);

        if (!mediaShare) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(context.t.mediaSharingDisabledGroup)),
            );
          }
          return false;
        }
        if ((restrictMessaging || adminOnly) && !isAdmin) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(context.t.cannotSendMediaGroup)),
            );
          }
          return false;
        }
      }
    } catch (e) {
      debugPrint('Error checking group permissions: $e');
    }
    return true;
  }

  /// Bottom sheet listing the supported attachment types. Replaces the
  /// old "tap camera = open gallery" flow so users can also send videos
  /// and arbitrary files.
  Future<void> _showAttachMenu() async {
    if (!_checkCanSendMedia()) return;
    final choice = await showModalBottomSheet<_AttachChoice>(
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
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.borderColor,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 4),
            ListTile(
              leading:
                  const Icon(Icons.image_outlined, color: Color(0xFFB05ECC)),
              title: Text(context.t.photo),
              onTap: () => Navigator.pop(sheet, _AttachChoice.image),
            ),
            ListTile(
              leading:
                  const Icon(Icons.videocam_outlined, color: Color(0xFFB05ECC)),
              title: Text(context.t.video),
              onTap: () => Navigator.pop(sheet, _AttachChoice.video),
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined,
                  color: Color(0xFFB05ECC)),
              title: Text(context.t.fileLabel),
              subtitle: Text(
                context.t.fileSubtitle,
                style: const TextStyle(fontSize: 12),
              ),
              onTap: () => Navigator.pop(sheet, _AttachChoice.file),
            ),
            ListTile(
              leading: const Icon(Icons.location_on_outlined,
                  color: Color(0xFFB05ECC)),
              title: Text(context.t.locationLabel),
              subtitle: Text(
                context.t.locationSubtitle,
                style: const TextStyle(fontSize: 12),
              ),
              onTap: () => Navigator.pop(sheet, _AttachChoice.location),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    switch (choice) {
      case _AttachChoice.image:
        await _pickAndSendImage();
        break;
      case _AttachChoice.video:
        await _pickAndSendVideo();
        break;
      case _AttachChoice.file:
        await _pickAndSendFile();
        break;
      case _AttachChoice.location:
        await _shareCurrentLocation();
        break;
      case null:
        return;
    }
  }

  Future<void> _shareCurrentLocation() async {
    final uid = _currentUid;
    if (uid == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (mounted) {
          AppFeedback.showErrorOn(
            messenger,
            context.t.locationServicesOff,
          );
        }
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) {
          AppFeedback.showErrorOn(messenger, context.t.locationPermDenied);
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.medium),
      );

      // Best-effort reverse geocode for a human-readable label.
      String? label;
      try {
        final marks =
            await geo.placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (marks.isNotEmpty) {
          final p = marks.first;
          final parts = <String>[
            (p.name ?? '').trim(),
            (p.locality ?? p.subAdministrativeArea ?? '').trim(),
          ].where((s) => s.isNotEmpty).toList();
          if (parts.isNotEmpty) label = parts.join(', ');
        }
      } catch (_) {}

      final reply = _replyTarget;
      try {
        await ref.read(chatServiceProvider).sendMessage(
              chatId: widget.chatId,
              senderUid: uid,
              receiverUid: widget.otherUid,
              text: '',
              locationLat: pos.latitude,
              locationLng: pos.longitude,
              locationLabel: label,
              replyToId: reply?.id,
              replyToText: reply == null ? null : _previewOf(reply),
              replyToSenderUid: reply?.senderUid,
            );
        if (mounted) setState(() => _replyTarget = null);
        if (mounted) {
          AppFeedback.showSuccessOn(messenger, context.t.locationShared);
        }
      } catch (e) {
        // Reply context is intentionally preserved so the user can retry
        // the location share with the same quote.
        if (mounted) {
          AppFeedback.showErrorOn(
              messenger, context.t.couldNotShareLocation(e));
        }
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.showErrorOn(
            messenger, context.t.couldNotShareLocation(e));
      }
    }
  }

  Future<void> _pickAndSendImage() async {
    final uid = _currentUid;
    if (uid == null || !_checkCanSendMedia()) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (picked == null) return;
    if (!mounted) return;

    final size = await File(picked.path).length();
    if (!mounted) return;

    final confirmed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _AttachmentPreviewScreen(
          kind: _AttachKind.image,
          file: File(picked.path),
          fileName: picked.name,
          fileSizeBytes: size,
          recipient: widget.otherName,
        ),
      ),
    );
    if (confirmed != true) return;

    final reply = _replyTarget;
    setState(() => _replyTarget = null);
    final pending = _PendingAttachment(
      localId: 'p_${DateTime.now().microsecondsSinceEpoch}',
      kind: _AttachKind.image,
      file: File(picked.path),
      fileName: picked.name,
      sizeBytes: size,
    );
    _addPending(pending);
    unawaited(_runImageUpload(uid: uid, pending: pending, reply: reply));
  }

  Future<void> _runImageUpload({
    required String uid,
    required _PendingAttachment pending,
    required ChatMessage? reply,
  }) async {
    try {
      final url =
          await StorageService().uploadChatImage(pending.file, widget.chatId);
      _updatePending(pending.localId, status: _PendingStatus.sending);
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
      _removePending(pending.localId);
    } catch (e) {
      _updatePending(pending.localId,
          status: _PendingStatus.failed, error: e.toString());
    }
  }

  Future<void> _pickAndSendVideo() async {
    final uid = _currentUid;
    if (uid == null || !_checkCanSendMedia()) return;

    final picker = ImagePicker();
    final picked = await picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 5),
    );
    if (picked == null) return;

    final videoSize = await picked.length();
    if (videoSize > _kMaxAttachmentBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(context.t.videoTooLarge)),
        );
      }
      return;
    }
    if (!mounted) return;

    final confirmed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _AttachmentPreviewScreen(
          kind: _AttachKind.video,
          file: File(picked.path),
          fileName: picked.name,
          fileSizeBytes: videoSize,
          recipient: widget.otherName,
        ),
      ),
    );
    if (confirmed != true) return;

    final reply = _replyTarget;
    setState(() => _replyTarget = null);
    final pending = _PendingAttachment(
      localId: 'p_${DateTime.now().microsecondsSinceEpoch}',
      kind: _AttachKind.video,
      file: File(picked.path),
      fileName: picked.name,
      sizeBytes: videoSize,
    );
    _addPending(pending);
    unawaited(_runVideoUpload(uid: uid, pending: pending, reply: reply));
  }

  Future<void> _runVideoUpload({
    required String uid,
    required _PendingAttachment pending,
    required ChatMessage? reply,
  }) async {
    try {
      final url =
          await StorageService().uploadChatVideo(pending.file, widget.chatId);
      _updatePending(pending.localId, status: _PendingStatus.sending);
      await ref.read(chatServiceProvider).sendMessage(
            chatId: widget.chatId,
            senderUid: uid,
            receiverUid: widget.otherUid,
            text: '',
            videoUrl: url,
            replyToId: reply?.id,
            replyToText: reply == null ? null : _previewOf(reply),
            replyToSenderUid: reply?.senderUid,
          );
      _removePending(pending.localId);
    } catch (e) {
      _updatePending(pending.localId,
          status: _PendingStatus.failed, error: e.toString());
    }
  }

  Future<void> _pickAndSendFile() async {
    final uid = _currentUid;
    if (uid == null || !_checkCanSendMedia()) return;

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const [
          'pdf',
          'doc',
          'docx',
          'xls',
          'xlsx',
          'ppt',
          'pptx',
          'txt',
          'rtf',
          'csv',
          'zip',
        ],
        withData: false,
        allowMultiple: false,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t.couldNotOpenFilePicker(e))),
        );
      }
      return;
    }
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    final path = picked.path;
    if (path == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t.couldNotReadFile)),
        );
      }
      return;
    }
    if (picked.size > _kMaxAttachmentBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t.fileTooLarge)),
        );
      }
      return;
    }
    if (!mounted) return;

    final confirmed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _AttachmentPreviewScreen(
          kind: _AttachKind.file,
          file: File(path),
          fileName: picked.name,
          fileSizeBytes: picked.size,
          recipient: widget.otherName,
        ),
      ),
    );
    if (confirmed != true) return;

    final reply = _replyTarget;
    setState(() => _replyTarget = null);
    final pending = _PendingAttachment(
      localId: 'p_${DateTime.now().microsecondsSinceEpoch}',
      kind: _AttachKind.file,
      file: File(path),
      fileName: picked.name,
      sizeBytes: picked.size,
    );
    _addPending(pending);
    unawaited(_runFileUpload(uid: uid, pending: pending, reply: reply));
  }

  Future<void> _runFileUpload({
    required String uid,
    required _PendingAttachment pending,
    required ChatMessage? reply,
  }) async {
    try {
      final url =
          await StorageService().uploadChatFile(pending.file, widget.chatId);
      _updatePending(pending.localId, status: _PendingStatus.sending);
      await ref.read(chatServiceProvider).sendMessage(
            chatId: widget.chatId,
            senderUid: uid,
            receiverUid: widget.otherUid,
            text: '',
            fileUrl: url,
            fileName: pending.fileName,
            fileMimeType: _mimeFromName(pending.fileName),
            fileSizeBytes: pending.sizeBytes,
            replyToId: reply?.id,
            replyToText: reply == null ? null : _previewOf(reply),
            replyToSenderUid: reply?.senderUid,
          );
      _removePending(pending.localId);
    } catch (e) {
      _updatePending(pending.localId,
          status: _PendingStatus.failed, error: e.toString());
    }
  }

  static String? _mimeFromName(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0) return null;
    final ext = name.substring(dot + 1).toLowerCase();
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'txt':
        return 'text/plain';
      case 'zip':
        return 'application/zip';
      default:
        return 'application/octet-stream';
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
        final restrictMessaging =
            chatDoc['restrictMessaging'] as bool? ?? false;
        final adminOnly = chatDoc['adminOnly'] as bool? ?? false;
        final admins = (chatDoc['admins'] as List<dynamic>?) ?? [];
        final isAdmin = admins.contains(uid);

        if (!mediaShare) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(context.t.mediaSharingDisabledGroup)),
            );
          }
          return;
        }

        if ((restrictMessaging || adminOnly) && !isAdmin) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(context.t.cannotSendVoiceGroup)),
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
          SnackBar(content: Text(context.t.microphonePermissionDenied)),
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
    // Best-effort live transcription. Both the recorder and the
    // speech recognizer want the mic, so on platforms where the
    // recognizer can't piggyback we just fall through with an empty
    // transcript — the audio still uploads fine.
    _voiceTranscript = '';
    unawaited(_startVoiceTranscription());
    setState(() {
      _isRecording = true;
      _recordStartedAt = DateTime.now();
    });
  }

  Future<void> _startVoiceTranscription() async {
    try {
      if (!_voiceSttInitialized) {
        _voiceSttInitialized = await _voiceStt.initialize(
          onError: (e) =>
              debugPrint('[chat-voice-stt] init error: ${e.errorMsg}'),
        );
      }
      if (!_voiceSttInitialized) return;
      // Match the user's preferred language so the recognizer picks
      // the right model. Fallback locale = device default.
      final lang = ref.read(preferredLanguageProvider);
      final localeId = _localeIdForLang(lang);
      await _voiceStt.listen(
        localeId: localeId,
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: stt.ListenMode.dictation,
        ),
        listenFor: const Duration(minutes: 5),
        pauseFor: const Duration(seconds: 6),
        onResult: (result) {
          _voiceTranscript = result.recognizedWords;
        },
      );
    } catch (e) {
      debugPrint('[chat-voice-stt] start failed: $e');
    }
  }

  /// Map a BCP-47 translate code to a speech-to-text locale id. The
  /// translate list uses short codes ("en"); the recognizer needs the
  /// full locale ("en_US"). Falls back to null (device default) for
  /// codes we don't have a mapping for.
  String? _localeIdForLang(String code) {
    for (final l in kTranslateLanguages) {
      if (l.code == code && l.stt != null) return l.stt;
    }
    return null;
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

    // Stop recording + the live transcript recognizer.
    final path = await _recorder.stop();
    try {
      if (_voiceStt.isListening) await _voiceStt.stop();
    } catch (_) {}
    final transcript = _voiceTranscript.trim();
    final startedAt = _recordStartedAt;
    setState(() {
      _isRecording = false;
      _recordStartedAt = null;
    });
    debugPrint('[chat-voice] recorder.stop() returned path=$path');
    if (path == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t.failedToRecordVoice)),
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
          SnackBar(content: Text(context.t.recordingFileNotFound)),
        );
      }
      return;
    }

    final fileSize = await file.length();
    debugPrint('[chat-voice] file size = $fileSize bytes');
    if (fileSize == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t.voiceRecordingEmpty)),
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
            SnackBar(
                content: Text(context.t.voiceMessageTooShort)),
          );
        }
        try {
          await file.delete();
        } catch (_) {}
        return;
      }

      debugPrint('[chat-voice] starting upload to storage…');
      final url = await StorageService().uploadChatAudio(file, widget.chatId);
      debugPrint('[chat-voice] upload returned url=$url');

      if (url.isEmpty) {
        debugPrint('[chat-voice] upload returned EMPTY url');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(context.t.failedUploadVoiceEmpty)),
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
            voiceTranscript: transcript.isEmpty ? null : transcript,
            replyToId: reply?.id,
            replyToText: reply == null ? null : _previewOf(reply),
            replyToSenderUid: reply?.senderUid,
          );
      debugPrint('[chat-voice] sendMessage OK');
    } catch (e, st) {
      debugPrint('[chat-voice] FAILED: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t.voiceUploadFailed(e))),
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
    try {
      if (_voiceStt.isListening) await _voiceStt.stop();
    } catch (_) {}
    _voiceTranscript = '';
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
  // Future<void> _toggleDictation() async {
  //   // TODO: Implement when speech-to-text is needed
  // }

  /// Long-press handler on the dictation mic — lets the user pick which
  /// language to dictate in for this chat. Includes an "Auto (device default)"
  /// option that resets back to the system locale.
  // Future<void> _pickDictationLocale() async {
  //   // TODO: Implement when dictation locale picker is needed
  // }

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
                    Text(
                      sheetContext.t.translation,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      sheetContext.t.translationAutoDescription,
                      style: TextStyle(
                          color:
                              Theme.of(sheetContext).textTheme.bodySmall?.color,
                          fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(sheetContext.t.autoTranslateIncoming),
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
                          decoration: InputDecoration(
                            labelText: context.t.translateInto,
                            border: const OutlineInputBorder(),
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

  void _flashMessage(String messageId) {
    setState(() => _flashedMessageId = messageId);
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      if (_flashedMessageId == messageId) {
        setState(() => _flashedMessageId = null);
      }
    });
  }

  Future<bool> _ensureMessageVisible(String messageId) async {
    final key = _messageKeys[messageId];
    final ctx = key?.currentContext;
    if (ctx == null) return false;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: 0.3,
    );
    if (!mounted) return true;
    _flashMessage(messageId);
    return true;
  }

  void _showReplyNavSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        duration: const Duration(milliseconds: 1500),
      ),
    );
  }

  /// Scroll the chat list to the message identified by [messageId] and
  /// flash it briefly so the user can spot the original of a reply.
  ///
  /// If the target widget is not currently mounted (off-screen), we seek by
  /// stream index and retry ensureVisible before showing an error toast.
  Future<void> _scrollToMessage(String messageId) async {
    final noLongerInView = context.t.chatReplyNoLongerInView;
    final wasDeleted = context.t.chatReplyWasDeleted;
    if (await _ensureMessageVisible(messageId)) return;

    if (_messageOrder.isEmpty) {
      _showReplyNavSnack(noLongerInView);
      return;
    }

    final targetIndex = _messageOrder.indexOf(messageId);
    if (targetIndex < 0) {
      _showReplyNavSnack(wasDeleted);
      return;
    }

    if (!_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_scrollToMessage(messageId));
      });
      return;
    }

    final totalItems = _messageOrder.length + _pending.length;
    if (totalItems <= 0) {
      _showReplyNavSnack(noLongerInView);
      return;
    }

    final position = _scrollController.position;
    final avgExtent =
        (position.maxScrollExtent + position.viewportDimension) / totalItems;
    final proportional = totalItems <= 1
        ? 0.0
        : position.maxScrollExtent * (targetIndex / (totalItems - 1));
    final centered =
        avgExtent * targetIndex - position.viewportDimension * 0.35;
    final candidates = <double>[
      centered,
      proportional,
      centered - position.viewportDimension * 0.9,
      centered + position.viewportDimension * 0.9,
    ];

    for (final candidate in candidates) {
      final target = candidate.clamp(0.0, position.maxScrollExtent);
      await _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
      await WidgetsBinding.instance.endOfFrame;
      if (await _ensureMessageVisible(messageId)) return;
    }

    _showReplyNavSnack(noLongerInView);
  }

  /// Records how far from the bottom of the rendered content the
  /// viewport currently sits. Saved into [_lastDistanceFromBottom] so
  /// the next messages emission can correctly decide whether the user
  /// "was at the bottom" before the list changed.
  void _captureDistanceFromBottom() {
    if (!mounted || !_scrollController.hasClients) return;
    final pos = _scrollController.position;
    _lastDistanceFromBottom = pos.maxScrollExtent - pos.pixels;
  }

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
    if (m.encryptedUnreadable) return context.t.chatEncryptedPreview;
    if (m.stickerUrl != null && m.stickerUrl!.isNotEmpty) {
      return context.t.chatStickerPreview;
    }
    if (m.voiceUrl != null && m.voiceUrl!.isNotEmpty) {
      return context.t.chatVoiceMessagePreview;
    }
    if (m.imageUrl != null && m.imageUrl!.isNotEmpty) {
      return context.t.chatPhotoPreview;
    }
    if (m.sharedPostId != null && m.sharedPostId!.isNotEmpty) {
      return context.t.chatSharedPostPreview;
    }
    return m.text;
  }

  Future<void> _sendSticker(String stickerUrl, String? packId) async {
    final uid = _currentUid;
    if (uid == null) return;
    setState(() => _showStickerPicker = false);
    final reply = _replyTarget;

    try {
      await ref.read(chatServiceProvider).sendMessage(
            chatId: widget.chatId,
            senderUid: uid,
            receiverUid: widget.otherUid,
            text: '',
            stickerUrl: stickerUrl,
            stickerPackId: packId,
            replyToId: reply?.id,
            replyToText: reply == null ? null : _previewOf(reply),
            replyToSenderUid: reply?.senderUid,
          );
      if (mounted) setState(() => _replyTarget = null);
    } catch (e) {
      // Keep reply context so the user can retry without re-quoting.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t.failedToSendSticker(e))),
        );
      }
    }
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
        ? context.t.youveBlockedUser
        : (theyBlockedMe ? context.t.cantReplyConversation : null);

    // Mark-seen-on-update. Used to be paired with an unconditional
    // _scrollToBottom() here, but that auto-scrolled even when nothing
    // about the message list had changed (Firestore re-emits on every
    // seenBy update too), which yanked the user away from older
    // messages they were reading. Scroll is now handled only by the
    // count-grew check in the data: builder below.
    ref.listen(messagesProvider(widget.chatId), (_, __) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_markSeenNow());
      });
    });

    final isOnline = presenceAsync?.whenOrNull(data: (p) => p.online) ?? false;
    final isTyping = typingAsync?.whenOrNull(data: (t) => t) ?? false;

    // The avatar passed into the screen comes from the chat doc's cached
    // userData snapshot, which can be stale or empty for older chats. For
    // 1:1 chats watch the peer's live user doc and prefer that avatar so
    // the header + message bubbles always show the current profile photo.
    final peerLive = isGroup || widget.otherUid.isEmpty
        ? null
        : ref.watch(userByUidProvider(widget.otherUid)).value;
    final liveAvatar = (peerLive?['avatarUrl'] as String?)?.trim() ?? '';
    final resolvedAvatar =
        liveAvatar.isNotEmpty ? liveAvatar : widget.otherAvatar;

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
                                backgroundImage: resolvedAvatar.isNotEmpty
                                    ? NetworkImage(resolvedAvatar)
                                    : null,
                                child: resolvedAvatar.isEmpty
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
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  isGroup ? groupName : widget.otherName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            isGroup
                                ? context.t.membersCount(participantCount)
                                : (isTyping
                                    ? context.t.typing
                                    : isOnline
                                        ? context.t.online
                                        : context.t.offline),
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
                        ? context.t.autoTranslateOnTooltip(_autoTranslateTarget)
                        : context.t.translationSettingsTooltip,
                    onPressed: _openTranslationSettings,
                    icon: Icon(
                      _autoTranslate
                          ? Icons.translate
                          : Icons.translate_outlined,
                      color: _autoTranslate
                          ? const Color(0xFFB05ECC)
                          : context.textSecondary,
                    ),
                  ),
                  if (isGroup)
                    IconButton(
                      tooltip: context.t.groupSettings,
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
                    tooltip: context.t.sharedMedia,
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
                  PopupMenuButton<String>(
                    tooltip: context.t.chatOptions,
                    icon: Icon(Icons.more_vert, color: context.textSecondary),
                    onSelected: (value) {
                      switch (value) {
                        case 'auto-delete':
                          _showAutoDeletePicker(
                            currentSeconds:
                                (chatDoc['autoDeleteSeconds'] as num?)?.toInt(),
                          );
                          break;
                        case 'delete':
                          _confirmDeleteChat(isGroup: isGroup);
                          break;
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'auto-delete',
                        child: Row(
                          children: [
                            const Icon(Icons.timer_outlined, size: 18),
                            const SizedBox(width: 8),
                            Text(context.t.autoDeleteMessages),
                          ],
                        ),
                      ),
                      if (!isGroup)
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              const Icon(Icons.delete_outline,
                                  size: 18, color: Colors.red),
                              const SizedBox(width: 8),
                              Text(context.t.deleteChat,
                                  style: const TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            Divider(height: 1, color: Theme.of(context).dividerColor),

            // MESSAGES
            Expanded(
              child: messagesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) =>
                    Center(child: Text(context.t.errorWithMessage(e))),
                data: (msgs) {
                  final ids = msgs.map((m) => m.id).toList(growable: false);
                  _messageOrder
                    ..clear()
                    ..addAll(ids);
                  final liveIds = ids.toSet();
                  _messageKeys.removeWhere((id, _) => !liveIds.contains(id));

                  final currentUid = _currentUid ?? '';
                  if (msgs.isEmpty && _pending.isEmpty) {
                    return Center(
                      child: Text(context.t.sayHello,
                          style: TextStyle(color: context.textSecondary)),
                    );
                  }
                  // Re-snap to the newest message when the list grows.
                  // We rely on the distance-from-bottom captured at
                  // the END of the previous frame (after layout has
                  // settled) rather than reading maxScrollExtent
                  // inside build — at build time the new items aren't
                  // laid out yet, so maxScrollExtent reflects the OLD
                  // shorter list and offset==old-bottom would falsely
                  // look like "user scrolled up by 2000 px" when the
                  // cache → live snapshot transition swaps in a much
                  // longer message list.
                  if (msgs.length > _lastRenderedCount) {
                    final wasNearBottom = _lastRenderedCount == 0 ||
                        _lastDistanceFromBottom < 120;
                    _lastRenderedCount = msgs.length;
                    if (wasNearBottom) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _scrollToBottom(animated: false);
                        // Re-measure once layout has settled so the
                        // next emission has fresh data.
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _captureDistanceFromBottom();
                        });
                      });
                    } else {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _captureDistanceFromBottom();
                      });
                    }
                  } else {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _captureDistanceFromBottom();
                    });
                  }
                  final pendingCount = _pending.length;
                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    itemCount: msgs.length + pendingCount,
                    itemBuilder: (context, i) {
                      if (i >= msgs.length) {
                        final p = _pending[i - msgs.length];
                        return _PendingAttachmentBubble(
                          pending: p,
                          onRetry: () => _retryPending(p),
                          onDismiss: () => _removePending(p.localId),
                        );
                      }
                      final msg = msgs[i];
                      final key =
                          _messageKeys.putIfAbsent(msg.id, () => GlobalKey());
                      return KeyedSubtree(
                        key: key,
                        child: _MessageBubble(
                          chatId: widget.chatId,
                          msg: msg,
                          isMe: msg.senderUid == currentUid,
                          otherUid: widget.otherUid,
                          otherAvatar: resolvedAvatar,
                          isGroup: isGroup,
                          onReply: () => _startReply(msg),
                          onReplyQuoteTap: _scrollToMessage,
                          flashing: _flashedMessageId == msg.id,
                          autoTranslate: _autoTranslate,
                          autoTranslateTarget: _autoTranslateTarget,
                        ),
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
                      Icon(Icons.block, size: 18, color: context.textSecondary),
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
                          _ChatIconButton(
                            tooltip: context.t.attach,
                            onPressed: _showAttachMenu,
                            icon: Icons.attach_file,
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () {
                              setState(() =>
                                  _showStickerPicker = !_showStickerPicker);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOutCubic,
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: _showStickerPicker
                                    ? context.purpleSoft
                                    : context.cardBg,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _showStickerPicker
                                      ? AppColors.purple.withValues(alpha: 0.32)
                                      : context.borderColor,
                                ),
                              ),
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                child: Icon(
                                  _showStickerPicker
                                      ? Icons.keyboard
                                      : Icons.emoji_emotions_outlined,
                                  key: ValueKey(_showStickerPicker),
                                  size: 21,
                                  color: _showStickerPicker
                                      ? AppColors.purpleVivid
                                      : context.textSecondary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ValueListenableBuilder<TextEditingValue>(
                              valueListenable: _controller,
                              builder: (context, value, _) {
                                final hasText = value.text.trim().isNotEmpty;
                                final dir = _detectTextDirection(value.text);
                                final activeBorder = _isInputFocused || hasText;
                                return AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  curve: Curves.easeOutCubic,
                                  padding: const EdgeInsets.only(
                                      left: 14, right: 10, top: 2, bottom: 2),
                                  decoration: BoxDecoration(
                                    color: context.cardBg,
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(
                                      color: activeBorder
                                          ? AppColors.purpleVivid
                                          : context.borderColor
                                              .withValues(alpha: 0.72),
                                      width: activeBorder ? 1.3 : 1,
                                    ),
                                    boxShadow: activeBorder
                                        ? [
                                            BoxShadow(
                                              color: AppColors.purple
                                                  .withValues(alpha: 0.16),
                                              blurRadius: 12,
                                              offset: const Offset(0, 2),
                                            ),
                                          ]
                                        : [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                  alpha:
                                                      context.isDark ? 0.18 : 0.05),
                                              blurRadius: 10,
                                              offset: const Offset(0, 3),
                                            ),
                                          ],
                                  ),
                                  child: TextField(
                                    controller: _controller,
                                    focusNode: _messageFocusNode,
                                    onChanged: _onTextChanged,
                                    minLines: 1,
                                    maxLines: 6,
                                    keyboardType: TextInputType.multiline,
                                    textInputAction: TextInputAction.newline,
                                    textDirection: dir,
                                    textAlign: dir == ui.TextDirection.rtl
                                        ? TextAlign.end
                                        : TextAlign.start,
                                    textCapitalization:
                                        TextCapitalization.sentences,
                                    decoration: InputDecoration(
                                      hintText: context.t.writeAMessage,
                                      hintStyle: TextStyle(
                                        color: context.textMuted,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      filled: false,
                                      fillColor: Colors.transparent,
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              vertical: 10),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 4),
                          // Voice ↔ Send morph. We watch the input controller
                          // so the button swaps the moment the user starts /
                          // stops typing instead of waiting for the next
                          // unrelated rebuild. AnimatedSwitcher gives a soft
                          // scale+rotate crossfade, and the wrapping circle
                          // also fills with purple when "send" appears so the
                          // change reads as a single fluid morph.
                          ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _controller,
                            builder: (context, value, _) {
                              final hasText = value.text.trim().isNotEmpty;
                              if (_uploadingVoice) {
                                return const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFFB05ECC)),
                                  ),
                                );
                              }
                              return _ChatGradientCircleButton(
                                active: hasText,
                                onTap: hasText
                                    ? _sendMessage
                                    : _startVoiceRecording,
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 220),
                                  switchInCurve: Curves.easeOutBack,
                                  switchOutCurve: Curves.easeIn,
                                  transitionBuilder: (child, animation) {
                                    return ScaleTransition(
                                      scale: animation,
                                      child: RotationTransition(
                                        turns: Tween<double>(
                                                begin: 0.75, end: 1.0)
                                            .animate(animation),
                                        child: FadeTransition(
                                          opacity: animation,
                                          child: child,
                                        ),
                                      ),
                                    );
                                  },
                                  child: Icon(
                                    hasText ? Icons.send : Icons.mic_none,
                                    key: ValueKey(hasText),
                                    color: hasText
                                        ? Colors.white
                                        : AppColors.purpleVivid,
                                    size: 22,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
              ),

            // STICKER PICKER (slides up below the input, like Telegram)
            if (_showStickerPicker && _currentUid != null)
              StickerPickerSheet(
                currentUid: _currentUid!,
                onStickerSelected: _sendSticker,
              ),
          ],
        ),
      ),
    );
  }

  /// Bottom sheet that lets the user pick an auto-delete period for
  /// this chat. Choosing a duration writes `autoDeleteSeconds` on the
  /// chat doc; "Off" clears the field. The chat doc itself is never
  /// deleted by this setting — only its messages are pruned by a
  /// scheduled job on the backend.
  Future<void> _showAutoDeletePicker({required int? currentSeconds}) async {
    final options = <_AutoDeleteOption>[
      _AutoDeleteOption(context.t.autoDeleteOff, null),
      _AutoDeleteOption(context.t.autoDeleteOneDay, const Duration(days: 1)),
      _AutoDeleteOption(context.t.autoDeleteOneWeek, const Duration(days: 7)),
      _AutoDeleteOption(context.t.autoDeleteOneMonth, const Duration(days: 30)),
    ];
    final picked = await showModalBottomSheet<_AutoDeleteOption>(
      context: context,
      backgroundColor: context.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  context.t.autoDeleteMessages,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  context.t.autoDeletePeriodDescription,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textSecondary,
                  ),
                ),
              ),
            ),
            for (final opt in options)
              ListTile(
                leading: Icon(
                  opt.duration == null
                      ? Icons.timer_off_outlined
                      : Icons.timer_outlined,
                  color: const Color(0xFFB05ECC),
                ),
                title: Text(opt.label),
                trailing: (opt.duration?.inSeconds == currentSeconds ||
                        (opt.duration == null && currentSeconds == null))
                    ? const Icon(Icons.check, color: Color(0xFFB05ECC))
                    : null,
                onTap: () => Navigator.pop(sheet, opt),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null) return;
    try {
      await ref.read(chatServiceProvider).setAutoDeletePeriod(
            chatId: widget.chatId,
            period: picked.duration,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            picked.duration == null
                ? context.t.autoDeleteTurnedOff
                : context.t.autoDeleteSet(picked.label),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.t.failedWithError(e))));
    }
  }

  Future<void> _confirmDeleteChat({required bool isGroup}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(context.t.deleteChatQuestion),
        content: Text(context.t.deleteChatBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.t.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              context.t.delete,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(chatServiceProvider).deleteChat(widget.chatId);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.t.deleteFailed(e))));
    }
  }
}

class _AutoDeleteOption {
  final String label;
  final Duration? duration;
  const _AutoDeleteOption(this.label, this.duration);
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
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.purple.withValues(alpha: 0.22),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.purple.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [AppColors.purple, AppColors.purpleVivid],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Icon(Icons.reply, size: 15, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              previewText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
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
        _ChatIconButton(
          onPressed: widget.onCancel,
          icon: Icons.delete_outline,
          foregroundColor: AppColors.red,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: context.cardBg,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: context.borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black
                      .withValues(alpha: context.isDark ? 0.18 : 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.fiber_manual_record,
                    color: AppColors.red, size: 14),
                const SizedBox(width: 8),
                Text(context.t.recordingElapsed(_elapsed()),
                    style: TextStyle(
                      color: context.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    )),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        _ChatGradientCircleButton(
          active: true,
          onTap: widget.onStop,
          child: const Icon(Icons.send, color: Colors.white, size: 21),
        ),
      ],
    );
  }
}

class _ChatIconButton extends StatelessWidget {
  final String? tooltip;
  final VoidCallback? onPressed;
  final IconData icon;
  final Color? foregroundColor;

  const _ChatIconButton({
    this.tooltip,
    required this.onPressed,
    required this.icon,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Ink(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: context.cardBg,
            shape: BoxShape.circle,
            border: Border.all(color: context.borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black
                    .withValues(alpha: context.isDark ? 0.16 : 0.04),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(
            icon,
            size: 20,
            color: foregroundColor ?? context.textSecondary,
          ),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

class _ChatGradientCircleButton extends StatelessWidget {
  final bool active;
  final Widget child;
  final VoidCallback? onTap;

  const _ChatGradientCircleButton({
    required this.active,
    required this.child,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: 44,
        height: 44,
        margin: const EdgeInsets.all(4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? null : context.cardBg,
          gradient: active
              ? const LinearGradient(
                  colors: [AppColors.purple, AppColors.purpleVivid],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          border: active ? null : Border.all(color: context.borderColor),
          boxShadow: [
            BoxShadow(
              color: (active ? AppColors.purple : Colors.black).withValues(
                alpha: active ? 0.32 : (context.isDark ? 0.16 : 0.04),
              ),
              blurRadius: active ? 12 : 8,
              offset: Offset(0, active ? 4 : 3),
            ),
          ],
        ),
        child: child,
      ),
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

  /// Tapping the "replied to" quote inside a bubble should scroll the
  /// chat back to the original message. The parent owns the scroll
  /// controller + per-message keys, so we accept the callback here.
  final void Function(String replyToId)? onReplyQuoteTap;

  /// True while the parent has just scrolled to this bubble in
  /// response to a reply-quote tap. The bubble paints a brief
  /// highlight tween so the user can spot which one we landed on.
  final bool flashing;

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
    this.onReplyQuoteTap,
    this.flashing = false,
  });

  @override
  ConsumerState<_MessageBubble> createState() => _MessageBubbleState();
}

enum _DeleteMessageScope { mine, everyone }

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
      !msg.encryptedUnreadable &&
      msg.text.trim().isNotEmpty &&
      !_showOriginal;

  bool get _isSenderOnlyProfanity => isMe && msg.profanityFiltered;

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
    final originalStyle = TextStyle(
      color: textColor,
      fontSize: 14.5,
      height: 1.34,
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
    );
    if (msg.encryptedUnreadable) {
      // Legacy ciphertext from an older client; no key to decrypt it
      // with anymore.
      return Text(context.t.messageUnavailable, style: originalStyle);
    }
    if (!widget.autoTranslate || isMe || msg.text.trim().isEmpty) {
      return Text(msg.text, style: originalStyle);
    }

    final body = _showOriginal
        ? msg.text
        : (_translated ?? msg.text); // until translation arrives, show original

    final hintColor = _isSenderOnlyProfanity
        ? const Color(0xFFB00020)
        : (isMe
            ? Colors.white.withValues(alpha: 0.85)
            : const Color(0xFFB05ECC));

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
                    ? context.t.translationFailedRetry
                    : _translating
                        ? context.t.translating
                        : _showOriginal
                            ? context.t.showTranslation
                            : context.t.showOriginal,
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

  /// Renders a sticker message without the colored bubble background
  /// (like Telegram) — stickers float as large emoji or images.
  Widget _buildStickerBubble(BuildContext context, bool hasReply) {
    final stickerUrl = msg.stickerUrl!;
    final isEmoji =
        !stickerUrl.startsWith('http') && !stickerUrl.startsWith('asset:');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasReply)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              color: context.inputFill,
              borderRadius: BorderRadius.circular(10),
            ),
            child: _RepliedQuote(
              isMe: isMe,
              senderUid: msg.replyToSenderUid ?? '',
              text: msg.replyToText ?? '',
              onTap: widget.onReplyQuoteTap == null
                  ? null
                  : () => widget.onReplyQuoteTap!(msg.replyToId!),
            ),
          ),
        if (isEmoji)
          Text(
            stickerUrl,
            style: const TextStyle(fontSize: 80),
          )
        else
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: stickerUrl,
              width: 140,
              height: 140,
              fit: BoxFit.contain,
              placeholder: (_, __) => const SizedBox(
                width: 140,
                height: 140,
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
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
    final senderName = isGroup
        ? ((senderLive?['username'] as String?) ?? context.t.member)
        : '';
    final senderUidForTap = isGroup ? msg.senderUid : otherUid;

    final hasReply = msg.replyToId != null && msg.replyToId!.isNotEmpty;
    final hasVoice = msg.voiceUrl != null && msg.voiceUrl!.isNotEmpty;
    final hasSticker = msg.stickerUrl != null && msg.stickerUrl!.isNotEmpty;
    final outgoingBodyColor =
        _isSenderOnlyProfanity ? const Color(0xFFB00020) : Colors.white;
    final outgoingGradient = widget.flashing
        ? LinearGradient(
            colors: [
              AppColors.purpleBright.withValues(alpha: 0.9),
              AppColors.purpleVivid.withValues(alpha: 0.9),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : const LinearGradient(
            colors: [AppColors.purple, AppColors.purpleVivid],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );

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
                  padding: const EdgeInsetsDirectional.only(bottom: 2, start: 4),
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
                    child: hasSticker
                        ? _buildStickerBubble(context, hasReply)
                        : AnimatedContainer(
                            duration: const Duration(milliseconds: 280),
                            curve: Curves.easeOut,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: isMe && !_isSenderOnlyProfanity
                                  ? null
                                  : (_isSenderOnlyProfanity
                                      ? const Color(0xFFFFE5E5)
                                      : context.cardBg),
                              gradient: isMe && !_isSenderOnlyProfanity
                                  ? outgoingGradient
                                  : null,
                              border: _isSenderOnlyProfanity
                                  ? Border.all(
                                      color: const Color(0xFFF28B82),
                                      width: 1,
                                    )
                                  : Border.all(
                                      color: isMe
                                          ? Colors.white.withValues(alpha: 0.10)
                                          : context.borderColor,
                                    ),
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(16),
                                topRight: const Radius.circular(16),
                                bottomLeft: Radius.circular(isMe ? 16 : 4),
                                bottomRight: Radius.circular(isMe ? 4 : 16),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: (isMe
                                          ? AppColors.purple
                                          : Colors.black)
                                      .withValues(
                                    alpha: widget.flashing
                                        ? 0.42
                                        : (isMe
                                            ? 0.22
                                            : (context.isDark ? 0.18 : 0.06)),
                                  ),
                                  blurRadius: widget.flashing ? 16 : 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (hasReply)
                                  _RepliedQuote(
                                    isMe: isMe,
                                    senderUid: msg.replyToSenderUid ?? '',
                                    text: msg.replyToText ?? '',
                                    onTap: widget.onReplyQuoteTap == null
                                        ? null
                                        : () => widget
                                            .onReplyQuoteTap!(msg.replyToId!),
                                  ),
                                if (msg.storyId != null &&
                                    msg.storyId!.isNotEmpty)
                                  _StoryReplyBanner(
                                    isMe: isMe,
                                    storyImageUrl: msg.storyImageUrl,
                                    storyId: msg.storyId!,
                                  ),
                                if (hasVoice)
                                  _VoiceMessageBubble(
                                    url: msg.voiceUrl!,
                                    durationMs: msg.voiceDurationMs,
                                    isMe: isMe,
                                  )
                                else if (msg.videoUrl != null &&
                                    msg.videoUrl!.isNotEmpty) ...[
                                  _VideoMessageBubble(url: msg.videoUrl!),
                                  if (msg.text.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    _buildBody(
                                      textColor: isMe
                                          ? outgoingBodyColor
                                          : context.textPrimary,
                                    ),
                                  ],
                                ] else if (msg.fileUrl != null &&
                                    msg.fileUrl!.isNotEmpty) ...[
                                  _FileMessageBubble(
                                    url: msg.fileUrl!,
                                    fileName:
                                        msg.fileName ?? context.t.attachmentDefaultName,
                                    mimeType: msg.fileMimeType,
                                    sizeBytes: msg.fileSizeBytes,
                                    isMe: isMe,
                                  ),
                                  if (msg.text.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    _buildBody(
                                      textColor: isMe
                                          ? outgoingBodyColor
                                          : context.textPrimary,
                                    ),
                                  ],
                                ] else if (msg.sharedPostId != null &&
                                    msg.sharedPostId!.isNotEmpty)
                                  _SharedPostPreview(
                                    postId: msg.sharedPostId!,
                                    isMe: isMe,
                                  )
                                else if (msg.hasLocation) ...[
                                  _LocationMessageBubble(
                                    lat: msg.locationLat!,
                                    lng: msg.locationLng!,
                                    label: msg.locationLabel,
                                    isMe: isMe,
                                  ),
                                  if (msg.text.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    _buildBody(
                                      textColor: isMe
                                          ? outgoingBodyColor
                                          : context.textPrimary,
                                    ),
                                  ],
                                ] else if (msg.imageUrl != null &&
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
                                          ? outgoingBodyColor
                                          : context.textPrimary,
                                    ),
                                  ],
                                ] else
                                  _buildBody(
                                    textColor: isMe
                                        ? outgoingBodyColor
                                        : context.textPrimary,
                                  ),
                              ],
                            ),
                          ),
                  ),
                ),
              ),
              if (_isSenderOnlyProfanity)
                Padding(
                  padding: const EdgeInsets.only(top: 4, right: 4),
                  child: Text(
                    context.t.visibleOnlyToYou,
                    style: const TextStyle(
                      color: Color(0xFFB00020),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
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
      alignment: alignLeft
          ? AlignmentDirectional.centerStart
          : AlignmentDirectional.centerEnd,
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
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: context.borderColor,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
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
                            await sheetRef.read(reactionServiceProvider).toggle(
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
                                  : context.inputFill.withValues(alpha: 0.62),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: selected
                                    ? AppColors.purple.withValues(alpha: 0.22)
                                    : context.borderColor
                                        .withValues(alpha: 0.62),
                              ),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _BubbleMenuAction(
                    icon: Icons.reply,
                    label: context.t.reply,
                    onTap: () {
                      Navigator.pop(sheet);
                      onReply();
                    },
                  ),
                  if (msg.text.trim().isNotEmpty) const SizedBox(height: 8),
                  // Translate to the user's preferred language. Falls back to
                  // English when the user hasn't set one yet (handled by the
                  // preferredLanguageProvider default).
                  if (msg.text.trim().isNotEmpty)
                    Consumer(
                      builder: (context, sheetRef, _) {
                        final target =
                            sheetRef.watch(preferredLanguageProvider);
                        return _BubbleMenuAction(
                          icon: Icons.translate,
                          label:
                              context.t.translateToLang(target.toUpperCase()),
                          subtitle: Text(
                            context.t.translateChangeInSettings,
                            style: TextStyle(
                              fontSize: 11,
                              color: context.textSecondary,
                            ),
                          ),
                          onTap: () {
                            Navigator.pop(sheet);
                            _showTranslationSheet(
                              context,
                              text: msg.text,
                              target: target,
                            );
                          },
                        );
                      },
                    ),
                  if (msg.voiceUrl != null && msg.voiceUrl!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _BubbleMenuAction(
                      icon: Icons.subtitles_outlined,
                      label: context.t.showTranscript,
                      subtitle: (msg.voiceTranscript ?? '').trim().isEmpty
                          ? Text(
                              context.t.transcriptUnavailable,
                              style: const TextStyle(fontSize: 11),
                            )
                          : null,
                      enabled:
                          (msg.voiceTranscript ?? '').trim().isNotEmpty,
                      onTap: () {
                        Navigator.pop(sheet);
                        _showVoiceTranscriptSheet(
                          context,
                          transcript: msg.voiceTranscript ?? '',
                        );
                      },
                    ),
                    if ((msg.voiceTranscript ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Consumer(
                        builder: (context, sheetRef, _) {
                          final target =
                              sheetRef.watch(preferredLanguageProvider);
                          return _BubbleMenuAction(
                            icon: Icons.translate,
                            label: context
                                .t
                                .translateVoiceToLang(target.toUpperCase()),
                            onTap: () {
                              Navigator.pop(sheet);
                              _showTranslationSheet(
                                context,
                                text: msg.voiceTranscript!,
                                target: target,
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ],
                  const SizedBox(height: 8),
                  _BubbleMenuAction(
                    icon: Icons.delete_outline,
                    label: context.t.delete,
                    destructive: true,
                    onTap: () {
                      Navigator.pop(sheet);
                      _showDeleteMessageOptions(context);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDeleteMessageOptions(BuildContext context) async {
    final currentUid = ref.read(authStateProvider).value?.uid;
    if (currentUid == null) return;

    final scope = await showModalBottomSheet<_DeleteMessageScope>(
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
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(context.t.deleteForMe),
              onTap: () => Navigator.pop(sheet, _DeleteMessageScope.mine),
            ),
            if (isMe)
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: Text(
                  widget.isGroup
                      ? context.t.deleteForEveryone
                      : context.t.deleteForBoth,
                  style: const TextStyle(color: Colors.red),
                ),
                onTap: () => Navigator.pop(
                  sheet,
                  _DeleteMessageScope.everyone,
                ),
              ),
          ],
        ),
      ),
    );
    if (scope == null || !mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          scope == _DeleteMessageScope.everyone
              ? (widget.isGroup
                  ? context.t.deleteForEveryoneQuestion
                  : context.t.deleteForBothQuestion)
              : context.t.deleteForMeQuestion,
        ),
        content: Text(
          scope == _DeleteMessageScope.everyone
              ? context.t.deleteForEveryoneBody
              : context.t.deleteForMeBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.t.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              context.t.delete,
              style: TextStyle(
                color:
                    scope == _DeleteMessageScope.everyone ? Colors.red : null,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      final chatService = ref.read(chatServiceProvider);
      if (scope == _DeleteMessageScope.everyone) {
        await chatService.deleteMessageForEveryone(
          chatId: widget.chatId,
          messageId: msg.id,
          uid: currentUid,
        );
      } else {
        await chatService.deleteMessageForMe(
          chatId: widget.chatId,
          messageId: msg.id,
          uid: currentUid,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            scope == _DeleteMessageScope.everyone
                ? context.t.messageDeletedEveryone
                : context.t.messageDeletedYou,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t.deleteFailed(e))),
      );
    }
  }

  Future<void> _showTranslationSheet(
    BuildContext context, {
    required String text,
    required String target,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _MessageTranslationSheet(text: text, target: target),
    );
  }

  Future<void> _showVoiceTranscriptSheet(
    BuildContext context, {
    required String transcript,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.subtitles_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    context.t.voiceTranscript,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SelectableText(
                transcript,
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
      ),
    );
  }
}

/// Modern action row used by the message long-press sheet.
class _BubbleMenuAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget? subtitle;
  final VoidCallback? onTap;
  final bool destructive;
  final bool enabled;

  const _BubbleMenuAction({
    required this.icon,
    required this.label,
    this.subtitle,
    this.onTap,
    this.destructive = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final active = enabled && onTap != null;
    final accent = destructive ? AppColors.red : AppColors.purpleVivid;
    final textColor = destructive ? AppColors.red : context.textPrimary;

    return Opacity(
      opacity: active ? 1 : 0.52,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: active ? onTap : null,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: destructive
                  ? AppColors.red.withValues(alpha: context.isDark ? 0.12 : 0.08)
                  : context.inputFill
                      .withValues(alpha: context.isDark ? 0.7 : 0.85),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: destructive
                    ? AppColors.red.withValues(alpha: 0.18)
                    : context.borderColor.withValues(alpha: 0.82),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: destructive ? 0.12 : 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: accent, size: 19),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        subtitle!,
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom-sheet that translates a message into the user's preferred
/// language. Read-only — for changing the language the user goes to
/// Settings → Preferred language.
class _MessageTranslationSheet extends StatefulWidget {
  final String text;
  final String target;
  const _MessageTranslationSheet({
    required this.text,
    required this.target,
  });

  @override
  State<_MessageTranslationSheet> createState() =>
      _MessageTranslationSheetState();
}

class _MessageTranslationSheetState extends State<_MessageTranslationSheet> {
  String? _translated;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
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
        targetLang: widget.target,
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

  @override
  Widget build(BuildContext context) {
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
                  context.t.translationWithLang(widget.target.toUpperCase()),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
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

// ─────────────────────────────────────────────
// Replied-to quote — thin colored bar + preview text shown atop a bubble
// whose sender is replying to another message.
// ─────────────────────────────────────────────

class _RepliedQuote extends ConsumerWidget {
  final bool isMe;
  final String senderUid;
  final String text;

  /// Tapping the quote scrolls the chat to the original message.
  /// Wired up by [_MessageBubble] when [onReplyQuoteTap] is provided.
  final VoidCallback? onTap;

  const _RepliedQuote({
    required this.isMe,
    required this.senderUid,
    required this.text,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final who = ref.watch(userByUidProvider(senderUid)).value;
    final name = (who?['username'] as String?) ?? context.t.someone;
    final bg = isMe
        ? Colors.white.withValues(alpha: 0.18)
        : Colors.black.withValues(alpha: 0.05);
    final body = Container(
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
    if (onTap == null) return body;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: body,
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
    final gap = (size.width - barWidth * heights.length) / (heights.length - 1);
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
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(context.t.originalPostUnavailable),
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
                        post.caption.isEmpty
                            ? context.t.sharedPost
                            : post.caption,
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
                context.t.memberOfEvent(title),
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
// class _DictationLocaleChoice {
//   final String? id;
//   final String label;
//   const _DictationLocaleChoice({required this.id, required this.label});
// }

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
/// in response to (or shared as) a story. Shows a thin label + a tiny
/// thumbnail when available; tap to open the underlying story doc.
class _StoryReplyBanner extends ConsumerWidget {
  final bool isMe;
  final String? storyImageUrl;
  final String storyId;
  const _StoryReplyBanner({
    required this.isMe,
    this.storyImageUrl,
    required this.storyId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fg =
        isMe ? Colors.white.withValues(alpha: 0.85) : const Color(0xFFB05ECC);
    final bg = isMe
        ? Colors.white.withValues(alpha: 0.15)
        : Colors.black.withValues(alpha: 0.05);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openStory(context, ref),
      child: Container(
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
                    child: Icon(Icons.broken_image, size: 14, color: fg),
                  ),
                ),
              )
            else
              Container(
                width: 28,
                height: 36,
                decoration: BoxDecoration(
                  color: fg.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.auto_stories, size: 16, color: fg),
              ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                context.t.sharedAStory,
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
      ),
    );
  }

  /// Fetches the story doc by id and opens the story viewer for it.
  /// Stories expire after 24 h; if the doc is gone we surface a snack
  /// rather than failing silently.
  Future<void> _openStory(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final t = context.t;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('stories')
          .doc(storyId)
          .get();
      if (!doc.exists) {
        messenger.showSnackBar(
          SnackBar(content: Text(t.storyUnavailable)),
        );
        return;
      }
      final story = Story.fromDoc(doc);
      if (!context.mounted) return;
      await openStoryViewer(context, [
        [story]
      ], 0);
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text(t.storyUnavailable)),
      );
    }
  }
}

// ─────────────────────────────────────────────
// Video message bubble — inline thumbnail + tap-to-play sheet.
// ─────────────────────────────────────────────

/// Bubble for a shared location: a mini OSM map preview + "Directions" button
/// that opens the device maps app routing from the user's current position.
class _LocationMessageBubble extends StatelessWidget {
  final double lat;
  final double lng;
  final String? label;
  final bool isMe;

  const _LocationMessageBubble({
    required this.lat,
    required this.lng,
    required this.label,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final fg = isMe ? Colors.white : context.textPrimary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 230,
          height: 130,
          child: MapPreview(
            lat: lat,
            lng: lng,
            height: 130,
            label: (label ?? '').trim().isEmpty
                ? context.t.sharedLocation
                : label,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(Icons.location_on_rounded, size: 14, color: fg),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                (label ?? '').trim().isEmpty
                    ? context.t.sharedLocation
                    : label!.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 230,
          child: OutlinedButton.icon(
            onPressed: () => openDirectionsTo(context, lat: lat, lng: lng),
            icon: Icon(Icons.directions_rounded, size: 16, color: fg),
            label: Text(context.t.directions, style: TextStyle(color: fg)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: fg.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              minimumSize: const Size(0, 34),
            ),
          ),
        ),
      ],
    );
  }
}

class _VideoMessageBubble extends StatefulWidget {
  final String url;
  const _VideoMessageBubble({required this.url});

  @override
  State<_VideoMessageBubble> createState() => _VideoMessageBubbleState();
}

class _VideoMessageBubbleState extends State<_VideoMessageBubble> {
  VideoPlayerController? _ctrl;
  bool _initFailed = false;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  Future<void> _initController() async {
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _ctrl = c);
    } catch (e) {
      debugPrint('[chat-video] init failed: $e');
      if (mounted) setState(() => _initFailed = true);
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _ctrl;
    return GestureDetector(
      onTap: () => _openFullScreen(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 240,
          height: 180,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (ctrl != null && ctrl.value.isInitialized)
                FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: ctrl.value.size.width,
                    height: ctrl.value.size.height,
                    child: VideoPlayer(ctrl),
                  ),
                )
              else
                Container(color: Colors.black.withValues(alpha: 0.55)),
              if (_initFailed)
                const Center(
                  child:
                      Icon(Icons.broken_image, color: Colors.white70, size: 36),
                )
              else
                const Center(
                  child: Icon(
                    Icons.play_circle_fill,
                    color: Colors.white,
                    size: 56,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _openFullScreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _VideoFullscreenScreen(url: widget.url),
      ),
    );
  }
}

class _VideoFullscreenScreen extends StatefulWidget {
  final String url;
  const _VideoFullscreenScreen({required this.url});

  @override
  State<_VideoFullscreenScreen> createState() => _VideoFullscreenScreenState();
}

class _VideoFullscreenScreenState extends State<_VideoFullscreenScreen> {
  VideoPlayerController? _ctrl;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    await c.initialize();
    if (!mounted) {
      await c.dispose();
      return;
    }
    setState(() => _ctrl = c);
    await c.play();
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _ctrl;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: GestureDetector(
        onTap: () => setState(() => _showControls = !_showControls),
        child: Center(
          child: c == null || !c.value.isInitialized
              ? const CircularProgressIndicator(color: Colors.white)
              : Stack(
                  alignment: Alignment.center,
                  children: [
                    AspectRatio(
                      aspectRatio: c.value.aspectRatio,
                      child: VideoPlayer(c),
                    ),
                    if (_showControls)
                      Container(
                        color: Colors.black.withValues(alpha: 0.25),
                        child: Center(
                          child: IconButton(
                            iconSize: 64,
                            color: Colors.white,
                            icon: Icon(c.value.isPlaying
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_filled),
                            onPressed: () {
                              setState(() {
                                c.value.isPlaying ? c.pause() : c.play();
                              });
                            },
                          ),
                        ),
                      ),
                    if (_showControls)
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 24,
                        child: VideoProgressIndicator(
                          c,
                          allowScrubbing: true,
                          colors: const VideoProgressColors(
                            playedColor: Color(0xFFB05ECC),
                            bufferedColor: Colors.white24,
                            backgroundColor: Colors.white12,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// File attachment bubble — name + size, tap to download & open.
// ─────────────────────────────────────────────

class _FileMessageBubble extends StatefulWidget {
  final String url;
  final String fileName;
  final String? mimeType;
  final int? sizeBytes;
  final bool isMe;

  const _FileMessageBubble({
    required this.url,
    required this.fileName,
    this.mimeType,
    this.sizeBytes,
    required this.isMe,
  });

  @override
  State<_FileMessageBubble> createState() => _FileMessageBubbleState();
}

class _FileMessageBubbleState extends State<_FileMessageBubble> {
  bool _opening = false;

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final dir = await getTemporaryDirectory();
      final safeName =
          widget.fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final path = '${dir.path}/$safeName';
      final file = File(path);
      if (!await file.exists()) {
        final res = await http.get(Uri.parse(widget.url));
        if (res.statusCode != 200) {
          throw Exception('HTTP ${res.statusCode}');
        }
        await file.writeAsBytes(res.bodyBytes);
      }
      final result = await OpenFilex.open(path, type: widget.mimeType);
      if (result.type != ResultType.done) {
        if (!mounted) return;
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

  String _formatSize(int? bytes) {
    if (bytes == null || bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.isMe ? Colors.white : context.textPrimary;
    final fgMuted = widget.isMe
        ? Colors.white.withValues(alpha: 0.8)
        : context.textSecondary;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: GestureDetector(
        onTap: _open,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: widget.isMe
                    ? Colors.white.withValues(alpha: 0.2)
                    : context.purpleSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: _opening
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Icon(
                      Icons.insert_drive_file_outlined,
                      color: widget.isMe ? Colors.white : AppColors.purple,
                    ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_formatSize(widget.sizeBytes).isNotEmpty)
                    Text(
                      _formatSize(widget.sizeBytes),
                      style: TextStyle(color: fgMuted, fontSize: 11),
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

/// Full-screen confirmation shown after the user picks an image, video, or
/// document. Pops `true` when the user taps Send and `false` (or null) when
/// they cancel. The caller does the actual upload — this screen is purely a
/// preview.
class _AttachmentPreviewScreen extends StatefulWidget {
  final _AttachKind kind;
  final File file;
  final String fileName;
  final int? fileSizeBytes;
  final String recipient;

  const _AttachmentPreviewScreen({
    required this.kind,
    required this.file,
    required this.fileName,
    required this.recipient,
    this.fileSizeBytes,
  });

  @override
  State<_AttachmentPreviewScreen> createState() =>
      _AttachmentPreviewScreenState();
}

class _AttachmentPreviewScreenState extends State<_AttachmentPreviewScreen> {
  VideoPlayerController? _videoController;

  @override
  void initState() {
    super.initState();
    if (widget.kind == _AttachKind.video) {
      final c = VideoPlayerController.file(widget.file);
      _videoController = c;
      c.initialize().then((_) {
        if (!mounted) return;
        c.setLooping(true);
        c.play();
        setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  String _formatBytes(int bytes) {
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
    if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  Widget _buildBody() {
    switch (widget.kind) {
      case _AttachKind.image:
        return Center(
          child: InteractiveViewer(
            maxScale: 4,
            child: Image.file(widget.file, fit: BoxFit.contain),
          ),
        );
      case _AttachKind.video:
        final c = _videoController;
        if (c == null || !c.value.isInitialized) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }
        return Center(
          child: AspectRatio(
            aspectRatio: c.value.aspectRatio,
            child: Stack(
              alignment: Alignment.center,
              children: [
                VideoPlayer(c),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      c.value.isPlaying ? c.pause() : c.play();
                    });
                  },
                  child: AnimatedOpacity(
                    opacity: c.value.isPlaying ? 0 : 1,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(16),
                      child: const Icon(Icons.play_arrow,
                          color: Colors.white, size: 48),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      case _AttachKind.file:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.insert_drive_file_outlined,
                    color: Colors.white,
                    size: 56,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  widget.fileName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (widget.fileSizeBytes != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _formatBytes(widget.fileSizeBytes!),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(context.t.sendToRecipient(widget.recipient)),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildBody()),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              color: Colors.black,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(context.t.cancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(true),
                      icon: const Icon(Icons.send),
                      label: Text(context.t.send),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
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
  }
}

/// Outgoing chat bubble shown for an attachment whose upload + Firestore
/// write are still in flight. Pops out of the list when the upload
/// completes and the real message arrives over the messages stream, or
/// transitions to a failed state with retry/dismiss buttons on error.
class _PendingAttachmentBubble extends StatelessWidget {
  final _PendingAttachment pending;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  const _PendingAttachmentBubble({
    required this.pending,
    required this.onRetry,
    required this.onDismiss,
  });

  String _statusLabel(BuildContext context) {
    switch (pending.status) {
      case _PendingStatus.uploading:
        return context.t.uploading;
      case _PendingStatus.sending:
        return context.t.sending;
      case _PendingStatus.failed:
        return context.t.failedToSend;
    }
  }

  Widget _buildPreview(BuildContext context) {
    switch (pending.kind) {
      case _AttachKind.image:
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            pending.file,
            width: 220,
            height: 220,
            fit: BoxFit.cover,
          ),
        );
      case _AttachKind.video:
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 220,
            height: 220,
            color: Colors.black,
            alignment: Alignment.center,
            child: const Icon(Icons.movie_outlined,
                color: Colors.white70, size: 56),
          ),
        );
      case _AttachKind.file:
        return Container(
          padding: const EdgeInsets.all(12),
          constraints: const BoxConstraints(maxWidth: 260),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.insert_drive_file_outlined,
                  color: Colors.white, size: 32),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  pending.fileName,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
            ],
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFailed = pending.status == _PendingStatus.failed;
    final bubbleColor =
        isFailed ? Colors.red.withValues(alpha: 0.85) : const Color(0xFFB05ECC);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Stack(
                  children: [
                    Opacity(
                      opacity: isFailed ? 0.6 : 1,
                      child: Container(
                        padding: pending.kind == _AttachKind.file
                            ? EdgeInsets.zero
                            : const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: bubbleColor,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(16),
                            topRight: Radius.circular(16),
                            bottomLeft: Radius.circular(16),
                            bottomRight: Radius.circular(4),
                          ),
                        ),
                        child: _buildPreview(context),
                      ),
                    ),
                    if (!isFailed)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Center(
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(10),
                              child: const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isFailed
                          ? Icons.error_outline
                          : Icons.cloud_upload_outlined,
                      size: 13,
                      color: isFailed ? Colors.red : Colors.white70,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _statusLabel(context),
                      style: TextStyle(
                        color: isFailed ? Colors.red : Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                    if (isFailed) ...[
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: onRetry,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 0),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(context.t.retryLabel,
                            style: const TextStyle(fontSize: 12)),
                      ),
                      TextButton(
                        onPressed: onDismiss,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white70,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 0),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(context.t.dismiss,
                            style: const TextStyle(fontSize: 12)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
