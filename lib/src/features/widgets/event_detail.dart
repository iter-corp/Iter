import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_strings.dart';
import '../../providers/auth_providers.dart';
import '../../providers/event_registration_providers.dart';
import '../../providers/preferred_language_provider.dart';
import '../../services/admin_service.dart';
import '../../services/event_registration_service.dart';
import '../../services/translate_service.dart';
import '../../theme/app_theme.dart';
import 'event_registration_sheet.dart';
import 'event_share.dart';

class EventDetailScreen extends ConsumerStatefulWidget {
  final String eventId;
  final String title;
  final String subtitle;
  final String location;
  final String eventType;
  final String funds;
  final DateTime? deadlineAt;
  final List<String> imageUrls;
  final String description;
  final String link;
  final String phone;
  final String email;
  // UID of the admin/user who created the event. Used to render the
  // author profile chip at the top of the page. Empty means we fall
  // back to a generic placeholder.
  final String createdByUid;

  const EventDetailScreen({
    super.key,
    required this.eventId,
    required this.title,
    required this.subtitle,
    required this.location,
    required this.eventType,
    required this.funds,
    required this.deadlineAt,
    required this.imageUrls,
    required this.description,
    required this.link,
    required this.phone,
    required this.email,
    this.createdByUid = '',
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

  Future<void> _translateDescription(
    BuildContext context, {
    required String target,
  }) async {
    final text = widget.description.trim();
    if (text.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EventTranslateSheet(
        text: text,
        target: target,
      ),
    );
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

  /// Reconstructs an [AdminEvent] from the widget's fields so the share
  /// sheet has a single object to work with. `country`/`createdAt`/`funds`
  /// aren't needed by the share flow (it only uses id/title/location/
  /// imageUrls), so the unavailable ones are left empty/null.
  AdminEvent _asAdminEvent() => AdminEvent(
        id: widget.eventId,
        title: widget.title,
        subtitle: widget.subtitle,
        location: widget.location,
        description: widget.description,
        link: widget.link,
        phone: widget.phone,
        email: widget.email,
        imageUrls: widget.imageUrls,
        createdAt: null,
        deadlineAt: widget.deadlineAt,
        eventType: widget.eventType,
        country: '',
        funds: widget.funds,
        createdByUid: widget.createdByUid,
      );

  void _prev() {
    if (_currentImage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _next(int totalImages) {
    if (_currentImage < totalImages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final preferredLang = ref.watch(preferredLanguageProvider);
    final phone = widget.phone.trim();
    final email = widget.email.trim();
    final validImages = widget.imageUrls
        .map((u) => u.trim())
        .where((u) => u.isNotEmpty)
        .toList();
    final hasContact = phone.isNotEmpty || email.isNotEmpty;
    return Scaffold(
      backgroundColor: context.cardBg,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 📌 SECTION: Back Arrow + Share
              Padding(
                padding: const EdgeInsetsDirectional.only(
                    start: 14, end: 14, top: 10, bottom: 6),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Icon(
                        Icons.arrow_back,
                        size: 22,
                        color: context.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => showEventShareSheet(
                        context,
                        event: _asAdminEvent(),
                      ),
                      child: Icon(
                        Icons.ios_share,
                        size: 22,
                        color: context.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),

              // 📌 SECTION: Author chip — the user who created the event.
              // Watches the user doc so the avatar/username stay live
              // even if the author updates their profile after publish.
              _EventAuthorHeader(
                createdByUid: widget.createdByUid,
                fallbackTitle: widget.title,
                fallbackSubtitle: widget.subtitle,
              ),

              const SizedBox(height: 14),

              // 📌 SECTION: Big banner image with title + subtitle overlay.
              // Uses CachedNetworkImage to reuse image caches from the events
              // list, with a graceful gradient fallback if no photo exists.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: SizedBox(
                    width: double.infinity,
                    height: 320,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (validImages.isNotEmpty)
                          PageView.builder(
                            controller: _pageController,
                            itemCount: validImages.length,
                            onPageChanged: (i) =>
                                setState(() => _currentImage = i),
                            itemBuilder: (_, i) => CachedNetworkImage(
                              imageUrl: validImages[i],
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                color: context.isDark
                                    ? const Color(0xFF22222B)
                                    : const Color(0xFFE8E8EE),
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.purple,
                                  ),
                                ),
                              ),
                              errorWidget: (_, __, ___) => Container(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      AppColors.purple,
                                      AppColors.purpleDeep,
                                    ],
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.event_rounded,
                                  color: Colors.white,
                                  size: 56,
                                ),
                              ),
                            ),
                          )
                        else
                          Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  AppColors.purple,
                                  AppColors.purpleDeep,
                                ],
                              ),
                            ),
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.event_rounded,
                              color: Colors.white,
                              size: 56,
                            ),
                          ),
                        // Dark gradient at the bottom so the white
                        // title/subtitle stay readable over any image.
                        Positioned.fill(
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withValues(alpha: 0.65),
                                  ],
                                  stops: const [0.45, 1.0],
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Title + subtitle overlay, anchored to the
                        // start side so it works in RTL too.
                        PositionedDirectional(
                          start: 16,
                          end: 16,
                          bottom: 16,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.title,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  height: 1.2,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black54,
                                      blurRadius: 6,
                                      offset: Offset(0, 1),
                                    ),
                                  ],
                                ),
                              ),
                              if (widget.subtitle.trim().isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  widget.subtitle,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.white70,
                                    height: 1.35,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black54,
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (validImages.length > 1) ...[
                          PositionedDirectional(
                            start: 12,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: _ArrowButton(
                                icon: Icons.chevron_left,
                                flipForRtl: true,
                                onTap: _prev,
                              ),
                            ),
                          ),
                          PositionedDirectional(
                            end: 12,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: _ArrowButton(
                                icon: Icons.chevron_right,
                                flipForRtl: true,
                                onTap: () => _next(validImages.length),
                              ),
                            ),
                          ),
                          PositionedDirectional(
                            top: 12,
                            end: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${_currentImage + 1} / ${validImages.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 18),

              if (widget.location.trim().isNotEmpty ||
                  widget.eventType.trim().isNotEmpty ||
                  widget.funds.trim().isNotEmpty ||
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
                      if (widget.funds.trim().isNotEmpty)
                        _MetaChip(
                          icon: Icons.account_balance_wallet_outlined,
                          label: widget.funds.trim(),
                        ),
                      if (widget.deadlineAt != null)
                        _MetaChip(
                          icon: Icons.calendar_month_outlined,
                          label: context.t.eventDetailDeadline(
                              _formatDate(context, widget.deadlineAt!)),
                        ),
                    ],
                  ),
                ),

              if (widget.location.trim().isNotEmpty ||
                  widget.eventType.trim().isNotEmpty ||
                  widget.funds.trim().isNotEmpty ||
                  widget.deadlineAt != null)
                const SizedBox(height: 14),

              // 📌 SECTION: Description text
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.description.trim().isNotEmpty) ...[
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: () => _translateDescription(
                            context,
                            target: preferredLang,
                          ),
                          icon: const Icon(Icons.translate, size: 18),
                          label: Text(context.t.translate),
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text(
                      widget.description,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: context.textPrimary,
                        height: 1.6,
                      ),
                    ),
                  ],
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
                          ? context.t.eventDetailApplyBelow
                          : context.t.eventDetailRegisterBelow,
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
                    context.t.eventDetailContact,
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

  /// When true, the chevron is mirrored under RTL so a "left" chevron
  /// visually points toward the start in both directions.
  final bool flipForRtl;

  const _ArrowButton({
    required this.icon,
    required this.onTap,
    this.flipForRtl = false,
  });

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    Widget iconWidget = Icon(icon, size: 20, color: Colors.white);
    if (flipForRtl && isRtl) {
      iconWidget = Transform.flip(flipX: true, child: iconWidget);
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          shape: BoxShape.circle,
        ),
        child: iconWidget,
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
class _EventTranslateSheet extends StatefulWidget {
  final String text;
  final String target;

