import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../screens/home_screen.dart';
import '../screens/event_screen.dart';      // ✅ Added
import '../screens/message_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/translate_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  final List<String> _navIcons = [
    "assets/icons/Home.svg",
    "assets/icons/Event.svg",
    "assets/icons/Translate.svg",
    "assets/icons/Message.svg",
    "assets/icons/Profile.svg",
  ];

  final List<Widget> _screens = [
    const HomeBody(),
    const EventBody(),
    const TranslateBody(),
    const MessageBody(),
    const ProfileScreen(),
  ];

  // 📌 SECTION: Resolve background color per tab
  Color get _backgroundColor {
    switch (_selectedIndex) {
      case 1: // Events   ✅ Added
      case 3: // Messages
      case 4: // Profile
        return Colors.white;
      default:
        return const Color(0xFFE8EAF0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      extendBody: true,
      body: Stack(
        children: [
          // 📌 SECTION: Current Screen
          _screens[_selectedIndex],

          // 📌 SECTION: Floating Bottom Nav
          Positioned(
            left: 20,
            right: 20,
            bottom: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(40),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(_navIcons.length, (index) {
                  final bool isSelected = _selectedIndex == index;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedIndex = index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: SvgPicture.asset(
                        _navIcons[index],
                        width: 24,
                        height: 24,
                        colorFilter: ColorFilter.mode(
                          isSelected ? Colors.black : Colors.white,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}