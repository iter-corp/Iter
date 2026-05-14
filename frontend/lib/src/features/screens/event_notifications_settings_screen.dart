import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/admin_providers.dart';
import '../../providers/auth_providers.dart';
import '../../providers/notification_providers.dart';
import '../../services/admin_service.dart';
import '../../services/user_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_feedback.dart';

/// Lets a user tune push notifications for newly published events:
///   1. Master on/off switch.
///   2. Event types — "All types" (default) or a custom subset.
///   3. Countries — "All countries" (default) or a custom subset.
class EventNotificationsSettingsScreen extends ConsumerStatefulWidget {
  const EventNotificationsSettingsScreen({super.key});

  @override
  ConsumerState<EventNotificationsSettingsScreen> createState() =>
      _EventNotificationsSettingsScreenState();
}

class _EventNotificationsSettingsScreenState
    extends ConsumerState<EventNotificationsSettingsScreen> {
  EventNotifPrefs _prefs = const EventNotifPrefs();
  bool _hydrated = false;
  bool _saving = false;

  void _hydrate(EventNotifPrefs p) {
    if (_hydrated) return;
    _prefs = p;
    _hydrated = true;
  }

  bool get _allTypes => _prefs.types.isEmpty;
  bool get _allCountries => _prefs.countries.isEmpty;

  void _selectAllTypes() => setState(() => _prefs = _prefs.copyWith(types: []));

  void _toggleType(String t, int totalTypes) {
    final has = _prefs.types.contains(t);
    final next = has
        ? _prefs.types.where((x) => x != t).toList()
        : [..._prefs.types, t];
    // If the user just selected every type one-by-one, collapse back to the
    // "All" state so it reads the same as never having customized it.
    setState(() {
      _prefs = _prefs.copyWith(
        types: next.length >= totalTypes ? <String>[] : next,
      );
    });
  }

  void _selectAllCountries() =>
      setState(() => _prefs = _prefs.copyWith(countries: []));

  void _toggleCountry(String displayName, int totalCountries) {
    final key = displayName.toLowerCase();
    final has = _prefs.countries.contains(key);
    final next = has
        ? _prefs.countries.where((x) => x != key).toList()
        : [..._prefs.countries, key];
    setState(() {
      _prefs = _prefs.copyWith(
        countries: next.length >= totalCountries ? <String>[] : next,
      );
    });
  }

  Future<void> _save() async {
    final uid = ref.read(authStateProvider).value?.uid;
    if (uid == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(userServiceProvider).setEventNotifPrefs(uid, _prefs);
      if (mounted) {
        AppFeedback.showSuccess(context, 'Event notification settings saved');
      }
    } catch (e) {
      if (mounted) AppFeedback.showError(context, 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefsAsync = ref.watch(eventNotifPrefsProvider);
    final cfg = ref.watch(adminConfigProvider).value ?? const AdminConfig();
    final eventTypes = cfg.eventTypes;
    final eventCountries = cfg.eventCountries;
    return Scaffold(
      backgroundColor: context.surfaceSoft,
      appBar: AppBar(
        title: const Text('Event notifications'),
        backgroundColor: context.cardBg,
        foregroundColor: context.textPrimary,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: prefsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (loaded) {
          _hydrate(loaded);
          final enabled = _prefs.mode != EventNotifMode.off;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _switchTile(
                title: 'New-event notifications',
                subtitle:
                    'Get a push when a new event matching your filters is published.',
                value: enabled,
                onChanged: (v) => setState(() => _prefs = _prefs.copyWith(
                    mode: v ? EventNotifMode.all : EventNotifMode.off)),
              ),
              if (enabled) ...[
                const SizedBox(height: 16),
                _sectionLabel('Event types'),
                Text(
                  _allTypes
                      ? 'You\'ll be notified about every type of event.'
                      : 'Only the types you picked. Tap "All types" to reset.',
                  style: TextStyle(fontSize: 12, color: context.textSecondary),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildChoiceChip(
                      label: 'All types',
                      selected: _allTypes,
                      onSelected: (_) => _selectAllTypes(),
                    ),
                    ...eventTypes.map((t) {
                      final selected = !_allTypes && _prefs.types.contains(t);
                      return _buildFilterChip(
                        label: t,
                        selected: selected,
                        onSelected: (_) =>
                            _toggleType(t, eventTypes.length),
                      );
                    }),
                  ],
                ),
                const SizedBox(height: 20),
                _sectionLabel('Countries'),
                Text(
                  _allCountries
                      ? 'You\'ll be notified about events in any country.'
                      : 'Only events in the countries you picked. Tap "All countries" to reset.',
                  style: TextStyle(fontSize: 12, color: context.textSecondary),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildChoiceChip(
                      label: 'All countries',
                      selected: _allCountries,
                      onSelected: (_) => _selectAllCountries(),
                    ),
                    ...eventCountries.map((c) {
                      final selected = !_allCountries &&
                          _prefs.countries.contains(c.toLowerCase());
                      return _buildFilterChip(
                        label: c,
                        selected: selected,
                        onSelected: (_) =>
                            _toggleCountry(c, eventCountries.length),
                      );
                    }),
                  ],
                ),
              ],
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionLabel(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            letterSpacing: 0.3,
            color: context.textSecondary,
          ),
        ),
      );

  Widget _switchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderColor),
      ),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        activeThumbColor: AppColors.purple,
        title: Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: context.textPrimary,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: context.textSecondary),
        ),
      ),
    );
  }

  Widget _buildChoiceChip({
    required String label,
    required bool selected,
    required ValueChanged<bool> onSelected,
  }) {
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? AppColors.purple : context.textPrimary,
        ),
      ),
      selected: selected,
      onSelected: onSelected,
      backgroundColor: context.cardBg,
      selectedColor: AppColors.purple.withValues(alpha: 0.18),
      side: BorderSide(
        color: selected
            ? AppColors.purple.withValues(alpha: 0.6)
            : context.borderColor,
      ),
      showCheckmark: false,
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool selected,
    required ValueChanged<bool> onSelected,
  }) {
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? AppColors.purple : context.textPrimary,
        ),
      ),
      selected: selected,
      onSelected: onSelected,
      backgroundColor: context.cardBg,
      selectedColor: AppColors.purple.withValues(alpha: 0.18),
      checkmarkColor: AppColors.purple,
      side: BorderSide(
        color: selected
            ? AppColors.purple.withValues(alpha: 0.6)
            : context.borderColor,
      ),
    );
  }
}
