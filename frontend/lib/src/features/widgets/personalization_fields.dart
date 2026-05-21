import 'package:flutter/material.dart';

import '../../services/admin_service.dart';
import '../../theme/app_theme.dart';

/// Canonical option lists for the optional "About you" personalization data
/// collected during onboarding (and editable later in Edit Profile).
///
/// NOTE: these are intentionally stored under `users/{uid}.profession`,
/// `.field`, `.academicLevel`, `.goals` — the existing `role` field is the
/// RBAC `'user' | 'admin'` flag and must not be reused.
/// True when an academic level question is relevant for the chosen profession.
bool academicLevelAppliesTo(String? profession) =>
    profession != null && profession != 'Traveler';

/// A labelled block of single-select choice chips.
class SingleChoiceChips extends StatelessWidget {
  final String label;
  final List<String> options;
  final String? selected;
  final ValueChanged<String?> onChanged;

  const SingleChoiceChips({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: context.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((o) {
            final isSel = o == selected;
            return ChoiceChip(
              label: Text(o),
              selected: isSel,
              onSelected: (_) => onChanged(isSel ? null : o),
              selectedColor: AppColors.purple.withValues(alpha: 0.18),
              labelStyle: TextStyle(
                color: isSel ? AppColors.purple : context.textPrimary,
                fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
              ),
              side: BorderSide(
                color: isSel ? AppColors.purple : context.borderColor,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

/// A labelled block of multi-select filter chips.
class MultiChoiceChips extends StatelessWidget {
  final String label;
  final List<String> options;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  const MultiChoiceChips({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: context.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((o) {
            final isSel = selected.contains(o);
            return FilterChip(
              label: Text(o),
              selected: isSel,
              onSelected: (_) {
                final next = isSel
                    ? selected.where((x) => x != o).toList()
                    : [...selected, o];
                onChanged(next);
              },
              selectedColor: AppColors.purple.withValues(alpha: 0.18),
              checkmarkColor: AppColors.purple,
              labelStyle: TextStyle(
                color: isSel ? AppColors.purple : context.textPrimary,
                fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
              ),
              side: BorderSide(
                color: isSel ? AppColors.purple : context.borderColor,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

/// The full "About you" editor — profession / field / academic level / goals.
/// Reused by onboarding (as a skippable step) and Edit Profile.
class AboutYouEditor extends StatelessWidget {
  final String? profession;
  final String? field;
  final String? academicLevel;
  final List<String> goals;
  final List<String> professionOptions;
  final List<String> fieldOptions;
  final List<String> academicLevelOptions;
  final List<String> goalOptions;
  final ValueChanged<String?> onProfessionChanged;
  final ValueChanged<String?> onFieldChanged;
  final ValueChanged<String?> onAcademicLevelChanged;
  final ValueChanged<List<String>> onGoalsChanged;

  const AboutYouEditor({
    super.key,
    required this.profession,
    required this.field,
    required this.academicLevel,
    required this.goals,
    this.professionOptions = kProfileProfessionOptions,
    this.fieldOptions = kProfileFieldOptions,
    this.academicLevelOptions = kProfileAcademicLevelOptions,
    this.goalOptions = kProfileGoalOptions,
    required this.onProfessionChanged,
    required this.onFieldChanged,
    required this.onAcademicLevelChanged,
    required this.onGoalsChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChoiceChips(
          label: 'I am a…',
          options: professionOptions,
          selected: profession,
          onChanged: (v) {
            onProfessionChanged(v);
            // Clear academic level if it no longer applies.
            if (!academicLevelAppliesTo(v)) onAcademicLevelChanged(null);
          },
        ),
        const SizedBox(height: 16),
        SingleChoiceChips(
          label: 'Field',
          options: fieldOptions,
          selected: field,
          onChanged: onFieldChanged,
        ),
        if (academicLevelAppliesTo(profession)) ...[
          const SizedBox(height: 16),
          SingleChoiceChips(
            label: 'Academic level',
            options: academicLevelOptions,
            selected: academicLevel,
            onChanged: onAcademicLevelChanged,
          ),
        ],
        const SizedBox(height: 16),
        MultiChoiceChips(
          label: 'My goals',
          options: goalOptions,
          selected: goals,
          onChanged: onGoalsChanged,
        ),
      ],
    );
  }
}
