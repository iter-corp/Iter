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
  final String eventType;
  final DateTime? deadlineAt;
  final List<String> imageUrls;
  final String description;
  final String link;
  final String phone;
  final String email;

  const EventDetailScreen({
    super.key,
    required this.eventId,
    required this.title,
    required this.subtitle,
    required this.location,
    required this.eventType,
    required this.deadlineAt,
    required this.imageUrls,
    required this.description,
    required this.link,
    required this.phone,
    required this.email,
  });

  @override
  ConsumerState<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends ConsumerState<EventDetailScreen> {
  int _currentImage = 0;
  late final PageController _pageController;

  Uri? _parsedEventLink() {
    final raw = widget.link.trim();
    if (raw.isEmpty) return null;
    final withScheme = raw.contains('://') ? raw : 'https://$raw';
    final uri = Uri.tryParse(withScheme);
    if (uri == null) return null;
    if (uri.host.trim().isEmpty) return null;
    return uri;
  }

  // Future<void> _openEventLink(Uri uri) async {
  //   // TODO: Implement event link opening when needed
  // }

  String _formatDate(BuildContext context, DateTime date) {
    return MaterialLocalizations.of(context).formatMediumDate(date);
  }

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
    final phone = widget.phone.trim();
    final email = widget.email.trim();
    final hasContact = phone.isNotEmpty || email.isNotEmpty;
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

              if (widget.location.trim().isNotEmpty ||
                  widget.eventType.trim().isNotEmpty ||
                  widget.deadlineAt != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (widget.location.trim().isNotEmpty)
                        _MetaChip(
                          icon: Icons.location_on_outlined,
                          label: widget.location.trim(),
                        ),
                      if (widget.eventType.trim().isNotEmpty)
                        _MetaChip(
                          icon: Icons.sell_outlined,
                          label: widget.eventType.trim(),
                        ),
                      if (widget.deadlineAt != null)
                        _MetaChip(
                          icon: Icons.calendar_month_outlined,
                          label:
                              'Deadline ${_formatDate(context, widget.deadlineAt!)}',
                        ),
                    ],
                  ),
                ),

              if (widget.location.trim().isNotEmpty ||
                  widget.eventType.trim().isNotEmpty ||
                  widget.deadlineAt != null)
                const SizedBox(height: 14),

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

              // 📌 SECTION: Registration
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _parsedEventLink() != null
                          ? 'If you would like to join, you\ncan apply below:'
                          : 'If you would like to become one of us, you\ncan register below:',
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
                      applyUri: _parsedEventLink(),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              if (hasContact) ...[
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
                if (phone.isNotEmpty)
                  _ContactRow(
                    icon: Icons.phone,
                    iconColor: const Color(0xFF26A69A), // teal — matches design
                    label: phone,
                  ),

                // 📌 SECTION: Email row
                if (email.isNotEmpty)
                  _ContactRow(
                    icon: Icons.mail,
                    iconColor: context.textPrimary,
                    label: email,
                  ),
              ],

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

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: context.surfaceSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: context.textSecondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: context.textPrimary,
              fontWeight: FontWeight.w600,
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
  final Uri? applyUri;

  const _RegistrationButton({
    required this.eventId,
    required this.eventTitle,
    this.applyUri,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (applyUri != null) {
      return Align(
        alignment: Alignment.center,
        child: GestureDetector(
          onTap: () async {
            final ok = await launchUrl(
              applyUri!,
              mode: LaunchMode.externalApplication,
            );
            if (!ok && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Could not open application link')),
              );
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFCE5DE5),
              borderRadius: BorderRadius.circular(30),
            ),
            child: const Text(
              'Apply',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ),
      );
    }

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
