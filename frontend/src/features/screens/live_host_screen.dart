import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../providers/live_providers.dart';
import '../../services/live_service.dart';

class LiveHostScreen extends ConsumerStatefulWidget {
  final LiveStream stream;

  const LiveHostScreen({super.key, required this.stream});

  @override
  ConsumerState<LiveHostScreen> createState() => _LiveHostScreenState();
}

class _LiveHostScreenState extends ConsumerState<LiveHostScreen> {
  RtcEngine? _engine;
  bool _joined = false;
  bool _loading = true;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _startHost();
  }

  Future<bool> _ensurePermissions() async {
    if (kIsWeb) return true;
    final statuses = await [
      Permission.camera,
      Permission.microphone,
    ].request();
    return statuses.values.every((status) => status.isGranted);
  }

  Future<void> _startHost() async {
    try {
      final hasPermissions = await _ensurePermissions();
      if (!hasPermissions) {
        setState(() {
          _errorText =
              'Camera and microphone permissions are required to go live.';
          _loading = false;
        });
        return;
      }

      if (widget.stream.appId == null || widget.stream.token == null) {
        setState(() {
          _errorText = 'Live credentials are not configured on the backend.';
          _loading = false;
        });
        return;
      }

      final engine = createAgoraRtcEngine();
      await engine.initialize(RtcEngineContext(appId: widget.stream.appId));
      await engine.enableVideo();
      await engine.startPreview();
      await engine.setClientRole(
        role: ClientRoleType.clientRoleBroadcaster,
      );

      engine.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (_, __) {
            if (!mounted) return;
            setState(() => _joined = true);
          },
          onError: (error, _) {
            if (!mounted) return;
            setState(() {
              _errorText = 'Agora error: $error';
            });
          },
        ),
      );

      await engine.joinChannel(
        token: widget.stream.token!,
        channelId: widget.stream.id,
        uid: 0,
        options: const ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          publishCameraTrack: true,
          publishMicrophoneTrack: true,
          autoSubscribeAudio: true,
          autoSubscribeVideo: true,
        ),
      );

      if (!mounted) {
        await engine.release();
        return;
      }

      setState(() {
        _engine = engine;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorText = 'Unable to start live stream';
        _loading = false;
      });
    }
  }

  Future<void> _retryStart() async {
    await _cleanupAgora();
    if (!mounted) return;
    setState(() {
      _errorText = null;
      _loading = true;
      _joined = false;
    });
    await _startHost();
  }

  Future<void> _cleanupAgora() async {
    final engine = _engine;
    _engine = null;
    if (engine == null) return;
    try {
      await engine.leaveChannel();
    } catch (_) {}
    await engine.release();
  }

  Future<void> _endLive() async {
    await ref.read(liveServiceProvider).endStream(widget.stream.id);
    await _cleanupAgora();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _cleanupAgora();
    super.dispose();
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorText != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _errorText!,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _retryStart,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_engine == null || !_joined) {
      return const Center(
        child: Text('Unable to start stream',
            style: TextStyle(color: Colors.white)),
      );
    }
    return AgoraVideoView(
      controller: VideoViewController(
        rtcEngine: _engine!,
        canvas: const VideoCanvas(uid: 0),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _buildBody()),
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _endLive,
                    child:
                        const Icon(Icons.close, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.stream.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: _endLive,
                    child: const Text(
                      'End',
                      style: TextStyle(color: Colors.redAccent),
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
