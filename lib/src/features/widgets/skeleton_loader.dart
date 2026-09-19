import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// An InheritedNotifier holding the synchronized [AnimationController]
/// for all skeleton elements in the sub-tree.
class _SkeletonScope extends InheritedNotifier<AnimationController> {
  final AnimationController controller;

  const _SkeletonScope({
    required this.controller,
    required super.child,
  }) : super(notifier: controller);
}

/// A wrapper that provides a synchronized shimmer animation to all
/// child [SkeletonBox] and skeleton components.
class SkeletonShimmer extends StatefulWidget {
  final Widget child;
  final Duration duration;

  const SkeletonShimmer({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 1200),
  });

  @override
  State<SkeletonShimmer> createState() => _SkeletonShimmerState();
}

class _SkeletonShimmerState extends State<SkeletonShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SkeletonScope(
      controller: _controller,
      child: widget.child,
    );
  }
}

/// Base responsive skeleton box.
/// Automatically hooks into the nearest [SkeletonShimmer] scope if available,
/// or falls back to an internal controller so it can also be used standalone.
class SkeletonBox extends StatefulWidget {
  final double? width;
  final double? height;
  final double borderRadius;
  final bool isCircle;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final Widget? child;

  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius = 8,
    this.isCircle = false,
    this.margin,
    this.padding,
    this.child,
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  AnimationController? _localController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = context.dependOnInheritedWidgetOfExactType<_SkeletonScope>();
    if (scope == null && _localController == null) {
      _localController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1200),
      )..repeat();
    } else if (scope != null && _localController != null) {
      _localController!.dispose();
      _localController = null;
    }
  }

  @override
  void dispose() {
    _localController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_SkeletonScope>();
    final controller = scope?.controller ?? _localController;

    final isDark = context.isDark;
    final baseColor = isDark
        ? const Color(0xFF1E1F26)
        : const Color(0xFFE8E9EF);
    final highlightColor = isDark
        ? const Color(0xFF2E303B)
        : const Color(0xFFF7F8FC);

    Widget buildContainer(double t) {
      return Container(
        width: widget.width,
        height: widget.height,
        margin: widget.margin,
        padding: widget.padding,
        decoration: BoxDecoration(
          shape: widget.isCircle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: widget.isCircle
              ? null
              : BorderRadius.circular(widget.borderRadius),
          gradient: LinearGradient(
            begin: Alignment(-2.0 + t * 4.0, -0.3),
            end: Alignment(-0.4 + t * 4.0, 0.3),
            colors: [baseColor, highlightColor, baseColor],
            stops: const [0.15, 0.5, 0.85],
          ),
        ),
        child: widget.child,
      );
    }

    if (controller == null) {
      return buildContainer(0.5);
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) => buildContainer(controller.value),
    );
  }
}

/// Circular avatar/icon skeleton
class SkeletonCircle extends StatelessWidget {
  final double size;
  final EdgeInsetsGeometry? margin;

  const SkeletonCircle({
    super.key,
    this.size = 40,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return SkeletonBox(
      width: size,
      height: size,
      isCircle: true,
      margin: margin,
    );
  }
}

/// Text line skeleton
class SkeletonLine extends StatelessWidget {
  final double? width;
  final double height;
  final double borderRadius;
  final EdgeInsetsGeometry? margin;

  const SkeletonLine({
    super.key,
    this.width,
    this.height = 14,
    this.borderRadius = 6,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return SkeletonBox(
      width: width,
      height: height,
      borderRadius: borderRadius,
      margin: margin,
    );
  }
}

/// Feed / Post detail post card skeleton
class SkeletonPostCard extends StatelessWidget {
  final bool isDetailed;

