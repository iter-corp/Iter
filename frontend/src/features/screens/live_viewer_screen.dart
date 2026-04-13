import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/live_providers.dart';
import '../../services/live_service.dart';

class LiveViewerScreen extends ConsumerStatefulWidget {
  final LiveStream stream;

  const LiveViewerScreen({super.key, required this.stream});

  @override
  ConsumerState<LiveViewerScreen> createState() => _LiveViewerScreenState();
}

class _LiveViewerScreenState extends ConsumerState<LiveViewerScreen> {
  bool _joined = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _join();
  }

  Future<void> _join() async {
    try {
      await ref.read(liveServiceProvider).joinStream(widget.stream.id);
      if (mounted) {
        setState(() {
          _joined = true;
          _loading = false;
        });
        // TODO: initialize Agora RTC engine with _token and widget.stream.id
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _leave() async {
    await ref.read(liveServiceProvider).leaveStream(widget.stream.id);
    // TODO: leave Agora channel
    if (mounted) Navigator.pop(context);
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
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _joined
                      ? Container(
                          color: const Color(0xFF1A1A2E),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.live_tv,
                                    color: Colors.white54, size: 64),
                                const SizedBox(height: 16),
                                // TODO: render Agora RtcLocalView here once SDK added
                                Text(
                                  widget.stream.title,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Live video integration coming soon',
                                  style: TextStyle(
                                      color: Colors.white54, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        )
                      : const Center(
                          child: Text('Unable to join stream',
                              style: TextStyle(color: Colors.white))),
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