  const _EventTranslateSheet({
    required this.text,
    required this.target,
  });

  @override
  State<_EventTranslateSheet> createState() => _EventTranslateSheetState();
}

class _EventTranslateSheetState extends State<_EventTranslateSheet> {
  late String _target;
  String? _translated;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _target = widget.target;
    _translate();
  }

  Future<void> _translate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final out = await const TranslateService().translateText(
        text: widget.text,
        sourceLang: 'auto',
        targetLang: _target,
      );
      if (!mounted) return;
      setState(() {
        _translated = out;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = TranslateService.userFriendlyErrorMessage(e);
        _loading = false;
      });
    }
  }

  void _selectLang(String code) {
    if (code == _target) return;
    setState(() => _target = code);
    _translate();
  }

  String _labelOf(String code) => kTranslateLanguages
      .firstWhere((l) => l.code == code,
          orElse: () => const TranslateLanguage('?', '?'))
      .label;

  @override
  Widget build(BuildContext context) {
    final seen = <String>{};
    final chipLangs = <TranslateLanguage>[];
    for (final lang in kTranslateLanguages) {
      if (seen.add(lang.code)) chipLangs.add(lang);
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.translate, size: 18),
                const SizedBox(width: 8),
                Text(
                  context.t.commentTranslateTo(_labelOf(_target)),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: chipLangs.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final lang = chipLangs[i];
                  final selected = lang.code == _target;
                  final label = lang.code == 'en' ? 'English' : lang.label;
                  return GestureDetector(
                    onTap: () => _selectLang(lang.code),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFFB05ECC)
                            : Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: selected ? Colors.white : null,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red))
            else
              SelectableText(
                _translated ?? '',
                style: const TextStyle(fontSize: 14, height: 1.4),
              ),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.t.close),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
                SnackBar(content: Text(context.t.eventDetailCouldNotOpenLink)),
              );
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFCE5DE5),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Text(
              context.t.eventDetailApply,
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

    final regAsync = ref.watch(myRegistrationProvider(eventId));
    final reg = regAsync.value;

    String label;
    Color color;
    VoidCallback? onTap;

    if (reg == null) {
      label = context.t.eventDetailRegistration;
      color = const Color(0xFFCE5DE5);
      onTap = () => showEventRegistrationSheet(
            context,
            eventId: eventId,
            eventTitle: eventTitle,
          );
    } else {
      switch (reg.status) {
        case RegistrationStatus.pending:
          label = context.t.eventDetailRequestPending;
          color = context.textSecondary;
          onTap = null;
          break;
        case RegistrationStatus.approved:
          label = context.t.eventDetailApproved;
          color = const Color(0xFF2EBD6B);
          onTap = null;
          break;
        case RegistrationStatus.rejected:
          label = context.t.eventDetailRejectedRetry;
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

/// Header showing the author of an event — avatar, username, handle.
///
/// Reads the author's live user doc so updates to their profile are
/// reflected on existing event pages. When [createdByUid] is empty
/// (legacy events that pre-date the field) or the user doc is missing,
/// falls back to the event's own title/subtitle so the row never
/// renders as an empty placeholder.
class _EventAuthorHeader extends ConsumerWidget {
  final String createdByUid;
  final String fallbackTitle;
  final String fallbackSubtitle;

  const _EventAuthorHeader({
    required this.createdByUid,
    required this.fallbackTitle,
    required this.fallbackSubtitle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authorAsync = createdByUid.isEmpty
        ? null
        : ref.watch(userByUidProvider(createdByUid));
    final author = authorAsync?.value;

    final username = (author?['username'] as String?)?.trim();
    final rawHandle = (author?['handle'] as String?)?.trim();
    final avatarUrl = (author?['avatarUrl'] as String?)?.trim();

    // Some user docs store the handle WITH a leading `@` (older signup
    // path), others store it without. Strip any leading `@` so we never
    // render the double-prefixed `@@mohammed`.
    final handle =
        (rawHandle == null) ? null : rawHandle.replaceFirst(RegExp(r'^@+'), '');

    final primary =
        (username != null && username.isNotEmpty) ? username : fallbackTitle;
    final secondary =
        (handle != null && handle.isNotEmpty) ? '@$handle' : fallbackSubtitle;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipOval(
            child: (avatarUrl != null && avatarUrl.isNotEmpty)
                ? Image.network(
                    avatarUrl,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _avatarPlaceholder(context),
                  )
                : _avatarPlaceholder(context),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  primary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                  ),
                ),
                if (secondary.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    secondary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarPlaceholder(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      color: context.borderColor,
      alignment: Alignment.center,
      child: Icon(
        Icons.person_outline,
        color: context.textSecondary,
        size: 22,
      ),
    );
  }
}
