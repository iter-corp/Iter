import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_strings.dart';
import '../../providers/locale_provider.dart';
import '../../theme/app_theme.dart';
import '../widgets/app_page_background.dart';

/// Full-screen language picker. Reachable from Settings → Language.
///
/// Switching the language updates [localeProvider]; because
/// `MaterialApp.locale` watches that provider, the whole app —
/// including text direction (LTR ↔ RTL) — rebuilds instantly.
class LanguageScreen extends ConsumerWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(localeProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppPageBackground(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              title: Text(context.t.appLanguage),
              centerTitle: false,
              backgroundColor: Colors.transparent,
              foregroundColor: context.textPrimary,
              elevation: 0,
              scrolledUnderElevation: 0,
              floating: true,
              snap: true,
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                24 + MediaQuery.of(context).padding.bottom,
              ),
              sliver: SliverList.list(
                children: [
                  for (final lang in AppLanguage.values)
                    _LanguageTile(
                      language: lang,
                      selected: lang == current,
                      onTap: () {
                        ref.read(localeProvider.notifier).setLanguage(lang);
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(
                            SnackBar(
                              content: Text(context.t.languageChanged),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.language,
    required this.selected,
    required this.onTap,
  });

  final AppLanguage language;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppGlassCard(
      margin: const EdgeInsets.symmetric(vertical: 4),
      radius: 16,
      emphasize: selected,
      surfaceAlpha: context.isDark ? 0.42 : 0.36,
      borderAlpha: selected ? 0.65 : (context.isDark ? 0.14 : 0.50),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: selected
              ? AppColors.purple
              : AppColors.purple.withValues(alpha: 0.12),
          child: Text(
            language.code.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : AppColors.purple,
            ),
          ),
        ),
        title: Text(
          language.nativeName,
          textDirection: language.direction,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          language.englishName,
          textDirection: TextDirection.ltr,
          style: TextStyle(fontSize: 12, color: context.textSecondary),
        ),
        trailing: selected
            ? const Icon(Icons.check_circle, color: AppColors.purple)
            : Icon(Icons.circle_outlined, color: context.textSecondary),
      ),
    );
  }
}
