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
    _loadAutoTranslatePrefs();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final uid = _currentUid;
      if (uid == null) return;
      ref.read(presenceServiceProvider).setOnline(uid);
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
        final restrictMessaging =
            chatDoc['restrictMessaging'] as bool? ?? false;
        final adminOnly = chatDoc['adminOnly'] as bool? ?? false;
        final admins = (chatDoc['admins'] as List<dynamic>?) ?? [];
        final isAdmin = admins.contains(uid);

        if (restrictMessaging && !isAdmin) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Messaging is restricted in this group')),
            );
          }
          return;
        }

        if (adminOnly && !isAdmin) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Only admins can message in this group')),
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
              const SnackBar(
                  content: Text('Media sharing is disabled in this group')),
            );
          }
          return false;
        }
        if ((restrictMessaging || adminOnly) && !isAdmin) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('You cannot send media in this group')),
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
              title: const Text('Photo'),
              onTap: () => Navigator.pop(sheet, _AttachChoice.image),
            ),
            ListTile(
              leading:
                  const Icon(Icons.videocam_outlined, color: Color(0xFFB05ECC)),
              title: const Text('Video'),
              onTap: () => Navigator.pop(sheet, _AttachChoice.video),
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined,
                  color: Color(0xFFB05ECC)),
              title: const Text('File'),
              subtitle: const Text(
                'PDF, document, archive, …',
                style: TextStyle(fontSize: 12),
              ),
              onTap: () => Navigator.pop(sheet, _AttachChoice.file),
            ),
            ListTile(
              leading: const Icon(Icons.location_on_outlined,
                  color: Color(0xFFB05ECC)),
              title: const Text('Location'),
              subtitle: const Text(
                'Share your current location',
                style: TextStyle(fontSize: 12),
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
        AppFeedback.showErrorOn(
          messenger,
          'Location services are off. Enable them in device settings.',
        );
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        AppFeedback.showErrorOn(messenger, 'Location permission denied.');
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
      setState(() => _replyTarget = null);
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
      AppFeedback.showSuccessOn(messenger, 'Location shared');
    } catch (e) {
      AppFeedback.showErrorOn(messenger, 'Could not share location: $e');
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
          const SnackBar(
              content: Text('Video is too large. Max size is 1 GB.')),
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
          SnackBar(content: Text('Could not open file picker: $e')),
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
          const SnackBar(content: Text('Could not read selected file')),
        );
      }
      return;
    }
    if (picked.size > _kMaxAttachmentBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File is too large. Max size is 1 GB.')),
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
              const SnackBar(
                  content: Text('Media sharing is disabled in this group')),
            );
          }
          return;
        }

        if ((restrictMessaging || adminOnly) && !isAdmin) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content:
                      Text('You cannot send voice messages in this group')),
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
            const SnackBar(
                content: Text('Voice message too short (min 300ms)')),
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
            const SnackBar(
                content: Text('Failed to upload voice message - empty URL')),
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
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Automatically translate the other person\'s messages '
                      'into your preferred language. You can still tap any '
                      'message to see the original.',
                      style: TextStyle(
                          color:
                              Theme.of(sheetContext).textTheme.bodySmall?.color,
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
    if (await _ensureMessageVisible(messageId)) return;

    if (_messageOrder.isEmpty) {
      _showReplyNavSnack('Original message is no longer in view');
      return;
    }

    final targetIndex = _messageOrder.indexOf(messageId);
    if (targetIndex < 0) {
      _showReplyNavSnack('Original message was deleted');
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
      _showReplyNavSnack('Original message is no longer in view');
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

    _showReplyNavSnack('Original message is no longer in view');
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
    if (m.encryptedUnreadable) return '🔒 Encrypted message';
    if (m.stickerUrl != null && m.stickerUrl!.isNotEmpty) return 'Sticker';
    if (m.voiceUrl != null && m.voiceUrl!.isNotEmpty) return 'Voice message';
    if (m.imageUrl != null && m.imageUrl!.isNotEmpty) return 'Photo';
    if (m.sharedPostId != null && m.sharedPostId!.isNotEmpty) {
      return 'Shared post';
    }
    return m.text;
  }

  Future<void> _sendSticker(String stickerUrl, String? packId) async {
    final uid = _currentUid;
    if (uid == null) return;
    setState(() => _showStickerPicker = false);
    final reply = _replyTarget;
    setState(() => _replyTarget = null);

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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send sticker: $e')),
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
        ? 'You\'ve blocked this user. Unblock from their profile to send messages.'
        : (theyBlockedMe ? 'You can\'t reply to this conversation.' : null);

    ref.listen(messagesProvider(widget.chatId), (_, __) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
        unawaited(_markSeenNow());
      });
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
                  PopupMenuButton<String>(
                    tooltip: 'Chat options',
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
                      const PopupMenuItem(
                        value: 'auto-delete',
                        child: Row(
                          children: [
                            Icon(Icons.timer_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Auto-delete messages'),
                          ],
                        ),
                      ),
                      if (!isGroup)
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline,
                                  size: 18, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Delete chat',
                                  style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            Divider(height: 1, color: Theme.of(context).dividerColor),

            // E2EE BANNER (1:1 + group chats; both are encrypted in v1)
            const _E2EEBanner(),

            // MESSAGES
            Expanded(
              child: messagesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
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
                      child: Text('Say hello!',
                          style: TextStyle(color: context.textSecondary)),
                    );
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
                          otherAvatar: widget.otherAvatar,
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
                          IconButton(
                            tooltip: 'Attach',
                            onPressed: _showAttachMenu,
                            icon: Icon(Icons.attach_file,
                                color: context.textSecondary),
                          ),
                          GestureDetector(
                            onTap: () {
                              setState(() =>
                                  _showStickerPicker = !_showStickerPicker);
                            },
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 2),
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                child: Icon(
                                  _showStickerPicker
                                      ? Icons.keyboard
                                      : Icons.emoji_emotions_outlined,
                                  key: ValueKey(_showStickerPicker),
                                  size: 24,
                                  color: _showStickerPicker
                                      ? const Color(0xFFB05ECC)
                                      : context.textSecondary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 2),
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
                                    color: context.inputFill,
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(
                                      color: activeBorder
                                          ? const Color(0xFFB05ECC)
                                          : context.borderColor
                                              .withValues(alpha: 0.72),
                                      width: activeBorder ? 1.3 : 1,
                                    ),
                                    boxShadow: activeBorder
                                        ? [
                                            BoxShadow(
                                              color: const Color(0xFFB05ECC)
                                                  .withValues(alpha: 0.16),
                                              blurRadius: 12,
                                              offset: const Offset(0, 2),
                                            ),
                                          ]
                                        : const [],
                                  ),
                                  child: TextField(
                                    controller: _controller,
                                    focusNode: _messageFocusNode,
                                    onChanged: _onTextChanged,
                                    onTapOutside: (_) =>
                                        _messageFocusNode.unfocus(),
                                    minLines: 1,
                                    maxLines: 6,
                                    keyboardType: TextInputType.multiline,
                                    textInputAction: TextInputAction.newline,
                                    textDirection: dir,
                                    textAlign: dir == ui.TextDirection.rtl
                                        ? TextAlign.right
                                        : TextAlign.left,
                                    textCapitalization:
                                        TextCapitalization.sentences,
                                    decoration: InputDecoration(
                                      hintText: 'Write a message',
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
                              return GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: hasText
                                    ? _sendMessage
                                    : _startVoiceRecording,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOutCubic,
                                  width: 44,
                                  height: 44,
                                  margin: const EdgeInsets.all(4),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: hasText
                                        ? const Color(0xFFB05ECC)
                                        : Colors.transparent,
                                  ),
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
                                          : const Color(0xFFB05ECC),
                                      size: 22,
                                    ),
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
    const options = <_AutoDeleteOption>[
      _AutoDeleteOption('Off', null),
      _AutoDeleteOption('1 day', Duration(days: 1)),
      _AutoDeleteOption('1 week', Duration(days: 7)),
      _AutoDeleteOption('1 month', Duration(days: 30)),
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
                alignment: Alignment.centerLeft,
                child: Text(
                  'Auto-delete messages',
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
                alignment: Alignment.centerLeft,
                child: Text(
                  'Messages older than the chosen period are removed. '
                  'The chat itself stays in your inbox.',
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
                ? 'Auto-delete turned off'
                : 'Auto-delete: messages older than ${picked.label}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _confirmDeleteChat({required bool isGroup}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete chat?'),
        content: const Text(
          'This permanently removes every message in this chat for both '
          'people. Photos and voice notes already uploaded won\'t be '
          'recoverable from the chat. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.red),
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
          .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }
}

class _AutoDeleteOption {
  final String label;
  final Duration? duration;
  const _AutoDeleteOption(this.label, this.duration);
}

// ─────────────────────────────────────────────
// E2EE banner + info sheet
//
// Shown at the top of every 1:1 chat. Tapping opens a sheet that explains,
// in honest detail, what's encrypted and what isn't — so users don't read
// "🔒 Encrypted" and assume things we don't actually cover (media, lat/lng,
// reply-to ids, etc.) are also secret.
// ─────────────────────────────────────────────

class _E2EEBanner extends StatelessWidget {
  const _E2EEBanner();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showE2EEInfoSheet(context),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: AppColors.purple.withValues(alpha: 0.08),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 14, color: AppColors.purple),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Messages are end-to-end encrypted. Tap for details.',
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
        ),
      ),
    );
  }
}

