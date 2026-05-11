import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/storage_service.dart';
import '../../services/story_service.dart';
import '../../utils/app_feedback.dart';

class StoryPreviewScreen extends StatefulWidget {
  final File file;
  const StoryPreviewScreen({super.key, required this.file});

  @override
  State<StoryPreviewScreen> createState() => _StoryPreviewScreenState();
}

class _StoryPreviewScreenState extends State<StoryPreviewScreen> {
  bool _uploading = false;

  Future<void> _publish() async {
    if (_uploading) return;
    // Capture the messenger up-front so the success toast survives popping
    // back to the root route.
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _uploading = true);
    try {
      final url = await StorageService().uploadStoryImage(widget.file);
      await StoryService().createStory(imageUrl: url);
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      AppFeedback.showSuccessOn(messenger, 'Story published — content uploaded');
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      AppFeedback.showErrorOn(messenger, 'Failed to publish story: $e');
    }
  }

  void _cancel() {
    if (_uploading) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
        children: [
          Hero(
            tag: 'story_preview_${widget.file.path}',
            child: Image.file(widget.file, fit: BoxFit.cover),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 140,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.55),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 220,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.75),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Row(
                    children: [
                      _CircleIcon(icon: Icons.close, onTap: _cancel),
                      const Spacer(),
                    ],
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                  child: Row(
                    children: [
                      _PillButton(
                        label: 'Cancel',
                        filled: false,
                        onTap: _cancel,
                      ),
                      const Spacer(),
                      _PillButton(
                        label: 'Publish',
                        icon: Icons.send_rounded,
                        filled: true,
                        onTap: _publish,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_uploading)
            Container(
              color: Colors.black.withValues(alpha: 0.55),
              alignment: Alignment.center,
              child: const CircularProgressIndicator(color: Colors.white),
            ),
        ],
        ),
      ),
    );
  }
}

class _CircleIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleIcon({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool filled;
  final VoidCallback onTap;
  const _PillButton({
    required this.label,
    required this.filled,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        decoration: BoxDecoration(
          color: filled ? const Color(0xFFB05ECC) : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
          border: filled
              ? null
              : Border.all(
                  color: Colors.white.withValues(alpha: 0.7),
                  width: 1.5,
                ),
          boxShadow: filled
              ? [
                  BoxShadow(
                    color: const Color(0xFFB05ECC).withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            if (icon != null) ...[
              const SizedBox(width: 8),
              Icon(icon, color: Colors.white, size: 18),
            ],
          ],
        ),
      ),
    );
  }
}
