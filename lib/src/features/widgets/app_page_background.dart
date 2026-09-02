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

/// Circular frosted back button that floats over a scrolling settings list,
/// matching the pill Instagram keeps pinned in the top-left of its
/// "Settings and activity" screen. Blurs whatever scrolls behind it and lays
/// a faint tint on top so it stays legible over any content.
class FrostedCircleBackButton extends StatelessWidget {
  const FrostedCircleBackButton({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return Center(
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: 6),
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Material(
              color: (isDark ? Colors.white : Colors.black)
                  .withValues(alpha: isDark ? 0.14 : 0.06),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap ?? () => Navigator.of(context).maybePop(),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(
                    Icons.arrow_back_ios_new,
                    size: 18,
                    color: context.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Frosted-glass fill for a pinned [SliverAppBar.flexibleSpace] so the list
/// blurs as it scrolls behind the title — the header treatment Instagram uses
/// on its "Settings and activity" screen. Blurs whatever sits behind the bar
/// and lays a translucent tint on top, matching [GlassBar].
class FrostedAppBarBackground extends StatelessWidget {
  const FrostedAppBarBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: (isDark ? const Color(0xFF12121A) : Colors.white)
                .withValues(alpha: 0.55),
            border: Border(
              bottom: BorderSide(
                color: (isDark ? Colors.white : Colors.black)
                    .withValues(alpha: 0.06),
              ),
            ),
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
            // Gives descendants like ListTile a Material ancestor to paint
            // ink splashes on — otherwise they'd render behind this card's
            // own background DecoratedBox and be invisible.
            child: Material(
              type: MaterialType.transparency,
              child: padding == null
                  ? child
                  : Padding(
                      padding: padding!,
                      child: child,
                    ),
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

/// Frosted-glass strip used behind a pinned [TabBar] / search row so the
/// header blends into the app's glass UI instead of showing a flat grey
/// slab. Blurs whatever sits behind it and lays a translucent surface tint
/// on top, matching [AppGlassCard].
class GlassBar extends StatelessWidget {
  const GlassBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF1E1E2C).withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.55),
            border: Border(
              bottom: BorderSide(
                color: (isDark ? Colors.white : Colors.black)
                    .withValues(alpha: 0.06),
              ),
            ),
          ),
          // Keeps TabBar / field ink splashes painting on a Material.
          child: Material(type: MaterialType.transparency, child: child),
        ),
      ),
    );
  }
}

/// A tabbed page whose title bar and [TabBar] are completely fixed — only
/// the content below the tabs scrolls. Drop-in replacement for the
/// `DefaultTabController` + `Scaffold` + `AppBar(bottom: TabBar)` +
/// `TabBarView` shape the admin screens used, with the tab row sitting on a
/// [GlassBar] so it blends into the app's glass UI.
class AppScrollTabScaffold extends StatelessWidget {
  const AppScrollTabScaffold({
    super.key,
    required this.length,
    required this.title,
    required this.tabs,
    required this.body,
    this.actions,
  });

  final int length;
  final Widget title;
  final List<Widget> tabs;
  final List<Widget>? actions;

  /// Content shown below the fixed tab bar — usually a [TabBarView], or a
  /// centered spinner / error while the data loads.
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: length,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // A plain AppBar never scrolls; the GlassBar covers the seam where
        // its gradient meets the body's.
        appBar: AppBar(
          title: title,
          actions: actions,
          centerTitle: false,
          backgroundColor: Colors.transparent,
          foregroundColor: context.textPrimary,
          elevation: 0,
          scrolledUnderElevation: 0,
          flexibleSpace: const AppPageBackground(child: SizedBox.expand()),
        ),
        body: AppPageBackground(
          child: Column(
            children: [
              GlassBar(
                child: TabBar(
                  labelColor: AppColors.purple,
                  unselectedLabelColor: context.textSecondary,
                  indicatorColor: AppColors.purple,
                  dividerColor: Colors.transparent,
                  dividerHeight: 0,
                  tabs: tabs,
                ),
              ),
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
  }
}
