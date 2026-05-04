import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

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
                      child: widget.imageUrls.isEmpty
                          ? Container(
                              width: 44,
                              height: 44,
                              color: context.borderColor,
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.event,
                                color: context.textSecondary,
                                size: 22,
                              ),
                            )
                          : Image.network(
                              widget.imageUrls.first,
                              width: 44,
                              height: 44,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 44,
                                height: 44,
                                color: context.borderColor,
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
                          style: TextStyle(
                            fontSize: 12,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // 📌 SECTION: Full-width image carousel (zero horizontal padding, no border radius)
              if (widget.imageUrls.isNotEmpty)
                SizedBox(
                  width: double.infinity,
                  height: 210,
                  child: Stack(
                    children: [
                      // 🔹 PageView — full bleed
                      Padding(
                        padding: const EdgeInsets.all(4),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(
                              20), // 🔹 change value as needed
                          child: PageView.builder(
                            controller: _pageController,
                            itemCount: widget.imageUrls.length,
                            onPageChanged: (i) =>
                                setState(() => _currentImage = i),
                            itemBuilder: (_, i) => Image.network(
                              widget.imageUrls[i],
                              width: double.infinity,
                              height: 210,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  Container(color: context.borderColor),
                            ),
                          ),
                        ),
                      ),
                      // 🔹 Left arrow — vertically centered
                      if (widget.imageUrls.length > 1)
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
                      if (widget.imageUrls.length > 1)
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

              const SizedBox(height: 24),

              // 📌 SECTION: Plan your trip (booking placeholders)
              if (widget.location.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _PlanTripSection(location: widget.location),
                ),

              const SizedBox(height: 24),

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
                iconColor: context.textPrimary,
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
          color = context.textSecondary;
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

// 📌 SECTION: Plan-your-trip booking placeholders
//
// External-link shortcuts to Booking.com (hotels) and Google Flights
// (flights). These are intentionally URL-based — no booking SDK is
// integrated yet. The destination is parsed from the event's location
// string, taking the first comma-separated segment as the city.
class _PlanTripSection extends StatelessWidget {
  final String location;
  const _PlanTripSection({required this.location});

  String get _destination {
    final first = location.split(',').first.trim();
    return first.isEmpty ? location.trim() : first;
  }

  Future<void> _openHotels(BuildContext context) async {
    final uri = Uri.parse(
      'https://www.booking.com/searchresults.html?ss=${Uri.encodeQueryComponent(_destination)}',
    );
    await _launch(context, uri, label: 'hotel search');
  }

  Future<void> _openFlights(BuildContext context) async {
    final uri = Uri.parse(
      'https://www.google.com/travel/flights?q=${Uri.encodeQueryComponent('Flights to $_destination')}',
    );
    await _launch(context, uri, label: 'flight search');
  }

  Future<void> _launch(BuildContext context, Uri uri,
      {required String label}) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $label')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.travel_explore_rounded,
                size: 18, color: Color(0xFFB05ECC)),
            const SizedBox(width: 6),
            Text(
              'Plan your trip',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Heading to $_destination? Find a place to stay or a flight in.',
          style: TextStyle(
            fontSize: 12.5,
            color: context.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _BookingTile(
                icon: Icons.hotel_rounded,
                label: 'Hotels',
                subtitle: 'Find stays',
                onTap: () => _openHotels(context),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _BookingTile(
                icon: Icons.flight_takeoff_rounded,
                label: 'Flights',
                subtitle: 'Search routes',
                onTap: () => _openFlights(context),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _BookingTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _BookingTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: context.cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.borderColor),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFB05ECC), Color(0xFF8A3FB8)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_outward_rounded,
                  size: 14, color: context.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