  const SkeletonPostCard({
    super.key,
    this.isDetailed = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final cardBg = isDark ? const Color(0xFF14161D) : Colors.white;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.06);

    return SkeletonShimmer(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header: Avatar + username + time + more icon
            const Row(
              children: [
                SkeletonCircle(size: 42),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonLine(width: 120, height: 14),
                      SizedBox(height: 6),
                      SkeletonLine(width: 70, height: 10),
                    ],
                  ),
                ),
                SkeletonBox(
                  width: 24,
                  height: 24,
                  borderRadius: 6,
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Post caption lines
            const SkeletonLine(width: double.infinity, height: 13),
            const SizedBox(height: 8),
            const FractionallySizedBox(
              widthFactor: 0.85,
              child: SkeletonLine(height: 13),
            ),
            const SizedBox(height: 8),
            const FractionallySizedBox(
              widthFactor: 0.55,
              child: SkeletonLine(height: 13),
            ),
            const SizedBox(height: 14),

            // Media block
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SkeletonBox(
                width: double.infinity,
                height: isDetailed ? 280 : 220,
                borderRadius: 14,
              ),
            ),
            const SizedBox(height: 16),

            // Action row (Like, Comment, Bookmark, Share)
            const Row(
              children: [
                SkeletonBox(width: 58, height: 28, borderRadius: 14),
                SizedBox(width: 12),
                SkeletonBox(width: 58, height: 28, borderRadius: 14),
                Spacer(),
                SkeletonBox(width: 32, height: 28, borderRadius: 14),
                SizedBox(width: 10),
                SkeletonBox(width: 32, height: 28, borderRadius: 14),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal story circles bar skeleton
class SkeletonStoryBar extends StatelessWidget {
  const SkeletonStoryBar({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: SizedBox(
        height: 104,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: 6,
          separatorBuilder: (_, __) => const SizedBox(width: 14),
          itemBuilder: (_, __) => const Column(
            children: [
              SkeletonCircle(size: 64),
              SizedBox(height: 6),
              SkeletonLine(width: 48, height: 9),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full Profile page skeleton
class SkeletonProfile extends StatelessWidget {
  final bool isOtherUser;

  const SkeletonProfile({
    super.key,
    this.isOtherUser = false,
  });

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          children: [
            // Cover banner & Avatar overlap
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.bottomLeft,
              children: [
                const SkeletonBox(
                  width: double.infinity,
                  height: 150,
                  borderRadius: 0,
                ),
                Positioned(
                  left: 20,
                  bottom: -40,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: context.isDark
                            ? const Color(0xFF101216)
                            : Colors.white,
                        width: 4,
                      ),
                    ),
                    child: const SkeletonCircle(size: 80),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 48),

            // Name, handle, bio
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonLine(width: 140, height: 18),
                          SizedBox(height: 6),
                          SkeletonLine(width: 90, height: 12),
                        ],
                      ),
                      SkeletonBox(
                        width: isOtherUser ? 96 : 84,
                        height: 36,
                        borderRadius: 18,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const SkeletonLine(width: double.infinity, height: 12),
                  const SizedBox(height: 6),
                  const FractionallySizedBox(
                    widthFactor: 0.65,
                    child: SkeletonLine(height: 12),
                  ),
                  const SizedBox(height: 20),

                  // Stats row (Posts, Followers, Following)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: List.generate(
                      3,
                      (_) => const Column(
                        children: [
                          SkeletonLine(width: 40, height: 18),
                          SizedBox(height: 4),
                          SkeletonLine(width: 60, height: 11),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Tab bar skeleton
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(
                  3,
                  (_) => const SkeletonLine(width: 64, height: 14),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 3-column square grid
            const SkeletonGrid(itemCount: 6),
          ],
        ),
      ),
    );
  }
}

/// 3-column square thumbnail grid for profile tabs
class SkeletonGrid extends StatelessWidget {
  final int itemCount;

  const SkeletonGrid({super.key, this.itemCount = 9});

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1,
        ),
        itemCount: itemCount,
        itemBuilder: (_, __) => const SkeletonBox(borderRadius: 14),
      ),
    );
  }
}

/// Comment tile skeleton
class SkeletonCommentTile extends StatelessWidget {
  const SkeletonCommentTile({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonCircle(size: 34),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SkeletonLine(width: 90, height: 13),
                    SizedBox(width: 8),
                    SkeletonLine(width: 44, height: 10),
                  ],
                ),
                SizedBox(height: 8),
                SkeletonLine(width: double.infinity, height: 12),
                SizedBox(height: 6),
                FractionallySizedBox(
                  widthFactor: 0.7,
                  child: SkeletonLine(height: 12),
                ),
              ],
            ),
          ),
          SizedBox(width: 8),
          SkeletonBox(width: 20, height: 20, borderRadius: 6),
        ],
      ),
    );
  }
}

/// List of comment skeletons
class SkeletonCommentList extends StatelessWidget {
  final int count;

  const SkeletonCommentList({super.key, this.count = 5});

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (_, __) => const SkeletonCommentTile(),
      ),
    );
  }
}

/// Notification item skeleton
class SkeletonNotificationTile extends StatelessWidget {
  const SkeletonNotificationTile({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF14161E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.04),
        ),
      ),
      child: const Row(
        children: [
          SkeletonCircle(size: 44),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLine(width: 150, height: 13),
                SizedBox(height: 6),
                SkeletonLine(width: 100, height: 11),
              ],
            ),
          ),
          SizedBox(width: 10),
          SkeletonBox(width: 32, height: 32, borderRadius: 8),
        ],
      ),
    );
  }
}

