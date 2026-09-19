import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;

import '../../l10n/app_strings.dart';

class ImageViewerScreen extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;

  const ImageViewerScreen({
    super.key,
    required this.urls,
    this.initialIndex = 0,
  });

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  late final PageController _controller;
  late int _index;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _saveCurrent() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final hasAccess = await Gal.hasAccess(toAlbum: false);
      final granted = hasAccess ? true : await Gal.requestAccess();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.t.permissionDenied)),
          );
        }
        return;
      }

      final resp = await http.get(Uri.parse(widget.urls[_index]));
      if (resp.statusCode != 200) {
        throw Exception('download failed (${resp.statusCode})');
      }
      await Gal.putImageBytes(resp.bodyBytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t.savedToGallery)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t.saveFailed(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: widget.urls.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: CachedNetworkImage(
                    imageUrl: widget.urls[i],
                    fit: BoxFit.contain,
                    placeholder: (_, __) => const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                    errorWidget: (_, __, ___) => const Center(
                      child: Icon(Icons.broken_image,
                          color: Colors.white, size: 48),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              child: _CircleAction(
                icon: Icons.arrow_back,
                onTap: () => Navigator.pop(context),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: _CircleAction(
                icon: _saving ? Icons.hourglass_bottom : Icons.download,
                onTap: _saveCurrent,
              ),
            ),
            if (widget.urls.length > 1) ...[
              if (_index > 0)
                PositionedDirectional(
                  start: 14,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _CircleAction(
                      icon: Directionality.of(context) == TextDirection.rtl
                          ? Icons.chevron_right_rounded
                          : Icons.chevron_left_rounded,
                      onTap: () {
                        _controller.previousPage(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeInOut,
                        );
                      },
                    ),
                  ),
                ),
              if (_index < widget.urls.length - 1)
                PositionedDirectional(
                  end: 14,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _CircleAction(
                      icon: Directionality.of(context) == TextDirection.rtl
                          ? Icons.chevron_left_rounded
                          : Icons.chevron_right_rounded,
                      onTap: () {
                        _controller.nextPage(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeInOut,
                        );
                      },
                    ),
                  ),
                ),
              Positioned(
                bottom: 20,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_index + 1} / ${widget.urls.length}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleAction({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}
