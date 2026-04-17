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
  bool _hydrated = false;
  bool _hasLocalEdits = false;
  bool _saving = false;
  AdminConfig _cfg = const AdminConfig();

  void _hydrate(AdminConfig cfg, {bool force = false}) {
    if (_hydrated && !force && _hasLocalEdits) return;
    _cfg = cfg;
<<<<<<< Updated upstream
    _announcementCtrl.text = cfg.announcement;
    _minVersionCtrl.text = cfg.minAppVersion;
=======
    if (_announcementCtrl.text != cfg.announcement) {
      _announcementCtrl.text = cfg.announcement;
    }
    if (_minVersionCtrl.text != cfg.minAppVersion) {
      _minVersionCtrl.text = cfg.minAppVersion;
    }
    if (_contactEmailCtrl.text != cfg.contactEmail) {
      _contactEmailCtrl.text = cfg.contactEmail;
    }
>>>>>>> Stashed changes
    _hydrated = true;
  }

  @override
  void dispose() {
    _announcementCtrl.dispose();
    _minVersionCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final next = _cfg.copyWith(
        announcement: _announcementCtrl.text.trim(),
        minAppVersion: _minVersionCtrl.text.trim(),
      );
      await ref.read(adminServiceProvider).saveConfig(next);
      if (mounted) {
        _hasLocalEdits = false;
        _hydrate(next, force: true);
        ref.invalidate(adminConfigProvider);
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
    final remoteCfg = cfgAsync.valueOrNull;
    if (remoteCfg != null) {
      _hydrate(remoteCfg);
    } else if (!_hydrated) {
      _hydrate(const AdminConfig());
    }

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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (cfgAsync.isLoading && remoteCfg == null)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (cfgAsync.hasError)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(10),
                child: ListTile(
                  leading: const Icon(Icons.warning_amber_rounded,
                      color: Colors.deepOrange),
                  title: const Text('Could not refresh app settings'),
                  subtitle: Text('${cfgAsync.error}'),
                  trailing: TextButton(
                    onPressed: () => ref.invalidate(adminConfigProvider),
                    child: const Text('Retry'),
                  ),
                ),
              ),
            ),
          _section('Feature flags'),
          _flag(
            title: 'Stories enabled',
            value: _cfg.storiesEnabled,
            onChanged: (v) => setState(() {
              _hasLocalEdits = true;
              _cfg = _cfg.copyWith(storiesEnabled: v);
            }),
          ),
          _flag(
            title: 'Live streaming enabled',
            value: _cfg.liveEnabled,
            onChanged: (v) => setState(() {
              _hasLocalEdits = true;
              _cfg = _cfg.copyWith(liveEnabled: v);
            }),
          ),
          _flag(
            title: 'Reposts enabled',
            value: _cfg.repostsEnabled,
            onChanged: (v) => setState(() {
              _hasLocalEdits = true;
              _cfg = _cfg.copyWith(repostsEnabled: v);
            }),
          ),
          _flag(
            title: 'Translate enabled',
            value: _cfg.translateEnabled,
            onChanged: (v) => setState(() {
              _hasLocalEdits = true;
              _cfg = _cfg.copyWith(translateEnabled: v);
            }),
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
              onChanged: (_) => _hasLocalEdits = true,
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
            onChanged: (v) => setState(() {
              _hasLocalEdits = true;
              _cfg = _cfg.copyWith(maintenanceMode: v);
            }),
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
              onChanged: (_) => _hasLocalEdits = true,
              decoration: const InputDecoration(
                hintText: 'e.g. 1.0.0',
                border: InputBorder.none,
              ),
<<<<<<< Updated upstream
              const SizedBox(height: 24),
            ],
          );
        },
=======
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
              onChanged: (_) => _hasLocalEdits = true,
              decoration: const InputDecoration(
                hintText: 'Email shown on "Become an event admin" mailto link',
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
>>>>>>> Stashed changes
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
