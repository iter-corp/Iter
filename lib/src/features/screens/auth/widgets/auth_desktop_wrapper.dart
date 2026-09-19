import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/app_strings.dart';
import '../../../../providers/locale_provider.dart';
import '../../../../theme/app_theme.dart';
import '../../../widgets/app_page_background.dart';

/// A Facebook-style responsive split layout for authentication pages (Login, Sign Up).
///
/// - On large screens (Desktop / Tablets >= 860px): Renders a 2-column layout with
///   rich brand storytelling on the left and the elevated auth card on the right,
///   plus a bottom language & legal footer.
/// - On mobile screens (< 860px): Renders the streamlined, centered single-column layout.
class AuthDesktopWrapper extends ConsumerWidget {
  final Widget mobileContent;
  final Widget cardContent;
  final Widget? underCardWidget;
  final String? customTagline;

  const AuthDesktopWrapper({
    super.key,
    required this.mobileContent,
    required this.cardContent,
    this.underCardWidget,
    this.customTagline,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktopOrWide = width >= 860;

    if (!isDesktopOrWide) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: AppPageBackground(
          child: SafeArea(
            child: mobileContent,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppPageBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1160),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Main Split Row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Left Column: Brand, Pitch & Community Highlights
                        Expanded(
                          flex: 6,
                          child: Padding(
                            padding: const EdgeInsetsDirectional.only(end: 48),
                            child: _BrandPitchSection(customTagline: customTagline),
                          ),
                        ),

                        // Right Column: Elevated Glass Card + Helper Link
                        Expanded(
                          flex: 5,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 460),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AppGlassCard(
                                  radius: 24,
                                  surfaceAlpha: context.isDark ? 0.65 : 0.75,
                                  borderAlpha: context.isDark ? 0.22 : 0.6,
                                  padding: const EdgeInsets.all(32),
                                  child: cardContent,
                                ),
                                if (underCardWidget != null) ...[
                                  const SizedBox(height: 20),
                                  underCardWidget!,
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 56),

                    // Bottom Language & Legal Footer
                    _AuthDesktopFooter(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandPitchSection extends StatelessWidget {
  final String? customTagline;

  const _BrandPitchSection({this.customTagline});

  @override
  Widget build(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    final isArabic = lang == 'ar';
    final isKurdish = lang == 'ckb';

    final String tagline;
    if (customTagline != null && customTagline!.isNotEmpty) {
      tagline = customTagline!;
    } else if (isArabic) {
      tagline = 'إيتر يساعدك على التواصل ومشاركة اللحظات واستكشاف المجتمعات حول العالم.';
    } else if (isKurdish) {
      tagline = 'ئیتەر یارمەتیت دەدات بۆ پەیوەندی، هاوبەشکردنی ساتەکان، و دۆزینەوەی کۆمەڵگاکان لە سەرتاسەری جیهان.';
    } else {
      tagline = 'Iter helps you connect, share moments, and explore communities worldwide.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Brand Title with Icon
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF9D4EDD).withValues(alpha: 0.35),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset(
                  'assets/img/app_icon.png',
                  width: 58,
                  height: 58,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Image.asset(
                    'assets/icons/app_icon.png',
                    width: 58,
                    height: 58,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF8A3FB8), Color(0xFFCE5DE5)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.public_rounded, color: Colors.white, size: 32),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Color(0xFFFFFFFF), Color(0xFFC77DFF), Color(0xFF9D4EDD)],
                stops: [0.1, 0.6, 1.0],
              ).createShader(bounds),
              child: Text(
                context.t.appName,
                style: const TextStyle(
                  fontSize: 52,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.0,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 22),

        // Tagline
        Text(
          tagline,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w500,
            height: 1.45,
            color: context.textPrimary.withValues(alpha: 0.92),
            letterSpacing: -0.2,
          ),
        ),

        const SizedBox(height: 32),

        // Feature Highlights
        _FeatureHighlightTile(
          icon: Icons.public_rounded,
          iconGradient: const [Color(0xFF8A3FB8), Color(0xFFCE5DE5)],
          title: isArabic
              ? 'مجتمع عالمي متكامل'
              : isKurdish
                  ? 'کۆمەڵگایەکی جیهانی'
                  : 'Global Social Network',
          subtitle: isArabic
              ? 'استكشف المنشورات، القصص اليومية، والنقاشات التفاعلية'
              : isKurdish
                  ? 'سەیری بڵاوکراوەکان، ستۆری ڕۆژانە و گفتوگۆکان بکە'
                  : 'Explore posts, live moments, stories & discussions.',
        ),

        const SizedBox(height: 16),

        _FeatureHighlightTile(
          icon: Icons.chat_bubble_outline_rounded,
          iconGradient: const [Color(0xFF3B82F6), Color(0xFF60A5FA)],
          title: isArabic
              ? 'محادثات فورية آمنة'
              : isKurdish
                  ? 'نامە ناردنی ڕاستەوخۆ'
                  : 'Real-time Messaging',
          subtitle: isArabic
              ? 'دردشة حية، رسائل صوتية، ومشاركة الوسائط بكل سلاسة'
              : isKurdish
                  ? 'چاتی ڕاستەوخۆ، دەنگ و هاوبەشکردنی میدیا بە ئاسانی'
                  : 'Instant chat, audio messages & seamless media sharing.',
        ),

        const SizedBox(height: 16),

        _FeatureHighlightTile(
          icon: Icons.event_available_rounded,
          iconGradient: const [Color(0xFF10B981), Color(0xFF34D399)],
          title: isArabic
              ? 'فعاليات وفرص حصرية'
              : isKurdish
                  ? 'چالاکییەکان و دەرفەتەکان'
                  : 'Events & Opportunities',
          subtitle: isArabic
              ? 'اكتشف المؤتمرات، المنح الدراسية، والفرص المهنية'
              : isKurdish
                  ? 'دۆزینەوەی کۆنفرانسەکان، سکۆلارشیپ و دەرفەتەکان'
                  : 'Discover conferences, scholarships & networking meetups.',
        ),
      ],
    );
  }
}

class _FeatureHighlightTile extends StatelessWidget {
  final IconData icon;
  final List<Color> iconGradient;
  final String title;
  final String subtitle;

