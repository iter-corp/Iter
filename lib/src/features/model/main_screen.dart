import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../providers/chat_providers.dart';
import '../../providers/post_providers.dart';
import '../../services/chat_service.dart';
import '../../services/error_report_service.dart';
import '../screens/home_screen.dart';
import '../screens/event_screen.dart'; // ✅ Added
import '../screens/explore_screen.dart';
import '../screens/message_screen.dart';
import '../screens/profile_screen.dart';
import '../widgets/app_page_background.dart';
import '../widgets/desktop_nav_sidebar.dart';
import '../widgets/desktop_right_sidebar.dart';

class MainScreen extends ConsumerStatefulWidget {
  final int initialTab;
  const MainScreen({super.key, this.initialTab = 0});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  late int _selectedIndex;
  final ScrollController _homeScrollController = ScrollController();
  late final PageController _pageController;

  static const List<String> _tabRoutes = [
    '/home',
    '/events',
    '/explore',
    '/messages',
    '/profile',
  ];

  final List<String> _navIcons = [
    "assets/icons/Home.svg",
    "assets/icons/Event.svg",
    "assets/icons/Translate.svg", // unused — index 2 renders Icons.explore_outlined instead
    "assets/icons/Message.svg",
    "assets/icons/Profile.svg",
  ];

  // Human-readable names for error-report "screen" tracking, parallel to the
  // PageView children below.
  static const List<String> _tabScreenNames = [
    'Home',
    'Events',
    'Explore',
    'Messages',
    'Profile',
  ];

