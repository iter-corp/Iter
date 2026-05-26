import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';

import '../../../l10n/app_strings.dart';
import '../../../providers/admin_providers.dart';
import '../../../providers/auth_providers.dart';
import '../../../services/admin_service.dart';
import '../../../services/city_service.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/responsive.dart';
import '../../widgets/personalization_fields.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  String? _gender;

  // Optional "About you" personalization — used to make Events / Connect
  // surfaces more relevant. All skippable.
  String? _profession;
  String? _field;
  String? _academicLevel;
  List<String> _goals = const [];

  bool _loading = false;
  String? _error;

  // Location state
  double? _lat;
  double? _lng;
  bool _gpsBusy = false;
  String? _gpsError;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    _bioCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  Future<void> _useGps() async {
    if (_gpsBusy) return;
    setState(() {
      _gpsBusy = true;
      _gpsError = null;
    });
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        throw 'Location services are off. Enable them in your device settings.';
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied) {
        throw 'Permission denied. You can enter your city manually below.';
      }
      if (perm == LocationPermission.deniedForever) {
        throw 'Permission permanently denied. Open Settings to allow location.';
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
      _lat = pos.latitude;
      _lng = pos.longitude;

      // Best-effort reverse geocode → fill city for the City filter.
      try {
        final places = await geo.placemarkFromCoordinates(_lat!, _lng!);
        if (places.isNotEmpty) {
          final p = places.first;
          final city = (p.locality?.isNotEmpty ?? false)
              ? p.locality!
              : (p.subAdministrativeArea ?? p.administrativeArea ?? '');
          if (city.isNotEmpty && mounted) {
            _cityCtrl.text = city;
          }
        }
      } catch (_) {
        // Reverse geocoding can fail on emulators / no Play Services. The lat/lng
        // is still saved so Nearby works; user can type a city manually.
      }

      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _gpsError = e.toString());
    } finally {
      if (mounted) setState(() => _gpsBusy = false);
    }
  }

  void _clearLocation() {
    setState(() {
      _lat = null;
      _lng = null;
      _gpsError = null;
    });
  }

  String _normalizeUsername(String raw) => raw.trim().toLowerCase();

  bool _isValidUsername(String username) {
    return RegExp(r'^[a-z0-9._]{3,24}$').hasMatch(username);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final userService = ref.read(userServiceProvider);
      final uid = ref.read(authServiceProvider).currentUser!.uid;
      final username = _normalizeUsername(_usernameCtrl.text);
      if (!_isValidUsername(username)) {
        setState(() {
          _error = 'Username must be 3-24 chars and use only a-z, 0-9, . or _';
        });
        return;
      }
      final taken =
          await userService.isUsernameTaken(username, excludeUid: uid);
      if (taken) {
        setState(() => _error = 'Username already taken');
        return;
      }

      final city = _cityCtrl.text.trim();
      final realName = _nameCtrl.text.trim();
      final applicableLevel =
          academicLevelAppliesTo(_profession) ? _academicLevel : null;
      final data = <String, dynamic>{
        // Display name = what the user typed in the Name field. Falls back
        // to the username so older callers that read `name` still get a
        // non-empty value.
        'name': realName.isEmpty ? username : realName,
        'username': username,
        'usernameLower': username,
        'handle': '@$username',
        'bio': _bioCtrl.text.trim(),
        'gender': _gender,
        if (city.isNotEmpty) 'city': city,
        if (_lat != null && _lng != null)
          'location': {'lat': _lat, 'lng': _lng},
        // Optional personalization (kept separate from the RBAC `role` field).
        if (_profession != null) 'profession': _profession,
        if (_field != null) 'field': _field,
        if (applicableLevel != null) 'academicLevel': applicableLevel,
        if (_goals.isNotEmpty) 'goals': _goals,
      };
      await userService.updateUser(uid, data);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(adminConfigProvider).valueOrNull ?? const AdminConfig();
    final pad = context.scaleW(16, 24);
    return Scaffold(
      appBar: AppBar(title: Text(context.t.onboardingSetupProfile)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(pad, pad, pad, pad + context.bottomSafeInset),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: context.t.onboardingName,
                    hintText: context.t.onboardingNameHint,
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? context.t.onboardingNameRequired
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _usernameCtrl,
                  decoration: InputDecoration(labelText: context.t.username),
                  validator: (v) => (v == null || v.trim().length < 3)
                      ? context.t.onboardingMin3Chars
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _bioCtrl,
                  decoration: InputDecoration(labelText: context.t.bio),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _gender,
                  decoration:
                      InputDecoration(labelText: context.t.onboardingGender),
                  items: [
                    DropdownMenuItem(
                        value: 'Male',
                        child: Text(context.t.onboardingGenderMale)),
                    DropdownMenuItem(
                        value: 'Female',
                        child: Text(context.t.onboardingGenderFemale)),
                    DropdownMenuItem(
                        value: 'Non-binary',
                        child: Text(context.t.onboardingGenderNonBinary)),
                    DropdownMenuItem(
                        value: 'Other',
                        child: Text(context.t.onboardingGenderOther)),
                  ],
                  onChanged: (v) => setState(() => _gender = v),
                ),
                const SizedBox(height: 24),
                _LocationSection(
                  hasGps: _lat != null,
                  busy: _gpsBusy,
                  error: _gpsError,
                  cityCtrl: _cityCtrl,
                  onCityChanged: () => setState(() {}),
                  onUseGps: _useGps,
                  onClear: _clearLocation,
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.surfaceSoft,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: context.borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.tune_rounded,
                              color: AppColors.purple, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              context.t.onboardingAboutYou,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: context.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            context.t.onboardingOptional,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: context.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        context.t.onboardingAboutYouDesc,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.textSecondary,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 16),
                      AboutYouEditor(
                        profession: _profession,
                        field: _field,
                        academicLevel: _academicLevel,
                        goals: _goals,
                        professionOptions: cfg.profileProfessionOptions,
                        fieldOptions: cfg.profileFieldOptions,
                        academicLevelOptions: cfg.profileAcademicLevelOptions,
                        goalOptions: cfg.profileGoalOptions,
                        onProfessionChanged: (v) =>
                            setState(() => _profession = v),
                        onFieldChanged: (v) => setState(() => _field = v),
                        onAcademicLevelChanged: (v) =>
                            setState(() => _academicLevel = v),
                        onGoalsChanged: (v) => setState(() => _goals = v),
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(context.t.continueLabel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LocationSection extends StatelessWidget {
  final bool hasGps;
  final bool busy;
  final String? error;
  final TextEditingController cityCtrl;

  /// Fired after the city picker writes a new value into [cityCtrl], so
  /// the parent can rebuild and reflect the selection.
  final VoidCallback onCityChanged;
  final VoidCallback onUseGps;
  final VoidCallback onClear;

  const _LocationSection({
    required this.hasGps,
    required this.busy,
    required this.error,
    required this.cityCtrl,
    required this.onCityChanged,
    required this.onUseGps,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.near_me_rounded,
                  color: Color(0xFFB05ECC), size: 20),
              const SizedBox(width: 8),
              Text(
                context.t.onboardingWhereAreYou,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ),
              ),
              const Spacer(),
              if (hasGps)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3BD671).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    context.t.onboardingGpsSet,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1F8D4D),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            context.t.onboardingLocationDesc,
            style: TextStyle(
                fontSize: 12, color: context.textSecondary, height: 1.3),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy ? null : onUseGps,
                  icon: busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          hasGps
                              ? Icons.refresh_rounded
                              : Icons.my_location_rounded,
                          size: 18,
                        ),
                  label: Text(hasGps
                      ? context.t.onboardingUpdateLocation
                      : context.t.onboardingUseMyLocation),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFB05ECC),
                  ),
                ),
              ),
              if (hasGps) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: onClear,
                  tooltip: context.t.clear,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              error!,
              style: const TextStyle(fontSize: 12, color: Colors.redAccent),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            context.t.onboardingCity,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          CityPickerField(
            value: cityCtrl.text,
            hintText: hasGps
                ? context.t.onboardingCityAutofilled
                : context.t.onboardingCityHint,
            onChanged: (city) {
              cityCtrl.text = city;
              onCityChanged();
            },
            onClear: () {
              cityCtrl.clear();
              onCityChanged();
            },
          ),
        ],
      ),
    );
  }
}