/// Notification list skeleton
class SkeletonNotificationList extends StatelessWidget {
  final int count;

  const SkeletonNotificationList({super.key, this.count = 7});

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: count,
        itemBuilder: (_, __) => const SkeletonNotificationTile(),
      ),
    );
  }
}

/// Explore search result list skeleton
class SkeletonExploreList extends StatelessWidget {
  final int count;

  const SkeletonExploreList({super.key, this.count = 6});

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return SkeletonShimmer(
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, __) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF151821) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.05),
            ),
          ),
          child: const Row(
            children: [
              SkeletonCircle(size: 46),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonLine(width: 110, height: 14),
                    SizedBox(height: 6),
                    SkeletonLine(width: 170, height: 11),
                  ],
                ),
              ),
              SizedBox(width: 8),
              SkeletonBox(width: 68, height: 30, borderRadius: 15),
            ],
          ),
        ),
      ),
    );
  }
}

/// Message / Conversation list skeleton
class SkeletonConversationList extends StatelessWidget {
  final int count;

  const SkeletonConversationList({super.key, this.count = 7});

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, __) => const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              SkeletonCircle(size: 50),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        SkeletonLine(width: 120, height: 14),
                        SkeletonLine(width: 40, height: 10),
                      ],
                    ),
                    SizedBox(height: 8),
                    SkeletonLine(width: 180, height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chat screen message bubble skeleton
class SkeletonChatMessages extends StatelessWidget {
  const SkeletonChatMessages({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: ListView(
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: const [
          // Outgoing
          Align(
            alignment: Alignment.centerRight,
            child: SkeletonBox(
              width: 210,
              height: 48,
              borderRadius: 18,
              margin: EdgeInsets.symmetric(vertical: 6),
            ),
          ),
          // Incoming
          Align(
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SkeletonCircle(size: 28),
                SizedBox(width: 8),
                SkeletonBox(
                  width: 170,
                  height: 40,
                  borderRadius: 18,
                  margin: EdgeInsets.symmetric(vertical: 6),
                ),
              ],
            ),
          ),
          // Outgoing
          Align(
            alignment: Alignment.centerRight,
            child: SkeletonBox(
              width: 140,
              height: 38,
              borderRadius: 18,
              margin: EdgeInsets.symmetric(vertical: 6),
            ),
          ),
          // Incoming
          Align(
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SkeletonCircle(size: 28),
                SizedBox(width: 8),
                SkeletonBox(
                  width: 240,
                  height: 60,
                  borderRadius: 18,
                  margin: EdgeInsets.symmetric(vertical: 6),
                ),
              ],
            ),
          ),
          // Outgoing
          Align(
            alignment: Alignment.centerRight,
            child: SkeletonBox(
              width: 180,
              height: 44,
              borderRadius: 18,
              margin: EdgeInsets.symmetric(vertical: 6),
            ),
          ),
        ],
      ),
    );
  }
}

/// Follow list / user list skeleton
class SkeletonUserList extends StatelessWidget {
  final int count;

  const SkeletonUserList({super.key, this.count = 7});

  static Widget sliver({int count = 6}) {
    return SliverToBoxAdapter(
      child: SkeletonUserList(count: count),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, __) => const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              SkeletonCircle(size: 46),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonLine(width: 110, height: 14),
                    SizedBox(height: 6),
                    SkeletonLine(width: 70, height: 11),
                  ],
                ),
              ),
              SkeletonBox(width: 78, height: 32, borderRadius: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// Generic list tile skeleton
class SkeletonListTile extends StatelessWidget {
  const SkeletonListTile({super.key});

  static Widget sliver({int count = 5}) {
    return SliverToBoxAdapter(
      child: SkeletonShimmer(
        child: ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: count,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, __) => const SkeletonListTile(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161822) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: const Row(
        children: [
          SkeletonBox(width: 36, height: 36, borderRadius: 8),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLine(width: 140, height: 13),
                SizedBox(height: 6),
                SkeletonLine(width: 90, height: 10),
              ],
            ),
          ),
          SkeletonBox(width: 24, height: 24, borderRadius: 6),
        ],
      ),
    );
  }
}

/// Full page list of skeleton tiles
class SkeletonList extends StatelessWidget {
  final int count;
  final EdgeInsetsGeometry padding;

  const SkeletonList({
    super.key,
    this.count = 6,
    this.padding = const EdgeInsets.all(12),
  });

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: ListView.separated(
        padding: padding,
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, __) => const SkeletonListTile(),
      ),
    );
  }
}

