import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/event_registration_providers.dart';
import '../../services/event_registration_service.dart';
import '../../theme/app_theme.dart';
import 'event_registration_sheet.dart';

class EventDetailScreen extends ConsumerStatefulWidget {
  final String eventId;
  final String title;
  final String subtitle;
  final String location;
  final List<String> imageUrls;
  final String description;
  final String phone;
  final String email;

  const EventDetailScreen({
    super.key,
    required this.eventId,
    required this.title,
    required this.subtitle,
    required this.location,
    required this.imageUrls,
    required this.description,
    required this.phone,
    required this.email,
  });

  @override
  ConsumerState<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends ConsumerState<EventDetailScreen> {
  int _currentImage = 0;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _prev() {
    if (_currentImage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _next() {
    if (_currentImage < widget.imageUrls.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.cardBg,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // 📌 SECTION: Back Arrow
              Padding(
                padding: const EdgeInsets.only(left: 14, top: 10, bottom: 6),
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Icon(
                    Icons.arrow_back,
                    size: 22,
                    color: context.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 6),

              // 📌 SECTION: Header — avatar + title + @subtitle
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 🔹 Circular avatar
                    ClipOval(
                      child: Image.network(
                        widget.imageUrls.first,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 44,
                          height: 44,
                          color: const Color(0xFFD0D0D0),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: context.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.subtitle,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF999999),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // 📌 SECTION: Full-width image carousel (zero horizontal padding, no border radius)
              SizedBox(
                width: double.infinity,
                height: 210,
                child: Stack(
                  children: [
                    // 🔹 PageView — full bleed
                 Padding(
                   padding: const EdgeInsets.all(4),
                   child: ClipRRect(
                    borderRadius: BorderRadius.circular(20), // 🔹 change value as needed
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: widget.imageUrls.length,
                      onPageChanged: (i) => setState(() => _currentImage = i),
                      itemBuilder: (_, i) => Image.network(
                        widget.imageUrls[i],
                        width: double.infinity,
                        height: 210,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            Container(color: const Color(0xFFD0D0D0)),
                      ),
                    ),
                  ),
                 ),
                    // 🔹 Left arrow — vertically centered
                    Positioned(
                      left: 12,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: _ArrowButton(
                          icon: Icons.chevron_left,
                          onTap: _prev,
                        ),
                      ),
                    ),

                    // 🔹 Right arrow — vertically centered
                    Positioned(
                      right: 12,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: _ArrowButton(
                          icon: Icons.chevron_right,
                          onTap: _next,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // 📌 SECTION: Description text
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  widget.description,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: context.textPrimary,
                    height: 1.6,
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // 📌 SECTION: Registration
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'If you would like to become one of us, you\ncan register below:',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimary,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _RegistrationButton(
                      eventId: widget.eventId,
                      eventTitle: widget.title,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // 📌 SECTION: Divider
              Divider(
                height: 1,
                thickness: 1,
                color: context.borderColor,
              ),

              const SizedBox(height: 20),

              // 📌 SECTION: Contact title
              Center(
                child: Text(
                  'Contact',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // 📌 SECTION: Phone row
              _ContactRow(
                icon: Icons.phone,
                iconColor: const Color(0xFF26A69A), // teal — matches design
                label: widget.phone,
              ),

              // 📌 SECTION: Email row
              _ContactRow(
                icon: Icons.mail,
                iconColor: Colors.black,
                label: widget.email,
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

// 📌 SECTION: Carousel Arrow Button
class _ArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _ArrowButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.4),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: Colors.white),
      ),
    );
  }
}

// 📌 SECTION: Contact Row
class _ContactRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;

  const _ContactRow({
    required this.icon,
    required this.iconColor,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 28, color: iconColor),
          const SizedBox(width: 16),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: context.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// 📌 SECTION: Registration Button (state-aware)
class _RegistrationButton extends ConsumerWidget {
  final String eventId;
  final String eventTitle;

  const _RegistrationButton({required this.eventId, required this.eventTitle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final regAsync = ref.watch(myRegistrationProvider(eventId));
    final reg = regAsync.value;

    String label;
    Color color;
    VoidCallback? onTap;

    if (reg == null) {
      label = 'Registration';
      color = const Color(0xFFCE5DE5);
      onTap = () => showEventRegistrationSheet(
            context,
            eventId: eventId,
            eventTitle: eventTitle,
          );
    } else {
      switch (reg.status) {
        case RegistrationStatus.pending:
          label = 'Request pending';
          color = Colors.grey.shade500;
          onTap = null;
          break;
        case RegistrationStatus.approved:
          label = 'Approved ✓';
          color = const Color(0xFF2EBD6B);
          onTap = null;
          break;
        case RegistrationStatus.rejected:
          label = 'Rejected — tap to retry';
          color = const Color(0xFFE04E5C);
          onTap = () => showEventRegistrationSheet(
                context,
                eventId: eventId,
                eventTitle: eventTitle,
              );
          break;
      }
    }

    return Align(
      alignment: Alignment.center,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(30),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}