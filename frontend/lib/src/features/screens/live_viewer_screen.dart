import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_strings.dart';
import '../../providers/live_providers.dart';
import '../../services/live_service.dart';

/// Viewer-side live join failure modes, resolved to a localized message in
/// [_buildVideoArea] where a BuildContext is available.
enum _LiveViewerError { sparkUnavailable, agora, unknown }

class LiveViewerScreen extends ConsumerStatefulWidget {
  final LiveStream stream;

  const LiveViewerScreen({super.key, required this.stream});

  @override
  ConsumerState<LiveViewerScreen> createState() => _LiveViewerScreenState();
}

class _LiveViewerScreenState extends ConsumerState<LiveViewerScreen> {
  RtcEngine? _engine;
  int? _remoteUid;
  _LiveViewerError? _errorKind;
  String _agoraErrorDetail = '';

  bool _joined = false;
  bool _loading = true;
  bool _roomCountReleased = false;

  @override
  void initState() {
    super.initState();
    _join();
  }

  Future<void> _join() async {
    try {
      final stream =
          await ref.read(liveServiceProvider).joinStream(widget.stream.id);

      if (!mounted) return;

      if (stream.appId == null || stream.token == null) {
        setState(() {
          _joined = false;
          _loading = false;
          _errorKind = _LiveViewerError.sparkUnavailable;
        });
        return;
      }

      final engine = createAgoraRtcEngine();
      await engine.initialize(RtcEngineContext(appId: stream.appId));
      await engine.enableVideo();
      await engine.setClientRole(
        role: ClientRoleType.clientRoleAudience,
      );

      engine.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (_, __) {
            if (!mounted) return;
            setState(() => _joined = true);
          },
          onUserJoined: (_, uid, __) {
            if (!mounted) return;
            setState(() => _remoteUid = uid);
          },
          onUserOffline: (_, uid, __) {
            if (!mounted) return;
            if (_remoteUid == uid) {
              setState(() => _remoteUid = null);
            }
          },
          onError: (error, _) {
            if (!mounted) return;
            setState(() {
              _errorKind = _LiveViewerError.agora;
              _agoraErrorDetail = '$error';
            });
          },
        ),
      );

      await engine.joinChannel(
        token: stream.token!,
        channelId: stream.id,
        uid: 0,
        options: const ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
          clientRoleType: ClientRoleType.clientRoleAudience,
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
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _errorKind = _LiveViewerError.unknown;
        });
      }
    }
  }

  Future<void> _leaveAgora() async {
    final engine = _engine;
    _engine = null;
    if (engine == null) return;
    try {
      await engine.leaveChannel();
    } catch (_) {}
    await engine.release();
  }

  Future<void> _releaseViewerCount() async {
    if (_roomCountReleased) return;
    _roomCountReleased = true;
    await ref.read(liveServiceProvider).leaveStream(widget.stream.id);
  }

  Future<void> _leave() async {
    await _releaseViewerCount();
    await _leaveAgora();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _releaseViewerCount();
    _leaveAgora();
    super.dispose();
  }

  Widget _buildVideoArea() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorKind != null) {
      final String message;
      switch (_errorKind!) {
        case _LiveViewerError.sparkUnavailable:
          message = context.t.liveUnavailableSpark;
          break;
        case _LiveViewerError.agora:
          message = context.t.liveAgoraError(_agoraErrorDetail);
          break;
        case _LiveViewerError.unknown:
          message = context.t.liveUnableToJoin;
          break;
      }
      return Center(
        child: Text(
          message,
          style: const TextStyle(color: Colors.white70),
          textAlign: TextAlign.center,
        ),
      );
    }
    if (_engine == null || !_joined) {
      return Center(
        child: Text(context.t.liveUnableToJoin,
            style: const TextStyle(color: Colors.white)),
      );
    }
    if (_remoteUid == null) {
      return Center(
        child: Text(
          context.t.liveWaitingHostVideo,
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }
    return AgoraVideoView(
      controller: VideoViewController.remote(
        rtcEngine: _engine!,
        canvas: VideoCanvas(uid: _remoteUid),
        connection: RtcConnection(channelId: widget.stream.id),
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
            // Video area placeholder
            Positioned.fill(
              child: _buildVideoArea(),
            ),

            // Top bar
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _leave,
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
                          fontSize: 15),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.person, color: Colors.white54, size: 18),
                  const SizedBox(width: 4),
                  StreamBuilder<List<LiveStream>>(
                    stream: ref.read(liveServiceProvider).getActiveStreams(),
                    builder: (context, snap) {
                      final count = snap.data
                              ?.firstWhere(
                                (s) => s.id == widget.stream.id,
                                orElse: () => widget.stream,
                              )
                              .viewersCount ??
                          widget.stream.viewersCount;
                      return Text(
                        '$count',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
                      );
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
}
