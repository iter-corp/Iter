import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/admin_providers.dart';
import '../../../services/admin_service.dart';

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
  bool _hydrated = false;
  bool _saving = false;
  AdminConfig _cfg = const AdminConfig();

  void _hydrate(AdminConfig cfg) {
    if (_hydrated) return;
    _cfg = cfg;
    _announcementCtrl.text = cfg.announcement;
    _minVersionCtrl.text = cfg.minAppVersion;
    _contactEmailCtrl.text = cfg.contactEmail;
    _hydrated = true;
  }

  @override
  void dispose() {
    _announcementCtrl.dispose();
    _minVersionCtrl.dispose();
    _contactEmailCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final next = _cfg.copyWith(
        announcement: _announcementCtrl.text.trim(),
        minAppVersion: _minVersionCtrl.text.trim(),
        contactEmail: _contactEmailCtrl.text.trim(),
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
      backgroundColor: const Color(0xFFF7F7FB),
      appBar: AppBar(
        title: const Text('App settings'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
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
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFEDEDF2)),
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
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFEDEDF2)),
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
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFEDEDF2)),
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
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: Colors.grey,
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEDEDF2)),
      ),
      child: SwitchListTile(
        title: Text(title),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
