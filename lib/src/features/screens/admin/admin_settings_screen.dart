import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_strings.dart';
import '../../../providers/admin_providers.dart';
import '../../../services/admin_service.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/app_page_background.dart';

class AdminSettingsScreen extends ConsumerStatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  ConsumerState<AdminSettingsScreen> createState() =>
      _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends ConsumerState<AdminSettingsScreen> {
  final _announcementCtrl = TextEditingController();
  final _minVersionCtrl = TextEditingController();
  final _iosUrlCtrl = TextEditingController();
  final _androidUrlCtrl = TextEditingController();
  final _newTypeCtrl = TextEditingController();
  final _newProfessionCtrl = TextEditingController();
  final _newFieldCtrl = TextEditingController();
  final _newAcademicLevelCtrl = TextEditingController();
  final _newGoalCtrl = TextEditingController();
  final _newProfanityCtrl = TextEditingController();
  String? _newTypeError;
  String? _newProfessionError;
  String? _newFieldError;
  String? _newAcademicLevelError;
  String? _newGoalError;
  String? _newProfanityError;
  bool _hydrated = false;
  bool _saving = false;
  AdminConfig _cfg = const AdminConfig();

  String? _validateBadgeInput({
    required String value,
    required List<String> existing,
  }) {
    if (value.isEmpty) return 'You must write something.';
    if (existing.any((x) => x.toLowerCase() == value.toLowerCase())) {
      return 'The badge you are adding already exists.';
    }
    return null;
  }

  void _hydrate(AdminConfig cfg) {
    if (_hydrated) return;
    _cfg = cfg;
    _announcementCtrl.text = cfg.announcement;
    _minVersionCtrl.text = cfg.minAppVersion;
    _iosUrlCtrl.text = cfg.iosAppStoreUrl;
    _androidUrlCtrl.text = cfg.androidPlayStoreUrl;
    _hydrated = true;
  }

  @override
  void dispose() {
    _announcementCtrl.dispose();
    _minVersionCtrl.dispose();
    _iosUrlCtrl.dispose();
    _androidUrlCtrl.dispose();
    _newTypeCtrl.dispose();
    _newProfessionCtrl.dispose();
    _newFieldCtrl.dispose();
    _newAcademicLevelCtrl.dispose();
    _newGoalCtrl.dispose();
    _newProfanityCtrl.dispose();
    super.dispose();
  }

  void _addEventType() {
    final v = _newTypeCtrl.text.trim();
    final error = _validateBadgeInput(value: v, existing: _cfg.eventTypes);
    if (error != null) {
      setState(() => _newTypeError = error);
      return;
    }
    setState(() {
      _newTypeError = null;
      _cfg = _cfg.copyWith(eventTypes: [..._cfg.eventTypes, v]);
      _newTypeCtrl.clear();
    });
  }

  void _removeEventType(String t) {
    if (_cfg.eventTypes.length <= 1) return; // keep at least one
    setState(() => _cfg = _cfg.copyWith(
        eventTypes: _cfg.eventTypes.where((x) => x != t).toList()));
  }

  void _addProfession() {
    final v = _newProfessionCtrl.text.trim();
    final error = _validateBadgeInput(
      value: v,
      existing: _cfg.profileProfessionOptions,
    );
    if (error != null) {
      setState(() => _newProfessionError = error);
      return;
    }
    setState(() {
      _newProfessionError = null;
      _cfg = _cfg.copyWith(
        profileProfessionOptions: [..._cfg.profileProfessionOptions, v],
      );
      _newProfessionCtrl.clear();
    });
  }

  void _removeProfession(String v) {
    if (_cfg.profileProfessionOptions.length <= 1) return;
    setState(() => _cfg = _cfg.copyWith(
          profileProfessionOptions:
              _cfg.profileProfessionOptions.where((x) => x != v).toList(),
        ));
  }

  void _addField() {
    final v = _newFieldCtrl.text.trim();
    final error =
        _validateBadgeInput(value: v, existing: _cfg.profileFieldOptions);
    if (error != null) {
      setState(() => _newFieldError = error);
      return;
    }
    setState(() {
      _newFieldError = null;
      _cfg = _cfg.copyWith(
        profileFieldOptions: [..._cfg.profileFieldOptions, v],
      );
      _newFieldCtrl.clear();
    });
  }

  void _removeField(String v) {
    if (_cfg.profileFieldOptions.length <= 1) return;
    setState(() => _cfg = _cfg.copyWith(
          profileFieldOptions:
              _cfg.profileFieldOptions.where((x) => x != v).toList(),
        ));
  }

  void _addAcademicLevel() {
    final v = _newAcademicLevelCtrl.text.trim();
    final error = _validateBadgeInput(
      value: v,
      existing: _cfg.profileAcademicLevelOptions,
    );
    if (error != null) {
      setState(() => _newAcademicLevelError = error);
      return;
    }
    setState(() {
      _newAcademicLevelError = null;
      _cfg = _cfg.copyWith(
        profileAcademicLevelOptions: [..._cfg.profileAcademicLevelOptions, v],
      );
      _newAcademicLevelCtrl.clear();
    });
  }

  void _removeAcademicLevel(String v) {
    if (_cfg.profileAcademicLevelOptions.length <= 1) return;
    setState(() => _cfg = _cfg.copyWith(
          profileAcademicLevelOptions:
              _cfg.profileAcademicLevelOptions.where((x) => x != v).toList(),
        ));
  }

  void _addGoal() {
    final v = _newGoalCtrl.text.trim();
    final error =
        _validateBadgeInput(value: v, existing: _cfg.profileGoalOptions);
    if (error != null) {
      setState(() => _newGoalError = error);
      return;
    }
    setState(() {
      _newGoalError = null;
      _cfg = _cfg.copyWith(profileGoalOptions: [..._cfg.profileGoalOptions, v]);
      _newGoalCtrl.clear();
    });
  }

  void _removeGoal(String v) {
    if (_cfg.profileGoalOptions.length <= 1) return;
    setState(() => _cfg = _cfg.copyWith(
          profileGoalOptions:
              _cfg.profileGoalOptions.where((x) => x != v).toList(),
        ));
  }

  void _addProfanity() {
    final v = _newProfanityCtrl.text.trim().toLowerCase();
    final error =
        _validateBadgeInput(value: v, existing: _cfg.profanityWordsEn);
    if (error != null) {
      setState(() => _newProfanityError = error);
      return;
    }
    setState(() {
      _newProfanityError = null;
      _cfg = _cfg.copyWith(
          profanityWordsEn: [..._cfg.profanityWordsEn, v]..sort());
      _newProfanityCtrl.clear();
    });
  }

  void _removeProfanity(String v) {
    if (_cfg.profanityWordsEn.length <= 1) return;
    setState(() => _cfg = _cfg.copyWith(
          profanityWordsEn: _cfg.profanityWordsEn.where((x) => x != v).toList(),
        ));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final next = _cfg.copyWith(
        announcement: _announcementCtrl.text.trim(),
        minAppVersion: _minVersionCtrl.text.trim(),
        iosAppStoreUrl: _iosUrlCtrl.text.trim(),
        androidPlayStoreUrl: _androidUrlCtrl.text.trim(),
        // _cfg already carries the edited list fields.
      );
      await ref.read(adminServiceProvider).saveConfig(next);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t.adminSaved)),
        );
        Navigator.of(context).pop();
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
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(context.t.adminAppSettings),
        backgroundColor: Colors.transparent,
        foregroundColor: context.textPrimary,
        elevation: 0,
        flexibleSpace: const AppPageBackground(child: SizedBox.expand()),
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
      body: AppPageBackground(
        child: cfgAsync.when(
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
                errorText: _newTypeError,
                onInputChanged: (_) {
                  if (_newTypeError != null) {
                    setState(() => _newTypeError = null);
                  }
                },
                onAdd: _addEventType,
                onRemove: _removeEventType,
              ),
              const SizedBox(height: 16),
              _section(context.t.adminSettingsSectionProfessions),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text(
                  context.t.adminSettingsSectionProfessionsDesc,
                  style: TextStyle(fontSize: 12, color: context.textSecondary),
                ),
              ),
              _editableList(
                items: _cfg.profileProfessionOptions,
                controller: _newProfessionCtrl,
                hint: context.t.adminSettingsAddProfession,
                errorText: _newProfessionError,
                onInputChanged: (_) {
                  if (_newProfessionError != null) {
                    setState(() => _newProfessionError = null);
                  }
                },
                onAdd: _addProfession,
                onRemove: _removeProfession,
              ),
              const SizedBox(height: 16),
              _section(context.t.adminSettingsSectionFields),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text(
                  context.t.adminSettingsSectionFieldsDesc,
                  style: TextStyle(fontSize: 12, color: context.textSecondary),
                ),
              ),
              _editableList(
                items: _cfg.profileFieldOptions,
                controller: _newFieldCtrl,
                hint: context.t.adminSettingsAddField,
                errorText: _newFieldError,
                onInputChanged: (_) {
                  if (_newFieldError != null)
                    setState(() => _newFieldError = null);
                },
                onAdd: _addField,
                onRemove: _removeField,
              ),
              const SizedBox(height: 16),
              _section(context.t.adminSettingsSectionAcademicLevels),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text(
                  context.t.adminSettingsSectionAcademicLevelsDesc,
                  style: TextStyle(fontSize: 12, color: context.textSecondary),
                ),
              ),
              _editableList(
                items: _cfg.profileAcademicLevelOptions,
                controller: _newAcademicLevelCtrl,
                hint: context.t.adminSettingsAddAcademicLevel,
                errorText: _newAcademicLevelError,
                onInputChanged: (_) {
                  if (_newAcademicLevelError != null) {
                    setState(() => _newAcademicLevelError = null);
                  }
                },
                onAdd: _addAcademicLevel,
                onRemove: _removeAcademicLevel,
              ),
              const SizedBox(height: 16),
              _section(context.t.adminSettingsSectionGoals),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text(
                  context.t.adminSettingsSectionGoalsDesc,
                  style: TextStyle(fontSize: 12, color: context.textSecondary),
                ),
              ),
              _editableList(
                items: _cfg.profileGoalOptions,
                controller: _newGoalCtrl,
                hint: context.t.adminSettingsAddGoal,
                errorText: _newGoalError,
                onInputChanged: (_) {
                  if (_newGoalError != null)
                    setState(() => _newGoalError = null);
                },
                onAdd: _addGoal,
                onRemove: _removeGoal,
              ),
              const SizedBox(height: 16),
              _section(context.t.adminSettingsSectionProfanity),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text(
                  context.t.adminSettingsSectionProfanityDesc,
                  style: TextStyle(fontSize: 12, color: context.textSecondary),
                ),
              ),
              _editableList(
                items: _cfg.profanityWordsEn,
                controller: _newProfanityCtrl,
                hint: context.t.adminSettingsAddProfanity,
                errorText: _newProfanityError,
                onInputChanged: (_) {
                  if (_newProfanityError != null) {
                    setState(() => _newProfanityError = null);
                  }
                },
                onAdd: _addProfanity,
                onRemove: _removeProfanity,
              ),
              const SizedBox(height: 24),
            ],
          );
        },
        ),
      ),
    );
  }

  Widget _editableList({
    required List<String> items,
    required TextEditingController controller,
    required String hint,
    String? errorText,
    ValueChanged<String>? onInputChanged,
    required VoidCallback onAdd,
    required ValueChanged<String> onRemove,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FocusInputRow(
          controller: controller,
          hintText: hint,
          errorText: errorText,
          onChanged: onInputChanged,
          onAdd: onAdd,
          decoration: _inputDecoration(hint),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              errorText,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ],
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
    return AppGlassCard(
      margin: const EdgeInsets.only(bottom: 8),
      radius: 16,
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
    return AppGlassCard(
      radius: 16,
      borderAlpha: _focusNode.hasFocus ? 0.65 : null,
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
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final VoidCallback onAdd;
  final InputDecoration decoration;

  const _FocusInputRow({
    required this.controller,
    required this.hintText,
    this.errorText,
    this.onChanged,
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
    return AppGlassCard(
      radius: 16,
      borderAlpha: widget.errorText != null || _focusNode.hasFocus ? 0.65 : null,
      padding: const EdgeInsets.fromLTRB(14, 2, 10, 2),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              focusNode: _focusNode,
              controller: widget.controller,
              textInputAction: TextInputAction.done,
              onChanged: widget.onChanged,
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
