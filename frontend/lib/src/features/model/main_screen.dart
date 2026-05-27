import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../providers/chat_providers.dart';
import '../../providers/post_providers.dart';
import '../../services/chat_service.dart';
import '../../services/error_report_service.dart';
import '../screens/home_screen.dart';
import '../screens/event_screen.dart'; // ✅ Added
import '../screens/message_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/translate_screen.dart';
import '../widgets/app_page_background.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  int _selectedIndex = 0;
  final ScrollController _homeScrollController = ScrollController();
  late final PageController _pageController;

  final List<String> _navIcons = [
    "assets/icons/Home.svg",
    "assets/icons/Event.svg",
    "assets/icons/Translate.svg",
    "assets/icons/Message.svg",
    "assets/icons/Profile.svg",
  ];

  // Human-readable names for error-report "screen" tracking, parallel to the
  // PageView children below.
  static const List<String> _tabScreenNames = [
    'Home',
    'Events',
    'Translate',
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
    _pageController = PageController(initialPage: _selectedIndex);
    _trackTab(_selectedIndex);
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
  }

  // 📌 SECTION: Resolve background color per tab
  @override
  Widget build(BuildContext context) {
    final inboxAsync = ref.watch(inboxProvider);
    final inbox = inboxAsync.valueOrNull ?? const <ChatConversation>[];
    final unreadChats = inbox.where((c) => c.unreadCount > 0).length;

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
              const TranslateBody(),
              const MessageBody(),
              const ProfileScreen(),
            ],
          ),

          // 📌 SECTION: Floating Bottom Nav
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
