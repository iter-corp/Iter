import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../utils/responsive.dart';

class BottomNav extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onTap;

  const BottomNav({
    super.key,
    required this.selectedIndex,
    required this.onTap,
  });

  static const List<String> _icons = [
    "assets/icons/Home.svg",
    "assets/icons/Event.svg",
    "assets/icons/Translate.svg",
    "assets/icons/Message.svg",
    "assets/icons/Profile.svg",
  ];

  @override
  Widget build(BuildContext context) {
    final isXSmall = context.isXSmall;
    final hMargin = context.scaleW(10, 20);
    // Honor iOS home indicator / Android nav bar inset; never go below 8.
    final double rawBottom = context.bottomSafeInset > 0
        ? context.bottomSafeInset * 0.5 + 6
        : 16.0;
    final bottomMargin = rawBottom.clamp(8.0, 28.0);
    final hPad = isXSmall ? 8.0 : 12.0;
    final vPad = isXSmall ? 10.0 : 12.0;
    final itemPad = isXSmall ? 6.0 : 8.0;
    final iconSize = isXSmall ? 20.0 : 24.0;

    return Container(
      margin: EdgeInsets.only(bottom: bottomMargin, left: hMargin, right: hMargin),
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
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
        children: List.generate(_icons.length, (index) {
          final bool isSelected = selectedIndex == index;

          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(index),
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: EdgeInsets.all(itemPad),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.white : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: SvgPicture.asset(
                    _icons[index],
                    width: iconSize,
                    height: iconSize,
                    colorFilter: ColorFilter.mode(
                      isSelected ? Colors.black : Colors.white,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}