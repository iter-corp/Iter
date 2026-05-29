import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/app_strings.dart';
import '../../providers/admin_providers.dart';
import '../../providers/auth_providers.dart';
import '../../services/admin_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_feedback.dart';
import '../widgets/app_page_background.dart';
import '../widgets/personalization_fields.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _bioController = TextEditingController();
  // Gender is no longer free-text — picked from a fixed list. Stored as
  // null when the user selects "Prefer not to say" so we don't put a
  // synthetic value into Firestore.
  String? _gender;

  static const List<String> _genderOptions = [
    'Female',
    'Male',
    'Non-binary',
    'Other',
    'Prefer not to say',
  ];

  // Optional "About you" personalization.
  String? _profession;
  String? _field;
  String? _academicLevel;
  List<String> _goals = const [];

  bool _initialized = false;
  bool _saving = false;
  bool _uploadingAvatar = false;
  bool _uploadingCover = false;
  String? _avatarUrl;
  String? _coverUrl;
  File? _pendingAvatarFile;
  File? _pendingCoverFile;

  ImageProvider? get _avatarImage {
    final pending = _pendingAvatarFile;
    if (pending != null) return FileImage(pending);
    final url = _avatarUrl?.trim();
    if (url != null && url.isNotEmpty) return CachedNetworkImageProvider(url);
    return null;
  }

  ImageProvider? get _coverImage {
    final pending = _pendingCoverFile;
    if (pending != null) return FileImage(pending);
    final url = _coverUrl?.trim();
    if (url != null && url.isNotEmpty) return CachedNetworkImageProvider(url);
    return null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _hydrate(Map<String, dynamic> user, AdminConfig cfg) {
    if (_initialized) return;
    final username = (user['username'] as String?) ?? '';
    _nameController.text = (user['name'] as String?) ?? username;
    _usernameController.text = username;
    _bioController.text = (user['bio'] as String?) ?? '';
    final raw = (user['gender'] as String?)?.trim() ?? '';
    if (raw.isEmpty) {
      _gender = null;
    } else {
      // Match case-insensitively against the canonical option set.
      final match = _genderOptions.firstWhere(
        (g) => g.toLowerCase() == raw.toLowerCase(),
        orElse: () => 'Other',
      );
      _gender = match;
    }
    _avatarUrl = user['avatarUrl'] as String?;
    _coverUrl = user['coverUrl'] as String?;
    _profession = _matchOption(user['profession'], cfg.profileProfessionOptions);
    _field = _matchOption(user['field'], cfg.profileFieldOptions);
    _academicLevel =
      _matchOption(user['academicLevel'], cfg.profileAcademicLevelOptions);
    _goals = ((user['goals'] as List?)?.cast<String>() ?? const [])
      .where(cfg.profileGoalOptions.contains)
        .toList();
    _initialized = true;
  }

  /// Returns the option whose lower-cased text equals [raw], or null.
  static String? _matchOption(dynamic raw, List<String> options) {
    final s = (raw as String?)?.trim() ?? '';
    if (s.isEmpty) return null;
    for (final o in options) {
      if (o.toLowerCase() == s.toLowerCase()) return o;
    }
    return null;
  }

  /// Maps a stable gender option value to its localized display label.
  String _genderLabel(String value) {
    switch (value) {
      case 'Female':
        return context.t.onboardingGenderFemale;
      case 'Male':
        return context.t.onboardingGenderMale;
      case 'Non-binary':
        return context.t.onboardingGenderNonBinary;
      case 'Other':
        return context.t.onboardingGenderOther;
      case 'Prefer not to say':
        return context.t.editProfilePreferNotToSay;
      default:
        return value;
    }
  }

  String _normalizeUsername(String raw) => raw.trim().toLowerCase();

  bool _isValidUsername(String username) {
    return RegExp(r'^[a-z0-9._]{3,24}$').hasMatch(username);
  }

  Future<void> _pickAvatar() async {
    if (_saving || _uploadingAvatar) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1024,
    );
    if (picked == null) return;
    if (mounted) setState(() => _pendingAvatarFile = File(picked.path));
  }

  Future<void> _pickCover() async {
    if (_saving || _uploadingCover) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (picked == null) return;
    if (mounted) setState(() => _pendingCoverFile = File(picked.path));
  }

  /// Append a unique version query param to a freshly uploaded image URL.
  ///
  /// The storage backend returns a deterministic path per user+kind, so
  /// replacing an avatar/cover yields the SAME url string as before. Both
  /// `CachedNetworkImage` and the CDN then keep serving the old bytes — the
  /// user picks a new photo, saves, and nothing visibly changes. A `?v=`
  /// stamp makes each saved url distinct so the new image actually loads.
  String _withCacheBust(String url) {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final sep = url.contains('?') ? '&' : '?';
    return '$url${sep}v=$stamp';
  }

  Future<void> _save() async {
    if (_saving) return;
    final username = _normalizeUsername(_usernameController.text);
    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t.editProfileUsernameEmpty)),
      );
      return;
    }
    if (!_isValidUsername(username)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.editProfileUsernameInvalid),
        ),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final updatedMsg = context.t.editProfileUpdated;
    final strings = context.t;
    setState(() => _saving = true);
    try {
      final uid = ref.read(authServiceProvider).currentUser!.uid;
      final currentUser = ref.read(currentUserDocProvider).valueOrNull;
      final existingUsername =
          _normalizeUsername((currentUser?['username'] as String?) ?? '');
      if (username != existingUsername) {
        final taken = await ref
            .read(userServiceProvider)
            .isUsernameTaken(username, excludeUid: uid);
        if (taken) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.t.editProfileUsernameTaken)),
            );
          }
          return;
        }
      }

      final name = _nameController.text.trim();
      final nameToSave = name.isEmpty ? username : name;
      // "Prefer not to say" / null both write an empty string so the
      // field exists in Firestore but doesn't surface anywhere.
      final genderToSave =
          (_gender == null || _gender == 'Prefer not to say') ? '' : _gender!;
      final applicableLevel =
          academicLevelAppliesTo(_profession) ? _academicLevel : null;
      String? avatarUrlToSave;
      String? coverUrlToSave;
      if (_pendingAvatarFile != null) {
        setState(() => _uploadingAvatar = true);
        try {
          avatarUrlToSave = _withCacheBust(
              await StorageService().uploadAvatar(_pendingAvatarFile!));
        } finally {
          if (mounted) setState(() => _uploadingAvatar = false);
        }
        if (!mounted) return;
      }
      if (_pendingCoverFile != null) {
        setState(() => _uploadingCover = true);
        try {
          coverUrlToSave = _withCacheBust(
              await StorageService().uploadCover(_pendingCoverFile!));
        } finally {
          if (mounted) setState(() => _uploadingCover = false);
        }
        if (!mounted) return;
      }

      await ref.read(userServiceProvider).updateUser(uid, {
        'name': nameToSave,
        'username': username,
        'usernameLower': username,
        'handle': '@$username',
        'bio': _bioController.text.trim(),
        'gender': genderToSave,
        // Personalization (separate from RBAC `role`). Empty/cleared values are
        // written so the fields stay in sync if the user removes a choice.
        'profession': _profession ?? '',
        'field': _field ?? '',
        'academicLevel': applicableLevel ?? '',
        'goals': _goals,
        if (avatarUrlToSave != null) 'avatarUrl': avatarUrlToSave,
        if (coverUrlToSave != null) 'coverUrl': coverUrlToSave,
      });

      // Keep FirebaseAuth profile displayName aligned for legacy fallbacks.
      await ref
          .read(authServiceProvider)
          .currentUser
          ?.updateDisplayName(nameToSave);

      if (mounted) {
        setState(() {
          if (avatarUrlToSave != null) {
            _avatarUrl = avatarUrlToSave;
            _pendingAvatarFile = null;
          }
          if (coverUrlToSave != null) {
            _coverUrl = coverUrlToSave;
            _pendingCoverFile = null;
          }
        });
        Navigator.pop(context);
        AppFeedback.showSuccessOn(messenger, updatedMsg);
      }
    } catch (e) {
      AppFeedback.showErrorOn(
          messenger, strings.editProfileCouldNotSave(e));
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _uploadingAvatar = false;
          _uploadingCover = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserDocProvider);
    final cfg = ref.watch(adminConfigProvider).valueOrNull ?? const AdminConfig();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppPageBackground(
        child: SafeArea(
          child: userAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text(context.t.errorWithMessage(e))),
            data: (user) {
              if (user == null) {
                return Center(child: Text(context.t.profileNoProfileData));
              }
              _hydrate(user, cfg);
              return Column(
                children: [
                  _Header(
                    saving: _saving,
                    onBack: () => Navigator.pop(context),
                    onSave: _save,
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildCoverAndAvatar(),
                          const SizedBox(height: 56),
                          _CenterEditLink(
                            label: context.t.editProfileChangePhoto,
                            onTap: _pickAvatar,
                          ),
                          const SizedBox(height: 4),
                          _CenterEditLink(
                            label: context.t.editProfileChangeCover,
                            onTap: _pickCover,
                          ),
                          const SizedBox(height: 24),
                          _SectionLabel(text: context.t.onboardingAboutYou),
                          _LabeledInput(
                            label: context.t.editProfileName,
                            icon: Icons.person_outline,
                            controller: _nameController,
                            hint: context.t.editProfileNameHint,
                            maxLength: 40,
                          ),
                          _LabeledInput(
                            label: context.t.username,
                            icon: Icons.alternate_email,
                            controller: _usernameController,
                            hint: context.t.editProfileUsernameHint,
                            maxLength: 24,
                          ),
                          _LabeledInput(
                            label: context.t.bio,
                            icon: Icons.short_text,
                            controller: _bioController,
                            hint: context.t.editProfileBioHint,
                            maxLines: 4,
                            maxLength: 160,
                          ),
                          _LabeledDropdown(
                            label: context.t.onboardingGender,
                            icon: Icons.person_outline,
                            value: _gender,
                            options: _genderOptions,
                            optionLabel: _genderLabel,
                            onChanged: (v) => setState(() => _gender = v),
                            hint: context.t.editProfileSelectGender,
                          ),
                          const SizedBox(height: 8),
                          _SectionLabel(
                              text: context.t.editProfileInterestsGoals),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                            child: Text(
                              context.t.editProfileInterestsDesc,
                              style: TextStyle(
                                fontSize: 12,
                                color: context.textSecondary,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                            child: AppGlassCard(
                              padding: const EdgeInsets.all(14),
                              radius: 18,
                              surfaceAlpha: context.isDark ? 0.24 : 0.52,
                              borderAlpha: context.isDark ? 0.16 : 0.50,
                              child: AboutYouEditor(
                                profession: _profession,
                                field: _field,
                                academicLevel: _academicLevel,
                                goals: _goals,
                                professionOptions: cfg.profileProfessionOptions,
                                fieldOptions: cfg.profileFieldOptions,
                                academicLevelOptions:
                                    cfg.profileAcademicLevelOptions,
                                goalOptions: cfg.profileGoalOptions,
                                onProfessionChanged: (v) =>
                                    setState(() => _profession = v),
                                onFieldChanged: (v) =>
                                    setState(() => _field = v),
                                onAcademicLevelChanged: (v) =>
                                    setState(() => _academicLevel = v),
                                onGoalsChanged: (v) =>
                                    setState(() => _goals = v),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCoverAndAvatar() {
    final coverImage = _coverImage;
    final avatarImage = _avatarImage;
    return SizedBox(
      height: 180 + 52,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onTap: _pickCover,
            child: Container(
              height: 180,
              width: double.infinity,
              decoration: BoxDecoration(
                color: context.inputFill,
                image: coverImage != null
                    ? DecorationImage(
                        image: coverImage,
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.18),
                        ],
                      ),
                    ),
                  ),
                  if (_uploadingCover)
                    const Center(
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5),
                    ),
                  Positioned(
                    right: 14,
                    top: 14,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.photo_camera_outlined,
                          color: Colors.white, size: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _pickAvatar,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: context.cardBg,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircleAvatar(
                        radius: 44,
                        backgroundColor: context.inputFill,
                        backgroundImage: avatarImage,
                        child: avatarImage == null
                            ? Icon(Icons.person,
                                size: 44, color: context.textSecondary)
                            : null,
                      ),
                      if (_uploadingAvatar)
                        const CircularProgressIndicator(
                          color: Color(0xFFB05ECC),
                          strokeWidth: 2.5,
                        ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: const Color(0xFFB05ECC),
                            shape: BoxShape.circle,
                            border: Border.all(color: context.cardBg, width: 2),
                          ),
                          child: const Icon(Icons.edit,
                              color: Colors.white, size: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final bool saving;
  final VoidCallback onBack;
  final VoidCallback onSave;

  const _Header({
    required this.saving,
    required this.onBack,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, size: 22),
          ),
          Expanded(
            child: Text(
              context.t.editProfile,
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(
            onPressed: saving ? null : onSave,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFB05ECC),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Color(0xFFB05ECC),
                    ),
                  )
                : Text(
                    context.t.save,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _CenterEditLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _CenterEditLink({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFFB05ECC),
              fontWeight: FontWeight.w600,
              fontSize: 13.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: context.textSecondary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _LabeledInput extends StatelessWidget {
  final String label;
  final String hint;
  final IconData icon;
  final TextEditingController controller;
  final int maxLines;
  final int? maxLength;

  const _LabeledInput({
    required this.label,
    required this.hint,
    required this.icon,
    required this.controller,
    this.maxLines = 1,
    this.maxLength,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: AppGlassCard(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        radius: 18,
        surfaceAlpha: context.isDark ? 0.24 : 0.52,
        borderAlpha: context.isDark ? 0.16 : 0.50,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: const Color(0xFFB05ECC)),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            TextField(
              controller: controller,
              maxLines: maxLines,
              maxLength: maxLength,
              style: TextStyle(
                fontSize: 15,
                color: context.textPrimary,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: context.textMuted, fontSize: 14),
                filled: false,
                fillColor: Colors.transparent,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                counterText: '',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LabeledDropdown extends StatelessWidget {
  final String label;
  final String hint;
  final IconData icon;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  /// Optional mapping from a stable option value to a localized label.
  final String Function(String)? optionLabel;

  const _LabeledDropdown({
    required this.label,
    required this.hint,
    required this.icon,
    required this.value,
    required this.options,
    required this.onChanged,
    this.optionLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: AppGlassCard(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
        radius: 18,
        surfaceAlpha: context.isDark ? 0.24 : 0.52,
        borderAlpha: context.isDark ? 0.16 : 0.50,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: const Color(0xFFB05ECC)),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            DropdownButtonFormField<String>(
              initialValue: value,
              isExpanded: true,
              icon: Icon(Icons.keyboard_arrow_down_rounded,
                  color: context.textSecondary),
              style: TextStyle(
                fontSize: 15,
                color: context.textPrimary,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: context.textMuted, fontSize: 14),
                filled: false,
                fillColor: Colors.transparent,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
              items: [
                for (final opt in options)
                  DropdownMenuItem(
                    value: opt,
                    child: Text(optionLabel?.call(opt) ?? opt),
                  ),
              ],
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