  void _trackTab(int index) {
    if (index >= 0 && index < _tabScreenNames.length) {
      ErrorReportService.instance.setCurrentScreen(_tabScreenNames[index]);
    }
  }

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialTab.clamp(0, 4);
    _pageController = PageController(initialPage: _selectedIndex);
    _trackTab(_selectedIndex);
  }

  @override
  void didUpdateWidget(covariant MainScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab && widget.initialTab != _selectedIndex) {
      final targetIndex = widget.initialTab.clamp(0, 4);
      setState(() => _selectedIndex = targetIndex);
      _trackTab(targetIndex);
      if (_pageController.hasClients) {
        _pageController.jumpToPage(targetIndex);
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _homeScrollController.dispose();
    super.dispose();
  }

  void _onNavTap(int index) {
    if (index == 0 && _selectedIndex == 0) {
      // Already on home — scroll to top and refresh feed
      if (_homeScrollController.hasClients) {
        _homeScrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        );
      }
      ref.invalidate(feedProvider);
      return;
    }
    if (index == _selectedIndex) return;

    setState(() => _selectedIndex = index);
    _trackTab(index);
    if (_pageController.hasClients) {
      _pageController.jumpToPage(index);
    }
    if (index >= 0 && index < _tabRoutes.length) {
      context.go(_tabRoutes[index]);
    }
  }

  // 📌 SECTION: Resolve background color per tab
  @override
  Widget build(BuildContext context) {
    final inboxAsync = ref.watch(inboxProvider);
    final inbox = inboxAsync.valueOrNull ?? const <ChatConversation>[];
    final unreadChats = inbox.where((c) => c.unreadCount > 0).length;

    // Hide the floating bottom nav while the keyboard is open so it doesn't
    // float above the keyboard / overlap the input the user is typing in.
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 1100;
    final isTablet = screenWidth >= 650 && screenWidth < 1100;
    final useSideNav = isDesktop || isTablet;
    final showRightSidebar = screenWidth >= 1260;

    if (useSideNav) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            const AppPageBackground(child: SizedBox.expand()),
            SafeArea(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Left Navigation Sidebar (Compact rail on Tablets, Full on Desktop) ──
                  DesktopNavSidebar(
                    selectedIndex: _selectedIndex,
                    onTabSelected: _onNavTap,
                    unreadChats: unreadChats,
                    isCompact: isTablet,
                  ),

                  // ── Center Content Column (Feed / Active Screen) ──
                  Expanded(
                    child: PageView(
                      controller: _pageController,
                      physics: const NeverScrollableScrollPhysics(),
                      onPageChanged: (index) {
                        if (_selectedIndex != index) {
                          setState(() => _selectedIndex = index);
                          _trackTab(index);
                        }
                      },
                      children: [
                        HomeBody(scrollController: _homeScrollController),
                        const EventBody(),
                        const ExploreBody(),
                        const MessageBody(),
                        const ProfileScreen(),
                      ],
                    ),
                  ),

                  // ── Right Sidebar (Widgets, Upcoming Events, Trending) ──
                  if (showRightSidebar)
                    DesktopRightSidebar(
                      onTabSelected: _onNavTap,
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: Stack(
        children: [
          const AppPageBackground(child: SizedBox.expand()),
          // 📌 SECTION: Current Screen
          PageView(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            onPageChanged: (index) {
              if (_selectedIndex != index) {
                setState(() => _selectedIndex = index);
                _trackTab(index);
              }
            },
            children: [
              HomeBody(scrollController: _homeScrollController),
              const EventBody(),
              const ExploreBody(),
              const MessageBody(),
              const ProfileScreen(),
            ],
          ),

          // 📌 SECTION: Floating Bottom Nav (hidden while the keyboard is up)
          if (!keyboardOpen)
            Positioned(
              left: 20,
              right: 20,
              bottom: 16 + MediaQuery.of(context).padding.bottom,
              child: ClipRRect(
              borderRadius: BorderRadius.circular(40),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(40),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.22)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.28),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: SizedBox(
                    height: 34,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        const bubbleSize = 34.0;
                        final slotWidth =
                            constraints.maxWidth / _navIcons.length;
                        // Distance of the selected slot from the *start*
                        // edge. AnimatedPositionedDirectional resolves
                        // `start` to left in LTR and right in RTL, so the
                        // white bubble tracks the (auto-mirrored) icon Row
                        // correctly in both directions.
                        final bubbleStart = (_selectedIndex * slotWidth) +
                            ((slotWidth - bubbleSize) / 2);

                        return Stack(
                          children: [
                            AnimatedPositionedDirectional(
                              duration: const Duration(milliseconds: 320),
                              curve: Curves.easeOutCubic,
                              start: bubbleStart,
                              top: 0,
                              width: bubbleSize,
                              height: bubbleSize,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.55),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.16),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                            Row(
                              children:
                                  List.generate(_navIcons.length, (index) {
                                final bool isSelected = _selectedIndex == index;
                                final showMessageBadge =
                                    index == 3 && unreadChats > 0;

                                return Expanded(
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => _onNavTap(index),
                                    child: SizedBox(
                                      height: bubbleSize,
                                      child: Center(
                                        child: Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            index == 1
                                                ? Icon(
                                                    Icons.diversity_3_rounded,
                                                    size: 22,
                                                    color: isSelected
                                                        ? Colors.black
                                                        : Colors.white,
                                                  )
                                                : index == 2
                                                    ? Icon(
                                                        Icons
                                                            .explore_outlined,
                                                        size: 22,
                                                        color: isSelected
                                                            ? Colors.black
                                                            : Colors.white,
                                                      )
                                                    : SvgPicture.asset(
                                                    _navIcons[index],
                                                    width: 22,
                                                    height: 22,
                                                    colorFilter:
                                                        ColorFilter.mode(
                                                      isSelected
                                                          ? Colors.black
                                                          : Colors.white,
                                                      BlendMode.srcIn,
                                                    ),
                                                  ),
                                            if (showMessageBadge)
                                              PositionedDirectional(
                                                end: -2,
                                                top: -2,
                                                child: Container(
                                                  width: 9,
                                                  height: 9,
                                                  decoration:
                                                      const BoxDecoration(
                                                    color: Color(0xFFFF4D4D),
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
