import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_providers.dart';
import '../../providers/notification_providers.dart';
import '../../services/admin_service.dart';
import '../../services/user_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_feedback.dart';

/// Lets a user choose when they want a push notification for newly published
/// events: all events, only certain cities, or never — optionally filtered by
/// event type.
class EventNotificationsSettingsScreen extends ConsumerStatefulWidget {
  const EventNotificationsSettingsScreen({super.key});

  @override
  ConsumerState<EventNotificationsSettingsScreen> createState() =>
      _EventNotificationsSettingsScreenState();
}

class _EventNotificationsSettingsScreenState
    extends ConsumerState<EventNotificationsSettingsScreen> {
  final _cityCtrl = TextEditingController();
  EventNotifPrefs _prefs = const EventNotifPrefs();
  bool _hydrated = false;
  bool _saving = false;

  void _hydrate(EventNotifPrefs p) {
    if (_hydrated) return;
    _prefs = p;
    _hydrated = true;
  }

  @override
  void dispose() {
    _cityCtrl.dispose();
    super.dispose();
  }

  void _addCity() {
    final c = _cityCtrl.text.trim().toLowerCase();
    if (c.isEmpty) return;
    if (_prefs.cities.contains(c)) {
      _cityCtrl.clear();
      return;
    }
    setState(() {
      _prefs = _prefs.copyWith(cities: [..._prefs.cities, c]);
      _cityCtrl.clear();
    });
  }

  void _removeCity(String c) {
    setState(() {
      _prefs = _prefs.copyWith(
        cities: _prefs.cities.where((x) => x != c).toList(),
      );
    });
  }

  void _toggleType(String t) {
    final has = _prefs.types.contains(t);
    setState(() {
      _prefs = _prefs.copyWith(
        types: has
            ? _prefs.types.where((x) => x != t).toList()
            : [..._prefs.types, t],
      );
    });
  }

  Future<void> _save() async {
    final uid = ref.read(authStateProvider).value?.uid;
    if (uid == null) return;
    setState(() => _saving = true);
    try {
      // If they picked "cities" but listed none, fall back to "off" so they
      // don't silently get nothing without realising why.
      var toSave = _prefs;
      if (toSave.mode == EventNotifMode.cities && toSave.cities.isEmpty) {
        toSave = toSave.copyWith(mode: EventNotifMode.off);
      }
      await ref.read(userServiceProvider).setEventNotifPrefs(uid, toSave);
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
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _sectionLabel('Notify me about new events'),
              _modeTile(
                title: 'All new events',
                subtitle: 'Get a notification whenever any event is published.',
                mode: EventNotifMode.all,
              ),
              _modeTile(
                title: 'Only selected cities',
                subtitle: 'Only events happening in cities you choose below.',
                mode: EventNotifMode.cities,
              ),
              _modeTile(
                title: 'Never',
                subtitle: 'Turn off new-event notifications entirely.',
                mode: EventNotifMode.off,
              ),
              if (_prefs.mode == EventNotifMode.cities) ...[
                const SizedBox(height: 16),
                _sectionLabel('Cities'),
                Container(
                  decoration: BoxDecoration(
                    color: context.cardBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.borderColor),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _cityCtrl,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _addCity(),
                          decoration: const InputDecoration(
                            hintText: 'Add a city (e.g. Erbil)',
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      TextButton(onPressed: _addCity, child: const Text('Add')),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                if (_prefs.cities.isEmpty)
                  Text(
                    'Add at least one city, or you won\'t get any event alerts.',
                    style:
                        TextStyle(fontSize: 12, color: context.textSecondary),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _prefs.cities
                        .map((c) => Chip(
                              label: Text(_titleCase(c)),
                              onDeleted: () => _removeCity(c),
                            ))
                        .toList(),
                  ),
              ],
              if (_prefs.mode != EventNotifMode.off) ...[
                const SizedBox(height: 16),
                _sectionLabel('Event types (optional)'),
                Text(
                  'Leave all unselected to be notified about every type.',
                  style: TextStyle(fontSize: 12, color: context.textSecondary),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: kEventTypes.map((t) {
                    final selected = _prefs.types.contains(t);
                    return FilterChip(
                      label: Text(t),
                      selected: selected,
                      onSelected: (_) => _toggleType(t),
                      selectedColor: AppColors.purple.withValues(alpha: 0.18),
                      checkmarkColor: AppColors.purple,
                    );
                  }).toList(),
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

  Widget _modeTile({
    required String title,
    required String subtitle,
    required EventNotifMode mode,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _prefs.mode == mode
              ? AppColors.purple
              : context.borderColor,
        ),
      ),
      child: RadioListTile<EventNotifMode>(
        value: mode,
        groupValue: _prefs.mode,
        onChanged: (v) => setState(
            () => _prefs = _prefs.copyWith(mode: v ?? EventNotifMode.all)),
        activeColor: AppColors.purple,
        title: Text(title),
        subtitle: Text(subtitle,
            style: TextStyle(fontSize: 12, color: context.textSecondary)),
      ),
    );
  }
}

String _titleCase(String s) {
  if (s.isEmpty) return s;
  return s
      .split(' ')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}