  const _FeatureHighlightTile({
    required this.icon,
    required this.iconGradient,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: iconGradient),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: iconGradient.first.withValues(alpha: 0.28),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 13,
                  color: context.textMuted,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AuthDesktopFooter extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLang = ref.watch(localeProvider);
    final isDark = context.isDark;

    return Container(
      padding: const EdgeInsets.only(top: 24),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: Column(
        children: [
          // Language Switcher Row
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: AppLanguage.values.map((lang) {
              final isSelected = lang == currentLang;
              return InkWell(
                onTap: () => ref.read(localeProvider.notifier).setLanguage(lang),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (isDark
                            ? const Color(0xFF9D4EDD).withValues(alpha: 0.25)
                            : const Color(0xFF9D4EDD).withValues(alpha: 0.12))
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    lang.nativeName,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                      color: isSelected ? const Color(0xFFCE5DE5) : context.textMuted,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 12),

          // Legal Links & Copyright
          Wrap(
            spacing: 16,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              GestureDetector(
                onTap: () => context.push('/contact-us'),
                child: Text(
                  context.t.contactUs,
                  style: TextStyle(fontSize: 12, color: context.textMuted),
                ),
              ),
              Text('•', style: TextStyle(fontSize: 12, color: context.textMuted)),
              Text(
                context.t.privacy,
                style: TextStyle(fontSize: 12, color: context.textMuted),
              ),
              Text('•', style: TextStyle(fontSize: 12, color: context.textMuted)),
              Text(
                'Iter © 2026',
                style: TextStyle(fontSize: 12, color: context.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
