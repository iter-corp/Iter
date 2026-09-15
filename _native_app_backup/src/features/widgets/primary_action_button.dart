import 'package:flutter/material.dart';

/// The canonical positive-action button for Iter.
///
/// Lifted verbatim from the "ناردن / Send" pill in the share sheets so
/// every affirmative action (Send, Save, Publish, Submit, Continue,
/// Confirm) shares the same gradient pill chrome. Negative / dismissive
/// actions should stay on a neutral surface (outline, plain text).
///
/// Visual spec — keep these tokens in sync everywhere this is reused:
/// • Gradient — #B05ECC → #7E3BE8 (topLeft → bottomRight)
/// • Radius   — 30 px (stadium / pill)
/// • Padding  — 16h × 8v by default; bumped via [size]
/// • Shadow   — #B05ECC @ 35 % alpha, blur 10, offset (0, 4)
/// • Text     — white, w700, 13 px (default) / 14 px (large)
/// • Icon     — white, 14 px (default) / 18 px (large), leading
class PrimaryActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final PrimaryActionSize size;
  final bool loading;
  final bool fullWidth;

  const PrimaryActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.size = PrimaryActionSize.regular,
    this.loading = false,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || loading;
    final dims = _dimsFor(size);
    final btn = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(30),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: disabled ? null : onPressed,
        borderRadius: BorderRadius.circular(30),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFB05ECC), Color(0xFF7E3BE8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(30),
            boxShadow: disabled
                ? null
                : [
                    BoxShadow(
                      color:
                          const Color(0xFFB05ECC).withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          padding: EdgeInsets.symmetric(
            horizontal: dims.horizontalPadding,
            vertical: dims.verticalPadding,
          ),
          child: Opacity(
            opacity: disabled && !loading ? 0.55 : 1.0,
            child: Row(
              mainAxisSize:
                  fullWidth ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (loading)
                  SizedBox(
                    width: dims.iconSize,
                    height: dims.iconSize,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                else if (icon != null)
                  Icon(icon, color: Colors.white, size: dims.iconSize),
                if ((loading || icon != null)) SizedBox(width: dims.gap),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: dims.fontSize,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!fullWidth) return btn;
    return SizedBox(width: double.infinity, child: btn);
  }

  _Dims _dimsFor(PrimaryActionSize s) {
    switch (s) {
      case PrimaryActionSize.regular:
        return const _Dims(
          horizontalPadding: 16,
          verticalPadding: 8,
          fontSize: 13,
          iconSize: 14,
          gap: 6,
        );
      case PrimaryActionSize.large:
        return const _Dims(
          horizontalPadding: 22,
          verticalPadding: 14,
          fontSize: 15,
          iconSize: 18,
          gap: 8,
        );
    }
  }
}

enum PrimaryActionSize { regular, large }

class _Dims {
  final double horizontalPadding;
  final double verticalPadding;
  final double fontSize;
  final double iconSize;
  final double gap;
  const _Dims({
    required this.horizontalPadding,
    required this.verticalPadding,
    required this.fontSize,
    required this.iconSize,
    required this.gap,
  });
}
