import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_strings.dart';
import '../../providers/admin_providers.dart';
import '../../providers/auth_providers.dart';
import '../../providers/notification_providers.dart';
import '../../services/admin_service.dart';
import '../../services/user_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_feedback.dart';
import '../widgets/app_page_background.dart';

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

  /// Inline search over the country chip list. ~200 countries is too
  /// many to scroll through one by one, so a search field above the
  /// chips lets the user jump to the one they want. Selected countries
  /// stay visible at the top of the filtered list regardless of query.
  final TextEditingController _countrySearchCtrl = TextEditingController();
  String _countryQuery = '';

  @override
  void dispose() {
    _countrySearchCtrl.dispose();
    super.dispose();
  }

  void _hydrate(EventNotifPrefs p) {
    if (_hydrated) return;
    _prefs = p;
    _hydrated = true;
  }

  bool get _allTypes => _prefs.types.isEmpty;
  bool get _allCountries => _prefs.countries.isEmpty;

  String _countryKey(String country) => country.trim().toLowerCase();

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
    final key = _countryKey(displayName);
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
        AppFeedback.showSuccess(context, context.t.eventNotifSaved);
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.showError(context, context.t.eventNotifCouldNotSave(e));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefsAsync = ref.watch(eventNotifPrefsProvider);
    final cfg = ref.watch(adminConfigProvider).value ?? const AdminConfig();
    final eventTypes = cfg.eventTypes;
    final eventCountries = kEventCountries;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(context.t.eventNotifTitle),
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
        child: prefsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(context.t.errorWithMessage(e))),
          data: (loaded) {
            _hydrate(loaded);
            final enabled = _prefs.mode != EventNotifMode.off;
            return ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                24 + MediaQuery.of(context).padding.bottom,
              ),
              children: [
              _switchTile(
                title: context.t.eventNotifNewEventNotifications,
                subtitle: context.t.eventNotifNewEventSubtitle,
                value: enabled,
                onChanged: (v) => setState(() => _prefs = _prefs.copyWith(
                    mode: v ? EventNotifMode.all : EventNotifMode.off)),
              ),
              if (enabled) ...[
                const SizedBox(height: 16),
                _sectionLabel(context.t.eventNotifEventTypes),
                Text(
                  _allTypes
                      ? context.t.eventNotifAllTypesDesc
                      : context.t.eventNotifCustomTypesDesc,
                  style: TextStyle(fontSize: 12, color: context.textSecondary),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildChoiceChip(
                      label: context.t.eventNotifAllTypes,
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
                _sectionLabel(context.t.eventNotifCountries),
                Text(
                  _allCountries
                      ? context.t.eventNotifAllCountriesDesc
                      : context.t.eventNotifCustomCountriesDesc,
                  style: TextStyle(fontSize: 12, color: context.textSecondary),
                ),
                const SizedBox(height: 10),
                // Inline search field over the country chips. Filters
                // case-insensitively; selected countries are always
                // included even when they don't match the query so the
                // user can deselect them from the same list.
                AppGlassCard(
                  radius: 16,
                  surfaceAlpha: context.isDark ? 0.42 : 0.36,
                  borderAlpha: context.isDark ? 0.14 : 0.50,
                  padding: EdgeInsets.zero,
                  child: TextField(
                    controller: _countrySearchCtrl,
                    onChanged: (v) =>
                        setState(() => _countryQuery = v.trim().toLowerCase()),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search, size: 20),
                      hintText: context.t.adminSearchCountry,
                      suffixIcon: _countryQuery.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () {
                                _countrySearchCtrl.clear();
                                setState(() => _countryQuery = '');
                              },
                            ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (!_allCountries) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildChoiceChip(
                        label: context.t.eventNotifAllCountries,
                        selected: false,
                        onSelected: (_) => _selectAllCountries(),
                      ),
                      ...eventCountries
                          .where((c) => _prefs.countries.contains(_countryKey(c)))
                          .map((c) => _buildFilterChip(
                                label: c,
                                selected: true,
                                onSelected: (_) =>
                                    _toggleCountry(c, eventCountries.length),
                              )),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (_allCountries)
                      _buildChoiceChip(
                        label: context.t.eventNotifAllCountries,
                        selected: true,
                        onSelected: (_) => _selectAllCountries(),
                      ),
                    ...eventCountries.where((c) {
                      final isSelected =
                          !_allCountries && _prefs.countries.contains(_countryKey(c));
                      if (isSelected) return false;
                      if (_countryQuery.isEmpty) return true;
                      return c.toLowerCase().contains(_countryQuery);
                    }).map((c) {
                      final selected = !_allCountries &&
                          _prefs.countries.contains(_countryKey(c));
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
    // Light up the whole card when ON: tinted background, brand-colored
    // border, and a filled bell icon. The bare Switch thumb on its own
    // wasn't a strong enough signal on Android in light mode — users
    // missed the on/off state.
    return AppGlassCard(
      radius: 16,
      emphasize: value,
      surfaceAlpha: context.isDark ? 0.42 : 0.36,
      borderAlpha: value ? 0.65 : (context.isDark ? 0.14 : 0.50),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        activeThumbColor: Colors.white,
        activeTrackColor: AppColors.purple,
        inactiveThumbColor: context.textSecondary,
        inactiveTrackColor: context.inputFill,
        secondary: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: value ? AppColors.purple : context.inputFill,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            value ? Icons.notifications_active : Icons.notifications_off,
            color: value ? Colors.white : context.textSecondary,
            size: 20,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: value ? AppColors.purple : context.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: value
                    ? AppColors.purple
                    : context.textSecondary.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                value ? context.t.on : context.t.off,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: value ? Colors.white : context.textSecondary,
                ),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            subtitle,
            style: TextStyle(fontSize: 12, color: context.textSecondary),
          ),
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
      backgroundColor: context.isDark
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.white.withValues(alpha: 0.30),
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
      backgroundColor: context.isDark
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.white.withValues(alpha: 0.30),
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