void _showE2EEInfoSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.borderColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.lock_outline, size: 22, color: AppColors.purple),
                  const SizedBox(width: 10),
                  Text(
                    'End-to-end encrypted',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: context.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Your messages are encrypted on this device using a key only '
                'you and the other members of this chat hold. The Coil '
                'servers and anyone with database access cannot read your '
                'message text — only ciphertext. In group chats, the key '
                'is rotated automatically when members are added or removed.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              _E2EERow(
                icon: Icons.check_circle_outline,
                color: Colors.green,
                title: 'Encrypted',
                body: 'Message text, voice transcripts, reply-to text, '
                    'location labels, and file names.',
              ),
              const SizedBox(height: 10),
              _E2EERow(
                icon: Icons.info_outline,
                color: Colors.orange,
                title: 'Not yet encrypted',
                body: 'Photos, videos, voice recordings, file contents, '
                    'shared posts, stickers, and exact location coordinates. '
                    'These still upload via the same secure transport but '
                    'are stored unencrypted on the server.',
              ),
              const SizedBox(height: 10),
              _E2EERow(
                icon: Icons.shield_outlined,
                color: AppColors.purple,
                title: 'Visible to the server',
                body: 'Sender, recipient, timestamps, and message size. '
                    'These are needed for delivery and notifications.',
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.surfaceSoft,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.borderColor),
                ),
                child: Text(
                  'Your private key never leaves this device. Signing in on '
                  'a new device creates a fresh key, so old encrypted '
                  'messages won\'t be readable there.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: context.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(sheetCtx),
                  child: const Text('Got it'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _E2EERow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  const _E2EERow({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: context.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
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
    if (msg.encryptedUnreadable) {
      return Text(
        '🔒 Encrypted message (can\'t decrypt on this device)',
        style: originalStyle,
      );
    }
    if (!widget.autoTranslate || isMe || msg.text.trim().isEmpty) {
      return Text(msg.text, style: originalStyle);
    }

    final body = _showOriginal
        ? msg.text
        : (_translated ?? msg.text); // until translation arrives, show original

    final hintColor =
        isMe ? Colors.white.withValues(alpha: 0.85) : const Color(0xFFB05ECC);

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
    final senderName =
        isGroup ? ((senderLive?['username'] as String?) ?? 'Member') : '';
    final senderUidForTap = isGroup ? msg.senderUid : otherUid;

    final hasReply = msg.replyToId != null && msg.replyToId!.isNotEmpty;
    final hasVoice = msg.voiceUrl != null && msg.voiceUrl!.isNotEmpty;
    final hasSticker = msg.stickerUrl != null && msg.stickerUrl!.isNotEmpty;

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
                    child: hasSticker
                        ? _buildStickerBubble(context, hasReply)
                        : AnimatedContainer(
                            duration: const Duration(milliseconds: 280),
                            curve: Curves.easeOut,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: widget.flashing
                                  ? const Color(0xFFB05ECC)
                                      .withValues(alpha: 0.85)
                                  : (isMe
                                      ? const Color(0xFFB05ECC)
                                      : context.inputFill),
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(16),
                                topRight: const Radius.circular(16),
                                bottomLeft: Radius.circular(isMe ? 16 : 4),
                                bottomRight: Radius.circular(isMe ? 4 : 16),
                              ),
                              boxShadow: widget.flashing
                                  ? [
                                      BoxShadow(
                                        color: const Color(0xFFB05ECC)
                                            .withValues(alpha: 0.5),
                                        blurRadius: 14,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
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
                                          ? Colors.white
                                          : context.textPrimary,
                                    ),
                                  ],
                                ] else if (msg.fileUrl != null &&
                                    msg.fileUrl!.isNotEmpty) ...[
                                  _FileMessageBubble(
                                    url: msg.fileUrl!,
                                    fileName: msg.fileName ?? 'Attachment',
                                    mimeType: msg.fileMimeType,
                                    sizeBytes: msg.fileSizeBytes,
                                    isMe: isMe,
                                  ),
                                  if (msg.text.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    _buildBody(
                                      textColor: isMe
                                          ? Colors.white
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
                                          ? Colors.white
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
                                          ? Colors.white
                                          : context.textPrimary,
                                    ),
                                  ],
                                ] else
                                  _buildBody(
                                    textColor: isMe
                                        ? Colors.white
                                        : context.textPrimary,
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
            // Translate to the user's preferred language. Falls back to
            // English when the user hasn't set one yet (handled by the
            // preferredLanguageProvider default).
            if (msg.text.trim().isNotEmpty)
              Consumer(
                builder: (context, sheetRef, _) {
                  final target = sheetRef.watch(preferredLanguageProvider);
                  return ListTile(
                    leading: const Icon(Icons.translate),
                    title: Text('Translate to ${target.toUpperCase()}'),
                    subtitle: Text(
                      'Change in Settings → Preferred language',
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
            // Voice message options. Transcript is captured on the
            // sender's device when the recording starts; if it's
            // missing (mic contention, language unsupported, etc.) we
            // still offer the entry but flag it as unavailable.
            if (msg.voiceUrl != null && msg.voiceUrl!.isNotEmpty) ...[
              ListTile(
                leading: const Icon(Icons.subtitles_outlined),
                title: const Text('Show transcript'),
                subtitle: (msg.voiceTranscript ?? '').trim().isEmpty
                    ? const Text(
                        'Transcript unavailable for this message',
                        style: TextStyle(fontSize: 11),
                      )
                    : null,
                enabled: (msg.voiceTranscript ?? '').trim().isNotEmpty,
                onTap: () {
                  Navigator.pop(sheet);
                  _showVoiceTranscriptSheet(
                    context,
                    transcript: msg.voiceTranscript ?? '',
                  );
                },
              ),
              if ((msg.voiceTranscript ?? '').trim().isNotEmpty)
                Consumer(
                  builder: (context, sheetRef, _) {
                    final target = sheetRef.watch(preferredLanguageProvider);
                    return ListTile(
                      leading: const Icon(Icons.translate),
                      title: Text('Translate voice to ${target.toUpperCase()}'),
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
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text(
                'Delete',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.pop(sheet);
                _showDeleteMessageOptions(context);
              },
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
              title: const Text('Delete for me'),
              onTap: () => Navigator.pop(sheet, _DeleteMessageScope.mine),
            ),
            if (isMe)
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: Text(
                  widget.isGroup
                      ? 'Delete for everyone'
                      : 'Delete for both people',
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
                  ? 'Delete for everyone?'
                  : 'Delete for both people?')
              : 'Delete for me?',
        ),
        content: Text(
          scope == _DeleteMessageScope.everyone
              ? 'This message will be removed for everyone in this chat.'
              : 'This message will only be removed from your chat history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Delete',
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
                ? 'Message deleted for everyone'
                : 'Message deleted for you',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
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
              const Row(
                children: [
                  Icon(Icons.subtitles_outlined, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Voice transcript',
                    style: TextStyle(
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
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ),
            ],
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
                  'Translation (${widget.target.toUpperCase()})',
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
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
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
    final name = (who?['username'] as String?) ?? 'Someone';
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
    final fg =
        isMe ? Colors.white.withValues(alpha: 0.85) : const Color(0xFFB05ECC);
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
                  child: Icon(Icons.broken_image, size: 14, color: fg),
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
            label: (label ?? '').trim().isEmpty ? 'Shared location' : label,
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
                    ? 'Shared location'
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
            label: Text('Directions', style: TextStyle(color: fg)),
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
          SnackBar(content: Text('Open failed: ${result.message}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Open failed: $e')),
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
        title: Text('Send to ${widget.recipient}'),
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
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(true),
                      icon: const Icon(Icons.send),
                      label: const Text('Send'),
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

  String _statusLabel() {
    switch (pending.status) {
      case _PendingStatus.uploading:
        return 'Uploading…';
      case _PendingStatus.sending:
        return 'Sending…';
      case _PendingStatus.failed:
        return 'Failed to send';
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
                      _statusLabel(),
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
                        child:
                            const Text('Retry', style: TextStyle(fontSize: 12)),
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
                        child: const Text('Dismiss',
                            style: TextStyle(fontSize: 12)),
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
