import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/admin_providers.dart';
import '../../../services/admin_service.dart';
import '../../../theme/app_theme.dart';

class AdminSettingsScreen extends ConsumerStatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  ConsumerState<AdminSettingsScreen> createState() =>
      _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends ConsumerState<AdminSettingsScreen> {
  final _announcementCtrl = TextEditingController();
  final _minVersionCtrl = TextEditingController();
  final _contactEmailCtrl = TextEditingController();
  final _iosUrlCtrl = TextEditingController();
  final _androidUrlCtrl = TextEditingController();
  final _newTypeCtrl = TextEditingController();
  final _newCountryCtrl = TextEditingController();
  bool _hydrated = false;
  bool _saving = false;
  AdminConfig _cfg = const AdminConfig();

  void _hydrate(AdminConfig cfg) {
    if (_hydrated) return;
    _cfg = cfg;
    _announcementCtrl.text = cfg.announcement;
    _minVersionCtrl.text = cfg.minAppVersion;
    _contactEmailCtrl.text = cfg.contactEmail;
    _iosUrlCtrl.text = cfg.iosAppStoreUrl;
    _androidUrlCtrl.text = cfg.androidPlayStoreUrl;
    _hydrated = true;
  }

  @override
  void dispose() {
    _announcementCtrl.dispose();
    _minVersionCtrl.dispose();
    _contactEmailCtrl.dispose();
    _iosUrlCtrl.dispose();
    _androidUrlCtrl.dispose();
    _newTypeCtrl.dispose();
    _newCountryCtrl.dispose();
    super.dispose();
  }

  void _addEventType() {
    final v = _newTypeCtrl.text.trim();
    if (v.isEmpty) return;
    if (_cfg.eventTypes.any((t) => t.toLowerCase() == v.toLowerCase())) {
      _newTypeCtrl.clear();
      return;
    }
    setState(() {
      _cfg = _cfg.copyWith(eventTypes: [..._cfg.eventTypes, v]);
      _newTypeCtrl.clear();
    });
  }

  void _removeEventType(String t) {
    if (_cfg.eventTypes.length <= 1) return; // keep at least one
    setState(() => _cfg = _cfg.copyWith(
        eventTypes: _cfg.eventTypes.where((x) => x != t).toList()));
  }

  void _addCountry() {
    final v = _newCountryCtrl.text.trim();
    if (v.isEmpty) return;
    if (_cfg.eventCountries.any((c) => c.toLowerCase() == v.toLowerCase())) {
      _newCountryCtrl.clear();
      return;
    }
    setState(() {
      _cfg = _cfg.copyWith(eventCountries: [..._cfg.eventCountries, v]);
      _newCountryCtrl.clear();
    });
  }

  void _removeCountry(String c) {
    if (_cfg.eventCountries.length <= 1) return;
    setState(() => _cfg = _cfg.copyWith(
        eventCountries: _cfg.eventCountries.where((x) => x != c).toList()));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final next = _cfg.copyWith(
        announcement: _announcementCtrl.text.trim(),
        minAppVersion: _minVersionCtrl.text.trim(),
        contactEmail: _contactEmailCtrl.text.trim(),
        iosAppStoreUrl: _iosUrlCtrl.text.trim(),
        androidPlayStoreUrl: _androidUrlCtrl.text.trim(),
        // _cfg already carries the edited eventTypes / eventCountries lists.
      );
      await ref.read(adminServiceProvider).saveConfig(next);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfgAsync = ref.watch(adminConfigProvider);
    return Scaffold(
      backgroundColor: context.surfaceSoft,
      appBar: AppBar(
        title: const Text('App settings'),
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
      body: cfgAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (cfg) {
          _hydrate(cfg);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _section('Feature flags'),
              _flag(
                title: 'Stories enabled',
                value: _cfg.storiesEnabled,
                onChanged: (v) => setState(() => _cfg =
                    _cfg.copyWith(storiesEnabled: v)),
              ),
              _flag(
                title: 'Live streaming enabled',
                value: _cfg.liveEnabled,
                onChanged: (v) =>
                    setState(() => _cfg = _cfg.copyWith(liveEnabled: v)),
              ),
              _flag(
                title: 'Reposts enabled',
                value: _cfg.repostsEnabled,
                onChanged: (v) =>
                    setState(() => _cfg = _cfg.copyWith(repostsEnabled: v)),
              ),
              _flag(
                title: 'Translate enabled',
                value: _cfg.translateEnabled,
                onChanged: (v) =>
                    setState(() => _cfg = _cfg.copyWith(translateEnabled: v)),
              ),
              const SizedBox(height: 16),
              _section('Announcement'),
              Container(
                decoration: BoxDecoration(
                  color: context.cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.borderColor),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: TextField(
                  controller: _announcementCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText:
                        'Shown at the top of the home screen. Leave empty to hide.',
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _section('Maintenance'),
              _flag(
                title: 'Maintenance mode (read-only banner)',
                value: _cfg.maintenanceMode,
                onChanged: (v) => setState(() => _cfg =
                    _cfg.copyWith(maintenanceMode: v)),
              ),
              const SizedBox(height: 16),
              _section('Minimum app version'),
              Container(
                decoration: BoxDecoration(
                  color: context.cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.borderColor),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: TextField(
                  controller: _minVersionCtrl,
                  decoration: const InputDecoration(
                    hintText: 'e.g. 1.0.0',
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _section('Contact email'),
              Container(
                decoration: BoxDecoration(
                  color: context.cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.borderColor),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: TextField(
                  controller: _contactEmailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    hintText:
                        'Email shown on "Become an event admin" mailto link',
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _section('App store links (Invite friends)'),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text(
                  'Used by the "Invite friends" button in the profile. The app picks '
                  'the right link for the user\'s platform.',
                  style: TextStyle(fontSize: 12, color: context.textSecondary),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: context.cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.borderColor),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: TextField(
                  controller: _iosUrlCtrl,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    hintText: 'iOS App Store URL (https://apps.apple.com/...)',
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: context.cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.borderColor),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: TextField(
                  controller: _androidUrlCtrl,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    hintText:
                        'Google Play URL (https://play.google.com/store/apps/details?id=...)',
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _section('Event types'),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text(
                  'Options admins choose from when creating an event, and users '
                  'filter notifications by.',
                  style: TextStyle(fontSize: 12, color: context.textSecondary),
                ),
              ),
              _editableList(
                items: _cfg.eventTypes,
                controller: _newTypeCtrl,
                hint: 'Add an event type',
                onAdd: _addEventType,
                onRemove: _removeEventType,
              ),
              const SizedBox(height: 16),
              _section('Event countries'),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text(
                  'Countries admins tag events with, and users filter '
                  'notifications by.',
                  style: TextStyle(fontSize: 12, color: context.textSecondary),
                ),
              ),
              _editableList(
                items: _cfg.eventCountries,
                controller: _newCountryCtrl,
                hint: 'Add a country',
                onAdd: _addCountry,
                onRemove: _removeCountry,
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Widget _editableList({
    required List<String> items,
    required TextEditingController controller,
    required String hint,
    required VoidCallback onAdd,
    required ValueChanged<String> onRemove,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                  controller: controller,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => onAdd(),
                  decoration: InputDecoration(
                    hintText: hint,
                    border: InputBorder.none,
                  ),
                ),
              ),
              TextButton(onPressed: onAdd, child: const Text('Add')),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items
              .map((it) => Chip(
                    label: Text(it),
                    onDeleted:
                        items.length <= 1 ? null : () => onRemove(it),
                  ))
              .toList(),
        ),
      ],
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: context.textSecondary,
          fontSize: 12,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _flag({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderColor),
      ),
      child: SwitchListTile(
        title: Text(title),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
