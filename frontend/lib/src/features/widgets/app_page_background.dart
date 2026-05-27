import 'dart:ui';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Shared soft page background used by the main app tabs.
class AppPageBackground extends StatelessWidget {
  final Widget child;

  const AppPageBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: context.isDark
              ? const [Color(0xFF101017), Color(0xFF171726), Color(0xFF11111A)]
              : const [Color(0xFFF8F5FF), Color(0xFFEFF6FF), Color(0xFFFDF7F2)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -60,
            right: -30,
            child: _AmbientGlow(
              size: 220,
              color: const Color(0xFF6FA8FF)
                  .withValues(alpha: context.isDark ? 0.12 : 0.18),
            ),
          ),
          Positioned(
            top: 140,
            left: -50,
            child: _AmbientGlow(
              size: 180,
              color: const Color(0xFFC08BFF)
                  .withValues(alpha: context.isDark ? 0.10 : 0.16),
            ),
          ),
          Positioned(
            bottom: -70,
            right: 30,
            child: _AmbientGlow(
              size: 200,
              color: const Color(0xFF6EE7B7)
                  .withValues(alpha: context.isDark ? 0.08 : 0.14),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _AmbientGlow extends StatelessWidget {
  final double size;
  final Color color;

  const _AmbientGlow({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, Colors.transparent],
          ),
        ),
      ),
    );
  }
}

/// Shared glass surface used for cards and tool panels on the app background.
class AppGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final bool emphasize;
  final double? width;
  final double? height;
  final BoxConstraints? constraints;
  final double? surfaceAlpha;
  final double? borderAlpha;

  const AppGlassCard({
    super.key,
    required this.child,
    this.margin,
    this.padding,
    this.radius = 18,
    this.emphasize = false,
    this.width,
    this.height,
    this.constraints,
    this.surfaceAlpha,
    this.borderAlpha,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final surfaceColor = isDark
        ? const Color(0xFF1E1E2C).withValues(alpha: surfaceAlpha ?? 0.50)
        : Colors.white.withValues(alpha: surfaceAlpha ?? 0.40);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: borderAlpha ?? 0.14)
        : Colors.white.withValues(alpha: borderAlpha ?? 0.45);
    final outerShadow = isDark
        ? Colors.black.withValues(alpha: 0.14)
        : const Color(0xFF0A1B3D).withValues(alpha: 0.07);

    Widget card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: outerShadow,
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
          if (emphasize)
            BoxShadow(
              color: AppColors.purple.withValues(alpha: isDark ? 0.20 : 0.10),
              blurRadius: 18,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: borderColor),
            ),
            child: padding == null
                ? child
                : Padding(
                    padding: padding!,
                    child: child,
                  ),
          ),
        ),
      ),
    );

    if (width != null || height != null || constraints != null) {
      card = Container(
        width: width,
        height: height,
        constraints: constraints,
        child: card,
      );
    }
    if (margin != null) {
      card = Padding(padding: margin!, child: card);
    }
    return card;
  }
}
