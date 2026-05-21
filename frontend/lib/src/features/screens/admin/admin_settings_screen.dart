import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_strings.dart';
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
          SnackBar(content: Text(context.t.adminSaved)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.t.failedWithError(e))));
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
        title: Text(context.t.adminAppSettings),
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
                : Text(context.t.save),
          ),
        ],
      ),
      body: cfgAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(context.t.errorWithMessage(e))),
        data: (cfg) {
          _hydrate(cfg);
          return ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + MediaQuery.of(context).padding.bottom + 8,
            ),
            children: [
              _section(context.t.adminSectionFeatureFlags),
              _flag(
                title: context.t.adminFlagStories,
                value: _cfg.storiesEnabled,
                onChanged: (v) =>
                    setState(() => _cfg = _cfg.copyWith(storiesEnabled: v)),
              ),
              _flag(
                title: context.t.adminFlagLive,
                value: _cfg.liveEnabled,
                onChanged: (v) =>
                    setState(() => _cfg = _cfg.copyWith(liveEnabled: v)),
              ),
              _flag(
                title: context.t.adminFlagReposts,
                value: _cfg.repostsEnabled,
                onChanged: (v) =>
                    setState(() => _cfg = _cfg.copyWith(repostsEnabled: v)),
              ),
              _flag(
                title: context.t.adminFlagTranslate,
                value: _cfg.translateEnabled,
                onChanged: (v) =>
                    setState(() => _cfg = _cfg.copyWith(translateEnabled: v)),
              ),
              const SizedBox(height: 16),
              _section(context.t.adminSectionAnnouncement),
              _textInputCard(
                controller: _announcementCtrl,
                hintText: context.t.adminAnnouncementHint,
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              _section(context.t.adminSectionMaintenance),
              _flag(
                title: context.t.adminFlagMaintenance,
                value: _cfg.maintenanceMode,
                onChanged: (v) =>
                    setState(() => _cfg = _cfg.copyWith(maintenanceMode: v)),
              ),
              const SizedBox(height: 16),
              _section(context.t.adminSectionMinAppVersion),
              _textInputCard(
                controller: _minVersionCtrl,
                hintText: context.t.adminMinVersionHint,
              ),
              const SizedBox(height: 16),
              _section(context.t.adminSectionContactEmail),
              _textInputCard(
                controller: _contactEmailCtrl,
                hintText: context.t.adminContactEmailHint,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              _section(context.t.adminSectionAppStoreLinks),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text(
                  context.t.adminAppStoreLinksDesc,
                  style: TextStyle(fontSize: 12, color: context.textSecondary),
                ),
              ),
              _textInputCard(
                controller: _iosUrlCtrl,
                hintText: context.t.adminIosUrlHint,
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 8),
              _textInputCard(
                controller: _androidUrlCtrl,
                hintText: context.t.adminAndroidUrlHint,
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 16),
              _section(context.t.adminSectionEventTypes),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text(
                  context.t.adminEventTypesDesc,
                  style: TextStyle(fontSize: 12, color: context.textSecondary),
                ),
              ),
              _editableList(
                items: _cfg.eventTypes,
                controller: _newTypeCtrl,
                hint: context.t.adminAddEventType,
                onAdd: _addEventType,
                onRemove: _removeEventType,
              ),
              const SizedBox(height: 16),
              _section(context.t.adminSectionEventCountries),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text(
                  context.t.adminEventCountriesDesc,
                  style: TextStyle(fontSize: 12, color: context.textSecondary),
                ),
              ),
              _editableList(
                items: _cfg.eventCountries,
                controller: _newCountryCtrl,
                hint: context.t.adminAddCountry,
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
        _FocusInputRow(
          controller: controller,
          hintText: hint,
          onAdd: onAdd,
          decoration: _inputDecoration(hint),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items
              .map((it) => Chip(
                    label: Text(it),
                    onDeleted: items.length <= 1 ? null : () => onRemove(it),
                  ))
              .toList(),
        ),
      ],
    );
  }

  Widget _textInputCard({
    required TextEditingController controller,
    required String hintText,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return _FocusInputCard(
      controller: controller,
      hintText: hintText,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: _inputDecoration(hintText),
    );
  }

  InputDecoration _inputDecoration(String hintText) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(
        fontSize: 13,
        color: context.textSecondary,
      ),
      filled: false,
      fillColor: Colors.transparent,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 14),
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

class _FocusInputCard extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final int maxLines;
  final TextInputType? keyboardType;
  final InputDecoration decoration;

  const _FocusInputCard({
    required this.controller,
    required this.hintText,
    required this.decoration,
    this.maxLines = 1,
    this.keyboardType,
  });

  @override
  State<_FocusInputCard> createState() => _FocusInputCardState();
}

class _FocusInputCardState extends State<_FocusInputCard> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: context.inputFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _focusNode.hasFocus
              ? AppColors.purple.withValues(alpha: 0.55)
              : context.borderColor,
          width: _focusNode.hasFocus ? 1.4 : 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: TextField(
        focusNode: _focusNode,
        controller: widget.controller,
        keyboardType: widget.keyboardType,
        maxLines: widget.maxLines,
        decoration: widget.decoration,
      ),
    );
  }
}

class _FocusInputRow extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final VoidCallback onAdd;
  final InputDecoration decoration;

  const _FocusInputRow({
    required this.controller,
    required this.hintText,
    required this.onAdd,
    required this.decoration,
  });

  @override
  State<_FocusInputRow> createState() => _FocusInputRowState();
}

class _FocusInputRowState extends State<_FocusInputRow> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: context.inputFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _focusNode.hasFocus
              ? AppColors.purple.withValues(alpha: 0.55)
              : context.borderColor,
          width: _focusNode.hasFocus ? 1.4 : 1,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 2, 10, 2),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              focusNode: _focusNode,
              controller: widget.controller,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => widget.onAdd(),
              decoration: widget.decoration,
            ),
          ),
          TextButton(onPressed: widget.onAdd, child: Text(context.t.add)),
        ],
      ),
    );
  }
}
