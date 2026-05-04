import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../providers/auth_providers.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';

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

  bool _initialized = false;
  bool _saving = false;
  bool _uploadingAvatar = false;
  bool _uploadingCover = false;
  String? _avatarUrl;
  String? _coverUrl;

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _hydrate(Map<String, dynamic> user) {
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
    _initialized = true;
  }

  String _normalizeUsername(String raw) => raw.trim().toLowerCase();

  bool _isValidUsername(String username) {
    return RegExp(r'^[a-z0-9._]{3,24}$').hasMatch(username);
  }

  Future<void> _pickAndUploadAvatar() async {
    if (_uploadingAvatar) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1024,
    );
    if (picked == null) return;

    setState(() => _uploadingAvatar = true);
    try {
      final url = await StorageService().uploadAvatar(File(picked.path));
      final uid = ref.read(authServiceProvider).currentUser!.uid;
      await ref.read(userServiceProvider).updateUser(uid, {'avatarUrl': url});
      if (mounted) setState(() => _avatarUrl = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _pickAndUploadCover() async {
    if (_uploadingCover) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (picked == null) return;

    setState(() => _uploadingCover = true);
    try {
      final url = await StorageService().uploadCover(File(picked.path));
      final uid = ref.read(authServiceProvider).currentUser!.uid;
      await ref.read(userServiceProvider).updateUser(uid, {'coverUrl': url});
      if (mounted) setState(() => _coverUrl = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cover upload failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingCover = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final username = _normalizeUsername(_usernameController.text);
    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Username can\'t be empty')),
      );
      return;
    }
    if (!_isValidUsername(username)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Username must be 3-24 chars and use only a-z, 0-9, . or _',
          ),
        ),
      );
      return;
    }

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
              const SnackBar(content: Text('Username is already taken')),
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
      await ref.read(userServiceProvider).updateUser(uid, {
        'name': nameToSave,
        'username': username,
        'usernameLower': username,
        'handle': '@$username',
        'bio': _bioController.text.trim(),
        'gender': genderToSave,
      });

      // Keep FirebaseAuth profile displayName aligned for legacy fallbacks.
      await ref
          .read(authServiceProvider)
          .currentUser
          ?.updateDisplayName(nameToSave);

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserDocProvider);

    return Scaffold(
      backgroundColor: context.surfaceSoft,
      body: SafeArea(
        child: userAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (user) {
            if (user == null) {
              return const Center(child: Text('No profile data'));
            }
            _hydrate(user);
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
                          label: 'Change profile photo',
                          onTap: _pickAndUploadAvatar,
                        ),
                        const SizedBox(height: 4),
                        _CenterEditLink(
                          label: 'Change cover image',
                          onTap: _pickAndUploadCover,
                        ),
                        const SizedBox(height: 24),
                        const _SectionLabel(text: 'About you'),
                        _LabeledInput(
                          label: 'Name',
                          icon: Icons.person_outline,
                          controller: _nameController,
                          hint: 'Your display name',
                          maxLength: 40,
                        ),
                        _LabeledInput(
                          label: 'Username',
                          icon: Icons.alternate_email,
                          controller: _usernameController,
                          hint: 'unique username',
                          maxLength: 24,
                        ),
                        _LabeledInput(
                          label: 'Bio',
                          icon: Icons.short_text,
                          controller: _bioController,
                          hint: 'Tell people a little about you',
                          maxLines: 4,
                          maxLength: 160,
                        ),
                        _LabeledDropdown(
                          label: 'Gender',
                          icon: Icons.person_outline,
                          value: _gender,
                          options: _genderOptions,
                          onChanged: (v) => setState(() => _gender = v),
                          hint: 'Select gender',
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
    );
  }

  Widget _buildCoverAndAvatar() {
    return SizedBox(
      height: 180 + 52,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onTap: _pickAndUploadCover,
            child: Container(
              height: 180,
              width: double.infinity,
              decoration: BoxDecoration(
                color: context.inputFill,
                image: _coverUrl != null
                    ? DecorationImage(
                        image: CachedNetworkImageProvider(_coverUrl!),
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
                onTap: _pickAndUploadAvatar,
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
                        backgroundImage: _avatarUrl != null
                            ? CachedNetworkImageProvider(_avatarUrl!)
                            : null,
                        child: _avatarUrl == null
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
          const Expanded(
            child: Text(
              'Edit profile',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
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
                : const Text(
                    'Save',
                    style: TextStyle(
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
      child: Container(
        decoration: BoxDecoration(
          color: context.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: context.borderColor.withValues(alpha: 0.6), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
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
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                border: InputBorder.none,
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

  const _LabeledDropdown({
    required this.label,
    required this.hint,
    required this.icon,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Container(
        decoration: BoxDecoration(
          color: context.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: context.borderColor.withValues(alpha: 0.6), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
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
                    child: Text(opt),
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
