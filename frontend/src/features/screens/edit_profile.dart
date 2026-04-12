import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_providers.dart';

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
  String? _avatarUrl;

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
    _initialized = true;
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
      backgroundColor: const Color(0xFFEEEFF4),
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 12),
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
                        const SizedBox(height: 20),
                        Center(
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(3),
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                ),
                                child: CircleAvatar(
                                  radius: 44,
                                  backgroundColor: Colors.grey.shade200,
                                  backgroundImage: _avatarUrl != null
                                      ? CachedNetworkImageProvider(_avatarUrl!)
                                      : null,
                                  child: _avatarUrl == null
                                      ? const Icon(Icons.person,
                                          size: 44, color: Colors.grey)
                                      : null,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                "Edit picture",
                                style: TextStyle(
                                  color: Color(0xFFB05ECC),
                                  fontWeight: FontWeight.w500,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        _buildField("Username", _usernameController),
                        _buildField("Bio", _bioController, maxLines: 3),
                        _buildField("Gender", _genderController),
                        const SizedBox(height: 32),
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),
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
                                          color: Colors.white,
                                          strokeWidth: 2),
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

  Widget _buildField(String hint, TextEditingController controller,
      {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: TextField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle:
                const TextStyle(color: Colors.grey, fontSize: 14),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: InputBorder.none,
          ),
        ),
      ),
    );
  }
}
