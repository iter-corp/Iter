import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_strings.dart';
import '../../../providers/auth_providers.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/primary_action_button.dart';

class AppIntroScreen extends ConsumerStatefulWidget {
  const AppIntroScreen({super.key});

  @override
  ConsumerState<AppIntroScreen> createState() => _AppIntroScreenState();
}

class _AppIntroScreenState extends ConsumerState<AppIntroScreen> {
  final _controller = PageController();
  int _index = 0;
  bool _loading = false;
  String? _error;

  late final List<_IntroSlide> _slides = [
    _IntroSlide(
      icon: Icons.dynamic_feed_rounded,
      title: context.t.appIntroPostsTitle,
      body: context.t.appIntroPostsBody,
      color: AppColors.purple,
    ),
    _IntroSlide(
      icon: Icons.forum_rounded,
      title: context.t.appIntroDiscussTitle,
      body: context.t.appIntroDiscussBody,
      color: const Color(0xFF1F9D8A),
    ),
    _IntroSlide(
      icon: Icons.travel_explore_rounded,
      title: context.t.appIntroTravelTitle,
      body: context.t.appIntroTravelBody,
      color: const Color(0xFF2E7CF6),
    ),
    _IntroSlide(
      icon: Icons.diversity_3_rounded,
      title: context.t.appIntroEventsTitle,
      body: context.t.appIntroEventsBody,
      color: const Color(0xFFE05A8A),
    ),
    _IntroSlide(
      icon: Icons.translate_rounded,
      title: context.t.appIntroTranslateTitle,
      body: context.t.appIntroTranslateBody,
      color: const Color(0xFF7E3BE8),
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uid = ref.read(authServiceProvider).currentUser!.uid;
      await ref.read(userServiceProvider).updateUser(uid, {
        'appIntroSeen': true,
      });
      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _next() {
    if (_index == _slides.length - 1) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final isLast = _index == _slides.length - 1;

    return Scaffold(
      backgroundColor: context.surfaceSoft,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 18, 24, 18 + bottom),
          child: Column(
            children: [
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: _loading ? null : _finish,
                  child: Text(context.t.skip),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _slides.length,
                  onPageChanged: (value) => setState(() => _index = value),
                  itemBuilder: (context, i) => _IntroSlideView(
                    slide: _slides[i],
                    page: i + 1,
                    count: _slides.length,
                  ),
                ),
              ),
              if (_error != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.cardBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.borderColor),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(fontSize: 13, color: context.textPrimary),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_slides.length, (i) {
                  final selected = i == _index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: selected ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: selected ? AppColors.purple : context.borderColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 22),
              PrimaryActionButton(
                label: isLast ? context.t.appIntroStart : context.t.next,
                icon:
                    isLast ? Icons.check_rounded : Icons.arrow_forward_rounded,
                onPressed: _loading ? null : _next,
                loading: _loading,
                size: PrimaryActionSize.large,
                fullWidth: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IntroSlide {
  final IconData icon;
  final String title;
  final String body;
  final Color color;

  const _IntroSlide({
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
  });
}

class _IntroSlideView extends StatelessWidget {
  final _IntroSlide slide;
  final int page;
  final int count;

  const _IntroSlideView({
    required this.slide,
    required this.page,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 132,
          height: 132,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: slide.color.withValues(alpha: 0.12),
          ),
          child: Icon(slide.icon, size: 58, color: slide.color),
        ),
        const SizedBox(height: 34),
        Text(
          '$page/$count',
          style: TextStyle(
            color: context.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          slide.title,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.textPrimary,
            fontSize: 28,
            fontWeight: FontWeight.w900,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 14),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Text(
            slide.body,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.textSecondary,
              fontSize: 15,
              height: 1.55,
            ),
          ),
        ),
      ],
    );
  }
}
