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
  final _usernameController = TextEditingController();
  final _bioController = TextEditingController();
  final _genderController = TextEditingController();

  bool _initialized = false;
  bool _saving = false;
  bool _uploadingAvatar = false;
  bool _uploadingCover = false;
  String? _avatarUrl;
  String? _coverUrl;

  @override
  void dispose() {
    _usernameController.dispose();
    _bioController.dispose();
    _genderController.dispose();
    super.dispose();
  }

  void _hydrate(Map<String, dynamic> user) {
    if (_initialized) return;
    _usernameController.text = (user['username'] as String?) ?? '';
    _bioController.text = (user['bio'] as String?) ?? '';
    _genderController.text = (user['gender'] as String?) ?? '';
    _avatarUrl = user['avatarUrl'] as String?;
    _coverUrl = user['coverUrl'] as String?;
    _initialized = true;
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
    setState(() => _saving = true);
    try {
      final uid = ref.read(authServiceProvider).currentUser!.uid;
      await ref.read(userServiceProvider).updateUser(uid, {
        'username': _usernameController.text.trim(),
        'bio': _bioController.text.trim(),
        'gender': _genderController.text.trim(),
      });
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
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back, size: 22),
                      ),
                      const Text(
                        "Edit profile",
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        // COVER + AVATAR composite
                        _buildCoverAndAvatar(),
                        const SizedBox(height: 56),
                        GestureDetector(
                          onTap: _pickAndUploadAvatar,
                          child: const Text(
                            "Edit picture",
                            style: TextStyle(
                              color: Color(0xFFB05ECC),
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: _pickAndUploadCover,
                          child: const Text(
                            "Edit cover",
                            style: TextStyle(
                              color: Color(0xFFB05ECC),
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _buildField("Username", _usernameController),
                        _buildField("Bio", _bioController, maxLines: 3),
                        _buildField("Gender", _genderController),
                        const SizedBox(height: 32),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton(
                              onPressed: _saving ? null : _save,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFB05ECC),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                              child: _saving
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                          color: Colors.white, strokeWidth: 2),
                                    )
                                  : const Text(
                                      "Save",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
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
          // Cover
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
                      child: const Icon(Icons.camera_alt_outlined,
                          color: Colors.white, size: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Avatar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _pickAndUploadAvatar,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: context.cardBg,
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

  Widget _buildField(String hint, TextEditingController controller,
      {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          color: context.cardBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: TextField(
          controller: controller,
          maxLines: maxLines,
          style: TextStyle(fontSize: 14, color: context.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: context.textMuted, fontSize: 14),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: InputBorder.none,
          ),
        ),
      ),
    );
  }
}
