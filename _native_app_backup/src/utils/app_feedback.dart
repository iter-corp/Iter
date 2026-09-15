import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Lightweight, consistent in-app feedback helpers.
///
/// Use [showSuccess] right after an action completes so the user gets a clear
/// confirmation (post published, content uploaded, saved, etc.). [showInfo] and
/// [showError] cover the neutral / failure cases with the same look.
///
/// The `…On` variants take a [ScaffoldMessengerState] directly — capture one
/// with `ScaffoldMessenger.of(context)` *before* popping a route so the toast
/// survives the navigation.
class AppFeedback {
  AppFeedback._();

  static const _success = (
    icon: Icons.check_circle_rounded,
    bg: AppColors.purple,
    fg: Colors.white,
  );
  static const _info = (
    icon: Icons.info_outline_rounded,
    bg: Color(0xFF333333),
    fg: Colors.white,
  );
  static const _error = (
    icon: Icons.error_outline_rounded,
    bg: Color(0xFFD7263D),
    fg: Colors.white,
  );

  static void showSuccess(BuildContext context, String message) =>
      showSuccessOn(ScaffoldMessenger.maybeOf(context), message);

  static void showInfo(BuildContext context, String message) =>
      showInfoOn(ScaffoldMessenger.maybeOf(context), message);

  static void showError(BuildContext context, String message) =>
      showErrorOn(ScaffoldMessenger.maybeOf(context), message);

  static void showSuccessOn(ScaffoldMessengerState? m, String message) =>
      _show(m, message, _success.icon, _success.bg, _success.fg);

  static void showInfoOn(ScaffoldMessengerState? m, String message) =>
      _show(m, message, _info.icon, _info.bg, _info.fg);

  static void showErrorOn(ScaffoldMessengerState? m, String message) =>
      _show(m, message, _error.icon, _error.bg, _error.fg);

  static void _show(
    ScaffoldMessengerState? messenger,
    String message,
    IconData icon,
    Color background,
    Color foreground,
  ) {
    if (messenger == null) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: background,
          duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          content: Row(
            children: [
              Icon(icon, color: foreground, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: foreground,
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

/// A small icon that briefly bumps in scale and flips to a "done" state when
/// [active] turns true. Used for save / bookmark / repost toggles so the tap
/// reads as a confirmed action rather than a silent state flip.
class PoppingActionIcon extends StatefulWidget {
  final bool active;
  final IconData activeIcon;
  final IconData inactiveIcon;
  final Color activeColor;
  final Color inactiveColor;
  final double size;

  const PoppingActionIcon({
    super.key,
    required this.active,
    required this.activeIcon,
    required this.inactiveIcon,
    required this.activeColor,
    required this.inactiveColor,
    this.size = 22,
  });

  @override
  State<PoppingActionIcon> createState() => _PoppingActionIconState();
}

class _PoppingActionIconState extends State<PoppingActionIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.35), weight: 40),
    TweenSequenceItem(tween: Tween(begin: 1.35, end: 1.0), weight: 60),
  ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

  @override
  void didUpdateWidget(covariant PoppingActionIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Icon(
        widget.active ? widget.activeIcon : widget.inactiveIcon,
        color: widget.active ? widget.activeColor : widget.inactiveColor,
        size: widget.size,
      ),
    );
  }
}
